import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/relay_error.dart';
import '../../../core/errors/result.dart';
import '../../../core/network/dto/pro_dto.dart';
import '../../../core/network/relay_client.dart';
import '../../cloud_voice/data/voice_quota_store.dart';
import '../../onboarding/domain/install_identity.dart';
import '../../onboarding/domain/install_repository.dart';
import '../domain/plan_repository.dart';
import '../domain/plan_status.dart';

const String _cacheKey = 'plan.last_status';

/// [PlanRepository] over `GET /v1/pro/status` and `POST /v1/pro/checkout`.
/// The last status JSON is kept in [SharedPreferences] so the Plan screen can
/// show something offline, marked stale. It is plan data, not learner data
/// (data-model.md B3, B5).
class PlanRepositoryImpl implements PlanRepository {
  PlanRepositoryImpl({
    required RelayClient relayClient,
    required InstallRepository installRepository,
    required SharedPreferences prefs,
    required VoiceQuotaStore voiceQuotaStore,
  })  : _relayClient = relayClient,
        _installRepository = installRepository,
        _prefs = prefs,
        _voiceQuotaStore = voiceQuotaStore;

  final RelayClient _relayClient;
  final InstallRepository _installRepository;
  final SharedPreferences _prefs;
  final VoiceQuotaStore _voiceQuotaStore;

  @override
  PlanStatus? cached() {
    final String? raw = _prefs.getString(_cacheKey);
    if (raw == null) {
      return null;
    }
    try {
      return PlanStatus.fromDto(ProStatusDto.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Result<PlanStatus>> refresh() async {
    final Result<String> installId = await _installId();
    if (installId is Err<String>) {
      return Err(installId.error);
    }
    try {
      final ProStatusDto dto = await _relayClient.proStatus(installId: (installId as Ok<String>).value);
      final PlanStatus status = PlanStatus.fromDto(dto);
      final PlanStatus? previous = cached();
      await _prefs.setString(_cacheKey, jsonEncode(dto.toJson()));
      // A device that had spent its free voice seconds trusts a stored "0
      // left" until midnight; asking the relay again is what lets Pro's
      // allowance show up (research.md R-13).
      if (previous?.plan != PlanKind.pro && status.plan == PlanKind.pro) {
        await _voiceQuotaStore.clear();
      }
      return Ok(status);
    } on RelayException catch (e) {
      return Err(e.error);
    } catch (_) {
      return const Err(RelayError.transport());
    }
  }

  @override
  Future<Result<Uri?>> startCheckout() async {
    final Result<String> installId = await _installId();
    if (installId is Err<String>) {
      return Err(installId.error);
    }
    try {
      final ProCheckoutDto dto = await _relayClient.proCheckout(installId: (installId as Ok<String>).value);
      if (dto.alreadyActive) {
        return const Ok(null);
      }
      final Uri? uri = dto.approveUrl == null ? null : Uri.tryParse(dto.approveUrl!);
      if (uri == null || uri.scheme != 'https') {
        return const Err(RelayError.unclearRetry());
      }
      return Ok(uri);
    } on RelayException catch (e) {
      return Err(e.error);
    } catch (_) {
      return const Err(RelayError.transport());
    }
  }

  Future<Result<String>> _installId() async {
    final Result<InstallIdentity> identity = await _installRepository.ensureIdentity();
    return switch (identity) {
      Ok<InstallIdentity>(:final value) => Ok(value.installId),
      Err<InstallIdentity>(:final error) => Err(error),
    };
  }
}
