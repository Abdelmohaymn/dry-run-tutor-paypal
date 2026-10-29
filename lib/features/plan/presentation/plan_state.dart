import 'package:freezed_annotation/freezed_annotation.dart';

import '../domain/plan_status.dart';

part 'plan_state.freezed.dart';

/// A one-off message the Plan screen shows once, after something happened.
/// None of them is styled as an error (US1-3): backing out of PayPal is a
/// choice, not a failure.
enum PlanNotice { activated, notCompleted, paypalUnavailable, alreadyActive }

/// data-model.md B4.
@freezed
sealed class PlanState with _$PlanState {
  const factory PlanState.loading() = PlanLoading;

  /// [ownKey] is `KeyRepository.read() != null`. [stale] means [status] came
  /// from the cache after a failed refresh.
  const factory PlanState.ready({
    required PlanStatus status,
    required bool ownKey,
    required bool stale,
    PlanNotice? notice,
  }) = PlanReady;

  /// The checkout request is in flight.
  const factory PlanState.checkingOut() = PlanCheckingOut;

  /// PayPal is open in the browser; waiting for the learner to come back.
  const factory PlanState.awaitingReturn() = PlanAwaitingReturn;

  /// Back from PayPal and polling the relay until the subscription shows up.
  const factory PlanState.confirming({required int elapsedSeconds}) = PlanConfirming;

  /// The first load failed and there is no cache to show.
  const factory PlanState.unavailable() = PlanUnavailable;
}
