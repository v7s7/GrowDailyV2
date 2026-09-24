// A lifetime owner whose Monthly is still set to renew pays twice, and the
// Premium page used to tell them "no subscription to manage" and hide the
// Manage subscription button, the one way to cancel it from the app.
//
// How it happens: a Monthly stuck on a failed payment drops Premium, the
// paywall leads with Lifetime, the buyer updates their card to buy it, and
// the store retries the Monthly with that same new card. Or Lifetime comes
// from a creator's App Store link while a Monthly runs. Either way the
// entitlement names only the lifetime (its open expiry beats any month
// end), so isLifetimeEntitled alone cannot see the Monthly.
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
  List<String> active = const [],
  Map<String, SubscriptionInfo> subs = const {},
}) {
  final ent = EntitlementInfo(
      PurchaseService.entitlementId, true, false, _day, _day, entitledBy, false);
  return CustomerInfo(
    EntitlementInfos(
      {PurchaseService.entitlementId: ent},
      {PurchaseService.entitlementId: ent},
    ),
    const {},
    active,
    const [],
    const [],
    _day,
    'uid',
    const {},
    _day,
    subscriptionsByProductIdentifier: subs,
  );
}

SubscriptionInfo _monthly({bool active = true, required bool willRenew}) =>
    SubscriptionInfo('growdaily_monthly', _day, false, active, willRenew);

void main() {
  group('subscriptionStillRenews', () {
    test('lifetime alone: nothing renews', () {
      expect(subscriptionStillRenews(_info(entitledBy: 'growdaily_lifetime')),
          isFalse);
    });

    test('lifetime beside a Monthly set to renew: it renews', () {
      final info = _info(
        entitledBy: 'growdaily_lifetime',
        active: const ['growdaily_monthly'],
        subs: {'growdaily_monthly': _monthly(willRenew: true)},
      );
      expect(PurchaseService.instance.isLifetimeEntitled(info), isTrue,
          reason: 'the entitlement names the lifetime, which is the trap');
      expect(subscriptionStillRenews(info), isTrue);
    });

    test('a Monthly already cancelled only runs out: nothing to warn about',
        () {
      final info = _info(
        entitledBy: 'growdaily_lifetime',
        active: const ['growdaily_monthly'],
        subs: {'growdaily_monthly': _monthly(willRenew: false)},
      );
      expect(subscriptionStillRenews(info), isFalse);
    });

    test('an expired Monthly does not count, even if marked to renew', () {
      final info = _info(
        entitledBy: 'growdaily_lifetime',
        subs: {'growdaily_monthly': _monthly(active: false, willRenew: true)},
      );
      expect(subscriptionStillRenews(info), isFalse);
    });

    test('Play keys: base plan in the active list, bare id in the details',
        () {
      SubscriptionInfo play(bool renews) => SubscriptionInfo(
          'growdaily_monthly', _day, false, true, renews,
          productPlanIdentifier: 'monthly-autorenew');
      final renewing = _info(
        entitledBy: 'growdaily_lifetime_offer:lifetime',
        active: const ['growdaily_monthly:monthly-autorenew'],
        subs: {'growdaily_monthly': play(true)},
      );
      final cancelled = _info(
        entitledBy: 'growdaily_lifetime_offer:lifetime',
        active: const ['growdaily_monthly:monthly-autorenew'],
        subs: {'growdaily_monthly': play(false)},
      );
      expect(subscriptionStillRenews(renewing), isTrue);
      expect(subscriptionStillRenews(cancelled), isFalse,
          reason: 'the base-plan key must still find its details');
    });

    test('an active subscription with no details counts as renewing', () {
      final info = _info(
        entitledBy: 'growdaily_lifetime',
        active: const ['growdaily_monthly'],
      );
      expect(subscriptionStillRenews(info), isTrue,
          reason: 'a wrong warning costs a tap, a wrong all-clear costs a '
              'month of charges');
    });
  });

  group('the Premium page', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lifetime_renewing_');
      Hive.init(tmp.path);
      await Hive.openBox<dynamic>('box_settings');
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    Future<void> pumpPremium(WidgetTester tester, CustomerInfo info,
        {String locale = 'ar'}) async {
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
            offeringLoader: () async => null,
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

    testWidgets('lifetime alone: "yours for life", no Manage button',
        (tester) async {
      await pumpPremium(tester, _info(entitledBy: 'growdaily_lifetime'));
      expect(find.text(ar.premiumLifetimeOwned), findsOneWidget);
      expect(find.text(ar.premiumLifetimeStillRenewing), findsNothing);
      expect(find.text(ar.premiumManageSubscription), findsNothing);
    });

    testWidgets('lifetime and a renewing Monthly: the warning and the button',
        (tester) async {
      await pumpPremium(
        tester,
        _info(
          entitledBy: 'growdaily_lifetime',
          active: const ['growdaily_monthly'],
          subs: {'growdaily_monthly': _monthly(willRenew: true)},
        ),
      );
      expect(find.text(ar.premiumLifetimeOwned), findsNothing,
          reason: '"no subscription to manage" would be untrue');
      expect(find.text(ar.premiumLifetimeStillRenewing), findsOneWidget);
      expect(find.text(ar.premiumManageSubscription), findsOneWidget);
    });

    testWidgets('the same in English', (tester) async {
      await pumpPremium(
        tester,
        _info(
          entitledBy: 'growdaily_lifetime',
          active: const ['growdaily_monthly'],
          subs: {'growdaily_monthly': _monthly(willRenew: true)},
        ),
        locale: 'en',
      );
      expect(find.text(en.premiumLifetimeStillRenewing), findsOneWidget);
      expect(find.text(en.premiumManageSubscription), findsOneWidget);
    });

    testWidgets('a Monthly subscriber keeps the button and no lifetime line',
        (tester) async {
      await pumpPremium(
        tester,
        _info(
          entitledBy: 'growdaily_monthly',
          active: const ['growdaily_monthly'],
          subs: {'growdaily_monthly': _monthly(willRenew: true)},
        ),
      );
      expect(find.text(ar.premiumManageSubscription), findsOneWidget);
      expect(find.text(ar.premiumLifetimeOwned), findsNothing);
      expect(find.text(ar.premiumLifetimeStillRenewing), findsNothing);
    });
  });
}
