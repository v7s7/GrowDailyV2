// The countdown strip above the Lifetime card, and the card's two offer
// looks (Aziz, 2026-09-22): a sale crosses out the regular price and shows
// the saving; the welcome price says "then" the regular price instead.
//
// The strip's timer must end the offer at zero, exactly once, so the paywall
// can take the price away in the same visit.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/premium/screens/premium_screen.dart';
import 'package:grow_daily_v2/features/premium/widgets/offer_strip.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child,
      {String locale = 'ar'}) async {
    await tester.pumpWidget(MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: GameTheme.dark,
      home: Scaffold(body: Center(child: SizedBox(width: 350, child: child))),
    ));
  }

  testWidgets('more than a day left: days, hours, minutes', (tester) async {
    var now = DateTime(2027, 2, 27, 9);
    await pump(
      tester,
      PremiumOfferStrip(
        title: 'عرض رمضان',
        subtitle: 'ينتهي العرض بعد',
        endsAt: now.add(
            const Duration(days: 2, hours: 14, minutes: 32, seconds: 40)),
        onEnded: () {},
        clock: () => now,
      ),
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('32'), findsOneWidget);
    expect(find.text('يوم'), findsOneWidget);
    expect(find.text('ثانية'), findsNothing);
  });

  testWidgets('the last day: hours, minutes, seconds, ticking', (tester) async {
    var now = DateTime(2027, 3, 9, 18);
    await pump(
      tester,
      PremiumOfferStrip(
        title: 'عرض رمضان',
        subtitle: 'ينتهي العرض بعد',
        endsAt: now.add(const Duration(hours: 5, minutes: 12, seconds: 9)),
        onEnded: () {},
        clock: () => now,
      ),
    );
    expect(find.text('05'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('09'), findsOneWidget);
    expect(find.text('ثانية'), findsOneWidget);
    expect(find.text('يوم'), findsNothing);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('08'), findsOneWidget);
  });

  testWidgets('at zero it stops and ends the offer exactly once',
      (tester) async {
    var now = DateTime(2027, 3, 9, 23, 59, 58);
    var ended = 0;
    await pump(
      tester,
      PremiumOfferStrip(
        title: 'سعر الترحيب',
        subtitle: 'لك أنت، ينتهي بعد',
        endsAt: DateTime(2027, 3, 10),
        onEnded: () => ended++,
        clock: () => now,
      ),
    );
    now = DateTime(2027, 3, 10);
    await tester.pump(const Duration(seconds: 1));
    now = DateTime(2027, 3, 10, 0, 0, 5);
    await tester.pump(const Duration(seconds: 5));
    expect(ended, 1);
  });

  testWidgets('a sale crosses out the regular price and shows the saving',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      PremiumPlanCard(
        label: 'مدى الحياة',
        price: r'$29.99',
        period: 'دفعة واحدة',
        badge: 'الأفضل قيمة',
        chip: '-25%',
        strikePrice: r'$39.99',
        selected: true,
        onTap: () {},
      ),
    );
    expect(find.text('-25%'), findsOneWidget);
    final strike = tester.widget<Text>(find.text(r'$39.99'));
    expect(strike.style?.decoration, TextDecoration.lineThrough);
    // A line through text is invisible to a screen reader, so the regular
    // price is spoken by name.
    expect(find.bySemanticsLabel(r'السعر العادي $39.99'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the welcome price says "then" instead of crossing out',
      (tester) async {
    await pump(
      tester,
      PremiumPlanCard(
        label: 'مدى الحياة',
        price: r'$29.99',
        period: 'دفعة واحدة',
        thenPrice: r'بعدها $39.99',
        selected: true,
        onTap: () {},
      ),
    );
    expect(find.text(r'بعدها $39.99'), findsOneWidget);
    expect(find.text('-25%'), findsNothing);
    final lineThrough = find.byWidgetPredicate((w) =>
        w is Text && w.style?.decoration == TextDecoration.lineThrough);
    expect(lineThrough, findsNothing);
  });
}
