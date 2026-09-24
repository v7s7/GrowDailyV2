// The whole paywall with the offers on (Aziz, 2026-09-22), rendered at
// phone width in Arabic and English with a fake store:
//
//  * the welcome window: $29.99 on the Lifetime card, "then $39.99" under
//    it, the countdown strip, the terms under the buy button, and the window
//    started exactly once;
//  * a sale: the regular price crossed out with the saving, the sale's own
//    name, and its terms;
//  * no offer at all when the store prices do not bear one out (before
//    Lifetime moves to 39.99), when the window has run out, or for someone
//    who is already Premium.
//
// Aziz's own simulator account holds a granted Premium, so it can never
// show these plans; this renders them instead, and fails on any overflow.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/premium/offers/offers_store.dart';
import 'package:grow_daily_v2/features/premium/offers/paywall_offer.dart';
import 'package:grow_daily_v2/features/premium/screens/premium_screen.dart';
import 'package:grow_daily_v2/features/premium/widgets/offer_strip.dart';
import 'package:hive/hive.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

const _ctx = PresentedOfferingContext('default', null, null);

Offering _offering({double regular = 39.99, String regularText = r'$39.99'}) {
  const monthly = Package(
    r'$rc_monthly',
    PackageType.monthly,
    StoreProduct('growdaily_monthly', '', '', 4.99, r'$4.99', 'USD'),
    _ctx,
  );
  final lifetime = Package(
    r'$rc_lifetime',
    PackageType.lifetime,
    StoreProduct('growdaily_lifetime', '', '', regular, regularText, 'USD'),
    _ctx,
  );
  const offer = Package(
    kLifetimeOfferPackageId,
    PackageType.custom,
    StoreProduct('growdaily_lifetime_offer', '', '', 29.99, r'$29.99', 'USD'),
    _ctx,
  );
  return Offering(
    'default',
    '',
    const {},
    [offer, monthly, lifetime],
    monthly: monthly,
    lifetime: lifetime,
  );
}

class _Source {
  _Source({this.config = OffersConfig.fallback, this.started});

  final OffersConfig config;
  DateTime? started;
  int starts = 0;

  PaywallOffersSource get source => PaywallOffersSource(
        loadConfig: () async => config,
        readWelcomeStart: (_) async => started,
        ensureWelcomeStarted: (now, _) async {
          starts++;
          return started ??= now;
        },
      );
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('paywall_offer_screen_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>('box_settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  Future<void> pumpPaywall(
    WidgetTester tester, {
    required Offering offering,
    required _Source source,
    String locale = 'ar',
    bool premium = false,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        premiumProvider.overrideWith((ref) => PremiumNotifier(initial: premium)),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: GameTheme.dark,
        home: PremiumScreen(
          offeringLoader: () async => offering,
          offersSource: source.source,
        ),
      ),
    ));
    // The offering, the offers and the welcome start are all futures;
    // then the entrance animations run for under a second.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Finder struck() => find.byWidgetPredicate((w) =>
      w is Text && w.style?.decoration == TextDecoration.lineThrough);

  testWidgets(r'welcome window: $29.99, then $39.99, countdown and terms',
      (tester) async {
    final src = _Source();
    await pumpPaywall(tester, offering: _offering(), source: src);

    expect(src.starts, 1, reason: 'the window starts on the first open');
    expect(find.byType(PremiumOfferStrip), findsOneWidget);
    expect(find.text('سعر الترحيب'), findsOneWidget);
    expect(find.text(r'$29.99'), findsOneWidget);
    expect(find.text(r'بعدها $39.99'), findsOneWidget);
    expect(struck(), findsNothing,
        reason: 'the welcome price never crosses out a price (W1)');
    expect(find.textContaining(r'سعر الترحيب $29.99 لك أنت حتى'),
        findsOneWidget);
    expect(find.textContaining(r'بعدها يصير السعر $39.99'), findsOneWidget);
    expect(find.text('يوم'), findsOneWidget,
        reason: 'nearly 72 hours left: days, hours, minutes');
  });

  testWidgets('the same in English, left to right', (tester) async {
    await pumpPaywall(tester,
        offering: _offering(), source: _Source(), locale: 'en');
    expect(find.text('Welcome price'), findsOneWidget);
    expect(find.text(r'then $39.99'), findsOneWidget);
    expect(find.textContaining(r'Welcome price $29.99, just for you'),
        findsOneWidget);
  });

  testWidgets('a sale: crossed-out regular price, the saving, its name',
      (tester) async {
    final now = DateTime.now();
    final src = _Source(
      config: OffersConfig(
        sale: SaleWindow(
          id: 'ramadan',
          nameAr: 'عرض رمضان',
          nameEn: 'Ramadan sale',
          startsAt: now.subtract(const Duration(days: 2)),
          endsAt: now.add(const Duration(days: 5)),
        ),
      ),
    );
    await pumpPaywall(tester, offering: _offering(), source: src);

    expect(find.text('عرض رمضان'), findsOneWidget,
        reason: 'the sale ends after the welcome window, so it is shown');
    expect(find.text('-25%'), findsOneWidget);
    expect(struck(), findsOneWidget);
    expect(find.text(r'$39.99'), findsOneWidget);
    expect(find.textContaining(r'سعر العرض $29.99 حتى'), findsOneWidget);
    expect(find.textContaining(r'بعدها يرجع السعر $39.99'), findsOneWidget);
  });

  testWidgets('no offer while the store prices both at 29.99', (tester) async {
    final src = _Source();
    await pumpPaywall(
      tester,
      offering: _offering(regular: 29.99, regularText: r'$29.99'),
      source: src,
    );
    expect(find.byType(PremiumOfferStrip), findsNothing);
    expect(src.starts, 0,
        reason: 'a window must not run down while it can not be shown');
    expect(find.textContaining('بعدها'), findsNothing);
  });

  testWidgets('a spent window never comes back', (tester) async {
    final src = _Source(
      started: DateTime.now().subtract(const Duration(days: 5)),
    );
    await pumpPaywall(tester, offering: _offering(), source: src);
    expect(find.byType(PremiumOfferStrip), findsNothing);
    expect(find.text(r'$39.99'), findsOneWidget);
    expect(find.text(r'$29.99'), findsNothing);
    expect(src.starts, 0);
  });

  testWidgets('no offer and no window for someone already Premium',
      (tester) async {
    final src = _Source();
    await pumpPaywall(tester,
        offering: _offering(), source: src, premium: true);
    expect(find.byType(PremiumOfferStrip), findsNothing);
    expect(src.starts, 0);
  });
}
