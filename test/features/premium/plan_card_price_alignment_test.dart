// The paywall's price has to sit hard against the card's far edge, and both
// cards' prices have to line up with each other.
//
// What this locks down: the plan card is a Row of [label | gap | price], and
// the price used to be a bare Flexible. A Flexible child is handed a SHARE of
// the row's free space and then painted at the START of that share, so a short
// price like "$4.99" stopped halfway across the card with dead space beyond
// it, while a longer one sat further out. The two cards therefore disagreed
// with each other, and neither touched the edge. An Align pins the child to
// the end of its share instead, which is what these measurements prove.
//
// Measured on the old layout with these same tests, in a 360pt card: the
// monthly price started 68.0pt from the card's edge instead of 14.5, and the
// two cards' prices were 21.2pt out of line with each other.
//
// Measured in BOTH directions on purpose: "the far edge" is the left in
// Arabic and the right in English, and an alignment written as a raw left/
// right (rather than start/end) passes one and fails the other.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/premium/screens/premium_screen.dart';

/// The card's own horizontal padding, from [PremiumPlanCard]'s decoration.
/// The price's outer edge should land on exactly this inset, plus the border,
/// which a BoxDecoration paints INSIDE the box and so insets the content by
/// its own width.
const double kCardPadding = 14;

/// Border widths: the selected card is drawn heavier to show the selection,
/// which pushes its content 1.1pt further in than an unselected card's. That
/// is the design, and it is the only reason the two prices are not pixel
/// identical.
const double kSelectedBorder = 1.6;
const double kUnselectedBorder = 0.5;

/// Slack for one glyph's worth of letter-spacing inside the text box: the
/// price is drawn at -0.8 letterSpacing, which the layout keeps after the
/// final digit.
const double kSlack = 1.5;

void _noop() {}

Future<void> pumpCards(
  WidgetTester tester,
  TextDirection direction, {
  String monthlyPrice = r'$4.99',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Directionality(
        textDirection: direction,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PremiumPlanCard(
                    label: 'مدى الحياة',
                    price: r'$29.99',
                    period: 'دفعة واحدة',
                    badge: 'الأفضل قيمة',
                    caption: 'أرخص من 7 أشهر اشتراك',
                    selected: true,
                    onTap: _noop,
                  ),
                  const SizedBox(height: 10),
                  PremiumPlanCard(
                    label: 'شهري',
                    price: monthlyPrice,
                    period: 'كل شهر',
                    selected: false,
                    onTap: _noop,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('RTL: the price hugs the card left edge, not the middle',
      (tester) async {
    await pumpCards(tester, TextDirection.rtl);

    final card = tester.getRect(find.byType(PremiumPlanCard).last);
    final price = tester.getRect(find.text(r'$4.99'));

    expect(price.left - card.left,
        closeTo(kCardPadding + kUnselectedBorder, kSlack),
        reason: 'the price should start at the card padding, not mid-card');
    // The failure this replaces put the price past the card's midpoint.
    expect(price.left - card.left, lessThan(card.width / 2));
  });

  testWidgets('LTR: the same edge, mirrored', (tester) async {
    await pumpCards(tester, TextDirection.ltr);

    final card = tester.getRect(find.byType(PremiumPlanCard).last);
    final price = tester.getRect(find.text(r'$4.99'));

    expect(card.right - price.right,
        closeTo(kCardPadding + kUnselectedBorder, kSlack),
        reason: 'in English the far edge is the right one');
  });

  testWidgets('both cards line their prices up with each other',
      (tester) async {
    await pumpCards(tester, TextDirection.rtl);

    final lifetime = tester.getRect(find.text(r'$29.99'));
    final monthly = tester.getRect(find.text(r'$4.99'));

    // Within the selected card's heavier border, and nothing else: before
    // the fix these two sat 21.2pt apart, each stopping wherever its own
    // text ran out.
    expect(monthly.left,
        closeTo(lifetime.left, kSelectedBorder - kUnselectedBorder + 0.1),
        reason: 'a short price and a long one share the same starting edge');
  });

  testWidgets('a long store price still lands on the edge', (tester) async {
    // Gulf storefronts render prices like this, and the old layout drifted
    // with the string's width.
    await pumpCards(tester, TextDirection.rtl, monthlyPrice: 'SAR 129.99');

    final card = tester.getRect(find.byType(PremiumPlanCard).last);
    final price = tester.getRect(find.text('SAR 129.99'));

    expect(price.left - card.left,
        closeTo(kCardPadding + kUnselectedBorder, kSlack));
    expect(tester.takeException(), isNull, reason: 'and never overflows');
  });
}
