import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/screens/auth_screen.dart';

import '../../helpers/landing_harness.dart';

/// Two things about the opening screens that are easy to break and invisible
/// when they are broken.
///
/// REDUCE MOTION. Every entrance on these screens is a fade plus a short
/// rise. Someone who gets motion sickness from that has told their phone so,
/// and until this pass nothing in the app listened on iOS, because the only
/// check anywhere read MediaQuery.disableAnimations, which is Android's flag.
/// The rule the code follows is that the FADE stays and the TRAVEL goes, so
/// what these assert is position: at the first frame, a calm build must
/// already be where it will finish, while a normal build must not be.
///
/// The language picker used to be tested here too. It no longer exists: the
/// app now opens in the phone's own language and offers a LanguageToggle on
/// this screen instead, so there is no picker left to keep calm.
///
/// DARK MODE. The signed-out screen was only ever looked at in light during
/// the redesign. These pump the whole thing under GameTheme.dark to prove it
/// lays out and that the two vendor buttons flip to their dark treatments.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LandingHarness harness;
  const en = S(Locale('en'));

  setUp(() async {
    harness = LandingHarness();
    await harness.prepare();
  });
  tearDown(() => harness.dispose());

  Widget hosted(Widget child, {required bool calm, ThemeData? theme}) {
    // The harness always builds with GameTheme.light, so dark is applied as
    // a nested Theme. context.gp reads Theme.of(context).brightness, so a
    // nested Theme is all the palette needs to flip.
    final themed = theme == null ? child : Theme(data: theme, child: child);
    return harness.app(
      home: MediaQuery(
        // disableAnimations is the flag MediaQuery actually carries, and
        // prefersReducedMotion ORs it with the iOS-only accessibility
        // feature. Setting it here exercises the same branch.
        data: MediaQueryData(disableAnimations: calm),
        child: themed,
      ),
    );
  }

  group('Reduce Motion removes the travel, not the screen', () {
    // Each case pumps its own fresh tree. Pumping a second AuthScreen into
    // the same test reuses the element tree, so flutter_animate's
    // controllers carry over already completed and the second build never
    // animates at all. That cost an hour once; do not merge these.

    testWidgets('calm: the guest button starts where it ends', (tester) async {
      await tester.pumpWidget(hosted(const AuthScreen(), calm: true));
      await tester.pump();
      final atFirstFrame = tester.getRect(find.text(en.tryAsGuest)).top;
      await harness.settle(tester);
      expect(tester.getRect(find.text(en.tryAsGuest)).top, atFirstFrame,
          reason: 'a calm build must not travel at all');
    });

    testWidgets('normal: the guest button does travel', (tester) async {
      // The control. Without it the assertion above would still pass if the
      // slide were removed for everybody, or if getRect stopped seeing the
      // transform at all.
      await tester.pumpWidget(hosted(const AuthScreen(), calm: false));
      await tester.pump();
      final atFirstFrame = tester.getRect(find.text(en.tryAsGuest)).top;
      await harness.settle(tester);
      expect(tester.getRect(find.text(en.tryAsGuest)).top, isNot(atFirstFrame),
          reason: 'the normal build is supposed to slide, so if this fails '
              'the calm assertion has stopped proving anything');
    });

    testWidgets('calm: the cross-fade is kept', (tester) async {
      // Motion goes; the fade is the accessible replacement for it and must
      // survive, or the screen simply appears with no transition. Opacity,
      // not FadeTransition: that is what flutter_animate's FadeEffect builds.
      await tester.pumpWidget(hosted(const AuthScreen(), calm: true));
      await tester.pump();

      // FadeTransition, not Opacity: flutter_animate's FadeEffect builds a
      // FadeTransition, which is a render-object widget and never appears as
      // an Opacity in the tree. Checking the whole tree rather than one
      // button's ancestors, because how it nests its wrappers is its
      // business, not this test's.
      final fading = tester
          .widgetList<FadeTransition>(find.byType(FadeTransition))
          .map((f) => f.opacity.value)
          .where((v) => v < 1.0);
      expect(fading, isNotEmpty,
          reason: 'at the first frame of a calm build the cross-fades should '
              'still be running; if nothing is part-way faded the fade has '
              'been removed along with the movement');

      // flutter_animate schedules a zero-duration Timer from initState to
      // start its controller. Ending the test while it is pending fails with
      // "A Timer is still pending", which reads like an assertion failure and
      // is not one. Settling drains it.
      await harness.settle(tester);
    });
  });

  group('dark mode', () {
    // The Apple button is an iOS/macOS thing. SocialAuthService used to ask
    // dart:io's Platform, which on the Mac running these tests happened to
    // say macOS, so the button appeared by accident of the host. It now
    // asks defaultTargetPlatform (Android under flutter test), so the two
    // tests that are ABOUT the button state the platform they mean. Reset
    // inside the body, not in tearDown: the binding asserts every
    // foundation debug variable is back to null before the test ends.
    Future<void> onIOS(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('the whole screen lays out', (tester) => onIOS(() async {
      await tester.pumpWidget(
        hosted(const AuthScreen(), calm: false, theme: GameTheme.dark),
      );
      await harness.settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(en.continueWithApple), findsOneWidget);
      expect(find.text(en.continueWithEmail), findsOneWidget);
      expect(find.text(en.tryAsGuest), findsOneWidget);
      expect(find.textContaining(en.authAccountLead), findsOneWidget);
    }));

    testWidgets('the Apple button inverts, as its own guidelines require',
        (tester) => onIOS(() async {
      // Apple asks for the treatment that contrasts with the background:
      // black on light, white on dark. Hard-coding black would make the
      // button vanish into this app's dark ground.
      await tester.pumpWidget(
        hosted(const AuthScreen(), calm: false, theme: GameTheme.dark),
      );
      await harness.settle(tester);

      final appleButton = tester.widget<FilledButton>(
        find
            .ancestor(
              of: find.text(en.continueWithApple),
              matching: find.byType(FilledButton),
            )
            .first,
      );
      expect(
        appleButton.style!.backgroundColor!.resolve(<WidgetState>{}),
        const Color(0xFFFFFFFF),
      );
    }));

    testWidgets('the guest button keeps a readable label on the dark ground',
        (tester) async {
      await tester.pumpWidget(
        hosted(const AuthScreen(), calm: false, theme: GameTheme.dark),
      );
      await harness.settle(tester);

      final style = tester
          .widget<FilledButton>(
            find
                .ancestor(
                  of: find.text(en.tryAsGuest),
                  matching: find.byType(FilledButton),
                )
                .first,
          )
          .style!;
      final label = style.foregroundColor!.resolve(<WidgetState>{})!;
      // The label is the theme's own dark ink, and the tonal fill sits on
      // the dark ground, so the pair is the one measured at 13.11:1. Assert
      // it is the light ink rather than re-deriving the arithmetic here.
      expect(label, GameColors.textPrimary);
    });
  });
}
