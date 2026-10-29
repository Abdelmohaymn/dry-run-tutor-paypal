// showReplayLockedPrompt (FR-027): says what the free tier is before anything
// is spent, offers "Get Pro Plus" only when Pro is configured, and pushes the
// right screen for each choice.
import 'package:dry_run/core/config/runtime_config.dart';
import 'package:dry_run/core/l10n/generated/app_localizations.dart';
import 'package:dry_run/core/router/app_route.dart';
import 'package:dry_run/core/theme/app_theme.dart';
import 'package:dry_run/features/plan/domain/replay_gate.dart';
import 'package:dry_run/features/plan/presentation/replay_locked_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../fakes/fake_config_repository.dart';
import '../fakes/fake_key_repository.dart';
import '../fakes/fake_plan_repository.dart';

const ProConfig _pro = ProConfig(
  enabled: true,
  priceLabel: r'$4.99 / month',
  sessionsPerDay: 5,
  voiceSecondsPerDay: 900,
  manageUrl: 'https://www.sandbox.paypal.com/myaccount/autopay/',
);

ReplayGate _gate({required bool proOffered}) {
  final FakeRemoteConfigRepository config = FakeRemoteConfigRepository()
    ..cachedValue = RuntimeConfig(
      minSupportedVersion: '1.0.0',
      killedProblemIds: const <String>[],
      chat: const ChatConfig(turnCap: 4, wrapUpAtTurn: 3, minTurnChars: 5),
      trial: const TrialConfig(turnCap: 4, replayEnabled: false),
      keyedProviders: const <String>['groq'],
      pro: proOffered ? _pro : null,
    );
  return ReplayGate(
    configRepository: config,
    keyRepository: FakeKeyRepository(),
    planRepository: FakePlanRepository(),
  );
}

Future<void> _pump(WidgetTester tester, ReplayGate gate) async {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showReplayLockedPrompt(context, gate),
                child: const Text('tap'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(path: AppRoute.keysEntry.path, builder: (_, _) => const Scaffold(body: Text('KEYS'))),
      GoRoute(path: AppRoute.settingsPlan.path, builder: (_, _) => const Scaffold(body: Text('PLAN'))),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: appTheme,
      routerConfig: router,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
  await tester.tap(find.text('tap'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('says what free practice is, and offers Pro Plus when it is configured', (WidgetTester tester) async {
    await _pump(tester, _gate(proOffered: true));
    expect(find.text('Practice again is part of Pro Plus'), findsOneWidget);
    expect(find.textContaining("Free practice is today's problem, once."), findsOneWidget);
    expect(find.text('Get Pro Plus'), findsOneWidget);
    expect(find.text('Add your key'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('without Pro configured there is only the key', (WidgetTester tester) async {
    await _pump(tester, _gate(proOffered: false));
    expect(find.text('Practice again is part of Pro Plus'), findsOneWidget);
    expect(find.text('Get Pro Plus'), findsNothing);
    expect(find.text('Add your key'), findsOneWidget);
  });

  testWidgets('Get Pro Plus pushes the Plan screen', (WidgetTester tester) async {
    await _pump(tester, _gate(proOffered: true));
    await tester.tap(find.text('Get Pro Plus'));
    await tester.pumpAndSettle();
    expect(find.text('PLAN'), findsOneWidget);
  });

  testWidgets('Add your key pushes key entry', (WidgetTester tester) async {
    await _pump(tester, _gate(proOffered: true));
    await tester.tap(find.text('Add your key'));
    await tester.pumpAndSettle();
    expect(find.text('KEYS'), findsOneWidget);
  });

  testWidgets('Not now pushes nothing', (WidgetTester tester) async {
    await _pump(tester, _gate(proOffered: true));
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('KEYS'), findsNothing);
    expect(find.text('PLAN'), findsNothing);
    expect(find.text('tap'), findsOneWidget);
  });
}
