import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app.dart';
import 'core/config/remote_config_repository.dart';
import 'core/config/runtime_config.dart';
import 'core/di/service_locator.dart';
import 'core/errors/crash_reporter.dart';
import 'core/queue/outbox_drain_bloc.dart';
import 'core/router/app_router.dart';
import 'core/time/trusted_time_source.dart';
import 'features/assessment/domain/assessment_repository.dart';
import 'features/chat/domain/session_repository.dart';
import 'features/onboarding/domain/install_repository.dart';
import 'features/plan/domain/plan_repository.dart';
import 'features/plan/domain/replay_gate.dart';
import 'features/problem/domain/problem_repository.dart';
import 'features/settings/domain/settings_repository.dart';
import 'features/streak/domain/streak_repository.dart';
import 'features/voice/domain/mic_rationale_repository.dart';
import 'features/voice/domain/recognition_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupLocator();

  // The only two places `sl<T>()` may be called: here, and a route's
  // `BlocProvider(create:)` (contracts/routes.md's composition-root rule,
  // enforced by the `no_service_locator_outside_root` lint).
  //
  // **Nothing on this path awaits a socket.** `hydrateFromCache()` is a
  // single Drift read, so a returning learner's guards see their real
  // config within milliseconds and go straight to today's problem.
  //
  // This used to `await` install → config → manifest here, in sequence,
  // before `runApp`. With `connectTimeout` at 10s and `receiveTimeout` at
  // 75s that held the native splash for as long as the network took to
  // fail — three times over — which made SC-007 ("usable within 3s of
  // launch with the config endpoint unreachable") impossible to meet by
  // construction. `/seeding` already runs this exact sequence with
  // connectivity-driven retry and a designed waiting screen (FR-047a/b,
  // T145), so awaiting it here was duplicated work that could only ever
  // delay the frame.
  final RuntimeConfig? cachedConfig = await sl<RemoteConfigRepository>().hydrateFromCache();

  // A returning learner: refresh in the background so a changed turn cap
  // or model lands, without the frame waiting on it. A genuine first
  // launch (no cached config) is left entirely to `/seeding`, so the
  // install call is not raced by two callers.
  //
  // Completes only when that refresh actually lands, so the router below can
  // re-run its guards against it: a raised `min_supported_version` then walls
  // this launch, not the next one.
  final Completer<void> configRefreshed = Completer<void>();
  if (cachedConfig != null) {
    unawaited(() async {
      try {
        await sl<InstallRepository>().ensureIdentity();
      } catch (_) {
        // Identity is already stored for a returning learner; a failed
        // refresh changes nothing they can see.
      }
      try {
        await sl<RemoteConfigRepository>().load();
        configRefreshed.complete();
      } catch (_) {
        // FR-046 fail open — the hydrated cache above is still in force.
      }
      try {
        await sl<ProblemRepository>().fetchPractice();
      } catch (_) {
        // The warm-up is a prefetch, not a precondition.
      }
    }());
  }

  // The reminder is a one-shot alarm (FR-048b needs an occurrence that can
  // be skipped, which a repeating alarm cannot give), and Android drops
  // every pending alarm on reboot. This is what arms the next one, so a
  // reminder set once keeps arriving daily. Never awaited — it is a
  // preferences read and an alarm registration, and SC-007 gives the frame
  // no time to wait on anything.
  unawaited(sl<SettingsRepository>().restoreReminder());

  // Constructed once, here, so its `connectivity_plus` subscription and
  // the drain-on-launch it triggers exist for the app's whole lifetime —
  // a `registerLazySingleton` never builds it otherwise, since nothing
  // else resolves it directly (T134).
  sl<OutboxDrainBloc>();

  final PackageInfo packageInfo = await PackageInfo.fromPlatform();
  final GoRouter router = buildAppRouter(
    configRepository: sl<RemoteConfigRepository>(),
    installRepository: sl<InstallRepository>(),
    problemRepository: sl<ProblemRepository>(),
    sessionRepository: sl<SessionRepository>(),
    assessmentRepository: sl<AssessmentRepository>(),
    streakRepository: sl<StreakRepository>(),
    recognitionService: sl<RecognitionService>(),
    micRationaleRepository: sl<MicRationaleRepository>(),
    settingsRepository: sl<SettingsRepository>(),
    timeSource: sl<TrustedTimeSource>(),
    currentAppVersion: packageInfo.version,
    planRepository: sl<PlanRepository>(),
    replayGate: sl<ReplayGate>(),
  );

  unawaited(configRefreshed.future.then((_) => router.refresh()));

  // Feature 009. With Pro Plus on, read the plan once the fresh config lands,
  // so a webhook the relay missed heals on the next launch (research.md R-12).
  unawaited(
    configRefreshed.future.then((_) {
      if (sl<RemoteConfigRepository>().cached()?.pro != null) {
        unawaited(sl<PlanRepository>().refresh());
      }
    }),
  );

  // Anything nobody expected gets a popup with a code the learner can send
  // back, instead of a frozen screen and nothing to report.
  CrashReporter(navigatorKey: router.routerDelegate.navigatorKey, appVersion: packageInfo.version).install();

  runApp(App(router: router));
}
