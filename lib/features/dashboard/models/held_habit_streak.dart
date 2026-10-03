/// The run a habit's streak was on when TODAY was ticked while yesterday,
/// the one day missing in between, was still open.
///
/// ── Why this exists ────────────────────────────────────────────────────
/// Between midnight and kDayCutoffHour yesterday can still be marked, and
/// ticking today first is the natural order at that hour: the Fajr habit
/// gets done, last night's habit gets remembered afterwards. Measured on its
/// own that tap is a gap of two days, so the habit's streak restarts at 1,
/// and that is the honest reading for the moment, because yesterday is not
/// done. What used to go wrong came next. The restart overwrote the run it
/// replaced, so when yesterday was marked a few minutes later there was
/// nothing left to join it to: the per-habit streak stayed at 1 for good,
/// though every day had been done.
///
/// The per-habit streak is an incremental counter (DashboardState
/// .habitStreakCounts), and it cannot be recomputed without reading the
/// habit's whole history, so the half that the restart throws away has to be
/// kept somewhere. This is that half. It is written by the tap on today that
/// restarted the streak, and it is spent the first time that habit is touched
/// again: by yesterday being marked (the runs join, see
/// habitStreakForEarlierDay), by any other completion of the habit (it is
/// stale then and simply dropped), or by today's tap being undone (the run
/// comes back exactly as it was).
///
/// Only ever honoured while it still describes the run the counters hold:
/// [cutOnKey] has to be the habit's last completed day. Once yesterday has
/// closed there is no day left that could join it, so a leftover record is
/// inert, and the next completion of the habit removes it.
class HeldHabitStreak {
  /// The streak the interrupted run had reached.
  final int streak;

  /// 'YYYY-MM-DD' of that run's last completed day.
  final String lastKey;

  /// 'YYYY-MM-DD' of the day whose tap restarted the streak (today, when it
  /// was written).
  final String cutOnKey;

  const HeldHabitStreak({
    required this.streak,
    required this.lastKey,
    required this.cutOnKey,
  });

  DateTime? get lastDay => DateTime.tryParse(lastKey);

  Map<String, dynamic> toJson() => {
        'streak': streak,
        'last': lastKey,
        'cutOn': cutOnKey,
      };

  /// Null on anything that is not a well-formed record, for the same reason
  /// UndoneCompletion.fromJson degrades instead of throwing: one malformed
  /// entry must cost that entry, never the whole account's load.
  static HeldHabitStreak? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final streak = raw['streak'];
    final last = raw['last'];
    final cutOn = raw['cutOn'];
    if (streak is! num || streak < 1) return null;
    if (last is! String || DateTime.tryParse(last) == null) return null;
    if (cutOn is! String || DateTime.tryParse(cutOn) == null) return null;
    return HeldHabitStreak(
      streak: streak.toInt(),
      lastKey: last,
      cutOnKey: cutOn,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HeldHabitStreak &&
      other.streak == streak &&
      other.lastKey == lastKey &&
      other.cutOnKey == cutOnKey;

  @override
  int get hashCode => Object.hash(streak, lastKey, cutOnKey);

  @override
  String toString() => 'HeldHabitStreak($streak to $lastKey, cut on $cutOnKey)';
}
