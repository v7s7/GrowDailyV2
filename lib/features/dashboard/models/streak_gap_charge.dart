import '../../../core/services/local_store_service.dart';

/// The receipt a streak-gap judgement leaves behind, so a day recorded late
/// inside the window it judged can give back what that day was charged.
///
/// ── Why this exists ────────────────────────────────────────────────────
/// DashboardNotifier.resolveStreakGap runs once, at the app's next open, and
/// what it does is final: it spends freezes, or it ends the streak. It judges
/// from what the app knew at that moment, which is not always what happened.
/// Someone who trained on Tuesday and only opened the app on Thursday is
/// charged for Tuesday, and the square they paint for it afterwards arrives
/// too late to matter: a past square deliberately pays nothing (see
/// WeeklyGridNotifier.setSquare), and the judgement has already been written
/// down and the freeze already spent.
///
/// This is the trace of that judgement. It names the window that was judged
/// and what the window cost, so when one of those days turns green the count
/// can be redone against the squares as they are now and the difference
/// handed back.
///
/// ── What it can and cannot hand back ───────────────────────────────────
/// Nothing here is minted. A refund never exceeds [freezesSpent], a restored
/// streak is exactly the number the break took away plus whatever has been
/// earned since, and a day is only ever discounted once it is genuinely
/// green. A late square still earns no XP, no gold and no new streak point:
/// all it does is stop a day being charged as missed, which is the one thing
/// the person can prove was wrong.
class StreakGapCharge {
  /// The last day that earned a streak point before the gap. EXCLUSIVE: the
  /// judgement started the day after it, exactly as resolveStreakGap does.
  final DateTime from;

  /// The last settled day the judgement covered, INCLUSIVE. Days after it
  /// were still open and were left to be judged when they close.
  final DateTime through;

  /// How many days in that window owed something and were blank when the
  /// judgement ran. What was charged for.
  final int owed;

  /// How many freezes it spent. 0 when it ended the streak instead.
  final int freezesSpent;

  /// The streak the break took away. 0 when nothing broke, which is every
  /// case where [freezesSpent] is not 0.
  final int streakBefore;

  const StreakGapCharge({
    required this.from,
    required this.through,
    required this.owed,
    required this.freezesSpent,
    required this.streakBefore,
  });

  /// Whether [day] is one of the days this charge judged.
  bool covers(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return d.isAfter(from) && !d.isAfter(through);
  }

  /// The days it judged, in order: the day after [from] through [through].
  List<DateTime> get days => [
        for (var d = from.add(const Duration(days: 1));
            !d.isAfter(through);
            d = d.add(const Duration(days: 1)))
          d,
      ];

  StreakGapCharge copyWith({int? owed, int? freezesSpent}) => StreakGapCharge(
        from: from,
        through: through,
        owed: owed ?? this.owed,
        freezesSpent: freezesSpent ?? this.freezesSpent,
        streakBefore: streakBefore,
      );

  /// Day keys rather than instants, for the reason UndoneCompletion.undoneOnKey
  /// gives: nothing here needs sub-day precision, and a stored calendar day
  /// cannot drift across a timezone change the way a Timestamp can.
  Map<String, dynamic> toJson() => {
        'from': LocalStoreService.dateKey(from),
        'through': LocalStoreService.dateKey(through),
        'owed': owed,
        'freezes': freezesSpent,
        'streakBefore': streakBefore,
      };

  /// Null on anything that is not a well-formed record, degrading rather than
  /// throwing for the same reason UndoneCompletion.fromJson does: one damaged
  /// entry costs itself, not the whole account's load.
  static StreakGapCharge? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final from = DateTime.tryParse('${raw['from']}');
    final through = DateTime.tryParse('${raw['through']}');
    if (from == null || through == null) return null;
    if (through.isBefore(from)) return null;
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    final owed = asInt(raw['owed']);
    if (owed <= 0) return null;
    return StreakGapCharge(
      from: DateTime(from.year, from.month, from.day),
      through: DateTime(through.year, through.month, through.day),
      owed: owed,
      freezesSpent: asInt(raw['freezes']),
      streakBefore: asInt(raw['streakBefore']),
    );
  }

  @override
  String toString() => 'StreakGapCharge(${LocalStoreService.dateKey(from)} '
      '→ ${LocalStoreService.dateKey(through)}, owed: $owed, '
      'freezes: $freezesSpent, streakBefore: $streakBefore)';
}
