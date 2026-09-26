// A Monthly subscriber could not buy Lifetime from the app at all: anyone
// entitled sees «بريميوم مفعّل» and Manage subscription, and the plans are
// hidden (Aziz, 2026-09-25, "do 4"). Now a store subscriber gets the
// regular Lifetime card under it, with the one step the store will not take
// for them (cancelling the Monthly) said before they buy.
//
// Who must NOT see it: a Lifetime owner (nothing left to buy), a hand grant
// (RevenueCat promotional, which is what Aziz's own account and three others
// hold), and anyone whose store serves no Lifetime package.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/core/services/purchase_service.dart';
import 'package:grow_daily_v2/core/theme/game_theme.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';
import 'package:grow_daily_v2/features/premium/offers/offers_store.dart';
import 'package:grow_daily_v2/features/premium/offers/paywall_offer.dart';
import 'package:grow_daily_v2/features/premium/screens/premium_screen.dart';
import 'package:hive/hive.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

const _day = '2026-09-20T00:00:00Z';

CustomerInfo _info({
  required String entitledBy,
  Store store = Store.appStore,
  bool active = true,
}) {
  final ent = EntitlementInfo(
    PurchaseService.entitlementId,
    active,
    true,
    _day,
    _day,
    entitledBy,
    false,
    store: store,
  );
  return CustomerInfo(
    EntitlementInfos(
      {PurchaseService.entitlementId: ent},
      {if (active) PurchaseService.entitlementId: ent},
    ),
    const {},
    [if (active && !isLifetimeProductId(entitledBy)) entitledBy],
    const [],
    const [],
    _day,
    'uid',
    const {},
    _day,
  );
}

const _ctx = PresentedOfferingContext('default', null, null);

Offering _offering({bool withLifetime = true}) {
  const monthly = Package(
    r'$rc_monthly',
    PackageType.monthly,
    StoreProduct('growdaily_monthly', '', '', 4.99, r'$4.99', 'USD'),
    _ctx,
  );
  const lifetime = Package(
    r'$rc_lifetime',
    PackageType.lifetime,
    StoreProduct('growdaily_lifetime', '', '', 29.99, r'$29.99', 'USD'),
    _ctx,
  );
  return Offering(
    'default',
    '',
    const {},
    [monthly, if (withLifetime) lifetime],
    monthly: monthly,
    lifetime: withLifetime ? lifetime : null,
  );
}

void main() {
  group('premiumFromStoreSubscription', () {
    test('a Monthly bought on the App Store or Play: yes', () {
      expect(premiumFromStoreSubscription(_info(entitledBy: 'growdaily_monthly')),
          isTrue);
      expect(
        premiumFromStoreSubscription(_info(
          entitledBy: 'growdaily_monthly',
          store: Store.playStore,
        )),
        isTrue,
      );
    });

    test('Lifetime, either product, with or without a Play option: no', () {
      for (final id in [
        'growdaily_lifetime',
        'growdaily_lifetime_offer',
        'growdaily_lifetime_offer:lifetime',
      ]) {
        expect(premiumFromStoreSubscription(_info(entitledBy: id)), isFalse,
            reason: id);
      }
    });

    test('a hand grant or an unknown store: no', () {
      expect(
        premiumFromStoreSubscription(_info(
          entitledBy: 'rc_promo_Grow Daily Premium_lifetime',
          store: Store.promotional,
        )),
        isFalse,
      );
      expect(
        premiumFromStoreSubscription(_info(
          entitledBy: 'growdaily_monthly',
          store: Store.unknownStore,
        )),
        isFalse,
      );
    });

    test('a Monthly that has run out: no, the paywall sells to them', () {
      expect(
        premiumFromStoreSubscription(
            _info(entitledBy: 'growdaily_monthly', active: false)),
        isFalse,
      );
    });
  });

  group('the Premium page', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('monthly_to_lifetime_');
      Hive.init(tmp.path);
      await Hive.openBox<dynamic>('box_settings');
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    Future<void> pumpPremium(
      WidgetTester tester,
      CustomerInfo info, {
      Offering? offering,
      String locale = 'ar',
    }) async {
      tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          premiumProvider.overrideWith((ref) => PremiumNotifier(initial: true)),
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
            offeringLoader: () async => offering ?? _offering(),
            offersSource: PaywallOffersSource(
              loadConfig: () async => OffersConfig.fallback,
              readWelcomeStart: (_) async => null,
              ensureWelcomeStarted: (now, _) async => now,
            ),
            customerInfoLoader: () async => info,
          ),
        ),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    const ar = S(Locale('ar'));
    const en = S(Locale('en'));

    testWidgets('a Monthly subscriber is offered Lifetime, cancel note first',
        (tester) async {
      await pumpPremium(tester, _info(entitledBy: 'growdaily_monthly'));
      expect(find.text(ar.premiumActive), findsOneWidget);
      expect(find.text(ar.premiumManageSubscription), findsOneWidget);
      expect(find.text(ar.premiumUpgradeTitle), findsOneWidget);
      expect(find.text(r'$29.99'), findsOneWidget);
      expect(find.text(ar.premiumLifetimeBreakEven(7)), findsOneWidget,
          reason: r'29.99 / 4.99 rounds up to 7 months');
      expect(find.text(ar.premiumUpgradeCancelNote), findsOneWidget);
      expect(find.text(ar.premiumUpgradeCta), findsOneWidget);
      // The note comes before the button, so it is read before buying.
      expect(
        tester.getTopLeft(find.text(ar.premiumUpgradeCancelNote)).dy,
        lessThan(tester.getTopLeft(find.text(ar.premiumUpgradeCta)).dy),
      );
      // Never the plan picker's own buy button beside it.
      expect(find.text(ar.premiumCta), findsNothing);
    });

    testWidgets('the button starts a purchase', (tester) async {
      await pumpPremium(tester, _info(entitledBy: 'growdaily_monthly'));
      await tester.ensureVisible(find.text(ar.premiumUpgradeCta));
      await tester.tap(find.text(ar.premiumUpgradeCta));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The SDK is not configured in a test, so a real attempt ends in the
      // error line. A button wired to nothing, or to no package, would stay
      // silent.
      expect(find.text(ar.premiumPurchaseError), findsOneWidget);
    });

    testWidgets('a Lifetime owner is not offered Lifetime', (tester) async {
      await pumpPremium(tester, _info(entitledBy: 'growdaily_lifetime'));
      expect(find.text(ar.premiumLifetimeOwned), findsOneWidget);
      expect(find.text(ar.premiumUpgradeTitle), findsNothing);
      expect(find.text(ar.premiumUpgradeCta), findsNothing);
    });

    testWidgets('a hand grant is not offered Lifetime', (tester) async {
      await pumpPremium(
        tester,
        _info(
          entitledBy: 'rc_promo_Grow Daily Premium_lifetime',
          store: Store.promotional,
        ),
      );
      expect(find.text(ar.premiumActive), findsOneWidget);
      expect(find.text(ar.premiumUpgradeTitle), findsNothing);
    });

    testWidgets('no Lifetime package in the store: no card', (tester) async {
      await pumpPremium(
        tester,
        _info(entitledBy: 'growdaily_monthly'),
        offering: _offering(withLifetime: false),
      );
      expect(find.text(ar.premiumUpgradeTitle), findsNothing);
      expect(find.text(ar.premiumUpgradeCta), findsNothing);
    });

    testWidgets('English renders the same, no overflow', (tester) async {
      await pumpPremium(tester, _info(entitledBy: 'growdaily_monthly'),
          locale: 'en');
      expect(find.text(en.premiumUpgradeTitle), findsOneWidget);
      expect(find.text(en.premiumUpgradeCancelNote), findsOneWidget);
      expect(find.text(en.premiumUpgradeCta), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
