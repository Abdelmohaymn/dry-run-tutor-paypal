// The Plan screen (feature 009): what is shown for each plan, that the offer
// follows the relay's switch, and that backing out of PayPal is never styled
// as an error. The cubit is real; only the repository is scripted.
import 'package:dry_run/core/config/runtime_config.dart';
import 'package:dry_run/core/errors/relay_error.dart';
import 'package:dry_run/core/errors/result.dart';
import 'package:dry_run/core/l10n/generated/app_localizations.dart';
import 'package:dry_run/core/theme/app_theme.dart';
import 'package:dry_run/features/keys/domain/learner_key.dart';
import 'package:dry_run/features/plan/domain/plan_status.dart';
import 'package:dry_run/features/plan/presentation/plan_cubit.dart';
import 'package:dry_run/features/plan/presentation/plan_screen.dart';
import 'package:dry_run/features/plan/presentation/widgets/pro_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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

RuntimeConfig _config({ProConfig? pro = _pro}) => RuntimeConfig(
      minSupportedVersion: '1.0.0',
      killedProblemIds: const <String>[],
      chat: const ChatConfig(turnCap: 4, wrapUpAtTurn: 3, minTurnChars: 5),
      trial: const TrialConfig(turnCap: 4),
      keyedProviders: const <String>['groq'],
      pro: pro,
    );

Future<FakePlanRepository> _pump(
  WidgetTester tester, {
  required Result<PlanStatus> refresh,
  PlanStatus? cached,
  ProConfig? pro = _pro,
  bool ownKey = false,
  Result<Uri?>? checkout,
}) async {
  final FakePlanRepository repo = FakePlanRepository(cachedStatus: cached)..refreshResults.add(refresh);
  if (checkout != null) {
    repo.checkoutResults.add(checkout);
  }
  final FakeKeyRepository keys = FakeKeyRepository();
  if (ownKey) {
    keys.storedKey = const LearnerKey(providerId: 'groq', value: 'gsk_x');
  }
  final FakeRemoteConfigRepository config = FakeRemoteConfigRepository()..cachedValue = _config(pro: pro);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: BlocProvider<PlanCubit>(
        create: (_) => PlanCubit(
          repo,
          keyRepository: keys,
          configRepository: config,
          openUrl: (Uri _) async => true,
        ),
        child: const PlanScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('a free learner sees the plan, lifetime usage and the offer', (WidgetTester tester) async {
    await _pump(tester, refresh: Ok<PlanStatus>(freeStatus()));
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Free sessions used: 1 of 3'), findsOneWidget);
    expect(find.text('Voice today: 1 of 5 min'), findsOneWidget);
    expect(find.text('Pro Plus'), findsOneWidget); // the offer heading
    expect(find.text(r'$4.99 / month'), findsOneWidget);
    expect(find.textContaining('5 sessions a day and 15 minutes of voice'), findsOneWidget);
    expect(find.textContaining("PayPal's test environment"), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Subscribe'), findsOneWidget);
    expect(find.text('Manage or cancel in PayPal'), findsNothing);
    expect(find.byType(ProBadge), findsNothing);
  });

  testWidgets('US5-2: the offer is hidden when the relay says it is off', (WidgetTester tester) async {
    await _pump(tester, refresh: Ok<PlanStatus>(freeStatus(offerEnabled: false)), pro: null);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Subscribe'), findsNothing);
    expect(find.text(r'$4.99 / month'), findsNothing);
  });

  testWidgets('US3-3: an own key is named, with a note, and the offer stays', (WidgetTester tester) async {
    await _pump(tester, refresh: Ok<PlanStatus>(freeStatus()), ownKey: true);
    expect(find.text('Your own key'), findsOneWidget);
    expect(find.text('Free'), findsNothing);
    expect(find.textContaining('Your own key is in use'), findsOneWidget);
    expect(find.text('Subscribe'), findsOneWidget);
  });

  testWidgets('the own-key note is not shown when Pro is not on offer', (WidgetTester tester) async {
    await _pump(tester, refresh: Ok<PlanStatus>(freeStatus(offerEnabled: false)), pro: null, ownKey: true);
    expect(find.text('Your own key'), findsOneWidget);
    expect(find.textContaining('Your own key is in use'), findsNothing);
  });

  testWidgets('a Pro learner: name, badge, daily usage, renewal date and Manage', (WidgetTester tester) async {
    await _pump(tester, refresh: Ok<PlanStatus>(proStatus()));
    expect(find.text('Pro Plus'), findsOneWidget);
    expect(find.byType(ProBadge), findsOneWidget);
    expect(find.text('Sessions today: 2 of 5'), findsOneWidget);
    expect(find.text('Voice today: 2 of 15 min'), findsOneWidget);
    expect(find.textContaining('Renews on'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Manage or cancel in PayPal'), findsOneWidget);
    expect(find.text('Subscribe'), findsNothing);
  });

  testWidgets('a cancelled subscription still paid up says when it ends', (WidgetTester tester) async {
    await _pump(
      tester,
      refresh: Ok<PlanStatus>(proStatus(subscription: SubscriptionState.cancelled)),
    );
    expect(find.textContaining('Ends on'), findsOneWidget);
    expect(find.textContaining('Renews on'), findsNothing);
  });

  testWidgets('a suspended subscription says it is not active', (WidgetTester tester) async {
    await _pump(tester, refresh: Ok<PlanStatus>(freeStatus(subscription: SubscriptionState.suspended)));
    expect(find.text('Your Pro Plus subscription is not active.'), findsOneWidget);
    expect(find.text('Subscribe'), findsOneWidget);
  });

  testWidgets('the Pro limits are explained', (WidgetTester tester) async {
    await _pump(tester, refresh: Ok<PlanStatus>(proStatus(proLimit: ProLimit.sessionsUsed)));
    expect(find.textContaining("Today's Pro sessions are used"), findsOneWidget);
  });

  testWidgets('Pro at capacity is not the learner\'s doing', (WidgetTester tester) async {
    await _pump(tester, refresh: Ok<PlanStatus>(proStatus(proLimit: ProLimit.capacity)));
    expect(find.textContaining('at capacity for now'), findsOneWidget);
  });

  testWidgets('a stale plan shows the relay\'s time, not the phone\'s', (WidgetTester tester) async {
    await _pump(
      tester,
      refresh: const Err<PlanStatus>(RelayError.transport()),
      cached: freeStatus(asOf: DateTime.utc(2026, 10, 20, 10)),
    );
    expect(find.textContaining('Last checked'), findsOneWidget);
    expect(find.textContaining('Oct 20'), findsOneWidget);
  });

  testWidgets('a fresh plan shows no "last checked" line', (WidgetTester tester) async {
    await _pump(tester, refresh: Ok<PlanStatus>(freeStatus()));
    expect(find.textContaining('Last checked'), findsNothing);
  });

  testWidgets('with nothing cached and no relay, the screen says so and offers a retry', (WidgetTester tester) async {
    final FakePlanRepository repo = await _pump(tester, refresh: const Err<PlanStatus>(RelayError.transport()));
    expect(find.text("The plan can't be loaded right now."), findsOneWidget);
    repo.refreshResults.add(Ok<PlanStatus>(freeStatus()));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Free'), findsOneWidget);
  });

  testWidgets('a checkout failure is a plain snackbar, not an error style', (WidgetTester tester) async {
    await _pump(
      tester,
      refresh: Ok<PlanStatus>(freeStatus()),
      checkout: const Err<Uri?>(RelayError.unclearRetry()),
    );
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();
    expect(find.text('PayPal is unavailable. Try again later.'), findsOneWidget);
    final SnackBar bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.backgroundColor, isNull, reason: 'no custom, error-coloured background');
  });

  testWidgets('while PayPal is open the screen says to finish there', (WidgetTester tester) async {
    await _pump(
      tester,
      refresh: Ok<PlanStatus>(freeStatus()),
      checkout: Ok<Uri?>(Uri.parse('https://www.sandbox.paypal.com/webapps/billing/subscriptions?ba_token=BA-1')),
    );
    await tester.tap(find.text('Subscribe'));
    await tester.pumpAndSettle();
    expect(find.text('Finish in PayPal, then come back here.'), findsOneWidget);
    expect(find.text('Subscribe'), findsNothing);
  });
}
