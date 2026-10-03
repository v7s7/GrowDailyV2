// Settings › Language as the two language squares (Aziz, 2026-10-02): Doum
// in the suit for English and in the thobe for العربية, both on screen.
// Picking a square changes the language and its Doum greets, and the sheet
// STAYS OPEN, so neither look disappears (it used to close itself the moment
// the one Doum had turned).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/mascot/doum_language_look.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';
import 'package:grow_daily_v2/features/profile/screens/profile_screen.dart';

import '../../helpers/landing_harness.dart';

Future<void> _inMemory(ProviderContainer c, Locale l) async =>
    c.read(localeProvider.notifier).set(l);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LandingHarness harness;

  setUp(() async {
    harness = LandingHarness();
    await harness.prepare(
      extraOverrides: [doumLocaleCommitProvider.overrideWithValue(_inMemory)],
    );
  });

  tearDown(() => harness.dispose());

  Future<void> open(WidgetTester tester, {bool reduced = false}) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(375, 667) * 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.app(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(disableAnimations: reduced),
                      child: languageSheetForTest(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  String language() => harness.container.read(localeProvider).languageCode;
  bool sheetOpen() => find.byType(DoumLanguageSquares).evaluate().isNotEmpty;

  SproutPose pose(WidgetTester tester, String code) => tester
      .widget<Sprout>(
        find.descendant(
          of: find.byKey(ValueKey('doum-square-$code')),
          matching: find.byType(Sprout),
        ),
      )
      .pose;

  testWidgets('fits a small phone with both Doums', (tester) async {
    await open(tester);
    expect(tester.takeException(), isNull);
    expect(sheetOpen(), isTrue);
    expect(pose(tester, 'en'), SproutPose.langSuitFront);
    expect(pose(tester, 'ar'), SproutPose.langThobeFront);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets(
      'the other square: the language changes, its Doum greets, and the '
      'sheet stays open', (tester) async {
    await open(tester);
    await tester.tap(find.text('العربية'));
    await tester.pump();
    expect(language(), 'en');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(language(), 'ar');
    expect(pose(tester, 'ar'), SproutPose.langThobeGreet);
    await tester.pump(const Duration(seconds: 3));
    expect(sheetOpen(), isTrue, reason: 'nothing closes on its own');
    expect(pose(tester, 'en'), SproutPose.langSuitFront);
    expect(pose(tester, 'ar'), SproutPose.langThobeFront);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('the square already chosen greets and keeps the sheet',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(sheetOpen(), isTrue);
    expect(language(), 'en');
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('Reduce Motion: the language changes, the sheet stays',
      (tester) async {
    await open(tester, reduced: true);
    await tester.tap(find.text('العربية'));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(language(), 'ar');
    await tester.pump(const Duration(seconds: 1));
    expect(sheetOpen(), isTrue);
    await tester.pump(const Duration(seconds: 12));
  });
}
