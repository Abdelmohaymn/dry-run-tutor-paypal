import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../config/brand.dart';
import '../config/remote_config_repository.dart';
import '../config/runtime_config.dart';
import '../di/service_locator.dart';
import 'app_route.dart';
import 'placeholder_screen.dart';
import '../../features/assessment/domain/assessment_repository.dart';
import '../../features/assessment/presentation/reveal_screen.dart';
import '../../features/assessment/presentation/verdict_screen.dart';
import '../../features/chat/domain/session_repository.dart';
import '../../features/chat/presentation/confirm_solution_screen.dart';
import '../../features/chat/presentation/daily_screen.dart';
import '../../features/chat/presentation/daily_session_shell.dart';
import '../../features/daily/presentation/review_day_screen.dart';
import '../../features/daily/presentation/withdrawn_screen.dart';
import '../../features/keys/domain/key_repository.dart';
import '../../features/keys/presentation/key_entry_screen.dart';
import '../../features/keys/presentation/wall_screen.dart';
import '../../features/onboarding/domain/install_repository.dart';
import '../../features/onboarding/presentation/mic_rationale_screen.dart';
import '../../features/onboarding/presentation/practice_screen.dart';
import '../../features/onboarding/presentation/seeding_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/plan/domain/plan_repository.dart';
import '../../features/plan/domain/replay_gate.dart';
import '../../features/plan/presentation/plan_cubit.dart';
import '../../features/plan/presentation/plan_screen.dart';
import '../../features/problem/domain/problem_repository.dart';
import '../../features/problem/presentation/problem_picker_screen.dart';
import '../../features/settings/presentation/key_management_screen.dart';
import '../../features/settings/presentation/reminder_screen.dart';
import '../../features/settings/domain/settings_repository.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/wipe_screen.dart';
import '../../features/streak/domain/streak_repository.dart';
import '../../features/streak/presentation/streak_screen.dart';
import '../../features/transcript/presentation/review_screen.dart';
import '../../features/voice/domain/mic_rationale_repository.dart';
import '../../features/voice/domain/recognition_service.dart';
import '../../features/voice/presentation/recognition_unavailable_screen.dart';
import '../../features/voice/presentation/recording_screen.dart';
import '../time/trusted_time_source.dart';
import '../update/update_required_screen.dart';

/// Routes that no guard may redirect away from: the states the guards
/// themselves route *to*, plus settings, so a learner in a strange state
/// is never boxed in (they can always reach wipe-all from here).
final Set<String> _guardExemptRoutes = <String>{
  AppRoute.seeding.path,
  AppRoute.update.path,
  AppRoute.settings.path,
  AppRoute.settingsKey.path,
  AppRoute.settingsReminder.path,
  AppRoute.settingsWipe.path,
};

/// Routes reachable before the welcome carousel has been through once —
/// the carousel itself, the walkthrough it hands off to, and everything
/// already exempt above.
final Set<String> _welcomeExemptRoutes = <String>{
  ..._guardExemptRoutes,
  AppRoute.welcome.path,
  AppRoute.welcomePractice.path,
};

/// Builds the app's one `GoRouter`, carrying the four guards from
/// contracts/routes.md **in order**: `seedGuard`, `updateGuard`,
/// `welcomeGuard`, `practiceGuard`.
/// Every dependency is passed in rather than resolved with `sl<T>()` here —
/// `main()` is the only place that may call `sl<T>()` for this, per the
/// `no_service_locator_outside_root` lint and the composition-root rule
/// (contracts/routes.md).
///
/// Every route not yet built resolves to [PlaceholderScreen]; each
/// user-story phase replaces its own routes' builders with the real
/// screen. `daily`, `sessionRecord`, `sessionReview`,
/// `sessionMicRationale`, and `sessionRecognitionUnavailable` (US1) share
/// one `DailySessionCubit` inside a `ShellRoute` — see
/// `daily_session_shell.dart` for why they can't each own a separate
/// `BlocProvider` the way an independent screen would.
GoRouter buildAppRouter({
  required RemoteConfigRepository configRepository,
  required InstallRepository installRepository,
  required ProblemRepository problemRepository,
  required SessionRepository sessionRepository,
  required AssessmentRepository assessmentRepository,
  required StreakRepository streakRepository,
  required RecognitionService recognitionService,
  required MicRationaleRepository micRationaleRepository,
  required SettingsRepository settingsRepository,
  required TrustedTimeSource timeSource,
  required String currentAppVersion,
  // Feature 009 (Pro Plus). Optional so every existing `buildAppRouter(...)`
  // call in tests keeps compiling; without them the plan is simply absent.
  PlanRepository? planRepository,
  ReplayGate? replayGate,
}) {
  final Set<String> shellPaths = <String>{
    AppRoute.daily.path,
    AppRoute.sessionRecord.path,
    AppRoute.sessionReview.path,
    AppRoute.sessionMicRationale.path,
    AppRoute.sessionRecognitionUnavailable.path,
    // The wall and key entry (US2) need `DailySessionCubit` to survive
    // the visit: the trial→keyed handover (FR-007a/b) and mid-session
    // `InvalidKey` re-entry (FR-005c) both resume the same conversation
    // on return, which only works if the Cubit was never disposed.
    AppRoute.keysWall.path,
    AppRoute.keysEntry.path,
    // Solution confirm, verdict, and reveal (US4) all read the same
    // Cubit's state — none of the three has anything to show if the
    // Cubit that carries the `Assessment` was disposed on the way here.
    AppRoute.sessionConfirmSolution.path,
    AppRoute.sessionVerdict.path,
    AppRoute.sessionReveal.path,
  };

  return GoRouter(
    initialLocation: AppRoute.daily.path,
    redirect: (_, GoRouterState state) =>
        deepLinkLocation(state.uri) ??
        resolveAppRedirect(
          state.matchedLocation,
          configRepository: configRepository,
          installRepository: installRepository,
          problemRepository: problemRepository,
          currentAppVersion: currentAppVersion,
        ),
    routes: <RouteBase>[
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) {
          return DailySessionShell(
            sessionRepository: sessionRepository,
            assessmentRepository: assessmentRepository,
            streakRepository: streakRepository,
            recognitionService: recognitionService,
            configRepository: configRepository,
            micRationaleRepository: micRationaleRepository,
            child: child,
          );
        },
        routes: <RouteBase>[
          GoRoute(
            path: AppRoute.daily.path,
            name: AppRoute.daily.path,
            builder: (_, _) => DailyScreen(
              planRepository: planRepository,
              proOffered: configRepository.cached()?.pro != null,
              replayGate: replayGate,
            ),
          ),
          GoRoute(
            path: AppRoute.problemPicker.path,
            name: AppRoute.problemPicker.path,
            builder: (_, _) =>
                ProblemPickerScreen(problemRepository: problemRepository),
          ),
          GoRoute(
            path: AppRoute.sessionRecord.path,
            name: AppRoute.sessionRecord.path,
            builder: (_, _) => const RecordingScreen(),
          ),
          GoRoute(
            path: AppRoute.sessionReview.path,
            name: AppRoute.sessionReview.path,
            builder: (_, _) => const ReviewScreen(),
          ),
          GoRoute(
            path: AppRoute.sessionMicRationale.path,
            name: AppRoute.sessionMicRationale.path,
            builder: (_, _) => const MicRationaleScreen(),
          ),
          GoRoute(
            path: AppRoute.sessionRecognitionUnavailable.path,
            name: AppRoute.sessionRecognitionUnavailable.path,
            builder: (_, _) => const RecognitionUnavailableScreen(),
          ),
          GoRoute(
            path: AppRoute.keysWall.path,
            name: AppRoute.keysWall.path,
            builder: (_, _) => const WallScreen(),
          ),
          GoRoute(
            path: AppRoute.keysEntry.path,
            name: AppRoute.keysEntry.path,
            builder: (_, _) => const KeyEntryScreen(),
          ),
          GoRoute(
            path: AppRoute.sessionConfirmSolution.path,
            name: AppRoute.sessionConfirmSolution.path,
            builder: (_, _) => const ConfirmSolutionScreen(),
          ),
          GoRoute(
            path: AppRoute.sessionVerdict.path,
            name: AppRoute.sessionVerdict.path,
            builder: (_, _) => VerdictScreen(replayGate: replayGate),
          ),
          GoRoute(
            path: AppRoute.sessionReveal.path,
            name: AppRoute.sessionReveal.path,
            builder: (_, _) => const RevealScreen(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoute.seeding.path,
        name: AppRoute.seeding.path,
        builder: (_, _) => SeedingScreen(
          installRepository: installRepository,
          configRepository: configRepository,
          problemRepository: problemRepository,
        ),
      ),
      GoRoute(
        path: AppRoute.update.path,
        name: AppRoute.update.path,
        builder: (_, _) => UpdateRequiredScreen(
          updateUrl: configRepository.cached()?.updateUrl,
        ),
      ),
      GoRoute(
        path: AppRoute.withdrawn.path,
        name: AppRoute.withdrawn.path,
        builder: (_, _) =>
            WithdrawnScreen(problemRepository: problemRepository),
      ),
      GoRoute(
        path: AppRoute.welcome.path,
        name: AppRoute.welcome.path,
        builder: (_, _) => WelcomeScreen(
          installRepository: installRepository,
          settingsRepository: settingsRepository,
        ),
      ),
      GoRoute(
        path: AppRoute.welcomePractice.path,
        name: AppRoute.welcomePractice.path,
        builder: (_, _) => PracticeScreen(
          recognitionService: recognitionService,
          micRationaleRepository: micRationaleRepository,
          installRepository: installRepository,
          sessionRepository: sessionRepository,
        ),
      ),
      GoRoute(
        path: AppRoute.streak.path,
        name: AppRoute.streak.path,
        builder: (_, _) => StreakScreen(
          streakRepository: streakRepository,
          timeSource: timeSource,
        ),
      ),
      GoRoute(
        path: AppRoute.sessionReviewDay.path,
        name: AppRoute.sessionReviewDay.path,
        builder: (_, _) => ReviewDayScreen(
          sessionRepository: sessionRepository,
          assessmentRepository: assessmentRepository,
          streakRepository: streakRepository,
        ),
      ),
      GoRoute(
        path: AppRoute.settings.path,
        name: AppRoute.settings.path,
        builder: (_, _) => SettingsScreen(planStatus: planRepository?.cached()),
      ),
      GoRoute(
        path: AppRoute.settingsKey.path,
        name: AppRoute.settingsKey.path,
        builder: (_, _) => const KeyManagementScreen(),
      ),
      GoRoute(
        path: AppRoute.settingsPlan.path,
        name: AppRoute.settingsPlan.path,
        builder: (_, _) => BlocProvider<PlanCubit>(
          create: (_) => PlanCubit(
            planRepository!,
            keyRepository: sl<KeyRepository>(),
            configRepository: configRepository,
          ),
          child: const PlanScreen(),
        ),
      ),
      GoRoute(
        path: AppRoute.settingsReminder.path,
        name: AppRoute.settingsReminder.path,
        builder: (_, _) => const ReminderScreen(),
      ),
      GoRoute(
        path: AppRoute.settingsWipe.path,
        name: AppRoute.settingsWipe.path,
        builder: (_, _) => const WipeScreen(),
      ),
      // T127: `dryruntutor://p/<problem_id>` always opens *today's*
      // problem — deliberately not a way into a past day, so the id
      // itself is never read back out of the location. Handles the
      // cold-launch case (Flutter's engine parses the Intent data URI
      // into the initial route on Android); a tap while the app is
      // already running additionally needs native `onNewIntent`
      // forwarding, which is out of scope here.
      GoRoute(path: '/p/:problemId', redirect: (_, _) => AppRoute.daily.path),
      // Feature 009: the PayPal return page offers `dryruntutor://pro/return`.
      // On a cold launch it opens the Plan screen; on a warm one Android brings
      // the app forward and the Plan screen's resume handling does the rest.
      GoRoute(
        path: '/pro/return',
        redirect: (_, _) => AppRoute.settingsPlan.path,
      ),
      for (final AppRoute route in AppRoute.values)
        if (!shellPaths.contains(route.path) &&
            route != AppRoute.welcome &&
            route != AppRoute.welcomePractice &&
            route != AppRoute.streak &&
            route != AppRoute.sessionReviewDay &&
            route != AppRoute.seeding &&
            route != AppRoute.update &&
            route != AppRoute.withdrawn &&
            route != AppRoute.settings &&
            route != AppRoute.settingsKey &&
            route != AppRoute.settingsPlan &&
            route != AppRoute.settingsReminder &&
            route != AppRoute.settingsWipe &&
            route != AppRoute.problemPicker)
          GoRoute(
            path: route.path,
            name: route.path,
            builder: (_, _) => PlaceholderScreen(routeName: route.name),
          ),
    ],
  );
}

/// `dryruntutor://pro/return` parses with `pro` as the host, so go_router
/// would only see `/return` and match nothing. This turns a custom-scheme
/// link back into the app path it names (`/pro/return`, `/p/<id>`); any
/// other URI returns null and goes through the normal guards.
@visibleForTesting
String? deepLinkLocation(Uri uri) {
  if (uri.scheme != AppBrand.deepLinkScheme) return null;
  return '/${uri.host}${uri.path}';
}

/// The guard logic itself, decoupled from `GoRouterState` so it is
/// directly unit-testable (`test/unit/router_guards_test.dart`) without
/// constructing go_router's internal state object or pumping a widget
/// tree — only the matched location string and the four guards' own
/// dependencies matter to the decision.
@visibleForTesting
Future<String?> resolveAppRedirect(
  String location, {
  required RemoteConfigRepository configRepository,
  required InstallRepository installRepository,
  required ProblemRepository problemRepository,
  required String currentAppVersion,
}) async {
  // 1. seedGuard — fires only when there is no cached config AND no
  // cached problem (FR-047). After a single success, a later offline
  // launch never sees this again, because at least one of the two caches
  // is now populated.
  if (location != AppRoute.seeding.path) {
    if (configRepository.cached() == null &&
        !await problemRepository.hasAnyCached()) {
      return AppRoute.seeding.path;
    }
  }

  // 2. updateGuard — evaluated only against a config the app actually
  // has. An unreachable config (cached() == null) must never produce an
  // update wall.
  final RuntimeConfig? config = configRepository.cached();
  if (config != null &&
      location != AppRoute.update.path &&
      location != AppRoute.seeding.path &&
      _isVersionBelow(currentAppVersion, config.minSupportedVersion)) {
    return AppRoute.update.path;
  }

  // 3. welcomeGuard — the one pass through the explanation, before
  // anything else. A redirect rather than a per-screen check is what makes
  // "every entry point" a finite, enumerable list rather than something
  // each screen has to remember. Settings stays exempt, so a learner who
  // lands here in a strange state is never boxed in.
  if (!_welcomeExemptRoutes.contains(location) &&
      !await installRepository.isWelcomeSeen()) {
    return AppRoute.welcome.path;
  }

  // 4. practiceGuard — the walkthrough is marked seen the moment the
  // carousel hands off to it, so `welcomeGuard` above will never send
  // anyone back. A learner who closed the app part-way through would
  // otherwise reopen straight into today's real problem, which is the
  // one thing the walkthrough exists to stand in front of. Same exempt
  // set as the welcome: settings stays reachable, so this is not a trap.
  if (!_welcomeExemptRoutes.contains(location) &&
      await installRepository.isPracticePending()) {
    return AppRoute.welcomePractice.path;
  }

  return null;
}

/// `true` if [current] is strictly below [minimum], comparing
/// `major.minor.patch` numerically. Either string failing to parse never
/// blocks — an update wall must only ever appear because of a real,
/// readable config value, not a parsing accident.
bool _isVersionBelow(String current, String minimum) {
  final List<int>? currentParts = _parseVersion(current);
  final List<int>? minimumParts = _parseVersion(minimum);
  if (currentParts == null || minimumParts == null) {
    return false;
  }
  for (int i = 0; i < 3; i++) {
    if (currentParts[i] != minimumParts[i]) {
      return currentParts[i] < minimumParts[i];
    }
  }
  return false;
}

List<int>? _parseVersion(String version) {
  final List<String> parts = version.split('.');
  if (parts.length < 3) {
    return null;
  }
  final List<int> numbers = <int>[];
  for (int i = 0; i < 3; i++) {
    final int? n = int.tryParse(parts[i]);
    if (n == null) {
      return null;
    }
    numbers.add(n);
  }
  return numbers;
}
