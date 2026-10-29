// PlanCubit (app-client.md §6): load, subscribe, the return from PayPal, and
// the poll that follows an approval. Timing is injected so the 60-second wait
// runs in milliseconds, and `openUrl` is a recorder instead of url_launcher.
import 'package:dry_run/core/config/runtime_config.dart';
import 'package:dry_run/core/errors/relay_error.dart';
import 'package:dry_run/core/errors/result.dart';
import 'package:dry_run/features/keys/domain/learner_key.dart';
import 'package:dry_run/features/plan/domain/plan_status.dart';
import 'package:dry_run/features/plan/presentation/plan_cubit.dart';
import 'package:dry_run/features/plan/presentation/plan_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_config_repository.dart';
import '../fakes/fake_key_repository.dart';
import '../fakes/fake_plan_repository.dart';

final Uri _approve = Uri.parse('https://www.sandbox.paypal.com/webapps/billing/subscriptions?ba_token=BA-1');

RuntimeConfig _config({ProConfig? pro}) => RuntimeConfig(
      minSupportedVersion: '1.0.0',
      killedProblemIds: const <String>[],
      chat: const ChatConfig(turnCap: 4, wrapUpAtTurn: 3, minTurnChars: 5),
      trial: const TrialConfig(turnCap: 4),
      keyedProviders: const <String>['groq'],
      pro: pro,
    );

const ProConfig _pro = ProConfig(
  enabled: true,
  priceLabel: r'$4.99 / month',
  sessionsPerDay: 5,
  voiceSecondsPerDay: 900,
  manageUrl: 'https://www.sandbox.paypal.com/myaccount/autopay/',
);

class _Harness {
  _Harness({ProConfig? pro = _pro, this.pollFor = const Duration(milliseconds: 60)}) {
    config.cachedValue = _config(pro: pro);
    cubit = PlanCubit(
      repo,
      keyRepository: keys,
      configRepository: config,
      pollEvery: const Duration(milliseconds: 10),
      pollFor: pollFor,
      openUrl: (Uri uri) async {
        opened.add(uri);
        return openResult;
      },
    );
    cubit.stream.listen(states.add);
  }

  final FakePlanRepository repo = FakePlanRepository();
  final FakeKeyRepository keys = FakeKeyRepository();
  final FakeRemoteConfigRepository config = FakeRemoteConfigRepository();
  final Duration pollFor;
  final List<Uri> opened = <Uri>[];
  final List<PlanState> states = <PlanState>[];
  bool openResult = true;
  late final PlanCubit cubit;

  /// Waits until [test] holds for the latest state (the polls run on a real timer).
  Future<void> until(bool Function(PlanState) test) async {
    for (int i = 0; i < 200; i++) {
      if (cubit.state.runtimeType != PlanLoading && test(cubit.state)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('state never matched; last was ${cubit.state}');
  }

  Matcher ready({PlanNotice? notice, bool stale = false, bool ownKey = false}) => isA<PlanReady>()
      .having((PlanReady s) => s.notice, 'notice', notice)
      .having((PlanReady s) => s.stale, 'stale', stale)
      .having((PlanReady s) => s.ownKey, 'ownKey', ownKey);
}

void main() {
  group('load', () {
    test('ok → loading, then ready with the fresh status', () async {
      final _Harness h = _Harness();
      h.repo.refreshResults.add(Ok<PlanStatus>(freeStatus()));
      await h.cubit.load();
      await pumpEventQueue();
      expect(h.states, <Matcher>[isA<PlanLoading>(), h.ready()]);
      expect((h.cubit.state as PlanReady).status, freeStatus());
    });

    test('an own key is reflected in ownKey', () async {
      final _Harness h = _Harness();
      h.keys.storedKey = const LearnerKey(providerId: 'groq', value: 'gsk_x');
      h.repo.refreshResults.add(Ok<PlanStatus>(freeStatus()));
      await h.cubit.load();
      expect(h.cubit.state, h.ready(ownKey: true));
    });

    test('a failed refresh with a cache is ready and stale', () async {
      final _Harness h = _Harness();
      h.repo.cachedStatus = freeStatus();
      h.repo.refreshResults.add(const Err<PlanStatus>(RelayError.transport()));
      await h.cubit.load();
      expect(h.cubit.state, h.ready(stale: true));
    });

    test('a failed refresh with no cache is unavailable', () async {
      final _Harness h = _Harness();
      h.repo.refreshResults.add(const Err<PlanStatus>(RelayError.transport()));
      await h.cubit.load();
      expect(h.cubit.state, isA<PlanUnavailable>());
    });
  });

  group('subscribe', () {
    test('opens PayPal and waits for the learner to return', () async {
      final _Harness h = _Harness();
      h.repo.refreshResults.add(Ok<PlanStatus>(freeStatus()));
      h.repo.checkoutResults.add(Ok<Uri?>(_approve));
      await h.cubit.load();
      await h.cubit.subscribe();
      await pumpEventQueue();
      expect(h.opened, <Uri>[_approve]);
      expect(h.states.map((PlanState s) => s.runtimeType), <Type>[
        PlanLoading,
        PlanReady,
        PlanCheckingOut,
        PlanAwaitingReturn,
      ]);
    });

    test('a checkout error is a gentle notice, back on the status it had', () async {
      final _Harness h = _Harness();
      h.repo.refreshResults.add(Ok<PlanStatus>(freeStatus()));
      h.repo.checkoutResults.add(const Err<Uri?>(RelayError.unclearRetry()));
      await h.cubit.load();
      await h.cubit.subscribe();
      expect(h.cubit.state, h.ready(notice: PlanNotice.paypalUnavailable));
      expect(h.opened, isEmpty);
    });

    test('a browser that will not open is the same notice', () async {
      final _Harness h = _Harness()..openResult = false;
      h.repo.refreshResults.add(Ok<PlanStatus>(freeStatus()));
      h.repo.checkoutResults.add(Ok<Uri?>(_approve));
      await h.cubit.load();
      await h.cubit.subscribe();
      expect(h.cubit.state, h.ready(notice: PlanNotice.paypalUnavailable));
    });

    test('already active: refreshes and says so', () async {
      final _Harness h = _Harness();
      h.repo.refreshResults
        ..add(Ok<PlanStatus>(freeStatus()))
        ..add(Ok<PlanStatus>(proStatus()));
      h.repo.checkoutResults.add(const Ok<Uri?>(null));
      await h.cubit.load();
      await h.cubit.subscribe();
      expect(h.cubit.state, h.ready(notice: PlanNotice.alreadyActive));
      expect((h.cubit.state as PlanReady).status.plan, PlanKind.pro);
      expect(h.opened, isEmpty);
    });

    test('is ignored when Pro is not on offer, or already Pro', () async {
      final _Harness off = _Harness();
      off.repo.refreshResults.add(Ok<PlanStatus>(freeStatus(offerEnabled: false)));
      await off.cubit.load();
      await off.cubit.subscribe();
      expect(off.repo.checkoutCalls, 0);

      final _Harness pro = _Harness();
      pro.repo.refreshResults.add(Ok<PlanStatus>(proStatus()));
      await pro.cubit.load();
      await pro.cubit.subscribe();
      expect(pro.repo.checkoutCalls, 0);
    });
  });

  group('onResumed', () {
    Future<_Harness> awaiting({Duration pollFor = const Duration(milliseconds: 60)}) async {
      final _Harness h = _Harness(pollFor: pollFor);
      h.repo.refreshResults.add(Ok<PlanStatus>(freeStatus()));
      h.repo.checkoutResults.add(Ok<Uri?>(_approve));
      await h.cubit.load();
      await h.cubit.subscribe();
      expect(h.cubit.state, isA<PlanAwaitingReturn>());
      return h;
    }

    test('entitled → activated', () async {
      final _Harness h = await awaiting();
      h.repo.refreshResults.add(Ok<PlanStatus>(proStatus()));
      await h.cubit.onResumed();
      expect(h.cubit.state, h.ready(notice: PlanNotice.activated));
    });

    test('approved → confirming, then activated when the relay catches up', () async {
      final _Harness h = await awaiting();
      h.repo.refreshResults
        ..add(Ok<PlanStatus>(freeStatus(subscription: SubscriptionState.approved)))
        ..add(Ok<PlanStatus>(freeStatus(subscription: SubscriptionState.approved)))
        ..add(Ok<PlanStatus>(proStatus()));
      await h.cubit.onResumed();
      expect(h.cubit.state, isA<PlanConfirming>());
      await h.until((PlanState s) => s is PlanReady);
      expect(h.cubit.state, h.ready(notice: PlanNotice.activated));
      expect(h.states.whereType<PlanConfirming>(), isNotEmpty);
    });

    test('pending (the learner did not approve) → notCompleted at once, no polling', () async {
      final _Harness h = await awaiting();
      h.repo.refreshResults.add(Ok<PlanStatus>(freeStatus(subscription: SubscriptionState.pending)));
      await h.cubit.onResumed();
      expect(h.cubit.state, h.ready(notice: PlanNotice.notCompleted));
    });

    test('no subscription at all → notCompleted', () async {
      final _Harness h = await awaiting();
      h.repo.refreshResults.add(Ok<PlanStatus>(freeStatus()));
      await h.cubit.onResumed();
      expect(h.cubit.state, h.ready(notice: PlanNotice.notCompleted));
    });

    test('approved but never activated: the poll times out into notCompleted', () async {
      final _Harness h = await awaiting();
      h.repo.refreshResults.add(Ok<PlanStatus>(freeStatus(subscription: SubscriptionState.approved)));
      await h.cubit.onResumed();
      await h.until((PlanState s) => s is PlanReady);
      expect(h.cubit.state, h.ready(notice: PlanNotice.notCompleted));
    });

    test('an unreachable relay on return keeps asking rather than giving up', () async {
      final _Harness h = await awaiting();
      h.repo.refreshResults
        ..add(const Err<PlanStatus>(RelayError.transport()))
        ..add(const Err<PlanStatus>(RelayError.transport()))
        ..add(Ok<PlanStatus>(proStatus()));
      await h.cubit.onResumed();
      await h.until((PlanState s) => s is PlanReady);
      expect(h.cubit.state, h.ready(notice: PlanNotice.activated));
    });

    test('does nothing unless PayPal was opened from here', () async {
      final _Harness h = _Harness();
      h.repo.refreshResults.add(Ok<PlanStatus>(freeStatus()));
      await h.cubit.load();
      final int before = h.repo.refreshCalls;
      await h.cubit.onResumed();
      expect(h.repo.refreshCalls, before);
    });

    test('closing mid-poll stops the timer', () async {
      final _Harness h = await awaiting(pollFor: const Duration(seconds: 5));
      h.repo.refreshResults.add(Ok<PlanStatus>(freeStatus(subscription: SubscriptionState.approved)));
      await h.cubit.onResumed();
      await h.cubit.close();
      final int calls = h.repo.refreshCalls;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.repo.refreshCalls, calls);
    });
  });

  group('manage', () {
    test('opens the manage url from config', () async {
      final _Harness h = _Harness();
      await h.cubit.manage();
      expect(h.opened, <Uri>[Uri.parse('https://www.sandbox.paypal.com/myaccount/autopay/')]);
    });

    test('does nothing when Pro is off', () async {
      final _Harness h = _Harness(pro: null);
      await h.cubit.manage();
      expect(h.opened, isEmpty);
    });
  });
}
