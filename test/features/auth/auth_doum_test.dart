// The language squares at the head of the sign-in screen, where the app icon
// was: Doum in the suit for English on the left and in the thobe for العربية
// on the right (Aziz, 2026-10-02; they replaced the «العربية / EN» pill and the
// one Doum who turned round between the two looks).
//
// What has to hold:
//   1. The screen's measured budget is unchanged: the squares fill the box the
//      gap and the icon took together, so the wordmark and everything under
//      it sit exactly where they did (see auth_screen_composition).
//   2. A square picks its language behind a fade of the screen's words, and
//      its Doum greets.
//   3. Under the launch curtain neither Doum nor the buttons play their
//      entrance unseen: they wait for the curtain to lift.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/auth/screens/auth_screen.dart';
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

  SproutPose doumPose(WidgetTester tester, String code) => tester
      .widget<Sprout>(
        find.descendant(
          of: find.byKey(ValueKey('doum-square-$code')),
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
      // The two squares fill that box, side by side, and each Doum stands
      // inside his own.
      final squares = tester.getRect(find.byType(DoumLanguageSquares));
      expect(squares.top, moreOrLessEquals(0, epsilon: 0.01));
      expect(squares.bottom, moreOrLessEquals(head, epsilon: 0.01));
      expect(squares.left, greaterThanOrEqualTo(24));
      expect(squares.right, lessThanOrEqualTo(size.width - 24));
      for (final code in ['en', 'ar']) {
        final doum = tester.getRect(find.byKey(ValueKey('doum-square-$code')));
        expect(doum.top, greaterThanOrEqualTo(0), reason: code);
        expect(doum.bottom, lessThan(head), reason: code);
      }
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 12));
    });
  }

  testWidgets('both looks are there, each saying hello in his own language',
      (tester) async {
    await pumpAt(tester, const Size(402, 874));
    expect(doumPose(tester, 'en'), SproutPose.langSuitFront);
    expect(doumPose(tester, 'ar'), SproutPose.langThobeFront);
    expect(find.text('Hi'), findsOneWidget);
    expect(find.text('هلا'), findsOneWidget);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets(
      'a square picks its language behind the words, and its Doum greets',
      (tester) async {
    await pumpAt(tester, const Size(402, 874));
    await tester.pump(const Duration(seconds: 3));
    expect(language(), 'en');

    await tester.tap(find.text('العربية'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(wordsOpacity(tester), 0, reason: 'the words go out first');
    expect(language(), 'en');

    await tester.pump(const Duration(milliseconds: 60));
    expect(language(), 'ar');
    await tester.pump();
    expect(doumPose(tester, 'ar'), SproutPose.langThobeGreet);
    expect(doumPose(tester, 'en'), SproutPose.langSuitFront,
        reason: 'the other look stays where it is');
    await tester.pump(const Duration(milliseconds: 400));
    // The harness's app keeps its own locale, so the words come back in it;
    // what matters here is that they come back.
    expect(wordsOpacity(tester), 1, reason: 'and back in');
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets(
      'under the launch curtain the Doums and the buttons wait, and come in '
      'as it lifts', (tester) async {
    harness.container.read(launchCurtainUpProvider.notifier).state = true;
    await pumpAt(tester, const Size(402, 874));
    expect(find.byType(DoumLanguageLook), findsNothing);
    expect(wordsOpacity(tester), 0);

    harness.container.read(launchCurtainUpProvider.notifier).state = false;
    await tester.pump();
    await tester.pump();
    expect(find.byType(DoumLanguageLook), findsNWidgets(2));
    expect(wordsOpacity(tester), 1);
    await tester.pump(const Duration(seconds: 12));
  });
}
