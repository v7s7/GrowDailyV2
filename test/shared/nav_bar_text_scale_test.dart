// The bottom bar at the largest accessibility text size.
//
// Reported from a device: a yellow and black overflow stripe across the nav
// bar with Larger Accessibility Sizes turned all the way up. The iOS bar was
// a fixed 60pt box holding a 22pt icon, a 2pt gap and a 10pt label, which
// leaves 48pt of content space after the item's own 6pt vertical margins. At
// iOS's maximum the label alone is over 30pt, so it overflowed by 23.
//
// Note the platform override below, without which none of this tests
// anything: GameNavBar renders Material's self-sizing NavigationBar on
// Android and the app's own glass bar on iOS, a widget test reports Android,
// and the first version of this file passed against the unfixed code.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/shared/widgets/game_nav_bar.dart';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// Runs [body] as if on iOS, and always puts the override back.
  ///
  /// It has to be reset INSIDE the test body: the harness asserts every
  /// foundation debug variable is unset the moment the body returns, which is
  /// before any tearDown runs.
  Future<void> onIOS(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> pumpBar(
    WidgetTester tester, {
    required double scale,
    required Locale locale,
  }) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const Scaffold(
        bottomNavigationBar: GameNavBar(currentIndex: 0),
      ),
    ));
    await tester.pumpAndSettle();
  }

  double barHeight(WidgetTester tester) =>
      tester.getSize(find.byType(GameNavBar)).height;

  // 1.0 is default. 3.1 is iOS AX5, the largest a person can ask for.
  const scales = [1.0, 1.35, 2.0, 2.6, 3.1];

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final tag = locale.languageCode;
    for (final scale in scales) {
      testWidgets('[$tag] the bar does not overflow at ${scale}x',
          (tester) async {
        await onIOS(() async {
          await pumpBar(tester, scale: scale, locale: locale);
          // A RenderFlex overflow reports itself through the error handler
          // rather than by throwing, so pumping clean IS the assertion.
          expect(tester.takeException(), isNull);
        });
      });
    }

    testWidgets('[$tag] every tab is still readable at the largest size',
        (tester) async {
      await onIOS(() async {
        await pumpBar(tester, scale: 3.1, locale: locale);
        final labels = locale.languageCode == 'ar'
            ? ['العادات', 'ملفي', 'المهام']
            : ['Habits', 'Profile', 'Tasks'];
        for (final label in labels) {
          expect(find.text(label), findsOneWidget, reason: '$label vanished');
          expect(tester.getSize(find.text(label)).height, greaterThan(0));
        }
      });
    });
  }

  testWidgets('the bar is the same size at every text scale', (tester) async {
    // This assertion is the one that was missing, and the gap let a real
    // regression through to a device. The first version of this file only
    // compared the bar at 1.0x against the bar at 3.1x and allowed growth, so
    // when a fix replaced the fixed height with an unbounded minHeight the bar
    // expanded to fill the entire screen, the app came up blank, and every
    // test here still passed: a bar pumped into an otherwise empty Scaffold
    // has nothing to crowd out, and "3.1x is not much taller than 1.0x" is
    // true when both are 874 points tall.
    //
    // The label scale is capped instead, so the answer is simply 60 at every
    // size, and an absolute number cannot be satisfied by a bar that ate the
    // screen.
    await onIOS(() async {
      for (final scale in scales) {
        await pumpBar(tester, scale: scale, locale: const Locale('ar'));
        expect(barHeight(tester), closeTo(60 + 8, 0.5),
            reason: '60pt bar plus the SafeArea minimum of 8, at ${scale}x');
      }
    });
  });
}
