// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pro_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProSubscriptionDto _$ProSubscriptionDtoFromJson(Map<String, dynamic> json) =>
    ProSubscriptionDto(
      status: json['status'] as String,
      periodEnd: json['period_end'] as String?,
      confirmedAt: json['confirmed_at'] as String?,
    );

Map<String, dynamic> _$ProSubscriptionDtoToJson(ProSubscriptionDto instance) =>
    <String, dynamic>{
      'status': instance.status,
      'period_end': instance.periodEnd,
      'confirmed_at': instance.confirmedAt,
    };

ProUsageDto _$ProUsageDtoFromJson(Map<String, dynamic> json) => ProUsageDto(
  sessionsUsed: (json['sessions_used'] as num).toInt(),
  sessionsLimit: (json['sessions_limit'] as num).toInt(),
  sessionsPeriod: json['sessions_period'] as String,
  voiceSecondsUsed: (json['voice_seconds_used'] as num).toInt(),
  voiceSecondsLimit: (json['voice_seconds_limit'] as num).toInt(),
);

Map<String, dynamic> _$ProUsageDtoToJson(ProUsageDto instance) =>
    <String, dynamic>{
      'sessions_used': instance.sessionsUsed,
      'sessions_limit': instance.sessionsLimit,
      'sessions_period': instance.sessionsPeriod,
      'voice_seconds_used': instance.voiceSecondsUsed,
      'voice_seconds_limit': instance.voiceSecondsLimit,
    };

ProStatusDto _$ProStatusDtoFromJson(Map<String, dynamic> json) => ProStatusDto(
  offerEnabled: json['offer_enabled'] as bool,
  plan: json['plan'] as String,
  usage: ProUsageDto.fromJson(json['usage'] as Map<String, dynamic>),
  asOf: json['as_of'] as String,
  subscription: json['subscription'] == null
      ? null
      : ProSubscriptionDto.fromJson(
          json['subscription'] as Map<String, dynamic>,
        ),
  proLimit: json['pro_limit'] as String?,
);

Map<String, dynamic> _$ProStatusDtoToJson(ProStatusDto instance) =>
    <String, dynamic>{
      'offer_enabled': instance.offerEnabled,
      'plan': instance.plan,
      'subscription': instance.subscription?.toJson(),
      'pro_limit': instance.proLimit,
      'usage': instance.usage.toJson(),
      'as_of': instance.asOf,
    };

ProCheckoutDto _$ProCheckoutDtoFromJson(Map<String, dynamic> json) =>
    ProCheckoutDto(
      approveUrl: json['approve_url'] as String?,
      alreadyActive: json['already_active'] as bool? ?? false,
    );

Map<String, dynamic> _$ProCheckoutDtoToJson(ProCheckoutDto instance) =>
    <String, dynamic>{
      'approve_url': instance.approveUrl,
      'already_active': instance.alreadyActive,
    };
