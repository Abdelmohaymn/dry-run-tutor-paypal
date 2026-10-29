import 'package:dry_run/core/errors/result.dart';
import 'package:dry_run/features/plan/domain/plan_repository.dart';
import 'package:dry_run/features/plan/domain/plan_status.dart';

/// A plain fake, scripted like `FakeKeyRepository`. [refreshResults] and
/// [checkoutResults] are consumed in order; once a queue is empty, the last
/// value is repeated (or [defaultRefresh] when nothing was ever scripted).
class FakePlanRepository implements PlanRepository {
  FakePlanRepository({this.cachedStatus});

  PlanStatus? cachedStatus;

  /// Results `refresh()` returns, front first.
  final List<Result<PlanStatus>> refreshResults = <Result<PlanStatus>>[];

  /// Results `startCheckout()` returns, front first.
  final List<Result<Uri?>> checkoutResults = <Result<Uri?>>[];

  Result<PlanStatus>? _lastRefresh;
  Result<Uri?>? _lastCheckout;

  int refreshCalls = 0;
  int checkoutCalls = 0;

  @override
  PlanStatus? cached() => cachedStatus;

  @override
  Future<Result<PlanStatus>> refresh() async {
    refreshCalls += 1;
    if (refreshResults.isNotEmpty) {
      _lastRefresh = refreshResults.removeAt(0);
    }
    final Result<PlanStatus>? result = _lastRefresh;
    if (result == null) {
      throw StateError('FakePlanRepository: no refresh result scripted');
    }
    if (result case Ok<PlanStatus>(:final value)) {
      cachedStatus = value;
    }
    return result;
  }

  @override
  Future<Result<Uri?>> startCheckout() async {
    checkoutCalls += 1;
    if (checkoutResults.isNotEmpty) {
      _lastCheckout = checkoutResults.removeAt(0);
    }
    final Result<Uri?>? result = _lastCheckout;
    if (result == null) {
      throw StateError('FakePlanRepository: no checkout result scripted');
    }
    return result;
  }
}

/// A free-plan status with Pro on offer; override the bits a test cares about.
PlanStatus freeStatus({
  bool offerEnabled = true,
  SubscriptionState? subscription,
  DateTime? asOf,
}) => PlanStatus(
  offerEnabled: offerEnabled,
  plan: PlanKind.free,
  subscription: subscription,
  sessionsUsed: 1,
  sessionsLimit: 3,
  sessionsPeriod: SessionsPeriod.lifetime,
  voiceSecondsUsed: 60,
  voiceSecondsLimit: 300,
  asOf: asOf ?? DateTime.utc(2026, 10, 20, 10),
);

/// A Pro status; [proLimit] defaults to [ProLimit.ok].
PlanStatus proStatus({
  SubscriptionState subscription = SubscriptionState.active,
  ProLimit proLimit = ProLimit.ok,
  DateTime? periodEnd,
  DateTime? asOf,
}) => PlanStatus(
  offerEnabled: true,
  plan: PlanKind.pro,
  subscription: subscription,
  periodEnd: periodEnd ?? DateTime.utc(2026, 11, 20, 10),
  proLimit: proLimit,
  sessionsUsed: 2,
  sessionsLimit: 5,
  sessionsPeriod: SessionsPeriod.day,
  voiceSecondsUsed: 120,
  voiceSecondsLimit: 900,
  asOf: asOf ?? DateTime.utc(2026, 10, 20, 10),
);
