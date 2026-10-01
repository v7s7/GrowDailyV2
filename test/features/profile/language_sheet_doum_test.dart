// Settings › Language with Doum over the two cards (Aziz, 2026-10-01, the
// canvas "Doum picks the language"): picking the other card turns him round
// into its look, the language changing while his back is turned, and the
// sheet closes itself once he has landed, so a change is still one tap.
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
  bool sheetOpen() => find.byType(DoumLanguageLook).evaluate().isNotEmpty;

  testWidgets('fits a small phone with Doum over the cards', (tester) async {
    await open(tester);
    expect(tester.takeException(), isNull);
    expect(sheetOpen(), isTrue);
    expect(
      tester.widget<Sprout>(
        find.descendant(
          of: find.byType(DoumLanguageLook),
          matching: find.byType(Sprout),
        ),
      ).pose,
      SproutPose.langSuitFront,
    );
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets(
      'the other card: he turns, the language changes behind his back, '
      'the sheet closes after he lands', (tester) async {
    await open(tester);
    await tester.tap(find.text('العربية'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(language(), 'en');
    expect(sheetOpen(), isTrue);
    await tester.pump(const Duration(milliseconds: 150));
    expect(language(), 'ar');
    expect(sheetOpen(), isTrue, reason: 'it waits for him to land');
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();
    expect(sheetOpen(), isTrue, reason: 'a moment for his greeting');
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump(const Duration(milliseconds: 500));
    expect(sheetOpen(), isFalse);
    expect(language(), 'ar');
  });

  testWidgets('the card already chosen just closes the sheet', (tester) async {
    await open(tester);
    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(sheetOpen(), isFalse);
    expect(language(), 'en');
  });

  testWidgets('Reduce Motion: the language at once, the sheet closes',
      (tester) async {
    await open(tester, reduced: true);
    await tester.tap(find.text('العربية'));
    await tester.pump();
    expect(language(), 'ar');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(sheetOpen(), isFalse);
  });
}
