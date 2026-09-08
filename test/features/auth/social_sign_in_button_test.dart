import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/widgets/brand_logos.dart';
import 'package:grow_daily_v2/features/auth/widgets/social_sign_in_buttons.dart';

/// These buttons carry two other companies' brands and one App Store rule,
/// so the things worth pinning are the ones that quietly stop being true:
/// the Apple button's colour flipping with the theme (Apple's HIG asks for
/// contrast, not for black), the logo staying on the leading edge in Arabic,
/// and the loading state not resizing the button under someone's thumb.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Never reach the network for a typeface inside a test.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget host(
    Widget child, {
    ThemeData? theme,
    TextDirection direction = TextDirection.ltr,
  }) {
    return MaterialApp(
      theme: theme ?? GameTheme.light,
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Center(
            child: SizedBox(width: 320, child: child),
          ),
        ),
      ),
    );
  }

  group('SocialSignInButton', () {
    testWidgets('shows the label and the Google mark', (tester) async {
      await tester.pumpWidget(
        host(
          SocialSignInButton.google(
            label: 'Continue with Google',
            onPressed: () {},
          ),
        ),
      );

      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.byType(GoogleLogo), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('matches the app button height so the column does not jog',
        (tester) async {
      await tester.pumpWidget(
        host(
          SocialSignInButton.google(label: 'Google', onPressed: () {}),
        ),
      );

      // 52 is the theme's own FilledButton minimumSize. A social button that
      // does not match it makes the auth screen look assembled rather than
      // designed.
      expect(
        tester.getSize(find.byType(SocialSignInButton)).height,
        52,
      );
    });

    testWidgets('loading swaps the label for a spinner at the same height',
        (tester) async {
      await tester.pumpWidget(
        host(
          SocialSignInButton.google(
            label: 'Continue with Google',
            onPressed: () {},
            loading: true,
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Continue with Google'), findsNothing);
      expect(find.byType(GoogleLogo), findsNothing);
      // The whole point of reserving the height: no reflow mid-tap.
      expect(tester.getSize(find.byType(SocialSignInButton)).height, 52);
    });

    testWidgets('a loading button cannot be tapped again', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          SocialSignInButton.google(
            label: 'Google',
            onPressed: () => taps++,
            loading: true,
          ),
        ),
      );

      await tester.tap(find.byType(SocialSignInButton));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('a null callback disables it', (tester) async {
      await tester.pumpWidget(
        host(
          const SocialSignInButton.google(label: 'Google', onPressed: null),
        ),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.enabled, isFalse);
    });

    group('Apple button colour', () {
      // Apple's HIG allows black, white or white-with-outline and asks for
      // the one that contrasts with the background. Hard-coding black would
      // make the button vanish into this app's dark theme, which is the
      // default one.
      testWidgets('is black on a light background', (tester) async {
        await tester.pumpWidget(
          host(
            SocialSignInButton.apple(label: 'Apple', onPressed: () {}),
            theme: GameTheme.light,
          ),
        );

        final style = tester
            .widget<FilledButton>(find.byType(FilledButton))
            .style!;
        expect(
          style.backgroundColor!.resolve({}),
          Colors.black,
        );
        expect(style.foregroundColor!.resolve({}), Colors.white);
      });

      testWidgets('flips to white on a dark background', (tester) async {
        await tester.pumpWidget(
          host(
            SocialSignInButton.apple(label: 'Apple', onPressed: () {}),
            theme: GameTheme.dark,
          ),
        );

        final style = tester
            .widget<FilledButton>(find.byType(FilledButton))
            .style!;
        expect(style.backgroundColor!.resolve({}), Colors.white);
        expect(style.foregroundColor!.resolve({}), Colors.black);
      });
    });

    group('direction', () {
      // The logo is placed with PositionedDirectional and the label padded
      // with EdgeInsetsDirectional. Swap either for the non-directional
      // version and English still looks perfect while Arabic, which is half
      // this app's users, gets a logo overlapping its own label.
      testWidgets('logo sits on the left in English', (tester) async {
        await tester.pumpWidget(
          host(
            SocialSignInButton.google(label: 'Continue', onPressed: () {}),
          ),
        );

        final button = tester.getRect(find.byType(SocialSignInButton));
        final logo = tester.getRect(find.byType(GoogleLogo));
        expect(logo.center.dx, lessThan(button.center.dx));
      });

      testWidgets('logo sits on the right in Arabic', (tester) async {
        await tester.pumpWidget(
          host(
            SocialSignInButton.google(label: 'متابعة', onPressed: () {}),
            direction: TextDirection.rtl,
          ),
        );

        final button = tester.getRect(find.byType(SocialSignInButton));
        final logo = tester.getRect(find.byType(GoogleLogo));
        expect(logo.center.dx, greaterThan(button.center.dx));
      });

      testWidgets('the mark keeps its own size and is never flipped',
          (tester) async {
        // A mirrored brand mark is a real trademark problem, not a cosmetic
        // one. CustomPaint does not mirror on its own, so this guards
        // against someone later "fixing" RTL with a Transform.
        for (final direction in TextDirection.values) {
          await tester.pumpWidget(
            host(
              SocialSignInButton.google(label: 'x', onPressed: () {}),
              direction: direction,
            ),
          );
          expect(tester.getSize(find.byType(GoogleLogo)), const Size(18, 18));
          expect(
            find.ancestor(
              of: find.byType(GoogleLogo),
              matching: find.byType(Transform),
            ),
            findsNothing,
            reason: 'a Transform above the mark in $direction could flip it',
          );
        }
      });
    });
  });

  group('LabelledDivider', () {
    testWidgets('puts the word between two rules', (tester) async {
      await tester.pumpWidget(host(const LabelledDivider(label: 'or')));

      expect(find.text('or'), findsOneWidget);
      expect(find.byType(Divider), findsNWidgets(2));
    });
  });
}
