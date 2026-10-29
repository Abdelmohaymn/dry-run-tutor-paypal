import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/remote_config_repository.dart';
import '../../../core/config/runtime_config.dart';
import '../../../core/errors/result.dart';
import '../../keys/domain/key_repository.dart';
import '../domain/plan_repository.dart';
import '../domain/plan_status.dart';
import 'plan_state.dart';

Future<bool> _launchExternal(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Drives the Plan screen (app-client.md §6). The relay is the only thing that
/// says whether the device is Pro: this Cubit asks, shows the answer, and sends
/// the learner to PayPal in the system browser. Nothing here grants anything.
class PlanCubit extends Cubit<PlanState> {
  /// [pollEvery] and [pollFor] are injectable so tests run in milliseconds;
  /// [openUrl] is the `url_launcher` seam.
  PlanCubit(
    this._repo, {
    required KeyRepository keyRepository,
    required RemoteConfigRepository configRepository,
    this.pollEvery = const Duration(seconds: 3),
    this.pollFor = const Duration(seconds: 60),
    Future<bool> Function(Uri uri)? openUrl,
  })  : _keys = keyRepository,
        _config = configRepository,
        _openUrl = openUrl ?? _launchExternal,
        super(const PlanState.loading());

  final PlanRepository _repo;
  final KeyRepository _keys;
  final RemoteConfigRepository _config;
  final Duration pollEvery;
  final Duration pollFor;
  final Future<bool> Function(Uri uri) _openUrl;

  Timer? _timer;
  bool _polling = false;
  PlanStatus? _lastStatus;

  /// What the config says Pro Plus offers; null when Pro is off on this relay.
  ProConfig? get proConfig => _config.cached()?.pro;

  /// Loads the plan: fresh when the relay answers, the cache (marked stale)
  /// when it does not, and `unavailable` when there is neither.
  Future<void> load() async {
    emit(const PlanState.loading());
    final Result<PlanStatus> result = await _repo.refresh();
    if (isClosed) {
      return;
    }
    switch (result) {
      case Ok<PlanStatus>(:final value):
        await _emitReady(value, stale: false);
      case Err<PlanStatus>():
        final PlanStatus? cached = _repo.cached();
        if (cached == null) {
          emit(const PlanState.unavailable());
        } else {
          await _emitReady(cached, stale: true);
        }
    }
  }

  /// Starts a PayPal sandbox checkout. Ignored unless the offer is showing.
  Future<void> subscribe() async {
    final PlanState current = state;
    if (current is! PlanReady || !current.status.offerEnabled || current.status.plan != PlanKind.free) {
      return;
    }
    emit(const PlanState.checkingOut());
    final Result<Uri?> result = await _repo.startCheckout();
    if (isClosed) {
      return;
    }
    switch (result) {
      case Ok<Uri?>(:final value) when value == null:
        final Result<PlanStatus> refreshed = await _repo.refresh();
        if (isClosed) {
          return;
        }
        if (refreshed case Ok<PlanStatus>(:final value)) {
          await _emitReady(value, stale: false, notice: PlanNotice.alreadyActive);
        } else {
          await _backToReady(current.status, PlanNotice.alreadyActive);
        }
      case Ok<Uri?>(:final value):
        final bool opened = await _openUrl(value!);
        if (isClosed) {
          return;
        }
        if (opened) {
          emit(const PlanState.awaitingReturn());
        } else {
          await _backToReady(current.status, PlanNotice.paypalUnavailable);
        }
      case Err<Uri?>():
        await _backToReady(current.status, PlanNotice.paypalUnavailable);
    }
  }

  /// The app came back to the foreground. Only acts while PayPal is open.
  Future<void> onResumed() async {
    if (state is! PlanAwaitingReturn) {
      return;
    }
    final Result<PlanStatus> result = await _repo.refresh();
    if (isClosed || state is! PlanAwaitingReturn) {
      return;
    }
    switch (result) {
      case Ok<PlanStatus>(:final value):
        if (value.plan == PlanKind.pro) {
          await _emitReady(value, stale: false, notice: PlanNotice.activated);
        } else if (value.subscription == SubscriptionState.approved) {
          // PayPal has approved it and activation follows in seconds.
          _startPolling();
        } else {
          // APPROVAL_PENDING after return means the learner did not approve.
          await _emitReady(value, stale: false, notice: PlanNotice.notCompleted);
        }
      case Err<PlanStatus>():
        // The relay could not be reached just now; keep asking for a while
        // rather than telling the learner it did not work.
        _startPolling();
    }
  }

  /// Opens PayPal's own manage page in the system browser.
  Future<void> manage() async {
    final ProConfig? pro = proConfig;
    if (pro == null) {
      return;
    }
    final Uri? uri = Uri.tryParse(pro.manageUrl);
    if (uri != null) {
      await _openUrl(uri);
    }
  }

  void _startPolling() {
    _timer?.cancel();
    emit(const PlanState.confirming(elapsedSeconds: 0));
    _timer = Timer.periodic(pollEvery, (Timer timer) async {
      if (_polling) {
        return;
      }
      _polling = true;
      try {
        final Result<PlanStatus> result = await _repo.refresh();
        if (isClosed || state is! PlanConfirming) {
          timer.cancel();
          return;
        }
        if (result case Ok<PlanStatus>(:final value) when value.plan == PlanKind.pro) {
          timer.cancel();
          await _emitReady(value, stale: false, notice: PlanNotice.activated);
          return;
        }
        // Counted in ticks of the timer, so a slow request cannot stretch the
        // wait past `pollFor`.
        if (pollEvery * timer.tick >= pollFor) {
          timer.cancel();
          final PlanStatus? known = (result is Ok<PlanStatus> ? result.value : null) ?? _repo.cached() ?? _lastStatus;
          if (known == null) {
            emit(const PlanState.unavailable());
          } else {
            await _emitReady(known, stale: result is Err<PlanStatus>, notice: PlanNotice.notCompleted);
          }
        } else {
          emit(PlanState.confirming(elapsedSeconds: timer.tick * pollEvery.inSeconds));
        }
      } finally {
        _polling = false;
      }
    });
  }

  Future<void> _backToReady(PlanStatus status, PlanNotice notice) =>
      _emitReady(status, stale: false, notice: notice);

  Future<void> _emitReady(PlanStatus status, {required bool stale, PlanNotice? notice}) async {
    _lastStatus = status;
    final bool ownKey = await _keys.read() != null;
    if (isClosed) {
      return;
    }
    emit(PlanState.ready(status: status, ownKey: ownKey, stale: stale, notice: notice));
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
