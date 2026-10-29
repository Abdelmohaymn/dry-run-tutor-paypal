import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/assessment/data/assessment_repository_impl.dart';
import '../../features/assessment/domain/assessment_repository.dart';
import '../../features/chat/data/session_repository_impl.dart';
import '../../features/chat/domain/session_repository.dart';
import '../../features/cloud_voice/data/audio_recorder_port.dart';
import '../../features/cloud_voice/data/cloud_voice_repository_impl.dart';
import '../../features/cloud_voice/data/voice_quota_store.dart';
import '../../features/cloud_voice/domain/cloud_voice_repository.dart';
import '../../features/daily/data/daily_repository_impl.dart';
import '../../features/daily/domain/daily_repository.dart';
import '../../features/keys/data/key_repository_impl.dart';
import '../../features/keys/data/secure_key_store.dart';
import '../../features/keys/domain/key_repository.dart';
import '../../features/onboarding/data/install_repository_impl.dart';
import '../../features/onboarding/domain/install_repository.dart';
import '../../features/plan/data/plan_repository_impl.dart';
import '../../features/plan/domain/plan_repository.dart';
import '../../features/plan/domain/replay_gate.dart';
import '../../features/problem/data/problem_repository_impl.dart';
import '../../features/problem/domain/problem_repository.dart';
import '../../features/settings/data/settings_repository_impl.dart';
import '../../features/settings/domain/settings_repository.dart';
import '../../features/streak/data/streak_repository_impl.dart';
import '../../features/streak/domain/streak_repository.dart';
import '../../features/transcript/data/transcript_repair_repository_impl.dart';
import '../../features/transcript/domain/transcript_repair_repository.dart';
import '../../features/voice/data/mic_rationale_repository_impl.dart';
import '../../features/voice/data/recognition_service_impl.dart';
import '../../features/voice/data/spoken_language_repository_impl.dart';
import '../../features/voice/domain/mic_rationale_repository.dart';
import '../../features/voice/domain/recognition_service.dart';
import '../../features/voice/domain/spoken_language_repository.dart';
import '../config/remote_config_repository.dart';
import '../db/app_database.dart';
import '../device/device_id_platform.dart';
import '../errors/result.dart';
import '../models/wire_enums.dart';
import '../network/dio_client.dart';
import '../network/relay_client.dart';
import '../notifications/notification_service.dart';
import '../queue/outbox_drain_bloc.dart';
import '../queue/outbox_repository.dart';
import '../queue/outbox_repository_impl.dart';
import '../time/trusted_time_anchor_store.dart';
import '../time/trusted_time_platform.dart';
import '../time/trusted_time_source.dart';
import '../time/trusted_time_source_impl.dart';

/// The one `get_it` instance in the app. Resolved with `sl<T>()` in
/// exactly two places: `main()` and a route's `BlocProvider(create:)` —
/// enforced by the `no_service_locator_outside_root` lint
/// (contracts/routes.md's composition-root rule).
final GetIt sl = GetIt.instance;

/// Registers every dependency. `AppDatabase` and `SharedPreferences` are
/// the only two with genuinely async construction, registered with
/// `registerSingletonAsync`; everything else is a `registerLazySingleton`
/// that resolves those two synchronously via `sl<T>()` the first time it
/// is itself resolved — safe because nothing calls this locator before
/// `main()` has awaited [GetIt.allReady].
Future<void> setupLocator() async {
  sl.registerSingletonAsync<SharedPreferences>(SharedPreferences.getInstance);
  sl.registerSingletonAsync<AppDatabase>(() async => AppDatabase());

  sl.registerLazySingleton<TrustedTimePlatform>(
    () => MethodChannelTrustedTimePlatform(),
  );
  sl.registerLazySingleton<DeviceIdPlatform>(() => MethodChannelDeviceIdPlatform());
  sl.registerLazySingleton<TrustedTimeAnchorStore>(
    () => SharedPreferencesTrustedTimeAnchorStore(sl<SharedPreferences>()),
  );
  // Registered under both its concrete type (dio_client.dart's
  // onServerDate hook needs the extra `onServerDate` method) and its
  // interface (everything else depends on the interface only).
  sl.registerLazySingleton<TrustedTimeSourceImpl>(
    () => TrustedTimeSourceImpl(
      platform: sl<TrustedTimePlatform>(),
      anchorStore: sl<TrustedTimeAnchorStore>(),
    ),
  );
  sl.registerLazySingleton<TrustedTimeSource>(
    () => sl<TrustedTimeSourceImpl>(),
  );

  sl.registerLazySingleton<Dio>(
    () =>
        buildDioClient(onServerDate: sl<TrustedTimeSourceImpl>().onServerDate),
  );
  sl.registerLazySingleton<RelayClient>(() => RelayClient(sl<Dio>()));

  sl.registerLazySingleton<RemoteConfigRepository>(
    () => RemoteConfigRepositoryImpl(
      relayClient: sl<RelayClient>(),
      configDao: sl<AppDatabase>().configDao,
      timeSource: sl<TrustedTimeSource>(),
    ),
  );
  sl.registerLazySingleton<InstallRepository>(
    () => InstallRepositoryImpl(
      relayClient: sl<RelayClient>(),
      installDao: sl<AppDatabase>().installDao,
      prefs: sl<SharedPreferences>(),
      timeSource: sl<TrustedTimeSource>(),
      deviceIdPlatform: sl<DeviceIdPlatform>(),
    ),
  );
  sl.registerLazySingleton<ProblemRepository>(
    () => ProblemRepositoryImpl(
      relayClient: sl<RelayClient>(),
      problemDao: sl<AppDatabase>().problemDao,
      timeSource: sl<TrustedTimeSource>(),
      installRepository: sl<InstallRepository>(),
    ),
  );
  sl.registerLazySingleton<KeyRepository>(
    () => KeyRepositoryImpl(
      store: const FlutterSecureKeyStore(),
      relayClient: sl<RelayClient>(),
      installRepository: sl<InstallRepository>(),
      problemRepository: sl<ProblemRepository>(),
      configRepository: sl<RemoteConfigRepository>(),
    ),
  );
  sl.registerLazySingleton<DailyRepository>(
    () => DailyRepositoryImpl(
      problemRepository: sl<ProblemRepository>(),
      sessionDao: sl<AppDatabase>().sessionDao,
      configRepository: sl<RemoteConfigRepository>(),
      timeSource: sl<TrustedTimeSource>(),
    ),
  );
  sl.registerLazySingleton<StreakRepository>(
    () => StreakRepositoryImpl(
      streakDao: sl<AppDatabase>().streakDao,
      timeSource: sl<TrustedTimeSource>(),
    ),
  );
  sl.registerLazySingleton<OutboxRepository>(
    () => OutboxRepositoryImpl(
      outboxDao: sl<AppDatabase>().outboxDao,
      timeSource: sl<TrustedTimeSource>(),
    ),
  );
  // Eager, not lazy: `allReady()` initializes only eagerly-registered async
  // singletons, so a lazy one is still unready when `OutboxDrainBloc` and
  // `SettingsRepository` resolve it synchronously (main.dart's `sl<OutboxDrainBloc>()`).
  sl.registerSingletonAsync<NotificationService>(() async {
    final NotificationService service = NotificationService();
    await service.init();
    return service;
  });
  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(
      database: sl<AppDatabase>(),
      keyRepository: sl<KeyRepository>(),
      notificationService: sl<NotificationService>(),
      prefs: sl<SharedPreferences>(),
    ),
  );
  sl.registerLazySingleton<SessionRepository>(
    () => SessionRepositoryImpl(
      relayClient: sl<RelayClient>(),
      sessionDao: sl<AppDatabase>().sessionDao,
      messageDao: sl<AppDatabase>().messageDao,
      assessmentDao: sl<AppDatabase>().assessmentDao,
      outboxDao: sl<AppDatabase>().outboxDao,
      streakDao: sl<AppDatabase>().streakDao,
      problemRepository: sl<ProblemRepository>(),
      dailyRepository: sl<DailyRepository>(),
      configRepository: sl<RemoteConfigRepository>(),
      keyRepository: sl<KeyRepository>(),
      installRepository: sl<InstallRepository>(),
      timeSource: sl<TrustedTimeSource>(),
      outboxRepository: sl<OutboxRepository>(),
    ),
  );
  sl.registerLazySingleton<TranscriptRepairRepository>(
    () => TranscriptRepairRepositoryImpl(
      relayClient: sl<RelayClient>(),
      keyRepository: sl<KeyRepository>(),
      installRepository: sl<InstallRepository>(),
    ),
  );
  sl.registerLazySingleton<AssessmentRepository>(
    () => AssessmentRepositoryImpl(
      relayClient: sl<RelayClient>(),
      assessmentDao: sl<AppDatabase>().assessmentDao,
      sessionDao: sl<AppDatabase>().sessionDao,
      messageDao: sl<AppDatabase>().messageDao,
      configRepository: sl<RemoteConfigRepository>(),
      keyRepository: sl<KeyRepository>(),
      installRepository: sl<InstallRepository>(),
      timeSource: sl<TrustedTimeSource>(),
      outboxRepository: sl<OutboxRepository>(),
    ),
  );
  sl.registerLazySingleton<SpokenLanguageRepository>(
    () => SpokenLanguageRepositoryImpl(sl<SharedPreferences>()),
  );
  sl.registerLazySingleton<RecognitionService>(
    () => RecognitionServiceImpl(languages: sl<SpokenLanguageRepository>()),
  );
  sl.registerLazySingleton<MicRationaleRepository>(
    () => MicRationaleRepositoryImpl(sl<SharedPreferences>()),
  );
  sl.registerLazySingleton<VoiceQuotaStore>(
    () => VoiceQuotaStore(sl<SharedPreferences>()),
  );
  sl.registerLazySingleton<PlanRepository>(
    () => PlanRepositoryImpl(
      relayClient: sl<RelayClient>(),
      installRepository: sl<InstallRepository>(),
      prefs: sl<SharedPreferences>(),
      voiceQuotaStore: sl<VoiceQuotaStore>(),
    ),
  );
  sl.registerLazySingleton<ReplayGate>(
    () => ReplayGate(
      configRepository: sl<RemoteConfigRepository>(),
      keyRepository: sl<KeyRepository>(),
      planRepository: sl<PlanRepository>(),
    ),
  );
  sl.registerLazySingleton<AudioRecorderPort>(() => RecordAudioRecorder());
  sl.registerLazySingleton<CloudVoiceRepository>(
    () => CloudVoiceRepositoryImpl(
      configRepository: sl<RemoteConfigRepository>(),
      installRepository: sl<InstallRepository>(),
      relayClient: sl<RelayClient>(),
      timeSource: sl<TrustedTimeSource>(),
      store: sl<VoiceQuotaStore>(),
      recorder: sl<AudioRecorderPort>(),
      spokenLanguageRepository: sl<SpokenLanguageRepository>(),
      isOnline: () async {
        final List<ConnectivityResult> results =
            await Connectivity().checkConnectivity();
        return results.any((ConnectivityResult r) => r != ConnectivityResult.none);
      },
      tempDirPath: () async => (await getTemporaryDirectory()).path,
    ),
  );
  sl.registerLazySingleton<OutboxDrainBloc>(
    () => OutboxDrainBloc(
      outboxRepository: sl<OutboxRepository>(),
      relayClient: sl<RelayClient>(),
      messageDao: sl<AppDatabase>().messageDao,
      sessionDao: sl<AppDatabase>().sessionDao,
      assessmentDao: sl<AppDatabase>().assessmentDao,
      timeSource: sl<TrustedTimeSource>(),
      resolveInstallId: () async {
        final result = await sl<InstallRepository>().ensureIdentity();
        return switch (result) {
          Ok(:final value) => value.installId,
          Err() => throw StateError(
            'no install identity to drain the outbox with',
          ),
        };
      },
      resolveKeyedHeaders: (session) async {
        if (session.path != SessionPath.keyed) {
          return (null, null);
        }
        final key = await sl<KeyRepository>().read();
        return (key?.value, key?.providerId ?? session.providerId);
      },
      notificationService: sl<NotificationService>(),
    ),
  );

  await sl.allReady();

  // Delete clips left behind by a crash or a kill mid-upload. Fire and
  // forget; `sweepOrphanClips` swallows its own errors, and the resolve is
  // guarded so a construction failure can never reach startup.
  try {
    unawaited(sl<CloudVoiceRepository>().sweepOrphanClips());
  } catch (_) {}
}
