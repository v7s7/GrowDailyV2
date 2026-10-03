// The language as two squares, English left and العربية right, Doum in the
// suit and in the thobe, both on screen at once (Aziz, 2026-10-02: "two
// squares ... right and left, this for choosing, so the poses appear", and
// for the greeting "no bow, just hand on chest, and being lovely").
//
// What has to hold:
//   1. Both looks are always shown, in one physical order whichever language
//      the app is in, each Doum saying hello in his own language.
//   2. A tap lights its square at once and changes the language behind the
//      screen's words fading out (DoumLookController.wordsVisible), then the
//      chosen Doum greets: a hand on his chest in the thobe, his wave in the
//      suit, never the bow. The square already chosen only greets.
//   3. Nothing closes or disappears: both squares stay.
//   4. A screen gone inside the fade still gets the language asked for; a
//      busy screen's squares take no tap.
import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/mascot/doum_language_look.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';

Future<void> _inMemory(ProviderContainer c, Locale l) async =>
    c.read(localeProvider.notifier).set(l);

void main() {
  late DoumLookController words;

  setUp(() => words = DoumLookController());
  tearDown(() => words.dispose());

  Future<void> pump(
    WidgetTester tester, {
    Locale start = const Locale('en'),
    bool reduced = false,
    bool enabled = true,
    double height = 176,
    double doumHeight = 118,
    double textScale = 1,
    ValueNotifier<bool>? shown,
  }) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(375, 667) * 3;
    addTearDown(tester.view.reset);
    final visible = shown ?? ValueNotifier(true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...localeProviderOverrides(locale: start, chosen: false),
          doumLocaleCommitProvider.overrideWithValue(_inMemory),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: ref.watch(localeProvider),
            supportedLocales: kSupportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: GameTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: reduced,
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: visible,
                    builder: (_, on, __) => on
                        ? DoumLanguageSquares(
                            height: height,
                            doumHeight: doumHeight,
                            controller: words,
                            enabled: enabled,
                          )
                        : const SizedBox(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String language(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(Scaffold)),
      ).read(localeProvider).languageCode;

  Finder doum(String code) => find.descendant(
        of: find.byKey(ValueKey('doum-square-$code')),
        matching: find.byType(Sprout),
      );

  SproutPose pose(WidgetTester tester, String code) =>
      tester.widget<Sprout>(doum(code)).pose;

  /// Whether a hello is showing: the bubble stays in the tree, faded out,
  /// between hellos.
  bool saying(WidgetTester tester, String hi) =>
      tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.text(hi),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity ==
      1;

  bool chosen(WidgetTester tester, String name) => tester
      .getSemantics(find.bySemanticsLabel(name))
      .hasFlag(SemanticsFlag.isSelected);

  for (final start in const [Locale('en'), Locale('ar')]) {
    testWidgets(
        'in ${start.languageCode}: both looks on screen, English left and '
        'Arabic right, each saying hello in his own language', (tester) async {
      await pump(tester, start: start);
      await tester.pump(const Duration(milliseconds: 600));
      expect(pose(tester, 'en'), SproutPose.langSuitFront);
      expect(pose(tester, 'ar'), SproutPose.langThobeFront);
      expect(
        tester.getCenter(find.text('English')).dx,
        lessThan(tester.getCenter(find.text('العربية')).dx),
      );
      expect(saying(tester, 'Hi'), isTrue);
      expect(saying(tester, 'هلا'), isTrue);
      expect(chosen(tester, start.languageCode == 'ar' ? 'العربية' : 'English'),
          isTrue);
      await tester.pump(const Duration(seconds: 12));
    });
  }

  testWidgets(
      'the other square: chosen at once, the words out, the language changes, '
      'and the thobe Doum puts his hand on his chest', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(seconds: 4));

    await tester.tap(find.text('العربية'));
    await tester.pump();
    expect(chosen(tester, 'العربية'), isTrue, reason: 'lit from the tap');
    expect(chosen(tester, 'English'), isFalse);
    expect(words.wordsVisible, isFalse);
    expect(language(tester), 'en', reason: 'not until the words are out');

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(language(tester), 'ar');
    expect(words.wordsVisible, isTrue);
    expect(pose(tester, 'ar'), SproutPose.langThobeGreet);
    expect(saying(tester, 'هلا'), isTrue);
    expect(saying(tester, 'Hi'), isFalse);
    expect(pose(tester, 'en'), SproutPose.langSuitFront,
        reason: 'the other look stays, nothing disappears');

    await tester.pump(const Duration(milliseconds: 1900));
    expect(pose(tester, 'ar'), SproutPose.langThobeFront,
        reason: 'back on his wave after the greeting');
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('the suit greets with his wave, never the bow', (tester) async {
    await pump(tester, start: const Locale('ar'));
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.text('English'));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(language(tester), 'en');
    expect(saying(tester, 'Hi'), isTrue);
    for (var ms = 0; ms < 2000; ms += 50) {
      expect(pose(tester, 'en'), isNot(SproutPose.langSuitGreet));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 800));
    expect(saying(tester, 'Hi'), isFalse,
        reason: 'his hello comes and goes');
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('the square already chosen only greets', (tester) async {
    await pump(tester, start: const Locale('ar'));
    await tester.pump(const Duration(seconds: 4));
    expect(saying(tester, 'هلا'), isFalse);
    await tester.tap(find.text('العربية'));
    await tester.pump();
    expect(language(tester), 'ar');
    expect(words.wordsVisible, isTrue, reason: 'no change, so no fade');
    expect(pose(tester, 'ar'), SproutPose.langThobeGreet);
    await tester.pump(const Duration(milliseconds: 250));
    expect(saying(tester, 'هلا'), isTrue);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('one change at a time: a second square mid-change is spent',
      (tester) async {
    await pump(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.text('العربية'));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('English'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(language(tester), 'ar');
    expect(chosen(tester, 'العربية'), isTrue);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('gone inside the fade: the language still changes',
      (tester) async {
    final shown = ValueNotifier(true);
    await pump(tester, shown: shown);
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.text('العربية'));
    await tester.pump(const Duration(milliseconds: 40));
    shown.value = false;
    await tester.pump();
    await tester.pump();
    expect(language(tester), 'ar');
    expect(words.wordsVisible, isTrue, reason: 'never left faded out');
  });

  testWidgets('busy: no tap is taken', (tester) async {
    await pump(tester, enabled: false);
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.text('العربية'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(language(tester), 'en');
    expect(chosen(tester, 'English'), isTrue);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('Reduce Motion: the change and the greeting, no hop',
      (tester) async {
    await pump(tester, reduced: true);
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.text('العربية'));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(language(tester), 'ar');
    expect(pose(tester, 'ar'), SproutPose.langThobeGreet);
    await tester.pump(const Duration(seconds: 12));
  });

  for (final (name, height, doumHeight, scale) in const [
    ('tall phone', 176.0, 118.0, 1.0),
    ('small phone', 112.0, 66.0, 1.0),
    ('small phone, large text', 112.0, 66.0, 1.6),
  ]) {
    testWidgets('$name: Doum, his hello and the name fit the square',
        (tester) async {
      await pump(
        tester,
        height: height,
        doumHeight: doumHeight,
        textScale: scale,
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      for (final (code, label, hi) in const [
        ('en', 'English', 'Hi'),
        ('ar', 'العربية', 'هلا'),
      ]) {
        final square = tester.getRect(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        final body = tester.getRect(doum(code));
        final text = tester.getRect(find.text(label));
        final bubble = tester.getRect(find.text(hi));
        expect(body.top, greaterThanOrEqualTo(square.top), reason: code);
        expect(body.bottom, lessThanOrEqualTo(text.top + 1), reason: code);
        expect(text.bottom, lessThanOrEqualTo(square.bottom), reason: code);
        expect(bubble.top, greaterThanOrEqualTo(square.top - 2),
            reason: '$code: his hello stays inside his square');
        expect(bubble.left, greaterThanOrEqualTo(square.left - 2),
            reason: code);
        expect(bubble.right, lessThanOrEqualTo(square.right + 2),
            reason: code);
      }
      await tester.pump(const Duration(seconds: 12));
    });
  }
}
