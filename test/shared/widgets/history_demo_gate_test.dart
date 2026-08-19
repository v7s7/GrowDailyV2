import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/shared/widgets/history_demo_gate.dart';

/// The demo gate replaced a SnackBar refusal on every locked-history
/// surface. What has to stay true: the sheet opens, the fake data is
/// unmistakably labelled as an example, and the one button leads to the
/// paywall route. The preview being deterministic (no Random) is what lets
/// these assertions exist at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> open(WidgetTester tester, {String locale = 'ar'}) async {
    String? pushed;
    await tester.pumpWidget(MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.dark,
      onGenerateRoute: (settings) {
        pushed = settings.name;
        return MaterialPageRoute(builder: (_) => const Scaffold());
      },
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showHistoryDemoGate(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    addTearDown(() => pushed = pushed); // silence unused warning paths
    _lastPushed = () => pushed;
  }

  testWidgets('the fake month is stamped as an example, in Arabic',
      (tester) async {
    await open(tester);
    const s = S(Locale('ar'));
    expect(find.text(s.demoGateExample), findsOneWidget);
    expect(find.text(s.demoGatePerfectStamp), findsOneWidget);
    expect(find.text(s.historyLockedBody), findsOneWidget);
  });

  testWidgets('the CTA closes the sheet and opens the paywall route',
      (tester) async {
    await open(tester);
    const s = S(Locale('ar'));
    await tester.tap(find.text(s.demoGateCta));
    await tester.pumpAndSettle();
    expect(_lastPushed!(), '/premium');
    expect(find.text(s.demoGateExample), findsNothing,
        reason: 'sheet must close under the pushed route');
  });

  testWidgets('not-now dismisses without navigating', (tester) async {
    await open(tester);
    const s = S(Locale('ar'));
    await tester.tap(find.text(s.demoGateNotNow));
    await tester.pumpAndSettle();
    expect(_lastPushed!(), isNull);
    expect(find.text(s.demoGateExample), findsNothing);
  });

  testWidgets('renders in English too', (tester) async {
    await open(tester, locale: 'en');
    expect(find.text('EXAMPLE'), findsOneWidget);
    expect(find.text('Unlock your full history'), findsOneWidget);
  });
}

String? Function()? _lastPushed;
