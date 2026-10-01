// Doum at the head of the sign-in screen, where the app icon was (Aziz,
// 2026-10-01, the canvas "Doum picks the language").
//
// What has to hold:
//   1. The screen's measured budget is unchanged: he stands in the box the
//      gap and the icon took together, so the wordmark and everything under
//      it sit exactly where they did (see auth_screen_composition).
//   2. The pill hands its tap to him: it shows the choice at once, and the
//      language changes while his back is turned, the words out for that
//      moment.
//   3. Under the launch curtain neither he nor the buttons play their
//      entrance unseen: they wait for the curtain to lift.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/auth/screens/auth_screen.dart';
import 'package:grow_daily_v2/features/auth/widgets/language_toggle.dart';
import 'package:grow_daily_v2/features/launch/launch_curtain_up.dart';
import 'package:grow_daily_v2/features/mascot/doum_language_look.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';

import '../../helpers/landing_harness.dart';

Future<void> _inMemory(ProviderContainer c, Locale l) async =>
    c.read(localeProvider.notifier).set(l);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LandingHarness harness;
  const en = S(Locale('en'));

  setUp(() async {
    harness = LandingHarness();
    await harness.prepare(
      extraOverrides: [doumLocaleCommitProvider.overrideWithValue(_inMemory)],
    );
  });

  tearDown(() => harness.dispose());

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = size * 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.app(home: const AuthScreen()));
    await tester.pump();
    // flutter_animate starts its entrances from a Timer, so the first long
    // pump only starts them; the second sees them finished.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  String language() =>
      harness.container.read(localeProvider).languageCode;

  /// The screen's words: everything under the wordmark, in one wrapper.
  double wordsOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.text(en.tryAsGuest),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      )
      .opacity;

  SproutPose doumPose(WidgetTester tester) => tester
      .widget<Sprout>(
        find.descendant(
          of: find.byType(DoumLanguageLook),
          matching: find.byType(Sprout),
        ),
      )
      .pose;

  for (final (name, size, head) in const [
    ('tall phone', Size(402, 874), 88.0 + 88.0),
    ('small phone', Size(375, 667), 40.0 + 72.0),
  ]) {
    testWidgets('$name: the wordmark sits where the icon left it',
        (tester) async {
      await pumpAt(tester, size);
      // The gap, the icon's box, and the 18 under it, as before.
      expect(tester.getRect(find.text('Grow Daily')).top, head + 18);
      // He stands in that box, on its floor.
      final doum = tester.getRect(find.byType(DoumLanguageLook));
      expect(doum.bottom, moreOrLessEquals(head, epsilon: 0.01));
      expect(doum.top, greaterThanOrEqualTo(0));
      await tester.pump(const Duration(seconds: 12));
    });
  }

  testWidgets('he wears the language\'s look and says hello', (tester) async {
    await pumpAt(tester, const Size(402, 874));
    expect(doumPose(tester), SproutPose.langSuitFront);
    expect(find.text('Hi'), findsOneWidget);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets(
      'the pill hands him the tap: the choice shows at once, the language '
      'changes behind his back', (tester) async {
    await pumpAt(tester, const Size(402, 874));
    await tester.pump(const Duration(seconds: 3));
    expect(language(), 'en');

    await tester.tap(find.text('العربية'));
    await tester.pump();
    expect(
      tester.widget<LanguageToggle>(find.byType(LanguageToggle)).pending,
      'ar',
    );
    expect(language(), 'en');

    await tester.pump(const Duration(milliseconds: 280));
    expect(wordsOpacity(tester), 0,
        reason: 'the words are out while his back is turned');
    expect(language(), 'en');

    await tester.pump(const Duration(milliseconds: 70));
    expect(language(), 'ar');
    expect(wordsOpacity(tester), 1);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(doumPose(tester), SproutPose.langThobeGreet);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets(
      'under the launch curtain he and the buttons wait, and come in as it '
      'lifts', (tester) async {
    harness.container.read(launchCurtainUpProvider.notifier).state = true;
    await pumpAt(tester, const Size(402, 874));
    expect(find.byType(DoumLanguageLook), findsNothing);
    expect(wordsOpacity(tester), 0);

    harness.container.read(launchCurtainUpProvider.notifier).state = false;
    await tester.pump();
    await tester.pump();
    expect(find.byType(DoumLanguageLook), findsOneWidget);
    expect(wordsOpacity(tester), 1);
    await tester.pump(const Duration(seconds: 12));
  });
}
