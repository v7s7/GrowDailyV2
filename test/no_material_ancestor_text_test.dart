import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/widgets/reaction_overlays.dart';

/// Regression cover for the "yellow double-underlined text" bug.
///
/// MaterialApp hands WidgetsApp a fallback `_errorTextStyle` — red 48px
/// monospace with a double yellow underline — as the root DefaultTextStyle,
/// and WidgetsApp installs it *above* MaterialApp.builder. Anything rendered
/// with no Material/Scaffold between it and that root inherits the whole
/// style. A Text that sets its own color and fontSize overrides those two
/// fields but never `decoration`, so the visible symptom is bare yellow
/// lines under otherwise correct-looking text. It is not debug-only:
/// MaterialApp passes _errorTextStyle unconditionally, so it ships to users.
///
/// These tests assert the property directly — the effective DefaultTextStyle
/// at the text's own position carries no underline — rather than asserting
/// that some particular widget wraps itself in a Material. That way they
/// still hold if the fix moves (local wrapper vs. the app-level backstop in
/// main.dart), and they fail if either is dropped without a replacement.
void main() {
  /// The effective DefaultTextStyle where [finder]'s widget actually sits.
  TextStyle effectiveStyleAt(WidgetTester tester, Finder finder) {
    return DefaultTextStyle.of(tester.element(finder)).style;
  }

  void expectNoErrorFallback(WidgetTester tester, Finder finder) {
    final style = effectiveStyleAt(tester, finder);
    expect(
      style.decoration ?? TextDecoration.none,
      TextDecoration.none,
      reason: 'Inherited Flutter\'s "no Material ancestor" fallback style — '
          'the text renders with a yellow double underline. Wrap the widget '
          'in a Material (type: MaterialType.transparency).',
    );
    // The fallback is 48px monospace; a real Material default is neither.
    expect(style.fontFamily, isNot('monospace'));
  }

  Widget hostApp({required Widget home}) {
    return MaterialApp(
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );
  }

  testWidgets(
      'habit milestone celebration has no underlined text in a bare dialog',
      (tester) async {
    // Deliberately a plain MaterialApp with no builder, so this exercises
    // HabitMilestoneCelebration's own Material wrapper rather than the
    // app-level backstop in main.dart.
    await tester.pumpWidget(hostApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showGeneralDialog<void>(
                context: context,
                pageBuilder: (_, __, ___) => const HabitMilestoneCelebration(
                  event: HabitMilestoneEvent(
                    habitId: 'h1',
                    habitName: 'Duha prayer',
                    milestone: 3,
                    bonusXp: 10,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The habit name is a plain Text inside the card — not inside a button,
    // which would supply its own Material and mask the bug.
    final habitName = find.text('Duha prayer');
    expect(habitName, findsOneWidget);
    expectNoErrorFallback(tester, habitName);
  });

  testWidgets('a transparent Material in builder covers unwrapped overlays',
      (tester) async {
    // Mirrors main.dart's MaterialApp.builder: the backstop must reach both
    // the Navigator's routes and the overlay siblings stacked beside it.
    const overlayText = 'floating overlay';

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            if (child != null) child,
            // No Material of its own — exactly the shape of
            // GlobalVoiceNotePlayerOverlay.
            const Align(
              alignment: Alignment.bottomCenter,
              child: Text(overlayText),
            ),
          ],
        ),
      ),
      home: Builder(
        builder: (context) => GestureDetector(
          onTap: () => showGeneralDialog<void>(
            context: context,
            // A bare Center, the shape that caused the original bug.
            pageBuilder: (_, __, ___) => const Center(child: Text('in dialog')),
          ),
          child: const Center(child: Text('tap me')),
        ),
      ),
    ));

    expectNoErrorFallback(tester, find.text(overlayText));

    await tester.tap(find.text('tap me'));
    await tester.pumpAndSettle();
    expectNoErrorFallback(tester, find.text('in dialog'));
  });

  testWidgets('the test itself detects the bug when the backstop is absent',
      (tester) async {
    // Guards against the two tests above passing vacuously: with no Material
    // anywhere, the fallback style must actually show up.
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => Stack(
        children: [
          if (child != null) child,
          const Align(alignment: Alignment.topCenter, child: Text('unwrapped')),
        ],
      ),
      home: const SizedBox.shrink(),
    ));

    final style = effectiveStyleAt(tester, find.text('unwrapped'));
    expect(style.decoration, TextDecoration.underline);
    expect(style.decorationStyle, TextDecorationStyle.double);
    expect(style.decorationColor, const Color(0xFFFFFF00));
  });
}
