import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/services/local_store_service.dart';
import '../../core/utils/ramadan_calendar.dart';
import '../habits/catalog/islamic_habit_catalog.dart' show IslamicHabitTemplate;
import '../habits/models/habit_model.dart' show HabitCategory;

/// What Doum is doing on the launch curtain this time (Aziz, 2026-09-29:
/// "coffee in the morning, sleepy after 10 pm, and random when nothing
/// special", then the canvas's "More ideas" page, "fix it all"). Designed
/// on the canvas's "Through the day" and "More ideas" pages,
/// https://claude.ai/artifact/8Xc4wxXzucGmZC5ckseRwS.
enum LaunchScene {
  /// The first open of the day, before 11:00: his mug, steam rising.
  morningCoffee,

  /// A ring filling round him as the app loads. One of the two ordinary
  /// scenes, picked at random.
  dayRing,

  /// He turns round from behind to face you. The other ordinary scene.
  turnaround,

  /// 18:00 to 22:00: his checklist, three squares ticking green.
  eveningChecklist,

  /// 22:00 to 04:00: asleep while the screen dims to night. Quiet: no hop.
  nightAsleep,

  /// Every open in Ramadan: a lantern and a crescent. Never the mug.
  ramadanLantern,

  /// The first open after three days or more away: he walks in with his
  /// backpack.
  welcomeBack,

  /// The very first launch after installing: he points up at a seed that
  /// sprouts with the load and blooms when the app is ready.
  firstOpen,

  /// Eid's days (see isEidDay): the lights come on one by one, then
  /// confetti.
  eid,

  /// The first open after a day with every owed habit done: yesterday's
  /// squares drop in full, then sparkle.
  fullDay,

  /// Saturday's first open once the week's recap is ready (10:00): last
  /// week's page turns over and he is set for the new one.
  saturday,

  /// The first open of a new version of the app: the room is dim and the
  /// bulb brings the light up with the load.
  update,

  /// The first open after a day the steps goal was reached: he runs in to
  /// the finish flag.
  stepsGoal,

  /// June to September, 12:00 to 15:59: the sun climbs and he puts his
  /// sunglasses on.
  summerNoon,
}

/// The one line under Doum in each scene (Aziz, 2026-09-29: one short
/// English sentence from the pose's own idea, landing on "Grow Daily", no
/// "... and Grow Daily", some "you" and some "we"; English for everyone).
/// The launch lasts a second or two, so one sentence and no more.
String launchLine(LaunchScene scene) => switch (scene) {
      LaunchScene.morningCoffee => 'Sip by sip you Grow Daily',
      LaunchScene.dayRing => 'Small steps help you Grow Daily',
      LaunchScene.turnaround => 'Let’s Grow Daily',
      LaunchScene.eveningChecklist => 'With every tick you Grow Daily',
      LaunchScene.nightAsleep => 'Even asleep we Grow Daily',
      LaunchScene.ramadanLantern => 'By lantern light we Grow Daily',
      LaunchScene.welcomeBack => 'Back on the path to Grow Daily',
      LaunchScene.firstOpen => 'Are you ready to Grow Daily?',
      LaunchScene.eid => 'Together we Grow Daily',
      LaunchScene.fullDay => 'Square by square you Grow Daily',
      LaunchScene.saturday => 'Ready to Grow Daily?',
      LaunchScene.update => 'Bright ideas help you Grow Daily',
      LaunchScene.stepsGoal => 'On the move you Grow Daily',
      LaunchScene.summerNoon => 'Under the sun we Grow Daily',
    };

/// The line once a slow load has him looking with his magnifier (see
/// LaunchCurtain.slowAfter).
const kLaunchSlowLine = 'Slow or fast we Grow Daily';

/// Where the launch day turns: an open at 01:00 still belongs to the night
/// before, so the first open after it in the morning is the day's first.
const int kLaunchDayStartsHour = 4;

/// How long away counts as coming back.
const int kLaunchAwayDays = 3;

/// The launch day [t] belongs to, as a local midnight.
DateTime launchDayOf(DateTime t) {
  final shifted = t.subtract(const Duration(hours: kLaunchDayStartsHour));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

/// Whether [day] is inside Ramadan by the Umm al-Qura table.
bool isRamadanDay(DateTime day) {
  final date = DateTime(day.year, day.month, day.day);
  final r = ramadanOnOrAfter(date);
  return r != null && !date.isBefore(r.start) && date.isBefore(r.eid);
}

/// Whether the mug must stay away on [day]: Ramadan, and the day before it
/// too, since the Gulf's moon sighting can start the fast a day ahead of
/// the table (see ramadan_calendar.dart).
bool isNearRamadanDay(DateTime day) =>
    isRamadanDay(day) || isRamadanDay(day.add(const Duration(days: 1)));

/// Whether any habit on [day]'s plan is a fast.
///
/// A preset keeps its fasting category; a habit someone typed only ever gets
/// the broad chips (so «صيام الاثنين» lands in faith), which is why its name
/// is read here too. Reading the name is wrong for praise (see
/// praiseGroupFor) but right for this, where a false yes only means no mug.
bool fastingPlannedOn(Iterable<IslamicHabitTemplate> habits, DateTime day) {
  for (final h in habits) {
    if (!h.isScheduledFor(day)) continue;
    if (h.category == HabitCategory.fasting) return true;
    final words = '${h.name} ${h.nameAr ?? ''}'.toLowerCase();
    if (words.contains('صيام') ||
        words.contains('صوم') ||
        words.contains('fast')) {
      return true;
    }
  }
  return false;
}

bool _sameDate(DateTime? a, DateTime b) =>
    a != null && a.year == b.year && a.month == b.month && a.day == b.day;

/// Picks this launch's scene. Pure, so every rule is pinned by
/// test/features/launch/launch_scene_test.dart.
///
/// [lastOpen] is when the app was last opened on screen (null on a fresh
/// install). [fastingPlanned] is whether a fast is on today's plan; pass
/// true when the habits are not known yet, since the only cost of a wrong
/// true is a morning without the mug. [freshInstall] is the very first
/// launch (nothing seen yet); [updated] the first open of a new version.
/// [lastFullDay] and [lastStepsGoal] are the last days seen with every owed
/// habit done and with the steps goal reached (LaunchMemory).
///
/// In order: back after days away, then Ramadan, then night (those three
/// keep their place over everything); then the very first launch, a new
/// version, Eid, yesterday full, yesterday's steps goal, Saturday's recap;
/// then the morning's first open (never with a fast on the plan or near
/// Ramadan), a summer noon, the evening, and otherwise one of the two
/// ordinary scenes at random.
LaunchScene pickLaunchScene({
  required DateTime now,
  required DateTime? lastOpen,
  required bool fastingPlanned,
  bool freshInstall = false,
  bool updated = false,
  DateTime? lastFullDay,
  DateTime? lastStepsGoal,
  math.Random? random,
}) {
  final today = launchDayOf(now);
  if (lastOpen != null &&
      today.difference(launchDayOf(lastOpen)).inDays >= kLaunchAwayDays) {
    return LaunchScene.welcomeBack;
  }
  final date = DateTime(now.year, now.month, now.day);
  if (isRamadanDay(date)) return LaunchScene.ramadanLantern;
  final hour = now.hour;
  if (hour >= 22 || hour < kLaunchDayStartsHour) return LaunchScene.nightAsleep;

  if (freshInstall) return LaunchScene.firstOpen;
  if (updated) return LaunchScene.update;
  if (isEidDay(date)) return LaunchScene.eid;
  final firstToday = lastOpen == null || launchDayOf(lastOpen) != today;
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  if (firstToday && _sameDate(lastFullDay, yesterday)) {
    return LaunchScene.fullDay;
  }
  if (firstToday && _sameDate(lastStepsGoal, yesterday)) {
    return LaunchScene.stepsGoal;
  }
  final recapReady = DateTime(now.year, now.month, now.day, 10);
  if (now.weekday == DateTime.saturday &&
      !now.isBefore(recapReady) &&
      (lastOpen == null || lastOpen.isBefore(recapReady))) {
    return LaunchScene.saturday;
  }
  if (hour < 11) {
    if (firstToday && !fastingPlanned && !isNearRamadanDay(date)) {
      return LaunchScene.morningCoffee;
    }
  } else if (hour >= 18) {
    return LaunchScene.eveningChecklist;
  } else if (hour >= 12 && hour < 16 && now.month >= 6 && now.month <= 9) {
    return LaunchScene.summerNoon;
  }
  return (random ?? math.Random()).nextBool()
      ? LaunchScene.dayRing
      : LaunchScene.turnaround;
}

/// Set with `--dart-define=GD_LAUNCH_CYCLE=true` to see every scene on a
/// device without waiting for the hour: each cold start then plays the next
/// scene in [LaunchScene]'s order. Off in every normal build, where the
/// compiler drops it.
const bool kLaunchSceneCycle = bool.fromEnvironment('GD_LAUNCH_CYCLE');

/// What the launch scene is chosen from, kept on this phone.
///
/// Read once before the first frame ([load], from main.dart via
/// LaunchCurtain.prepare). The open is written when the curtain is actually
/// seen ([recordOpen]): a notification action run with the app closed
/// starts the same process in the background, and counting that as an open
/// would take the next morning's coffee away. A full day and a met steps
/// goal are written when the app sees them ([recordFullDay],
/// [recordStepsGoal]), so the next launch can know about yesterday at once
/// instead of waiting for the server.
class LaunchMemory {
  LaunchMemory._();

  static const _key = 'launch_last_open_v1';
  static const _cycleKey = 'launch_scene_cycle_v1';
  static const _versionKey = 'launch_last_version_v1';
  static const _fullDayKey = 'launch_full_day_v1';
  static const _stepsGoalKey = 'launch_steps_goal_v1';

  static DateTime? _lastOpen;
  static DateTime? _lastFullDay;
  static DateTime? _lastStepsGoal;
  static String? _lastVersion;
  static String? _version;
  static bool _loaded = false;
  static int _cycle = 0;

  /// The open before this one, or null (fresh install, or never loaded).
  static DateTime? get lastOpen => _lastOpen;

  /// The last day seen with every owed habit done, or null.
  static DateTime? get lastFullDay => _lastFullDay;

  /// The last day seen with the steps goal reached, or null.
  static DateTime? get lastStepsGoal => _lastStepsGoal;

  /// Whether this is the first open of a new version: the running version
  /// is known and is not the one last opened. False when either cannot be
  /// read.
  static bool get updated => _version != null && _lastVersion != _version;

  /// With [kLaunchSceneCycle], the scene this launch plays.
  static LaunchScene get cycledScene =>
      LaunchScene.values[_cycle % LaunchScene.values.length];

  static Future<void> load() async {
    if (kIsWeb) return;
    try {
      final box = await LocalStoreService.settingsBox();
      DateTime? read(String key) {
        final raw = box.get(key);
        return raw is String ? DateTime.tryParse(raw) : null;
      }

      _lastOpen = read(_key);
      _lastFullDay = read(_fullDayKey);
      _lastStepsGoal = read(_stepsGoalKey);
      final v = box.get(_versionKey);
      _lastVersion = v is String ? v : null;
      _loaded = true;
      if (kLaunchSceneCycle) {
        final at = box.get(_cycleKey);
        _cycle = at is int ? at : 0;
        await box.put(_cycleKey, _cycle + 1);
      }
    } catch (_) {
      _lastOpen = null;
    }
    try {
      final info = await PackageInfo.fromPlatform()
          .timeout(const Duration(milliseconds: 300));
      _version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _version = null;
    }
  }

  /// Stores [now] as the last open, and this version as the one last
  /// opened. A no-op unless [load] ran, which keeps widget tests (no boxes
  /// open) off the disk.
  static void recordOpen(DateTime now) {
    if (!_loaded) return;
    final version = _version;
    LocalStoreService.settingsBox().then((box) async {
      await box.put(_key, now.toIso8601String());
      if (version != null) await box.put(_versionKey, version);
    }).catchError((Object _) {});
  }

  /// Notes [day] as a day with every owed habit done (the Grid's day card
  /// says so). Only ever moves forward.
  static void recordFullDay(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    if (_lastFullDay != null && !date.isAfter(_lastFullDay!)) return;
    _lastFullDay = date;
    _write(_fullDayKey, date);
  }

  /// Notes [day] as a day the steps goal was reached (step_auto_complete
  /// gives the linked habit its green or blue square). Only ever moves
  /// forward.
  static void recordStepsGoal(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    if (_lastStepsGoal != null && !date.isAfter(_lastStepsGoal!)) return;
    _lastStepsGoal = date;
    _write(_stepsGoalKey, date);
  }

  static void _write(String key, DateTime date) {
    if (!_loaded) return;
    LocalStoreService.settingsBox()
        .then((box) => box.put(key, date.toIso8601String()))
        .catchError((Object _) {});
  }

  @visibleForTesting
  static void debugReset({
    DateTime? lastOpen,
    bool loaded = false,
    DateTime? lastFullDay,
    DateTime? lastStepsGoal,
    String? lastVersion,
    String? version,
  }) {
    _lastOpen = lastOpen;
    _loaded = loaded;
    _lastFullDay = lastFullDay;
    _lastStepsGoal = lastStepsGoal;
    _lastVersion = lastVersion;
    _version = version;
  }
}
