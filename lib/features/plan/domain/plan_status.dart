import 'package:equatable/equatable.dart';

import '../../../core/network/dto/pro_dto.dart';

enum PlanKind { free, pro }

enum SubscriptionState {
  pending,
  approved,
  active,
  paymentFailed,
  cancelled,
  suspended,
  expired,
}

enum ProLimit { ok, sessionsUsed, capacity }

enum SessionsPeriod { day, lifetime }

/// The device's plan as the relay last reported it (`GET /v1/pro/status`).
/// Display only: the relay decides Pro on every call, and this is never used
/// to grant anything (spec Edge Cases).
class PlanStatus extends Equatable {
  const PlanStatus({
    required this.offerEnabled,
    required this.plan,
    required this.sessionsUsed,
    required this.sessionsLimit,
    required this.sessionsPeriod,
    required this.voiceSecondsUsed,
    required this.voiceSecondsLimit,
    required this.asOf,
    this.subscription,
    this.periodEnd,
    this.proLimit,
  });

  /// An unknown enum string from the wire parses as null (subscription) or
  /// [ProLimit.ok]; it is never a crash (data-model.md B2).
  factory PlanStatus.fromDto(ProStatusDto dto) {
    final PlanKind plan = dto.plan == 'pro' ? PlanKind.pro : PlanKind.free;
    return PlanStatus(
      offerEnabled: dto.offerEnabled,
      plan: plan,
      subscription: _subscriptionState(dto.subscription?.status),
      periodEnd: _utc(dto.subscription?.periodEnd),
      proLimit: plan == PlanKind.pro ? _proLimit(dto.proLimit) : null,
      sessionsUsed: dto.usage.sessionsUsed,
      sessionsLimit: dto.usage.sessionsLimit,
      sessionsPeriod: dto.usage.sessionsPeriod == 'day' ? SessionsPeriod.day : SessionsPeriod.lifetime,
      voiceSecondsUsed: dto.usage.voiceSecondsUsed,
      voiceSecondsLimit: dto.usage.voiceSecondsLimit,
      asOf: _utc(dto.asOf) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final bool offerEnabled;
  final PlanKind plan;

  /// Null: never subscribed on this device.
  final SubscriptionState? subscription;

  /// UTC, from the relay.
  final DateTime? periodEnd;

  /// Null unless [plan] is [PlanKind.pro].
  final ProLimit? proLimit;

  final int sessionsUsed;
  final int sessionsLimit;
  final SessionsPeriod sessionsPeriod;
  final int voiceSecondsUsed;
  final int voiceSecondsLimit;

  /// The relay's time for this answer; shown as "last checked".
  final DateTime asOf;

  /// True while the relay would serve this device under Pro rules.
  bool get isPro => plan == PlanKind.pro;

  @override
  List<Object?> get props => <Object?>[
        offerEnabled,
        plan,
        subscription,
        periodEnd,
        proLimit,
        sessionsUsed,
        sessionsLimit,
        sessionsPeriod,
        voiceSecondsUsed,
        voiceSecondsLimit,
        asOf,
      ];
}

SubscriptionState? _subscriptionState(String? raw) => switch (raw) {
      'pending' => SubscriptionState.pending,
      'approved' => SubscriptionState.approved,
      'active' => SubscriptionState.active,
      'payment_failed' => SubscriptionState.paymentFailed,
      'cancelled' => SubscriptionState.cancelled,
      'suspended' => SubscriptionState.suspended,
      'expired' => SubscriptionState.expired,
      _ => null,
    };

ProLimit _proLimit(String? raw) => switch (raw) {
      'sessions_used' => ProLimit.sessionsUsed,
      'capacity' => ProLimit.capacity,
      _ => ProLimit.ok,
    };

DateTime? _utc(String? raw) => raw == null ? null : DateTime.tryParse(raw)?.toUtc();
