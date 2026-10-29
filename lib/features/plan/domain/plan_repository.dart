import '../../../core/errors/result.dart';
import 'plan_status.dart';

/// The learner's Pro Plus plan: what the relay says it is, and the way to
/// start a PayPal sandbox checkout. The app never decides entitlement; it
/// only asks and displays (research.md R-1).
abstract interface class PlanRepository {
  /// `GET /v1/pro/status`; caches it on success. Err on transport/envelope.
  Future<Result<PlanStatus>> refresh();

  /// Last cached status, or null. Display only — never grants anything.
  PlanStatus? cached();

  /// `POST /v1/pro/checkout`. Ok(uri) to open, Ok(null) when already active.
  Future<Result<Uri?>> startCheckout();
}
