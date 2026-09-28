import 'sprout.dart';

/// What the day card's sprout says. The words live in S (sprout*), so the
/// admin wording page can change them; this is only which one applies.
enum DayCardLine {
  /// Nothing done yet, before noon.
  morning,

  /// Nothing done yet, from noon on.
  hello,

  /// The first square of the day.
  firstDone,

  /// Two or more done, not all: «٣ من ٥ خلصت».
  progress,

  /// The day just earned its streak point: 80% of its habits (see
  /// kStreakDayCompletionThreshold). «يوم كامل» is the app's word for that
  /// day, the same words as the pop-up that fires on the same tap
  /// (S.perfectDayMsg), so this is only ever said at that moment, never as
  /// the card's standing mood.
  fullDay,

  /// Every square the day asks for is green: «يوم مثالي», the card's own
  /// word for 100% (S.gridPerfectDay).
  perfectDay,

  /// A perfect day, and it is late: the sprout goes to sleep.
  goodNight,

  /// After midnight on a new day with nothing done yet.
  lateNight,

  /// Today asks for no habit at all.
  restDay,
}

/// The sprout's pose and line on the Grid's day card.
class DayCardMood {
  const DayCardMood(this.pose, this.line);
  final SproutPose pose;
  final DayCardLine line;

  @override
  bool operator ==(Object other) =>
      other is DayCardMood && other.pose == pose && other.line == line;

  @override
  int get hashCode => Object.hash(pose, line);

  @override
  String toString() => 'DayCardMood(${pose.name}, ${line.name})';
}

/// The hour the sprout goes to sleep on a full day, and the one it wakes at.
const int kSproutBedtimeHour = 21;
const int kSproutWakeHour = 4;

/// Picks the day card's mood from the day alone, the same numbers the card
/// prints beside it: [greens] of [owed] squares green, and [perfectDay] once
/// every one of them is (the card's own definition, owed > 0 included).
/// [hour] is the wall clock, 0 to 23.
///
/// ── What it will never do ────────────────────────────────────────────────
/// Get sad, or sleep on an unfinished day. The sprout only ever reads the
/// day upward: waiting with a wave, pleased with progress, delighted with a
/// perfect day, asleep once that day is done. An unfinished evening keeps it
/// awake and waving, never sulking: these habits are prayer and dhikr, and a
/// mascot that droops at someone for an empty day is the guilt Duolingo is
/// known for and the reminder copy was rewritten to remove (see
/// reminder_copy.dart's dailyReminderLine).
///
/// After midnight a new day has begun with nothing on it yet, and a wave
/// asking «نبدأ؟» at 1am would be the wrong thing to say, so until
/// [kSproutWakeHour] the sprout sleeps on an empty new day. Yesterday is still
/// open until 10:00 (see DateTimeGameExt.isOpenDay), and the Profile banner
/// is the one that speaks for it.
DayCardMood dayCardMoodFor({
  required int greens,
  required int owed,
  required bool perfectDay,
  required int hour,
}) {
  if (owed <= 0) {
    return const DayCardMood(SproutPose.sleeping, DayCardLine.restDay);
  }
  final smallHours = hour < kSproutWakeHour;
  if (perfectDay) {
    return hour >= kSproutBedtimeHour || smallHours
        ? const DayCardMood(SproutPose.sleeping, DayCardLine.goodNight)
        : const DayCardMood(SproutPose.happySparkles, DayCardLine.perfectDay);
  }
  if (greens <= 0) {
    if (smallHours) {
      return const DayCardMood(SproutPose.sleeping, DayCardLine.lateNight);
    }
    return DayCardMood(
      SproutPose.frontWave,
      hour < 12 ? DayCardLine.morning : DayCardLine.hello,
    );
  }
  return DayCardMood(
    SproutPose.threeQuarterWave,
    greens == 1 ? DayCardLine.firstDone : DayCardLine.progress,
  );
}
