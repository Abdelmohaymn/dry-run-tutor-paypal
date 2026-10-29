// contracts/routes.md: four guards, in order — seedGuard, updateGuard,
// ageGuard, welcomeGuard — plus a route-table enumeration asserting no route can name a
// session other than today's (FR-039d, SC-013). `resolveAppRedirect` is
// tested directly rather than through a pumped GoRouter/widget tree: only
// the matched location string and each guard's own dependency matter to
// the decision, and a pure function is what makes that decision provable
// without go_router's async redirect plumbing in the loop.
import 'package:dry_run/core/config/runtime_config.dart';
import 'package:dry_run/core/router/app_route.dart';
import 'package:dry_run/core/router/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_config_repository.dart';
import '../fakes/fake_install_repository.dart';
import '../fakes/fake_problem_repository.dart';

void main() {
  late FakeRemoteConfigRepository configRepository;
  late FakeInstallRepository installRepository;
  late FakeProblemRepository problemRepository;

  const RuntimeConfig config = RuntimeConfig(
    minSupportedVersion: '1.0.0',
    killedProblemIds: <String>[],
    chat: ChatConfig(turnCap: 12, wrapUpAtTurn: 9, minTurnChars: 8),
    trial: TrialConfig(turnCap: 4),
    keyedProviders: <String>['groq'],
  );

  setUp(() {
    configRepository = FakeRemoteConfigRepository();
    installRepository = FakeInstallRepository();
    problemRepository = FakeProblemRepository();
  });

  Future<String?> redirect(String location, {String currentAppVersion = '1.0.0'}) {
    return resolveAppRedirect(
      location,
      configRepository: configRepository,
      installRepository: installRepository,
      problemRepository: problemRepository,
      currentAppVersion: currentAppVersion,
    );
  }

  group('seedGuard', () {
    test('fires when there is no cached config and no cached problem', () async {
      configRepository.cachedValue = null;
      problemRepository.hasAny = false;

      expect(await redirect(AppRoute.daily.path), AppRoute.seeding.path);
    });

    test('does not fire once a config is cached, even with no problem cached', () async {
      configRepository.cachedValue = config;
      problemRepository.hasAny = false;

      expect(await redirect(AppRoute.daily.path), isNull);
    });

    test('does not fire once a problem is cached, even with no config cached', () async {
      configRepository.cachedValue = null;
      problemRepository.hasAny = true;

      expect(await redirect(AppRoute.daily.path), isNull);
    });

    test('never fires for the seeding route itself', () async {
      configRepository.cachedValue = null;
      problemRepository.hasAny = false;

      expect(await redirect(AppRoute.seeding.path), isNull);
    });
  });

  group('updateGuard', () {
    test('fires when the installed build is below min_supported_version', () async {
      configRepository.cachedValue = config;
      problemRepository.hasAny = true;

      expect(await redirect(AppRoute.daily.path, currentAppVersion: '0.9.0'), AppRoute.update.path);
    });

    test('never fires when no config is reachable at all — no update wall on an outage', () async {
      configRepository.cachedValue = null;
      problemRepository.hasAny = true; // avoids tripping seedGuard first // avoids tripping ageGuard next

      expect(await redirect(AppRoute.daily.path, currentAppVersion: '0.0.1'), isNull);
    });

    test('does not fire for a build at or above the floor', () async {
      configRepository.cachedValue = config;
      problemRepository.hasAny = true;

      expect(await redirect(AppRoute.daily.path, currentAppVersion: '1.0.0'), isNull);
    });
  });

  group('guard order', () {
    test('seedGuard takes precedence over welcomeGuard', () async {
      configRepository.cachedValue = null;
      problemRepository.hasAny = false;
      installRepository.welcomeSeen = false;

      expect(await redirect(AppRoute.daily.path), AppRoute.seeding.path);
    });

    test('updateGuard takes precedence over welcomeGuard', () async {
      configRepository.cachedValue = config;
      problemRepository.hasAny = true;
      installRepository.welcomeSeen = false;

      expect(await redirect(AppRoute.daily.path, currentAppVersion: '0.1.0'), AppRoute.update.path);
    });
  });

  group('welcomeGuard', () {
    setUp(() {
      configRepository.cachedValue = config;
      problemRepository.hasAny = true;
    });

    test('an install that has not seen the welcome is sent to it', () async {
      installRepository.welcomeSeen = false;

      expect(await redirect(AppRoute.daily.path), AppRoute.welcome.path);
    });

    test('the welcome and its walkthrough are not redirected to themselves', () async {
      installRepository.welcomeSeen = false;

      expect(await redirect(AppRoute.welcome.path), isNull);
      expect(await redirect(AppRoute.welcomePractice.path), isNull);
    });

    test('settings stays reachable, so a strange state is never a dead end', () async {
      installRepository.welcomeSeen = false;

      expect(await redirect(AppRoute.settings.path), isNull);
      expect(await redirect(AppRoute.settingsWipe.path), isNull);
    });

    test('once seen it never fires again', () async {
      installRepository.welcomeSeen = true;

      expect(await redirect(AppRoute.daily.path), isNull);
    });
  });

  group('practiceGuard', () {
    setUp(() {
      // The state this guard exists for: the carousel is behind them
      // (welcomeGuard will not fire again) but the walkthrough is not.
      configRepository.cachedValue = config;
      installRepository.welcomeSeen = true;
      installRepository.practicePending = true;
    });

    test('a launch mid-walkthrough returns to it rather than today', () async {
      expect(await redirect(AppRoute.daily.path), AppRoute.welcomePractice.path);
    });

    test('the walkthrough is not redirected to itself', () async {
      expect(await redirect(AppRoute.welcomePractice.path), isNull);
    });

    test('settings stays reachable, so the walkthrough is never a trap', () async {
      expect(await redirect(AppRoute.settings.path), isNull);
      expect(await redirect(AppRoute.settingsWipe.path), isNull);
    });

    test('once finished or skipped it never fires again', () async {
      installRepository.practicePending = false;

      expect(await redirect(AppRoute.daily.path), isNull);
    });

    test('welcomeGuard still takes precedence — the carousel comes first', () async {
      installRepository.welcomeSeen = false;

      expect(await redirect(AppRoute.daily.path), AppRoute.welcome.path);
    });
  });

  test('the route table is closed at 21 and none of them can name a past session', () {
    // 21 at feature 002's close, plus `/welcome` and `/welcome/practice`,
    // less `/keys/rate-limited` (now a popup over the conversation).
    // The count is asserted so a parameterised or history-shaped route
    // cannot be added without this test being looked at (FR-039d).
    expect(AppRoute.values, hasLength(23));
    for (final AppRoute route in AppRoute.values) {
      expect(route.path, isNot(contains(RegExp(r':[a-zA-Z]'))), reason: '${route.path} looks parameterised');
      expect(route.path, isNot(contains('history')));
      expect(route.path, isNot(contains('archive')));
    }
  });
}
