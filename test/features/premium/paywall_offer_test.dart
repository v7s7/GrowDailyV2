// The paywall's welcome price and dated sales (Aziz, 2026-09-22): which
// offer a person has, when it ends, and when there is nothing honest to show.
//
// The rules these pin are the ones that keep a countdown lawful: a window
// that has run out never comes back, an offer ends at its deadline and not a
// second later, and no offer appears unless the store itself prices the
// offer product below Lifetime.
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/purchase_service.dart';
import 'package:grow_daily_v2/features/premium/offers/paywall_offer.dart';

void main() {
  final t0 = DateTime(2027, 2, 20, 12);

  SaleWindow sale(DateTime start, DateTime end) => SaleWindow(
        id: 'ramadan',
        nameAr: 'عرض رمضان',
        nameEn: 'Ramadan sale',
        startsAt: start,
        endsAt: end,
      );

  group('resolveOffer', () {
    test('no window started and no sale: no offer', () {
      expect(
        resolveOffer(now: t0, config: OffersConfig.fallback),
        isNull,
      );
    });

    test('the welcome window runs 72 hours from its start, then is gone', () {
      const config = OffersConfig();
      final started = t0.subtract(const Duration(hours: 10));
      final active = resolveOffer(
          now: t0, config: config, welcomeStartedAt: started);
      expect(active?.kind, OfferKind.welcome);
      expect(active?.endsAt, started.add(const Duration(hours: 72)));

      final atEnd = started.add(const Duration(hours: 72));
      expect(
        resolveOffer(now: atEnd, config: config, welcomeStartedAt: started),
        isNull,
        reason: 'the price ends the moment the countdown reads zero',
      );
      expect(
        resolveOffer(
          now: atEnd.add(const Duration(days: 30)),
          config: config,
          welcomeStartedAt: started,
        ),
        isNull,
        reason: 'a spent window never comes back',
      );
    });

    test('the admin can switch the welcome price off', () {
      const off = OffersConfig(welcomeEnabled: false);
      expect(
        resolveOffer(now: t0, config: off, welcomeStartedAt: t0),
        isNull,
      );
    });

    test('a sale counts from its start (inclusive) to its end (exclusive)',
        () {
      final config = OffersConfig(
        sale: sale(t0, t0.add(const Duration(days: 11))),
      );
      expect(
        resolveOffer(
            now: t0.subtract(const Duration(seconds: 1)), config: config),
        isNull,
        reason: 'a scheduled sale is invisible until it starts',
      );
      expect(resolveOffer(now: t0, config: config)?.kind, OfferKind.sale);
      expect(
        resolveOffer(now: t0.add(const Duration(days: 11)), config: config),
        isNull,
      );
    });

    test('both running: the later deadline is the one shown', () {
      final start = t0.subtract(const Duration(hours: 1));
      final longSale = OffersConfig(
        sale: sale(t0.subtract(const Duration(days: 1)),
            t0.add(const Duration(days: 5))),
      );
      final shortSale = OffersConfig(
        sale: sale(t0.subtract(const Duration(days: 1)),
            t0.add(const Duration(hours: 5))),
      );
      expect(
        resolveOffer(now: t0, config: longSale, welcomeStartedAt: start)?.kind,
        OfferKind.sale,
      );
      final welcome =
          resolveOffer(now: t0, config: shortSale, welcomeStartedAt: start);
      expect(welcome?.kind, OfferKind.welcome);
      expect(welcome?.endsAt, start.add(kDefaultWelcomeLength));
    });

    test('a tie goes to the sale, whose name says why the price is low', () {
      final start = t0;
      final config = OffersConfig(
        sale: sale(t0.subtract(const Duration(days: 1)),
            start.add(kDefaultWelcomeLength)),
      );
      expect(
        resolveOffer(now: t0, config: config, welcomeStartedAt: start)?.kind,
        OfferKind.sale,
      );
    });
  });

  group('OffersConfig.fromData', () {
    test('reads the admin document with Firestore timestamps', () {
      final config = OffersConfig.fromData({
        'welcome': {'enabled': true, 'hours': 72},
        'sale': {
          'id': 'r1',
          'nameAr': 'عرض رمضان',
          'nameEn': 'Ramadan sale',
          'startsAt': Timestamp.fromDate(t0),
          'endsAt': Timestamp.fromDate(t0.add(const Duration(days: 11))),
        },
      });
      expect(config.welcomeEnabled, isTrue);
      expect(config.welcomeLength, const Duration(hours: 72));
      expect(config.sale?.nameFor(isAr: true), 'عرض رمضان');
      expect(config.sale?.nameFor(isAr: false), 'Ramadan sale');
      expect(config.sale?.endsAt, t0.add(const Duration(days: 11)));
    });

    test('round-trips through the device copy', () {
      final original = OffersConfig(
        welcomeEnabled: false,
        welcomeLength: const Duration(hours: 48),
        sale: sale(t0, t0.add(const Duration(days: 7))),
      );
      final back = OffersConfig.fromData(original.toJson());
      expect(back.welcomeEnabled, isFalse);
      expect(back.welcomeLength, const Duration(hours: 48));
      expect(back.sale?.startsAt, t0);
      expect(back.sale?.endsAt, t0.add(const Duration(days: 7)));
    });

    test('damaged or missing parts never put an offer on screen', () {
      expect(OffersConfig.fromData(null).sale, isNull);
      expect(OffersConfig.fromData('junk').welcomeEnabled, isTrue);
      final badHours = OffersConfig.fromData({
        'welcome': {'enabled': true, 'hours': 100000},
      });
      expect(badHours.welcomeLength, kDefaultWelcomeLength,
          reason: 'outside 24..168 hours is ignored, not trusted');
      final backwards = OffersConfig.fromData({
        'sale': {
          'startsAt': t0.millisecondsSinceEpoch,
          'endsAt': t0.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        },
      });
      expect(backwards.sale, isNull);
      final noEnd = OffersConfig.fromData({
        'sale': {'startsAt': t0.millisecondsSinceEpoch},
      });
      expect(noEnd.sale, isNull);
    });

    test('a sale with only one name shows that name in both languages', () {
      final config = OffersConfig.fromData({
        'sale': {
          'nameAr': 'عرض رمضان',
          'startsAt': t0.millisecondsSinceEpoch,
          'endsAt': t0.add(const Duration(days: 3)).millisecondsSinceEpoch,
        },
      });
      expect(config.sale?.nameFor(isAr: false), 'عرض رمضان');
    });
  });

  group('prices', () {
    test('an offer needs the store to price it below Lifetime', () {
      expect(
        lifetimeOfferPricesOk(
          regularPrice: 39.99,
          regularCurrency: 'USD',
          offerPrice: 29.99,
          offerCurrency: 'USD',
        ),
        isTrue,
      );
      expect(
        lifetimeOfferPricesOk(
          regularPrice: 29.99,
          regularCurrency: 'USD',
          offerPrice: 29.99,
          offerCurrency: 'USD',
        ),
        isFalse,
        reason: 'before Lifetime moves to 39.99 both cost the same',
      );
      expect(
        lifetimeOfferPricesOk(
          regularPrice: 39.99,
          regularCurrency: 'USD',
          offerPrice: 109.99,
          offerCurrency: 'SAR',
        ),
        isFalse,
      );
    });

    test('the saving is rounded down, never overstated', () {
      expect(offerPercentOff(regular: 39.99, offer: 29.99), 25);
      expect(offerPercentOff(regular: 169.99, offer: 129.99), 23,
          reason: '23.53% in a SAR storefront reads 23, not 24');
      expect(offerPercentOff(regular: 29.99, offer: 29.99), isNull);
      expect(offerPercentOff(regular: 29.99, offer: 39.99), isNull);
      expect(offerPercentOff(regular: 39.99, offer: 39.49), isNull,
          reason: 'under 5% is not worth a chip');
    });

    test('both lifetime products count as owning Premium for life', () {
      expect(isLifetimeProductId('growdaily_lifetime'), isTrue);
      expect(isLifetimeProductId('growdaily_lifetime_offer'), isTrue);
      expect(isLifetimeProductId('growdaily_lifetime_offer:lifetime'), isTrue);
      expect(isLifetimeProductId('growdaily_monthly'), isFalse);
      expect(
        isLifetimeProductId('growdaily_monthly:monthly-autorenew'),
        isFalse,
      );
    });
  });

  group('CountdownParts', () {
    test('days, hours, minutes while a day or more is left', () {
      final parts = CountdownParts.of(
          const Duration(days: 2, hours: 14, minutes: 32, seconds: 40));
      expect(parts.days, 2);
      expect(parts.hours, 14);
      expect(parts.minutes, 32);
      expect(parts.seconds, 40);
      expect(parts.lastDay, isFalse);
    });

    test('the last day counts seconds', () {
      final parts =
          CountdownParts.of(const Duration(hours: 5, minutes: 12, seconds: 9));
      expect(parts.lastDay, isTrue);
      expect([parts.hours, parts.minutes, parts.seconds], [5, 12, 9]);
    });

    test('past the deadline it reads zero, never negative', () {
      expect(CountdownParts.of(const Duration(seconds: -30)),
          CountdownParts.of(Duration.zero));
    });
  });
}
