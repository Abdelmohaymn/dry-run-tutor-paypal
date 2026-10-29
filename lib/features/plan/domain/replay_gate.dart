import '../../../core/config/remote_config_repository.dart';
import '../../../core/config/runtime_config.dart';
import '../../../core/errors/result.dart';
import '../../keys/domain/key_repository.dart';
import 'plan_repository.dart';
import 'plan_status.dart';

/// Decides whether "Practice again" and the problem picker should show the
/// Pro offer instead of calling the relay (FR-027). Asking first means a free
/// learner never spends a session reset on a refusal.
class ReplayGate {
  ReplayGate({
    required RemoteConfigRepository configRepository,
    required KeyRepository keyRepository,
    required PlanRepository planRepository,
  })  : _config = configRepository,
        _keys = keyRepository,
        _plan = planRepository;

  final RemoteConfigRepository _config;
  final KeyRepository _keys;
  final PlanRepository _plan;

  /// True when replay is off, there is no own key, and the relay last said "free".
  Future<bool> isLocked() async {
    final RuntimeConfig? cfg = _config.cached();
    if (cfg == null || cfg.trial.replayEnabled) {
      return false;
    }
    if (await _keys.read() != null) {
      return false;
    }
    PlanStatus? status = _plan.cached();
    if (status == null && cfg.pro != null) {
      final Result<PlanStatus> r = await _plan.refresh();
      if (r case Ok<PlanStatus>(:final value)) {
        status = value;
      }
    }
    return status?.plan != PlanKind.pro;
  }

  /// Whether the prompt may offer Pro Plus (it is configured on this relay).
  bool get offerPro => _config.cached()?.pro != null;
}
