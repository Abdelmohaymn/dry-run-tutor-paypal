import 'package:shared_preferences/shared_preferences.dart';

import '../domain/voice_quota.dart';

const String _dateKey = 'cloud_voice.date';
const String _secondsLeftKey = 'cloud_voice.seconds_left';
const String _maxClipSecondsKey = 'cloud_voice.max_clip_seconds';

/// Persists the last cloud-voice quota the Worker reported, so a same-day
/// relaunch knows how many seconds are left without a new endpoint.
///
/// On-device data only. It holds counters and a UTC date, never audio or
/// transcript text.
class VoiceQuotaStore {
  VoiceQuotaStore(this._prefs);

  final SharedPreferences _prefs;

  /// Returns the stored quota, or null when any of the three keys is missing.
  VoiceQuota? read() {
    final String? date = _prefs.getString(_dateKey);
    final int? secondsLeft = _prefs.getInt(_secondsLeftKey);
    final int? maxClipSeconds = _prefs.getInt(_maxClipSecondsKey);
    if (date == null || secondsLeft == null || maxClipSeconds == null) {
      return null;
    }
    return VoiceQuota(
      date: date,
      secondsLeft: secondsLeft,
      maxClipSeconds: maxClipSeconds,
    );
  }

  Future<void> write(VoiceQuota q) async {
    await _prefs.setString(_dateKey, q.date);
    await _prefs.setInt(_secondsLeftKey, q.secondsLeft);
    await _prefs.setInt(_maxClipSecondsKey, q.maxClipSeconds);
  }

  /// Forgets the stored quota. Called when the plan changes (free → Pro), so
  /// a device that had hit its free limit asks the relay again instead of
  /// trusting a stale "0 seconds left" until midnight (research.md R-13).
  Future<void> clear() async {
    await _prefs.remove(_dateKey);
    await _prefs.remove(_secondsLeftKey);
    await _prefs.remove(_maxClipSecondsKey);
  }
}
