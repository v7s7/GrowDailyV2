// A reward the user named and priced for themselves, bought with gold.
//
// ── Why this exists ──────────────────────────────────────────────────────
// Gold had almost nothing to buy. Every purchasable accessory together
// totals 3,710 gold against roughly 77 a day for a committed five-habit
// board, so the whole catalog is affordable by about day 48 and after that
// the balance only ever grows. The one repeatable sink, streak freezes, is
// useless to the person the app's own reward curve produces: someone who
// does not break streaks. So gold stopped being a currency and became a
// score, while the purse and the home widget kept presenting it as
// spendable.
//
// More cosmetics could not fix it. Every [Accessory] needs a PNG, so the
// catalog cannot grow without a designer, and a fixed catalog empties again
// anyway.
//
// This is the sink that does not empty, because the user writes it. It is
// also the one that fits what the app is for: gold in a game buys a hat,
// but gold in a habit tracker should buy the thing you actually wanted when
// you set the habit in the first place. Someone saving 400 gold for a
// Friday coffee is using this app exactly as intended.

import 'package:uuid/uuid.dart';

/// A price must be a real number of gold, but the ceiling is deliberately
/// absurd rather than opinionated: someone saving for a holiday is not doing
/// anything wrong, and a cap low enough to be "sensible" would be the app
/// telling an adult what their own reward is worth.
const int kCustomRewardMinPrice = 1;
const int kCustomRewardMaxPrice = 999999;
const int kCustomRewardNameMaxChars = 60;

/// A list longer than this is a wish list, not a set of rewards, and every
/// entry past the first handful makes the ones above it less likely to be
/// claimed. Bounded mostly so the guest blob and the row list stay small.
const int kCustomRewardListMax = 20;

/// The daily gold figure every price SUGGESTION is quoted against.
///
/// Deliberately below the measured committed-user rate of about 77 a day.
/// The documented failure mode of a user-priced sink is pricing too HIGH,
/// never claiming, and abandoning the list, so a suggestion that lands
/// slightly cheap costs one early coffee, while one that lands slightly
/// expensive costs the first claim, which is the whole feature. Wrong in the
/// reachable direction on purpose.
///
/// Nothing is computed FROM this except the suggested numbers and the effort
/// label under the price field. No balance depends on it, and no stored
/// price changes when it changes: prices are stored in GOLD, never in days,
/// so moving this constant can never re-price a reward somebody already has.
const int kApproxGoldPerDay = 60;

/// What the price field opens at with nothing to prefill it from.
const int kSuggestedPriceDays = 7;

/// Gold for a number of days of effort, rounded to something a person would
/// say out loud. "420" reads as a price; "418.9" reads as arithmetic.
int priceForDays(double days) {
  final raw = kApproxGoldPerDay * days;
  if (raw < 20) {
    return raw.round().clamp(kCustomRewardMinPrice, kCustomRewardMaxPrice);
  }
  return ((raw / 5).round() * 5).clamp(5, kCustomRewardMaxPrice);
}

/// The inverse, for the live label under the price field.
double daysForPrice(int price) => price / kApproxGoldPerDay;

class CustomReward {
  /// Minted in [create] alongside createdAt so no call site can forget
  /// either, the way MatrixTask.create does it. Doubles as the Firestore
  /// document id, so there are never two id spaces to reconcile.
  final String id;
  final String name;

  /// Stored in GOLD, never in days. Storing days would make an existing
  /// reward silently re-price whenever [kApproxGoldPerDay] moved, which is
  /// the only way anything here could ever make a reward cost more than it
  /// did yesterday. Gold makes "nothing is taken from an existing user" a
  /// property of the data rather than a promise in a comment.
  final int priceGold;
  final DateTime createdAt;

  const CustomReward({
    required this.id,
    required this.name,
    required this.priceGold,
    required this.createdAt,
  });

  factory CustomReward.create({
    required String name,
    required int priceGold,
  }) =>
      CustomReward(
        id: const Uuid().v4(),
        name: name.trim(),
        priceGold: priceGold.clamp(kCustomRewardMinPrice, kCustomRewardMaxPrice),
        createdAt: DateTime.now(),
      );

  CustomReward copyWith({String? name, int? priceGold}) => CustomReward(
        id: id,
        name: name ?? this.name,
        priceGold: priceGold ?? this.priceGold,
        createdAt: createdAt,
      );

  /// Serves BOTH backends. The signed-in loader splices the document id in,
  /// since Firestore keeps it outside the data; the guest blob carries it in
  /// the map, the way MatrixTask.toMap does.
  ///
  /// Returns null rather than throwing on anything it cannot read. That is
  /// the whole defensive contract here: one malformed record must cost only
  /// itself. A load that throws leaves the list unusable, and the equivalent
  /// mistake on the dashboard sets loadFailed and refuses every reward write
  /// for the rest of the session.
  static CustomReward? fromMap(Map<String, dynamic> raw, {String? id}) {
    final theId = (id ?? raw['id']) as String?;
    final name = raw['name'];
    final price = raw['priceGold'];
    if (theId == null || theId.isEmpty) return null;
    if (name is! String || name.trim().isEmpty) return null;

    // num, not int: a value that round-tripped through JSON or arrived from
    // Firestore as a double still names a real price.
    final priceInt = price is num ? price.toInt() : null;
    if (priceInt == null || priceInt < kCustomRewardMinPrice) return null;

    return CustomReward(
      id: theId,
      name: name.length > kCustomRewardNameMaxChars
          ? name.substring(0, kCustomRewardNameMaxChars)
          : name,
      priceGold: priceInt.clamp(kCustomRewardMinPrice, kCustomRewardMaxPrice),
      // A missing or unreadable date is not worth discarding a reward over:
      // createdAt only orders the list.
      createdAt: _asDate(raw['createdAt']) ?? DateTime.now(),
    );
  }

  static DateTime? _asDate(Object? v) {
    if (v is String) return DateTime.tryParse(v);
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    // Firestore hands back a Timestamp, which this file must not import.
    // Every Timestamp exposes toDate(), so ask duck-typed and give up
    // quietly if it is something else entirely.
    try {
      final d = (v as dynamic)?.toDate();
      return d is DateTime ? d : null;
    } catch (_) {
      return null;
    }
  }

  /// The guest blob keeps the id; ISO-8601 rather than a Timestamp so the
  /// same map shape works in Hive and in Firestore.
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'priceGold': priceGold,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Firestore holds the id in the document key, so it is left out here, the
  /// same split IslamicHabitTemplate uses.
  Map<String, dynamic> toFirestore() => {
        'name': name,
        'priceGold': priceGold,
        'createdAt': createdAt.toIso8601String(),
      };

  @override
  String toString() => 'CustomReward($id, "$name", $priceGold gold)';
}
