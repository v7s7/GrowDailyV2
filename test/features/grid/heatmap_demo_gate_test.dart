// The Monthly Heatmap's one paywall affordance.
//
// Every other locked-history surface answers a blocked reach with the
// shared demo sheet: the grid journal, night review history, matrix
// history, the reports hub, the per-habit detail sheet and the month
// picker. The heatmap was the exception, and structurally so: it never
// renders a locked month at all (see _visibleMonths), so it has no chevron
// or locked chip to tap through. Its wall is the top of a scroll list, and
// a scroll end cannot carry a tap handler.
//
// That left one card as the whole paywall story on the screen, and it used
// to jump straight to /premium while the month picker on the SAME screen
// answered the same question with the preview sheet. Two answers to one
// question. What has to stay true is that the card now previews first, and
// that the card is not shown to people who already paid.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/grid/screens/monthly_heatmap_screen.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/premium/screens/premium_screen.dart';

class _Premium extends PremiumNotifier {
  _Premium(bool value) {
    state = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('heatmap_gate_');
    Hive.init(tmp.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  /// Route names pushed during the test, so a bypass straight to the paywall
  /// is observable rather than merely absent from the screen.
  late List<String?> pushed;

  Future<void> pump(WidgetTester tester, {required bool premium}) async {
    pushed = <String?>[];
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        premiumProvider.overrideWith((ref) => _Premium(premium)),
        habitYearHistoryProvider.overrideWith((ref) async => const {}),
      ],
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        onGenerateRoute: (settings) {
          pushed.add(settings.name);
          return MaterialPageRoute(builder: (_) => const Scaffold());
        },
        home: const MonthlyHeatmapScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Walks the month list back to its top.
  ///
  /// The screen deliberately opens at the BOTTOM (newest month) via
  /// _landOnCurrentMonth, and the list is oldest-first, so the upgrade card
  /// sitting above the first month is not merely off-screen: it is outside
  /// the cache extent and never built. Nothing can be found or tapped until
  /// the list is scrolled back up, which is also exactly what a real user
  /// has to do to meet this card at all.
  Future<void> scrollToTop(WidgetTester tester) async {
    final list = find.byType(ListView);
    for (var i = 0; i < 40; i++) {
      await tester.drag(list, const Offset(0, 600));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('free: the upgrade card previews the history instead of '
      'jumping to the paywall', (tester) async {
    const s = S(Locale('ar'));
    await pump(tester, premium: false);
    await scrollToTop(tester);

    final card = find.text(s.heatmapUpgradeTitle);
    expect(card, findsOneWidget,
        reason: 'the card is this screen\'s only "there is more" signal');

    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.text(s.demoGateExample), findsOneWidget,
        reason: 'the reach has to be previewed, not refused');
    expect(pushed, isEmpty,
        reason: 'the card must not bypass the gate straight to /premium');
  });

  testWidgets('free: the gate CTA still reaches the paywall', (tester) async {
    // The preview adds one tap; it must not cost the destination.
    const s = S(Locale('ar'));
    await pump(tester, premium: false);
    await scrollToTop(tester);
    await tester.tap(find.text(s.heatmapUpgradeTitle));
    await tester.pumpAndSettle();

    // The gate's CTA and this screen's card carry the SAME string
    // (demoGateCta == heatmapUpgradeTitle, both "افتح سجلّك الكامل"), so the
    // button has to be targeted by type or the finder matches both.
    await tester.tap(find.widgetWithText(FilledButton, s.demoGateCta));
    await tester.pumpAndSettle();
    // A direct push carrying source/reason now, not the bare named route —
    // the paywall screen itself is the destination to assert on.
    expect(find.byType(PremiumScreen), findsOneWidget);
  });

  testWidgets('premium: no upgrade card at all', (tester) async {
    // Scrolled to the very top before asserting, so this cannot pass just
    // because the card was never built into the viewport.
    const s = S(Locale('ar'));
    await pump(tester, premium: true);
    await scrollToTop(tester);
    expect(find.text(s.heatmapUpgradeTitle), findsNothing);
    expect(find.text(s.demoGateExample), findsNothing);
  });
}
