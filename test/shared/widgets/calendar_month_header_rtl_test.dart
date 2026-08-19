// Which way the month arrows actually point in Arabic.
//
// This pins a bug that shipped in Matrix History: that screen carried its
// own copy of this header, and the copy wrapped each chevron in a
// `Transform.flip(flipX: true)` under RTL on the theory that `Icon` has no
// RTL mirroring of its own. It does. `Icons.chevron_left_rounded` and
// `chevron_right_rounded` are both declared `matchTextDirection: true`, and
// `Icon.build` mirrors such a glyph itself with a horizontal `scale(-1)`
// whenever the ambient `Directionality` is RTL (widgets/icon.dart). The
// hand flip therefore mirrored an already-mirrored glyph: the arrows landed
// on the correct physical sides — `Row` reverses child order under RTL, so
// "previous" sits at the right edge in Arabic — while pointing the wrong
// way, which is precisely the failure that looks fine in a screenshot
// unless you know which arrow you are looking at.
//
// So position alone is not a sufficient assertion; both bugs and the fix
// agree on position. What separates them is the *net* horizontal scale
// accumulated from the glyph up to the header: mirrored an odd number of
// times (correct under RTL) or an even number (the bug, and correct under
// LTR). That is what these tests measure.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/shared/widgets/calendar_month_scaffold.dart';
import 'package:intl/date_symbol_data_local.dart';

Widget _host(Widget child, {required String locale}) => MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.dark,
      home: Scaffold(body: child),
    );

Widget _header() => CalendarMonthHeader(
      month: DateTime(2026, 8),
      canGoBack: true,
      canGoForward: true,
      onBack: () {},
      onForward: () {},
    );

/// The horizontal scale the glyph for [icon] has accumulated by the time it
/// reaches the header — the product of every mirroring [Transform] between
/// the two, not just the nearest one.
///
/// Reading the transform *around* the [Icon] would not catch the original
/// bug: the hand flip wrapped the Icon from outside while Icon's own flip
/// sat inside it, so either one inspected alone looks correct. Measuring
/// the whole chain is the only way the two cancelling flips are visible.
double _netScaleX(WidgetTester tester, IconData icon) {
  final glyph = tester.renderObject<RenderBox>(
    find.descendant(of: find.byIcon(icon), matching: find.byType(RichText)),
  );
  final header = tester.renderObject<RenderBox>(
    find.byType(CalendarMonthHeader),
  );
  return glyph.getTransformTo(header).entry(0, 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // DateFormat throws for 'ar' until the locale data is loaded.
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  group('CalendarMonthHeader arrow direction', () {
    testWidgets('under RTL each chevron is mirrored exactly once',
        (tester) async {
      await tester.pumpWidget(_host(_header(), locale: 'ar'));

      expect(
        _netScaleX(tester, Icons.chevron_left_rounded),
        lessThan(0),
        reason: 'the previous-month glyph must end up mirrored, so the '
            'left-pointing chevron reads as pointing right in Arabic. A '
            'positive scale means it was flipped twice and cancelled out — '
            'the Transform.flip bug.',
      );
      expect(
        _netScaleX(tester, Icons.chevron_right_rounded),
        lessThan(0),
        reason: 'the next-month glyph is mirrored by the same rule',
      );
    });

    testWidgets('under LTR neither chevron is mirrored', (tester) async {
      await tester.pumpWidget(_host(_header(), locale: 'en'));

      expect(_netScaleX(tester, Icons.chevron_left_rounded), greaterThan(0));
      expect(_netScaleX(tester, Icons.chevron_right_rounded), greaterThan(0));
    });

    testWidgets('the direction is driven by Directionality, not the locale',
        (tester) async {
      // The broken copy took an `isRtl` bool from the app's own `isAr`
      // flag rather than reading Directionality, which is why it could
      // disagree with what Flutter had already done to the glyph. Forcing
      // RTL around an English header proves the mirroring follows the
      // ambient direction on its own.
      await tester.pumpWidget(_host(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: _RtlProbe(),
        ),
        locale: 'en',
      ));

      expect(_netScaleX(tester, Icons.chevron_left_rounded), lessThan(0));
    });

    testWidgets('previous sits on the right in Arabic and the left in English',
        (tester) async {
      // Position is not what the fix changed — both the bug and the fix get
      // this right, because Row reverses child order under RTL. It is
      // asserted so that a future "fix" which corrects the glyph by
      // reordering the children instead fails here.
      await tester.pumpWidget(_host(_header(), locale: 'ar'));
      final rtlPrev = tester.getCenter(find.byIcon(Icons.chevron_left_rounded));
      final rtlNext = tester.getCenter(find.byIcon(Icons.chevron_right_rounded));
      expect(rtlPrev.dx, greaterThan(rtlNext.dx));

      await tester.pumpWidget(_host(_header(), locale: 'en'));
      final ltrPrev = tester.getCenter(find.byIcon(Icons.chevron_left_rounded));
      final ltrNext = tester.getCenter(find.byIcon(Icons.chevron_right_rounded));
      expect(ltrPrev.dx, lessThan(ltrNext.dx));
    });
  });
}

class _RtlProbe extends StatelessWidget {
  const _RtlProbe();

  @override
  Widget build(BuildContext context) => _header();
}
