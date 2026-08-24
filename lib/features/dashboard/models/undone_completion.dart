/// The receipt an undone habit completion leaves behind, so marking the same
/// habit-day done again is understood as a CORRECTION rather than as a
/// backfill.
///
/// ── Why this exists ────────────────────────────────────────────────────
/// Un-ticking a habit is a full, canonical reversal: XP, gold, the lifetime
/// counters and this habit's streak all go back (see
/// DashboardNotifier.uncompleteHabit). Re-ticking it is only symmetric while
/// the day is still today. Once the day has rolled over, the same square is a
/// past day, and the anti-backdating rule (WeeklyGridNotifier.setSquare) keeps
/// every past day out of the reward system on purpose: colouring in a week you
/// never lived must never pay.
///
/// That rule is right, and it made one honest case unrecoverable. Someone who
/// clears a mark by mistake and notices two days later re-paints the square,
/// the square goes green, and none of what the undo took back ever comes back.
/// The streak in particular reads that day as a miss forever, because the
/// chain is driven by `habitLastCompletedDate`, which only a same-day
/// completion ever writes.
///
/// The app could not tell those two cases apart because the undo erased every
/// trace that the day had ever been completed. This is that trace. It is
/// written by the undo, it names one exact habit and one exact date, and it is
/// consumed the first time that habit-day is marked done again. So the only
/// way to be paid for a past day is to have genuinely been paid for it once
/// already and given it back, and it can only happen once. There is nothing
/// here to farm.
class UndoneCompletion {
  final String habitId;

  /// 'YYYY-MM-DD' of the day whose completion was undone.
  final String dateKey;

  /// The habit's category at the time, so the restore can put
  /// `categoryCompletions` back without the caller having to look the habit
  /// up. Null for a habit that had none.
  final String? category;

  /// Exactly what the undo refunded: base reward plus whatever bonus it was
  /// able to reverse. Restoring pays back this, not a freshly computed
  /// reward, so a room boost or a surprise bonus that applied then still
  /// applies now.
  final int xp;
  final int gold;

  /// This habit's streak and longest-streak as they stood at the completion
  /// being undone, i.e. the values that completion itself produced.
  final int streakAtCompletion;
  final int longestAtCompletion;

  /// The day the undo happened, for the expiry sweep on load. A dateKey, not
  /// an instant: nothing here needs sub-day precision, and a stored calendar
  /// day cannot drift across a timezone change the way a Timestamp can (see
  /// _loadToday's lastActiveDay comment for the bug that taught us that).
  final String undoneOnKey;

  const UndoneCompletion({
    required this.habitId,
    required this.dateKey,
    required this.category,
    required this.xp,
    required this.gold,
    required this.streakAtCompletion,
    required this.longestAtCompletion,
    required this.undoneOnKey,
  });

  /// The map key one record lives under, in both Firestore and the guest
  /// store. A habit and a day together, because the same habit can have an
  /// outstanding receipt on more than one day.
  ///
  /// The separator has to be something no habit id contains: catalog ids are
  /// lowercase words joined by underscores and custom ones are generated, so
  /// '|' is safe, and unlike '.' it is never mistaken for a field path.
  static String keyFor(String habitId, String dateKey) => '$habitId|$dateKey';

  String get key => keyFor(habitId, dateKey);

  Map<String, dynamic> toJson() => {
        'habitId': habitId,
        'dateKey': dateKey,
        if (category != null) 'category': category,
        'xp': xp,
        'gold': gold,
        'streak': streakAtCompletion,
        'longest': longestAtCompletion,
        'undoneOn': undoneOnKey,
      };

  /// Null on anything that is not a well-formed record.
  ///
  /// Degrading rather than throwing, for the same reason
  /// DashboardNotifierLoading._asIntMap does: one malformed entry should cost
  /// that entry, not the whole account's load (a throw in the loader presents
  /// as level 1 with zero XP and then refuses every reward write).
  static UndoneCompletion? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final habitId = raw['habitId'];
    final dateKey = raw['dateKey'];
    if (habitId is! String || habitId.isEmpty) return null;
    if (dateKey is! String || dateKey.isEmpty) return null;
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    final category = raw['category'];
    final undoneOn = raw['undoneOn'];
    return UndoneCompletion(
      habitId: habitId,
      dateKey: dateKey,
      category: category is String && category.isNotEmpty ? category : null,
      xp: asInt(raw['xp']),
      gold: asInt(raw['gold']),
      streakAtCompletion: asInt(raw['streak']),
      longestAtCompletion: asInt(raw['longest']),
      undoneOnKey: undoneOn is String && undoneOn.isNotEmpty
          ? undoneOn
          // An older record with no stamp is read as undone on the day it
          // covers, which is when the undo actually had to have happened:
          // uncompleteHabit only ever runs against today.
          : dateKey,
    );
  }

  @override
  String toString() =>
      'UndoneCompletion($habitId, $dateKey, xp: $xp, gold: $gold, '
      'streak: $streakAtCompletion)';
}
