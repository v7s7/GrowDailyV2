// Six examples for the empty screen, and the reason they exist.
//
// The documented way a self-priced reward list dies is the blank first
// screen: someone opens it, faces an empty box and a blank price field, and
// never comes back. Naming a reward for yourself sounds easy until the
// cursor is blinking, and pricing one in a currency you have never spent is
// genuinely hard the first time.
//
// So these are shown as chips on the empty state and nowhere else. Tapping
// one opens the editor PREFILLED and nothing is saved until the user taps
// Save, so nobody ends up with a list they did not write. They are shape
// setters, not defaults.
//
// Priced in DAYS rather than gold, because a day of effort is the thing
// these are actually claiming, and it lets every suggestion re-derive from
// kApproxGoldPerDay if the economy is ever re-measured. What the user saves
// is always gold, never days.

/// One example reward. Never persisted: only its name and price ever reach
/// storage, and only after the user saves them.
class StarterReward {
  final String nameEn;
  final String nameAr;

  /// Days of habits this is worth, run through [priceForDays] for display.
  final double days;

  const StarterReward({
    required this.nameEn,
    required this.nameAr,
    required this.days,
  });

  String name(bool isAr) => isAr ? nameAr : nameEn;
}

abstract final class StarterRewardCatalog {
  /// Ordered cheapest first, so the row reads as a ladder from "tonight" to
  /// "worth saving for". The spread is deliberate: a list where everything
  /// costs a week teaches nothing about pricing.
  static const List<StarterReward> all = [
    StarterReward(
      nameEn: 'A coffee out',
      nameAr: 'قهوة من برّا',
      days: 1,
    ),
    StarterReward(
      nameEn: 'An hour of games',
      nameAr: 'ساعة ألعاب',
      days: 2,
    ),
    StarterReward(
      nameEn: 'A new book',
      nameAr: 'كتاب جديد',
      days: 4,
    ),
    StarterReward(
      nameEn: 'Dinner at your favourite place',
      nameAr: 'عشا في مطعمك المفضل',
      days: 6,
    ),
    StarterReward(
      nameEn: 'A weekend outing',
      nameAr: 'طلعة نهاية الأسبوع',
      days: 10,
    ),
    StarterReward(
      nameEn: 'A day off, guilt free',
      nameAr: 'يوم راحة من دون تفكير',
      days: 14,
    ),
  ];
}
