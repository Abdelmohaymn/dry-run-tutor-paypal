// The Pro Plus reasons of the key prompt (feature 009): their own copy, and a
// third "Get Pro Plus" button only when Pro is on offer. `showKeyPrompt` keeps
// its old bool contract on top of the same dialog.
import 'package:dry_run/core/l10n/generated/app_localizations.dart';
import 'package:dry_run/core/theme/app_theme.dart';
import 'package:dry_run/features/keys/presentation/key_prompt_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Future<void> Function(BuildContext) onTap) => MaterialApp(
      theme: appTheme,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(onPressed: () => onTap(context), child: const Text('open')),
          ),
        ),
      ),
    );

void main() {
  testWidgets('proSessionsUsed shows its own title and body', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app((BuildContext c) => showKeyPromptWithPro(c, KeyPromptReason.proSessionsUsed, offerPro: false)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text("Today's Pro sessions are used"), findsOneWidget);
    expect(find.textContaining('They come back tomorrow (UTC)'), findsOneWidget);
    expect(find.text('Add your key'), findsOneWidget);
  });

  testWidgets('proCapacity shows its own title and body', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app((BuildContext c) => showKeyPromptWithPro(c, KeyPromptReason.proCapacity, offerPro: false)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Pro Plus is at capacity'), findsOneWidget);
    expect(find.textContaining('at capacity for now'), findsOneWidget);
  });

  testWidgets('offerPro adds "Get Pro Plus", which returns getPro', (WidgetTester tester) async {
    KeyPromptChoice? result;
    await tester.pumpWidget(
      _app((BuildContext c) async {
        result = await showKeyPromptWithPro(c, KeyPromptReason.trialConsumed, offerPro: true);
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Get Pro Plus'), findsOneWidget);
    await tester.tap(find.text('Get Pro Plus'));
    await tester.pumpAndSettle();
    expect(result, KeyPromptChoice.getPro);
  });

  testWidgets('without offerPro there is no Pro button', (WidgetTester tester) async {
    await tester.pumpWidget(
      _app((BuildContext c) => showKeyPromptWithPro(c, KeyPromptReason.trialConsumed, offerPro: false)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Get Pro Plus'), findsNothing);
  });

  testWidgets('the primary and dismiss buttons return addKey and dismiss', (WidgetTester tester) async {
    KeyPromptChoice? result;
    await tester.pumpWidget(
      _app((BuildContext c) async {
        result = await showKeyPromptWithPro(c, KeyPromptReason.trialConsumed, offerPro: true);
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add your key'));
    await tester.pumpAndSettle();
    expect(result, KeyPromptChoice.addKey);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(result, KeyPromptChoice.dismiss);
  });

  testWidgets('showKeyPrompt keeps its bool contract', (WidgetTester tester) async {
    bool? chose;
    await tester.pumpWidget(
      _app((BuildContext c) async {
        chose = await showKeyPrompt(c, KeyPromptReason.trialConsumed);
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Get Pro Plus'), findsNothing);
    await tester.tap(find.text('Add your key'));
    await tester.pumpAndSettle();
    expect(chose, isTrue);
  });
}
