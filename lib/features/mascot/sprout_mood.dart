import 'pet_settings.dart';
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

  /// Two or more done, not all: «خلصت 3 من 5».
  progress,

  /// The day just earned its streak point: 80% of its habits (see
  /// kStreakDayCompletionThreshold), so it counts in the streak. A streak
  /// pass, never a full or perfect day (Aziz, 2026-09-28: that is every
  /// habit the day asked for). Said only on that tap, with the pop-up that
  /// fires on it (S.perfectDayMsg), never as the card's standing mood.
  streakPoint,

  /// Every habit the day asked for is done: «يوم مثالي», the card's own
  /// word for it (S.gridPerfectDay).
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

/// The hour the sprout goes to sleep on a full day, and the one it wakes at:
/// the built-in ones. The admin's «دوم» page can move both, and the hour
/// «صباح الخير» turns into «هلا» (see pet_settings.dart).
const int kSproutBedtimeHour = kPetBedtimeHour;
const int kSproutWakeHour = kPetWakeHour;

/// Picks the day card's mood from the day alone, the same numbers the card
/// prints beside it: [greens] of [owed] squares green, and [perfectDay] once
/// every one of them is (the card's own definition, owed > 0 included).
/// [hour] is the wall clock, 0 to 23. The hours it turns on are [settings]'
/// (the ones in force when not given), so every caller agrees with the
/// sprout it draws.
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
  PetSettings? settings,
}) {
  final s = settings ?? PetSettings.current;
  if (owed <= 0) {
    return const DayCardMood(SproutPose.sleeping, DayCardLine.restDay);
  }
  final smallHours = hour < s.wakeHour;
  if (perfectDay) {
    return hour >= s.bedtimeHour || smallHours
        ? const DayCardMood(SproutPose.sleeping, DayCardLine.goodNight)
        : const DayCardMood(SproutPose.happySparkles, DayCardLine.perfectDay);
  }
  if (greens <= 0) {
    if (smallHours) {
      return const DayCardMood(SproutPose.sleeping, DayCardLine.lateNight);
    }
    return DayCardMood(
      SproutPose.frontWave,
      hour < s.morningUntilHour ? DayCardLine.morning : DayCardLine.hello,
    );
  }
  return DayCardMood(
    SproutPose.threeQuarterWave,
    greens == 1 ? DayCardLine.firstDone : DayCardLine.progress,
  );
}
