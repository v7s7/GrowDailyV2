import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/shared/widgets/calendar_month_scaffold.dart';
import 'package:grow_daily_v2/shared/widgets/month_picker_sheet.dart';
import 'package:intl/date_symbol_data_local.dart';

/// The month picker and the header that opens it.
///
/// These exist because the bug they follow was invisible to every kind of
/// test the screen had: the bounds collapsed to a single month, and a
/// header showing one month with two dim arrows looks exactly like a header
/// that is working. The picker is the fix precisely because it makes the
/// whole reachable range visible at once — so what is asserted here is that
/// the range really does reach the screen, in Arabic, with the locked part
/// distinguishable from the free part.
/// ProviderScope is required now, not incidental: the picker sheet watches
/// premiumProvider so that buying Premium from one of its own locked chips
/// repaints it. Before that it subscribed to nothing, and every history
/// picker in the app kept showing padlocks to a customer who had just paid.
Widget _host(Widget child, {String locale = 'ar'}) => ProviderScope(
      child: _app(child, locale: locale),
    );

Widget _app(Widget child, {String locale = 'ar'}) => MaterialApp(
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // DateFormat throws for 'ar' until the locale data is loaded.
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
  });

  group('CalendarMonthHeader', () {
    testWidgets('the title is inert without onTapMonth', (tester) async {
      await tester.pumpWidget(_host(CalendarMonthHeader(
        month: DateTime(2026, 8),
        canGoBack: true,
        canGoForward: false,
        onBack: () {},
        onForward: () {},
      )));
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
    });

    testWidgets('onTapMonth turns the title into a control', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_host(CalendarMonthHeader(
        month: DateTime(2026, 8),
        canGoBack: true,
        canGoForward: false,
        onBack: () {},
        onForward: () {},
        onTapMonth: () => tapped++,
      )));
      // The affordance matters as much as the callback: a title that opens
      // something must not look like a caption.
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.expand_more_rounded));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('Arabic month name, Western year digits', (tester) async {
      await tester.pumpWidget(_host(CalendarMonthHeader(
        month: DateTime(2026, 8),
        canGoBack: true,
        canGoForward: false,
        onBack: () {},
        onForward: () {},
      )));
      // The header used to render "أغسطس ٢٠٢٦" above a card whose every
      // number was ASCII. Arabic month name, Western year.
      expect(find.textContaining('2026'), findsOneWidget);
      expect(find.textContaining('٢٠٢٦'), findsNothing);
    });

    testWidgets('in Arabic the back arrow sits on the right', (tester) async {
      await tester.pumpWidget(_host(CalendarMonthHeader(
        month: DateTime(2026, 8),
        canGoBack: true,
        canGoForward: true,
        onBack: () {},
        onForward: () {},
      )));
      final back = tester.getCenter(find.byIcon(Icons.chevron_left_rounded));
      final forward =
          tester.getCenter(find.byIcon(Icons.chevron_right_rounded));
      // Row reverses child order under RTL, so "older" lands on the right.
      // The glyphs themselves are mirrored by Flutter, since both icons
      // carry matchTextDirection - which is why nothing here flips by hand.
      expect(back.dx, greaterThan(forward.dx));
    });

    testWidgets('in English the back arrow sits on the left', (tester) async {
      await tester.pumpWidget(_host(
        CalendarMonthHeader(
          month: DateTime(2026, 8),
          canGoBack: true,
          canGoForward: true,
          onBack: () {},
          onForward: () {},
        ),
        locale: 'en',
      ));
      final back = tester.getCenter(find.byIcon(Icons.chevron_left_rounded));
      final forward =
          tester.getCenter(find.byIcon(Icons.chevron_right_rounded));
      expect(back.dx, lessThan(forward.dx));
    });
  });

  group('showMonthPicker', () {
    /// Opens the picker over a trivial host and returns whatever it pops.
    Future<DateTime?> open(
      WidgetTester tester, {
      required List<DateTime> months,
      required DateTime selected,
      bool Function(DateTime)? isUnlocked,
      bool Function(DateTime)? hasStory,
    }) async {
      DateTime? result;
      var opened = false;
      await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            opened = true;
            result = await showMonthPicker(
              context,
              months: months,
              selected: selected,
              isUnlocked: isUnlocked ?? (_) => true,
              hasStory: hasStory ?? (_) => true,
            );
          },
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
      return result;
    }

    testWidgets('every month in the range reaches the screen', (tester) async {
      final months = [
        for (var m = 8; m >= 1; m--) DateTime(2026, m),
      ];
      await open(tester, months: months, selected: DateTime(2026, 8));
      expect(find.text(const S(Locale('ar')).monthPickerTitle), findsOneWidget);
      // The whole point of the picker: the range is visible, not inferred
      // from whether an arrow happens to be lit.
      expect(find.text('يناير'), findsOneWidget);
      expect(find.text('أغسطس'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
    });

    testWidgets('months are grouped under their own year', (tester) async {
      final months = [
        DateTime(2026, 2),
        DateTime(2026, 1),
        DateTime(2025, 12),
        DateTime(2025, 11),
      ];
      await open(tester, months: months, selected: DateTime(2026, 2));
      expect(find.text('2026'), findsOneWidget);
      expect(find.text('2025'), findsOneWidget);
      expect(find.text('ديسمبر'), findsOneWidget);
    });

    testWidgets('picking a month pops it back', (tester) async {
      final months = [DateTime(2026, 8), DateTime(2026, 7), DateTime(2026, 6)];
      DateTime? picked;
      await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            picked = await showMonthPicker(
              context,
              months: months,
              selected: DateTime(2026, 8),
              isUnlocked: (_) => true,
              hasStory: (_) => true,
            );
          },
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('يونيو'));
      await tester.pumpAndSettle();
      expect(picked, DateTime(2026, 6));
    });

    testWidgets('a locked month shows a lock and does NOT close the sheet',
        (tester) async {
      // The whole reason a locked cell stays in the grid rather than being
      // hidden: someone who taps it should learn why and still be able to
      // pick a free month without reopening the picker.
      final months = [DateTime(2026, 8), DateTime(2026, 7), DateTime(2026, 3)];
      await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
          onPressed: () => showMonthPicker(
            context,
            months: months,
            selected: DateTime(2026, 8),
            isUnlocked: (m) => m.month >= 7,
            hasStory: (_) => true,
          ),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);

      await tester.tap(find.text('مارس'));
      await tester.pumpAndSettle();
      // Still open.
      expect(find.text(const S(Locale('ar')).monthPickerTitle), findsOneWidget);
      expect(find.text('مارس'), findsOneWidget);
    });

    testWidgets('a month with no story is dimmed, a used one is not',
        (tester) async {
      final months = [DateTime(2026, 8), DateTime(2026, 7)];
      await open(
        tester,
        months: months,
        selected: DateTime(2026, 8),
        hasStory: (m) => m.month == 8,
      );
      // July has nothing recorded, so it is dimmed but still fully usable.
      // Without this, a run of months from before someone started looks
      // identical to months they used, which is what made a broken range
      // impossible to spot in the first place.
      final julyOpacity = tester.widgetList<Opacity>(
        find.ancestor(of: find.text('يوليو'), matching: find.byType(Opacity)),
      );
      expect(julyOpacity.any((o) => o.opacity == 0.55), isTrue);
      final augustOpacity = tester.widgetList<Opacity>(
        find.ancestor(of: find.text('أغسطس'), matching: find.byType(Opacity)),
      );
      expect(augustOpacity.any((o) => o.opacity == 0.55), isFalse);
    });

    testWidgets('English renders English month names', (tester) async {
      DateTime? picked;
      await tester.pumpWidget(_host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showMonthPicker(
                context,
                months: [DateTime(2026, 8), DateTime(2026, 7)],
                selected: DateTime(2026, 8),
                isUnlocked: (_) => true,
                hasStory: (_) => true,
              );
            },
            child: const Text('open'),
          ),
        ),
        locale: 'en',
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('July'), findsOneWidget);
      await tester.tap(find.text('July'));
      await tester.pumpAndSettle();
      expect(picked, DateTime(2026, 7));
    });
  });
}
