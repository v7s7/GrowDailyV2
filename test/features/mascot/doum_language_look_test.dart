// Doum turning round into a language's look (Aziz, 2026-10-01, the canvas
// "Doum picks the language"): the sign-in screen's pill and the Settings
// sheet's cards hand him the tap, and the language changes while his back
// is turned. What has to hold:
//
//   1. The language changes at the swap, not at the tap, and the screen's
//      words are out for exactly that moment (DoumLookController.wordsVisible).
//   2. Every frame of the turn stands on the same spot: the side views carry
//      the ghutra or the jacket behind him, and a frame placed by its picture
//      rather than his feet slid him sideways.
//   3. A screen closed mid-turn still gets the language that was asked for.
//   4. Reduce Motion: no turn, the language at once.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/mascot/doum_language_look.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';

/// The commit, in memory (the real one writes the settings box and asks
/// Firebase who is signed in).
Future<void> _inMemory(ProviderContainer c, Locale l) async =>
    c.read(localeProvider.notifier).set(l);

class _Stage extends StatefulWidget {
  const _Stage({
    required this.controller,
    this.startPlain = false,
    this.onTurned,
  });

  final DoumLookController controller;
  final bool startPlain;
  final VoidCallback? onTurned;

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  bool shown = true;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: shown
              ? DoumLanguageLook(
                  height: 150,
                  controller: widget.controller,
                  startPlain: widget.startPlain,
                  onTurned: widget.onTurned,
                )
              : const SizedBox(),
        ),
      );
}

void main() {
  late DoumLookController controller;

  setUp(() => controller = DoumLookController());
  tearDown(() => controller.dispose());

  Future<void> pump(
    WidgetTester tester, {
    Locale start = const Locale('ar'),
    bool reduced = false,
    bool startPlain = false,
    VoidCallback? onTurned,
  }) async {
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
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: _Stage(
              controller: controller,
              startPlain: startPlain,
              onTurned: onTurned,
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

  SproutPose restPose(WidgetTester tester) =>
      tester.widget<Sprout>(find.byType(Sprout)).pose;

  /// The frame the turn is drawing, and whether it is mirrored.
  (SproutPose, bool)? frame(WidgetTester tester) {
    final layer = find.byKey(kDoumTurnKey);
    if (layer.evaluate().isEmpty) return null;
    final image = tester.widget<Image>(
      find.descendant(of: layer, matching: find.byType(Image)),
    );
    final asset =
        ((image.image as ResizeImage).imageProvider as AssetImage).assetName;
    final pose = SproutPose.values.firstWhere((p) => p.asset == asset);
    final mirrored = find
        .descendant(
          of: layer,
          matching: find.byWidgetPredicate(
            (w) => w is Transform && w.transform.storage[0] < 0,
          ),
        )
        .evaluate()
        .isNotEmpty;
    return (pose, mirrored);
  }

  testWidgets('he wears the look of the app\'s language', (tester) async {
    await pump(tester);
    expect(restPose(tester), SproutPose.langThobeFront);
  });

  testWidgets(
      'turns away, swaps behind his back, and lands in the other look '
      'with a hello', (tester) async {
    var turned = 0;
    await pump(tester, onTurned: () => turned++);
    await tester.pump(const Duration(seconds: 3)); // past his pop and hello

    expect(controller.switchTo('en'), isTrue);
    await tester.pump();
    expect(controller.pendingLanguage, 'en',
        reason: 'the switch shows the choice from the tap');
    expect(frame(tester), (SproutPose.langThobeFront, false));

    await tester.pump(const Duration(milliseconds: 120));
    expect(frame(tester), (SproutPose.langThobeThreeQuarter, false));
    await tester.pump(const Duration(milliseconds: 80));
    expect(frame(tester), (SproutPose.langThobeSide, false));
    expect(language(tester), 'ar');
    expect(controller.wordsVisible, isTrue);

    await tester.pump(const Duration(milliseconds: 70)); // 270 ms
    expect(frame(tester), (SproutPose.langThobeBack, false));
    expect(controller.wordsVisible, isFalse,
        reason: 'the words fade a moment before the swap');
    expect(language(tester), 'ar');

    await tester.pump(const Duration(milliseconds: 70)); // 340 ms
    expect(frame(tester), (SproutPose.langSuitBack, false));
    expect(language(tester), 'en', reason: 'the swap changes the language');
    expect(controller.wordsVisible, isTrue);
    expect(controller.pendingLanguage, isNull);

    await tester.pump(const Duration(milliseconds: 80)); // 420
    expect(frame(tester), (SproutPose.langSuitSide, true));
    await tester.pump(const Duration(milliseconds: 80)); // 500
    expect(frame(tester), (SproutPose.langSuitThreeQuarter, true));
    await tester.pump(const Duration(milliseconds: 80)); // 580
    expect(frame(tester), (SproutPose.langSuitFront, false));
    await tester.pump(const Duration(milliseconds: 100)); // 680
    expect(frame(tester), (SproutPose.langSuitJump, false));
    expect(turned, 0);

    await tester.pump(const Duration(milliseconds: 400)); // 1080: landed
    await tester.pump();
    expect(frame(tester), isNull);
    expect(restPose(tester), SproutPose.langSuitGreet);
    expect(turned, 1);
    expect(find.text('Hi'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1700));
    expect(restPose(tester), SproutPose.langSuitFront,
        reason: 'back on his wave after the greeting');
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('the other way: the suit turns away and the thobe greets',
      (tester) async {
    await pump(tester, start: const Locale('en'));
    expect(restPose(tester), SproutPose.langSuitFront);
    controller.switchTo('ar');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 340));
    expect(frame(tester), (SproutPose.langThobeBack, false));
    expect(language(tester), 'ar');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(restPose(tester), SproutPose.langThobeGreet);
    expect(find.text('هلا'), findsOneWidget);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('every frame of the turn stands on the same spot',
      (tester) async {
    await pump(tester);
    final stand = tester.getRect(find.byType(DoumLanguageLook));
    controller.switchTo('en');
    await tester.pump();
    for (var ms = 0; ms < 1040; ms += 10) {
      final f = frame(tester);
      if (f == null) break;
      final (pose, mirrored) = f;
      final layer = find.byKey(kDoumTurnKey);
      final rect = tester.getRect(
        find.descendant(of: layer, matching: find.byType(Image)),
      );
      final cx = kDoumFeetCentre[pose]!;
      final feet = rect.left + (mirrored ? 1 - cx : cx) * rect.width;
      expect(feet, moreOrLessEquals(stand.center.dx, epsilon: 0.5),
          reason: '$pose at $ms ms stands off his spot');
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('one turn at a time: a second tap mid-turn is spent',
      (tester) async {
    await pump(tester);
    controller.switchTo('en');
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.switchTo('ar'), isTrue);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump();
    expect(language(tester), 'en');
    expect(restPose(tester), SproutPose.langSuitGreet);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('closed before his back is turned: the language still changes',
      (tester) async {
    await pump(tester);
    controller.switchTo('en');
    await tester.pump(const Duration(milliseconds: 150));
    expect(language(tester), 'ar');
    final container =
        ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    tester.state<_StageState>(find.byType(_Stage)).setState(() {
      tester.state<_StageState>(find.byType(_Stage)).shown = false;
    });
    await tester.pump();
    await tester.pump();
    expect(container.read(localeProvider).languageCode, 'en');
    expect(controller.wordsVisible, isTrue);
    expect(controller.pendingLanguage, isNull);
  });

  testWidgets('Reduce Motion: no turn, the language at once', (tester) async {
    var turned = 0;
    await pump(tester, reduced: true, onTurned: () => turned++);
    controller.switchTo('en');
    await tester.pump();
    expect(language(tester), 'en');
    expect(frame(tester), isNull);
    expect(restPose(tester), SproutPose.langSuitFront);
    expect(turned, 1);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets(
      'an arrival dresses him: everyday Doum to his look, the language '
      'and the words untouched', (tester) async {
    await pump(tester, startPlain: true);
    expect(restPose(tester), SproutPose.frontWave);
    controller.arriveDressed();
    await tester.pump();
    var wordsEverHidden = false;
    for (var ms = 0; ms < 1100; ms += 20) {
      wordsEverHidden |= !controller.wordsVisible;
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
    expect(wordsEverHidden, isFalse);
    expect(language(tester), 'ar');
    expect(restPose(tester), SproutPose.langThobeGreet);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets(
      'a tap while he is still dressing: he turns into the language just '
      'picked and changes it at the swap', (tester) async {
    await pump(tester, startPlain: true, start: const Locale('en'));
    controller.arriveDressed();
    await tester.pump(); // the turn's clock starts on this frame
    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.switchTo('ar'), isTrue);
    expect(controller.pendingLanguage, 'ar');
    await tester.pump(const Duration(milliseconds: 120)); // 270 ms
    expect(controller.wordsVisible, isFalse);
    await tester.pump(const Duration(milliseconds: 80)); // 350 ms
    expect(language(tester), 'ar');
    expect(frame(tester), (SproutPose.langThobeBack, false));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(restPose(tester), SproutPose.langThobeGreet);
    await tester.pump(const Duration(seconds: 12));
  });

  testWidgets('a language changed some other way changes his look',
      (tester) async {
    await pump(tester);
    ProviderScope.containerOf(tester.element(find.byType(Scaffold)))
        .read(localeProvider.notifier)
        .set(const Locale('en'));
    await tester.pump();
    expect(restPose(tester), SproutPose.langSuitFront);
    await tester.pump(const Duration(seconds: 12));
  });

  test('every language pose has its feet measured', () {
    for (final pose in SproutPose.values) {
      if (pose.file.startsWith('language/')) {
        expect(kDoumFeetCentre[pose], isNotNull, reason: '$pose');
      }
    }
    expect(doumLookFor('ar'), DoumLook.thobe);
    expect(doumLookFor('en'), DoumLook.suit);
  });
}
