import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/foundation.dart';

/// The paywall's two honest offers on Lifetime, decided by Aziz on
/// 2026-09-22 (see the paywall-offers-decided memory):
///
///  * a WELCOME price, once per person, for [kDefaultWelcomeLength] from
///    the first time they open the paywall, and
///  * dated SALES for everyone, scheduled from the admin tool's Sale page.
///
/// Both sell `growdaily_lifetime_offer` (the same permanent Premium unlock
/// as `growdaily_lifetime`, at the lower price), which RevenueCat serves as
/// the custom package [kLifetimeOfferPackageId] in the default offering.
/// Builds before this one read only the standard monthly and lifetime
/// packages, so they never show it.
///
/// Why the rules below are strict. A countdown that restarts, or a "then"
/// price nobody is ever charged, is a false price: Apple guideline 2.3.1(a)
/// removes apps for it and consumer regulators fine it (Emma Sleep, Epic's
/// Fortnite shop). So a welcome window starts once and is never restarted,
/// it ends at the moment its countdown reaches zero, and nothing here shows
/// an offer unless the store itself prices the offer product below the
/// regular one.
const String kLifetimeOfferPackageId = 'lifetime_offer';

/// Aziz chose 72 hours over the 48 first proposed.
const Duration kDefaultWelcomeLength = Duration(hours: 72);

enum OfferKind { welcome, sale }

/// One dated sale for everyone, as the admin tool writes it into
/// `offers/live.sale`. It may be scheduled ahead: it only counts between
/// [startsAt] (inclusive) and [endsAt] (exclusive).
@immutable
class SaleWindow {
  const SaleWindow({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.startsAt,
    required this.endsAt,
  });

  final String id;
  final String nameAr;
  final String nameEn;
  final DateTime startsAt;
  final DateTime endsAt;

  bool isOpenAt(DateTime now) =>
      !now.isBefore(startsAt) && now.isBefore(endsAt);

  String nameFor({required bool isAr}) {
    final name = isAr ? nameAr : nameEn;
    return name.trim().isEmpty ? (isAr ? nameEn : nameAr) : name;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'startsAt': startsAt.millisecondsSinceEpoch,
        'endsAt': endsAt.millisecondsSinceEpoch,
      };

  /// Null for anything that is not a complete, sane window, so a half
  /// edited or damaged document can never put a sale on screen.
  static SaleWindow? fromData(Object? data) {
    if (data is! Map) return null;
    final starts = _dateOf(data['startsAt']);
    final ends = _dateOf(data['endsAt']);
    if (starts == null || ends == null || !ends.isAfter(starts)) return null;
    final nameAr = data['nameAr'];
    final nameEn = data['nameEn'];
    return SaleWindow(
      id: data['id'] is String ? data['id'] as String : '',
      nameAr: nameAr is String ? nameAr : '',
      nameEn: nameEn is String ? nameEn : '',
      startsAt: starts,
      endsAt: ends,
    );
  }
}

/// What the admin tool has set in `offers/live`: the welcome switch and
/// length, and the current or next sale.
@immutable
class OffersConfig {
  const OffersConfig({
    this.welcomeEnabled = true,
    this.welcomeLength = kDefaultWelcomeLength,
    this.sale,
  });

  final bool welcomeEnabled;
  final Duration welcomeLength;
  final SaleWindow? sale;

  /// Used when the document has never been read on this device: the
  /// welcome price is on (Aziz's decision), no sale. Whatever the store
  /// prices say still has the last word (see [lifetimeOfferPricesOk]).
  static const OffersConfig fallback = OffersConfig();

  /// Reads a Firestore snapshot's data or this device's cached JSON. Every
  /// field is optional and checked, the way wording edits are read.
  factory OffersConfig.fromData(Object? data) {
    if (data is! Map) return fallback;
    final welcome = data['welcome'];
    var enabled = fallback.welcomeEnabled;
    var length = fallback.welcomeLength;
    if (welcome is Map) {
      if (welcome['enabled'] is bool) enabled = welcome['enabled'] as bool;
      final hours = welcome['hours'];
      // The admin tool allows 24 to 168; anything else is ignored rather
      // than trusted.
      if (hours is num && hours >= 24 && hours <= 168) {
        length = Duration(minutes: (hours * 60).round());
      }
    }
    return OffersConfig(
      welcomeEnabled: enabled,
      welcomeLength: length,
      sale: SaleWindow.fromData(data['sale']),
    );
  }

  Map<String, Object?> toJson() => {
        'welcome': {
          'enabled': welcomeEnabled,
          'hours': welcomeLength.inMinutes / 60,
        },
        'sale': sale?.toJson(),
      };
}

/// The offer a person has right now.
@immutable
class ActiveOffer {
  const ActiveOffer({required this.kind, required this.endsAt, this.sale});

  final OfferKind kind;
  final DateTime endsAt;

  /// Set for [OfferKind.sale], for its name.
  final SaleWindow? sale;
}

/// Which offer, if any, a person has at [now].
///
/// A sale counts while it is open. The welcome window counts from
/// [welcomeStartedAt] for the configured length; a person whose window has
/// never started has none yet (the paywall starts it the first time it can
/// show it), and a window that has run out never comes back.
///
/// When both are running they sell the same product at the same price, so
/// the one that ends LATER is shown: its countdown is the true deadline for
/// that price. A tie goes to the sale, whose name says why the price is low.
ActiveOffer? resolveOffer({
  required DateTime now,
  required OffersConfig config,
  DateTime? welcomeStartedAt,
}) {
  final sale = config.sale;
  final saleEnd = sale != null && sale.isOpenAt(now) ? sale.endsAt : null;
  DateTime? welcomeEnd;
  if (config.welcomeEnabled && welcomeStartedAt != null) {
    final end = welcomeStartedAt.add(config.welcomeLength);
    if (now.isBefore(end)) welcomeEnd = end;
  }
  if (saleEnd == null && welcomeEnd == null) return null;
  if (saleEnd != null && (welcomeEnd == null || !welcomeEnd.isAfter(saleEnd))) {
    return ActiveOffer(kind: OfferKind.sale, endsAt: saleEnd, sale: sale);
  }
  return ActiveOffer(kind: OfferKind.welcome, endsAt: welcomeEnd!);
}

/// Whether the store's own prices make an offer true: both known, the same
/// currency, and the offer product really cheaper. Until Lifetime moves to
/// its new price both products cost the same, and "then" the same price
/// would be nonsense, so no offer is shown at all.
bool lifetimeOfferPricesOk({
  required double regularPrice,
  required String regularCurrency,
  required double offerPrice,
  required String offerCurrency,
}) =>
    regularCurrency == offerCurrency &&
    offerPrice > 0 &&
    offerPrice < regularPrice;

/// The saving as a whole percent, rounded DOWN so it never overstates:
/// 29.99 against 39.99 is 25.006%, shown as 25. Computed from the store's
/// prices for this storefront, so it is true in every currency. Null when
/// there is nothing honest to show.
int? offerPercentOff({required double regular, required double offer}) {
  if (regular <= 0 || offer <= 0 || offer >= regular) return null;
  final pct = ((1 - offer / regular) * 100).floor();
  if (pct < 5 || pct > 90) return null;
  return pct;
}

/// A countdown split the way the paywall draws it (Aziz, 2026-09-22):
/// days, hours and minutes while a day or more is left, then hours, minutes
/// and seconds on the last day.
@immutable
class CountdownParts {
  const CountdownParts._(this.days, this.hours, this.minutes, this.seconds);

  factory CountdownParts.of(Duration left) {
    final total = left.isNegative ? 0 : left.inSeconds;
    return CountdownParts._(
      total ~/ 86400,
      (total % 86400) ~/ 3600,
      (total % 3600) ~/ 60,
      total % 60,
    );
  }

  final int days;
  final int hours;
  final int minutes;
  final int seconds;

  bool get lastDay => days == 0;

  @override
  bool operator ==(Object other) =>
      other is CountdownParts &&
      other.days == days &&
      other.hours == hours &&
      other.minutes == minutes &&
      other.seconds == seconds;

  @override
  int get hashCode => Object.hash(days, hours, minutes, seconds);
}

DateTime? _dateOf(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}
