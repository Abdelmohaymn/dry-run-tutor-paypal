import 'package:equatable/equatable.dart';

import '../network/dto/config_dto.dart';

/// `chat.{turn_cap, wrap_up_at_turn, min_turn_chars}` — the three chat
/// quota levers the app is allowed to read (FR-008c).
class ChatConfig extends Equatable {
  const ChatConfig({
    required this.turnCap,
    required this.wrapUpAtTurn,
    required this.minTurnChars,
  });

  final int turnCap;
  final int wrapUpAtTurn;
  final int minTurnChars;

  @override
  List<Object?> get props => <Object?>[turnCap, wrapUpAtTurn, minTurnChars];
}

/// `trial.turn_cap` and `trial.replay_enabled` — the only fields of `trial`
/// the app reads. `trial.pool` is server business (research.md R-005).
class TrialConfig extends Equatable {
  const TrialConfig({required this.turnCap, this.replayEnabled = true});

  final int turnCap;

  /// Feature 009 (FR-027). False: a free device gets today's problem once.
  final bool replayEnabled;

  @override
  List<Object?> get props => <Object?>[turnCap, replayEnabled];
}

/// `repair.{enabled, min_chars, timeout_ms}` — the three repair levers the
/// app is allowed to read (FR-008c). Null means repair is off.
class RepairConfig extends Equatable {
  const RepairConfig({
    required this.enabled,
    required this.minChars,
    required this.timeoutMs,
  });

  final bool enabled;
  final int minChars;
  final int timeoutMs;

  @override
  List<Object?> get props => <Object?>[enabled, minChars, timeoutMs];
}

/// `voice.{enabled, seconds_per_device, max_clip_seconds}` — the three
/// server speech-to-text levers the app is allowed to read. Null means
/// server voice is off (on-device speech recognition only).
class VoiceConfig extends Equatable {
  const VoiceConfig({
    required this.enabled,
    required this.secondsPerDevice,
    required this.maxClipSeconds,
  });

  final bool enabled;
  final int secondsPerDevice;
  final int maxClipSeconds;

  @override
  List<Object?> get props => <Object?>[enabled, secondsPerDevice, maxClipSeconds];
}

/// `pro.{enabled, price_label, sessions_per_day, voice_seconds_per_day,
/// manage_url}` — what the app may read of the Pro Plus lever. Null means
/// Pro is off (absent, or `enabled: false`).
class ProConfig extends Equatable {
  const ProConfig({
    required this.enabled,
    required this.priceLabel,
    required this.sessionsPerDay,
    required this.voiceSecondsPerDay,
    required this.manageUrl,
  });

  final bool enabled;
  final String priceLabel;
  final int sessionsPerDay;
  final int voiceSecondsPerDay;
  final String manageUrl;

  @override
  List<Object?> get props =>
      <Object?>[enabled, priceLabel, sessionsPerDay, voiceSecondsPerDay, manageUrl];
}

/// A read-only projection of `config.schema.json`, restricted to exactly
/// the keys FR-008c permits the app to read: `min_supported_version`, `update_url`,
/// `killed_problem_ids`, `chat.{turn_cap,wrap_up_at_turn,min_turn_chars}`,
/// `trial.{turn_cap,replay_enabled}`, `keyed_providers`, `repair.*`, `voice.*`,
/// `pro.*`.
///
/// **Deliberately has no field for `model`, `provider`, `providers`,
/// `trim`, or `trial.pool`.** Those are server business; FR-008c forbids
/// exposing model names or routing state, and giving this class a getter
/// for them would invite exactly that. `RemoteConfigRepository` keeps the
/// raw response body verbatim alongside this projection so an unread key
/// is not silently dropped from what is *retained* — only from what the
/// app can act on. No default is compiled in beyond what the seeding
/// screen needs to render (Principle X.3) — every value here always comes
/// from a real `ConfigDto`.
class RuntimeConfig extends Equatable {
  const RuntimeConfig({
    required this.minSupportedVersion,
    required this.killedProblemIds,
    required this.chat,
    required this.trial,
    required this.keyedProviders,
    this.updateUrl,
    this.repair,
    this.voice,
    this.pro,
  });

  factory RuntimeConfig.fromDto(ConfigDto dto) {
    return RuntimeConfig(
      minSupportedVersion: dto.minSupportedVersion,
      updateUrl: dto.updateUrl,
      killedProblemIds: List<String>.unmodifiable(dto.killedProblemIds),
      chat: ChatConfig(
        turnCap: dto.chat.turnCap,
        wrapUpAtTurn: dto.chat.wrapUpAtTurn,
        minTurnChars: dto.chat.minTurnChars,
      ),
      trial: TrialConfig(turnCap: dto.trial.turnCap, replayEnabled: dto.trial.replayEnabled),
      keyedProviders: List<String>.unmodifiable(dto.keyedProviders ?? const <String>[]),
      repair: dto.repair == null
          ? null
          : RepairConfig(
              enabled: dto.repair!.enabled,
              minChars: dto.repair!.minChars,
              timeoutMs: dto.repair!.timeoutMs,
            ),
      voice: dto.voice == null
          ? null
          : VoiceConfig(
              enabled: dto.voice!.enabled,
              secondsPerDevice: dto.voice!.secondsPerDevice,
              maxClipSeconds: dto.voice!.maxClipSeconds,
            ),
      pro: dto.pro == null || !dto.pro!.enabled
          ? null
          : ProConfig(
              enabled: dto.pro!.enabled,
              priceLabel: dto.pro!.priceLabel,
              sessionsPerDay: dto.pro!.sessionsPerDay,
              voiceSecondsPerDay: dto.pro!.voiceSecondsPerDay,
              manageUrl: dto.pro!.manageUrl,
            ),
    );
  }

  final String minSupportedVersion;

  /// The store listing the update wall opens. Null means the landing site.
  final String? updateUrl;

  final List<String> killedProblemIds;
  final ChatConfig chat;
  final TrialConfig trial;

  /// In the order key entry should offer them (FR-008a/b).
  final List<String> keyedProviders;

  /// Null means repair is off (feature 004's pre-feature behaviour).
  final RepairConfig? repair;

  /// Null means server voice is off (on-device speech recognition only).
  final VoiceConfig? voice;

  /// Null means Pro Plus is off: no offer anywhere (Constitution X.9).
  final ProConfig? pro;

  @override
  List<Object?> get props => <Object?>[
        minSupportedVersion,
        updateUrl,
        killedProblemIds,
        chat,
        trial,
        keyedProviders,
        repair,
        voice,
        pro,
      ];
}
