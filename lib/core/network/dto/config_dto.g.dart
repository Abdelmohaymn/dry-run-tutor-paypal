// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'config_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatConfigDto _$ChatConfigDtoFromJson(Map<String, dynamic> json) =>
    ChatConfigDto(
      turnCap: (json['turn_cap'] as num).toInt(),
      wrapUpAtTurn: (json['wrap_up_at_turn'] as num).toInt(),
      minTurnChars: (json['min_turn_chars'] as num).toInt(),
    );

Map<String, dynamic> _$ChatConfigDtoToJson(ChatConfigDto instance) =>
    <String, dynamic>{
      'turn_cap': instance.turnCap,
      'wrap_up_at_turn': instance.wrapUpAtTurn,
      'min_turn_chars': instance.minTurnChars,
    };

TrialConfigDto _$TrialConfigDtoFromJson(Map<String, dynamic> json) =>
    TrialConfigDto(
      turnCap: (json['turn_cap'] as num).toInt(),
      replayEnabled: json['replay_enabled'] as bool? ?? true,
    );

Map<String, dynamic> _$TrialConfigDtoToJson(TrialConfigDto instance) =>
    <String, dynamic>{
      'turn_cap': instance.turnCap,
      'replay_enabled': instance.replayEnabled,
    };

RepairConfigDto _$RepairConfigDtoFromJson(Map<String, dynamic> json) =>
    RepairConfigDto(
      enabled: json['enabled'] as bool,
      minChars: (json['min_chars'] as num).toInt(),
      timeoutMs: (json['timeout_ms'] as num).toInt(),
    );

Map<String, dynamic> _$RepairConfigDtoToJson(RepairConfigDto instance) =>
    <String, dynamic>{
      'enabled': instance.enabled,
      'min_chars': instance.minChars,
      'timeout_ms': instance.timeoutMs,
    };

VoiceConfigDto _$VoiceConfigDtoFromJson(Map<String, dynamic> json) =>
    VoiceConfigDto(
      enabled: json['enabled'] as bool,
      secondsPerDevice: (json['seconds_per_device'] as num).toInt(),
      maxClipSeconds: (json['max_clip_seconds'] as num).toInt(),
    );

Map<String, dynamic> _$VoiceConfigDtoToJson(VoiceConfigDto instance) =>
    <String, dynamic>{
      'enabled': instance.enabled,
      'seconds_per_device': instance.secondsPerDevice,
      'max_clip_seconds': instance.maxClipSeconds,
    };

ProConfigDto _$ProConfigDtoFromJson(Map<String, dynamic> json) => ProConfigDto(
  enabled: json['enabled'] as bool,
  priceLabel: json['price_label'] as String,
  sessionsPerDay: (json['sessions_per_day'] as num).toInt(),
  voiceSecondsPerDay: (json['voice_seconds_per_day'] as num).toInt(),
  manageUrl: json['manage_url'] as String,
);

Map<String, dynamic> _$ProConfigDtoToJson(ProConfigDto instance) =>
    <String, dynamic>{
      'enabled': instance.enabled,
      'price_label': instance.priceLabel,
      'sessions_per_day': instance.sessionsPerDay,
      'voice_seconds_per_day': instance.voiceSecondsPerDay,
      'manage_url': instance.manageUrl,
    };

ConfigDto _$ConfigDtoFromJson(Map<String, dynamic> json) => ConfigDto(
  minSupportedVersion: json['min_supported_version'] as String,
  killedProblemIds: (json['killed_problem_ids'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  chat: ChatConfigDto.fromJson(json['chat'] as Map<String, dynamic>),
  trial: TrialConfigDto.fromJson(json['trial'] as Map<String, dynamic>),
  updateUrl: json['update_url'] as String?,
  keyedProviders: (json['keyed_providers'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  repair: json['repair'] == null
      ? null
      : RepairConfigDto.fromJson(json['repair'] as Map<String, dynamic>),
  voice: json['voice'] == null
      ? null
      : VoiceConfigDto.fromJson(json['voice'] as Map<String, dynamic>),
  pro: json['pro'] == null
      ? null
      : ProConfigDto.fromJson(json['pro'] as Map<String, dynamic>),
);

Map<String, dynamic> _$ConfigDtoToJson(ConfigDto instance) => <String, dynamic>{
  'min_supported_version': instance.minSupportedVersion,
  'update_url': instance.updateUrl,
  'killed_problem_ids': instance.killedProblemIds,
  'chat': instance.chat.toJson(),
  'trial': instance.trial.toJson(),
  'keyed_providers': instance.keyedProviders,
  'repair': instance.repair?.toJson(),
  'voice': instance.voice?.toJson(),
  'pro': instance.pro?.toJson(),
};
