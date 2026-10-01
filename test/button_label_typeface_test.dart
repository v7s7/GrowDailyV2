// Button labels keep the app's typeface.
//
// A textStyle: handed to FilledButton / OutlinedButton / TextButton
// .styleFrom does not merge with the theme's button text style, it replaces
// it: ButtonStyleButton takes the widget's value whole, else the theme's,
// else the default. GameTheme's button themes carry the typeface in
// GameTextStyles.labelLarge, so a bare TextStyle(fontSize: 16) there left
// the label with no family at all, drawn in the phone's own font while
// everything around it was IBM Plex Sans Arabic. Found 2026-09-28 on the
// quiet-hours question, then on the three buttons below (the third has
// since been replaced, see its test). Each now puts its size and weight on
// the label's own Text, which merges instead.
//
// The expected family is labelLarge's, not GameTextStyles.fontFamily:
// google_fonts registers every weight as a family of its own, so the
// regular cut is IBMPlexSansArabic_regular while a themed button label is
// IBMPlexSansArabic_700.
//
// Harness built in setUp, never in a test body (see LandingHarness).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/providers/day_clock_provider.dart';
import 'package:grow_daily_v2/core/providers/theme_provider.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_prompts.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_providers.dart';
import 'package:grow_daily_v2/features/app_icon/app_icon_screen.dart';
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

import 'features/app_icon/app_icon_fakes.dart';
import 'helpers/landing_harness.dart';

void main() {
  late LandingHarness h;
  const s = S(Locale('ar'));

  // 35 full days: the grown plant has just opened, so the plant card has
  // something to say, and the Seedling tile can be picked.
  setUp(() async {
    h = LandingHarness();
    await h.prepare(
      extraOverrides: [
        appIconServiceProvider.overrideWithValue(FakeIconPhone()),
        appIconPrefsProvider.overrideWith((ref) => MemIconPrefs()),
        plantGrowthProvider.overrideWith((ref) => MemPlantGrowth()),
        plantFullDaysProvider.overrideWith((ref) async => 35),
        premiumAccessProvider.overrideWithValue(true),
        themePresetProvider.overrideWith((ref) => ThemePresetNotifier('sage')),
        // A fixed day, and no boundary timer left running after the test.
        dayClockProvider.overrideWithValue(DateTime(2026, 9, 25, 14)),
      ],
    );
  });
  tearDown(() => h.dispose());

  /// LandingHarness.app in Arabic, but under the dark theme.
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    double height = 874,
  }) async {
    await tester.binding.setSurfaceSize(Size(402, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: h.container,
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: GameTheme.dark,
          home: home,
        ),
      ),
    );
    await h.settle(tester);
  }

  /// What [label] is drawn with: Text merges its own style into the
  /// DefaultTextStyle the button's Material sets, and hands the result to
  /// its RichText.
  void expectAppTypeface(
    WidgetTester tester,
    String label, {
    required double fontSize,
  }) {
    final style = tester
        .widget<RichText>(
          find.descendant(of: find.text(label), matching: find.byType(RichText)),
        )
        .text
        .style!;
    expect(
      style.fontFamily,
      GameTextStyles.labelLarge.fontFamily,
      reason: '«$label» has lost the theme\'s typeface: a textStyle: in '
          'styleFrom replaces the whole theme style. Put the size on the '
          'label\'s Text instead.',
    );
    expect(style.fontSize, fontSize);
  }

  testWidgets('App Icon: «استخدم هذه الأيقونة»', (tester) async {
    await pump(tester, const AppIconScreen());
    await tester.tap(find.text(s.appIconShapeSeedling));
    await h.settle(tester);
    expectAppTypeface(tester, s.appIconUse, fontSize: 16);
  });

  testWidgets('the plant card: «استخدمها»', (tester) async {
    // The icon's cards only ever run on an iPhone.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pump(
        tester,
        Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => maybeShowIconCard(context, ref),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      // The card waits a beat before it shows.
      await tester.pump(const Duration(seconds: 1));
      await h.settle(tester);
      expectAppTypeface(tester, s.plantGrewUse, fontSize: 16);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // This case was the first habit's «أو اختر خطة جاهزة» link, a TextButton
  // whose styleFrom carried its own textStyle. The three-step page
  // (2026-10-01) took the link away (Plans are a card in the ideas door now),
  // so the TextButton the sheet still has stands in for it: the footer's
  // «رجوع» on the second step, which takes its whole label style from the
  // theme.
  testWidgets('Add Habit: «رجوع»', (tester) async {
    await pump(
      tester,
      Scaffold(body: AddHabitSheet(onBrowsePlans: () {})),
      height: 1400,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField).first, 'قراءة');
    await tester.pump();
    await tester.tap(find.text(s.continueAction));
    await h.settle(tester);
    expect(
      find.ancestor(of: find.text(s.back), matching: find.byType(TextButton)),
      findsOneWidget,
      reason: 'sanity: «رجوع» is the TextButton under test',
    );
    expectAppTypeface(
      tester,
      s.back,
      fontSize: GameTextStyles.labelLarge.fontSize!,
    );
  });
}
