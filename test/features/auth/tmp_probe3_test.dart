import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/auth/widgets/social_sign_in_buttons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final scale in [1.0, 1.3, 1.5, 2.0]) {
    testWidgets('labels @ ${scale}x', (tester) async {
      const size = Size(390, 844);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final ar = const S(Locale('ar'));
      final en = const S(Locale('en'));

      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: MaterialApp(
          theme: GameTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(children: [
                  SocialSignInButton.apple(
                      label: ar.continueWithApple, onPressed: () {}),
                  SocialSignInButton.google(
                      label: ar.continueWithGoogle, onPressed: () {}),
                  SocialSignInButton.apple(
                      label: en.continueWithApple, onPressed: () {}),
                  // Apple's own approved Continue title, for comparison.
                  SocialSignInButton.apple(
                      label: 'الاستمرار باستخدام Apple', onPressed: () {}),
                ]),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      for (final t in [
        ar.continueWithApple,
        ar.continueWithGoogle,
        en.continueWithApple,
        'الاستمرار باستخدام Apple',
      ]) {
        final f = find.text(t);
        if (f.evaluate().isEmpty) continue;
        final rp = tester.renderObject<RenderParagraph>(f);
        // ignore: avoid_print
        print('[${scale}x] "${t.length > 26 ? t.substring(0, 26) : t}" '
            'TRUNCATED=${rp.didExceedMaxLines} w=${rp.size.width.toStringAsFixed(0)} '
            'h=${rp.size.height.toStringAsFixed(0)}');
      }
      // ignore: avoid_print
      print('[${scale}x] exception=${tester.takeException()}');
    });
  }
}
