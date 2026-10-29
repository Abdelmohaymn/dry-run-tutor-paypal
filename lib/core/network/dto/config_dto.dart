import 'package:json_annotation/json_annotation.dart';

part 'config_dto.g.dart';

/// `config.schema.json#/properties/chat` — only the three keys the app is
/// allowed to read.
@JsonSerializable(fieldRename: FieldRename.snake)
class ChatConfigDto {
  ChatConfigDto({
    required this.turnCap,
    required this.wrapUpAtTurn,
    required this.minTurnChars,
  });

  factory ChatConfigDto.fromJson(Map<String, dynamic> json) => _$ChatConfigDtoFromJson(json);

  final int turnCap;
  final int wrapUpAtTurn;
  final int minTurnChars;

  Map<String, dynamic> toJson() => _$ChatConfigDtoToJson(this);
}

/// `config.schema.json#/properties/trial` — `turn_cap` and `replay_enabled`.
/// `ground_truth_tier`, `condense`, `daily_session_cap`, and `pool` are
/// server business the app has no reason to read and does not declare a
/// field for.
@JsonSerializable(fieldRename: FieldRename.snake)
class TrialConfigDto {
  TrialConfigDto({required this.turnCap, this.replayEnabled = true});

  factory TrialConfigDto.fromJson(Map<String, dynamic> json) => _$TrialConfigDtoFromJson(json);

  final int turnCap;

  /// Feature 009 (FR-027). False means a free device gets today's problem
  /// once; "Practice again" and the problem picker are Pro or own-key. Absent
  /// means true, which is the behaviour before the lever existed.
  @JsonKey(defaultValue: true)
  final bool replayEnabled;

  Map<String, dynamic> toJson() => _$TrialConfigDtoToJson(this);
}

/// `config.schema.json#/properties/repair` — only the three keys the app
/// needs to decide whether to call and how long to hold the review step.
/// **No field for `model`, `max_input_chars`, `max_output_ratio` or
/// `min_word_overlap`** (FR-008c) — the guards are server business.
@JsonSerializable(fieldRename: FieldRename.snake)
class RepairConfigDto {
  RepairConfigDto({
    required this.enabled,
    required this.minChars,
    required this.timeoutMs,
  });

  factory RepairConfigDto.fromJson(Map<String, dynamic> json) => _$RepairConfigDtoFromJson(json);

  final bool enabled;
  final int minChars;
  final int timeoutMs;

  Map<String, dynamic> toJson() => _$RepairConfigDtoToJson(this);
}

/// `config.schema.json#/properties/voice` — only the three keys the app
/// needs to decide whether to record for upload and when to stop the clip.
/// **No field for `model`** — which speech model the server uses is server
/// business, same rule as `repair.model`.
@JsonSerializable(fieldRename: FieldRename.snake)
class VoiceConfigDto {
  VoiceConfigDto({
    required this.enabled,
    required this.secondsPerDevice,
    required this.maxClipSeconds,
  });

  factory VoiceConfigDto.fromJson(Map<String, dynamic> json) => _$VoiceConfigDtoFromJson(json);

  final bool enabled;
  final int secondsPerDevice;
  final int maxClipSeconds;

  Map<String, dynamic> toJson() => _$VoiceConfigDtoToJson(this);
}

/// `config.schema.json#/properties/pro` — only the five keys the app needs to
/// show the offer and open PayPal's manage page. **No field for `plan_id`,
/// the token ceilings or `recheck_after_seconds`** — those are server business.
@JsonSerializable(fieldRename: FieldRename.snake)
class ProConfigDto {
  ProConfigDto({
    required this.enabled,
    required this.priceLabel,
    required this.sessionsPerDay,
    required this.voiceSecondsPerDay,
    required this.manageUrl,
  });

  factory ProConfigDto.fromJson(Map<String, dynamic> json) => _$ProConfigDtoFromJson(json);

  final bool enabled;
  final String priceLabel;
  final int sessionsPerDay;
  final int voiceSecondsPerDay;
  final String manageUrl;

  Map<String, dynamic> toJson() => _$ProConfigDtoToJson(this);
}

/// `GET /v1/config` response, restricted to the keys FR-008c permits the
/// app to read: `min_supported_version`, `update_url`, `killed_problem_ids`,
/// `chat.*`, `trial.turn_cap`, `keyed_providers`, `repair.*` (feature 004,
/// three fields only), `voice.*` (server speech-to-text, three fields only),
/// `pro.*` (Pro Plus, feature 009, five fields only).
/// The relay still sends `content_manifest_url` for
/// pre-006 apps; it is ignored here, like every other unknown key.
///
/// **This class has no field for `model`, `provider`, `providers`,
/// `trim`, or `trial.pool`.** `json_serializable`'s generated `fromJson`
/// silently ignores unknown keys by default, so those five stay
/// unreadable by construction rather than by convention — there is no
/// getter to reach for even by accident. `RemoteConfigRepository` stores
/// the *raw* response body verbatim alongside this parsed projection, so
/// an unread key is not silently dropped from what is retained — only
/// from what the app can act on.
@JsonSerializable(fieldRename: FieldRename.snake)
class ConfigDto {
  ConfigDto({
    required this.minSupportedVersion,
    required this.killedProblemIds,
    required this.chat,
    required this.trial,
    this.updateUrl,
    this.keyedProviders,
    this.repair,
    this.voice,
    this.pro,
  });

  factory ConfigDto.fromJson(Map<String, dynamic> json) => _$ConfigDtoFromJson(json);

  final String minSupportedVersion;

  /// Absent means the update button falls back to the landing site.
  final String? updateUrl;

  final List<String> killedProblemIds;
  final ChatConfigDto chat;
  final TrialConfigDto trial;

  /// Absent means the single (unread) `provider` value applied — see
  /// research.md R-005. When present, in the order key entry should
  /// offer them.
  final List<String>? keyedProviders;

  /// Absent means repair is off (feature 004's pre-feature behaviour).
  final RepairConfigDto? repair;

  /// Absent means server-side voice is off and the app uses on-device
  /// speech recognition only.
  final VoiceConfigDto? voice;

  /// Absent means Pro Plus is off: no offer anywhere (Constitution X.9).
  final ProConfigDto? pro;

  Map<String, dynamic> toJson() => _$ConfigDtoToJson(this);
}
