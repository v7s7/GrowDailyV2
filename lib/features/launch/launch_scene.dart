import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/services/local_store_service.dart';
import '../../core/utils/ramadan_calendar.dart';
import '../../core/utils/step_habit_detector.dart' show looksLikeStepHabit;
import '../habits/catalog/islamic_habit_catalog.dart' show IslamicHabitTemplate;
import '../habits/models/habit_model.dart' show HabitCategory;
import 'launch_settings.dart';

/// What Doum is doing on the launch curtain this time (Aziz, 2026-09-29:
/// "coffee in the morning, sleepy after 10 pm, and random when nothing
/// special", then the canvas's "More ideas" page, "fix it all"). Designed
/// on the canvas's "Through the day" and "More ideas" pages,
/// https://claude.ai/artifact/8Xc4wxXzucGmZC5ckseRwS.
///
/// The hours, months and order below are the built-in ones: the admin's
/// splash page can change them (launch_settings.dart).
enum LaunchScene {
  /// The morning's first open that no bigger moment took, before 11:00:
  /// his mug, steam rising.
  morningCoffee,

  /// A ring filling round him as the app loads. One of the anytime scenes
  /// (kSplashPoolWeights).
  dayRing,

  /// He turns round from behind to face you. An anytime scene.
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
  /// sprouts with the load and blooms when the app is ready. Also an
  /// anytime scene, the plant.
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
  /// the finish flag. Also an anytime scene, weighed up.
  stepsGoal,

  /// June to September, 12:00 to 15:59: the sun climbs and he puts his
  /// sunglasses on.
  summerNoon,

  /// Every month but December to February, Bahrain's winter, the first
  /// open from 15:00 to 17:59 and an anytime scene in those hours (Aziz,
  /// 2026-09-30, the "Missing winter" board; all months but winter since
  /// 2026-10-01): in his ghutra and bisht by his
  /// hourglass and a small fire while the late summer sky sinks into a
  /// starry desert night with the load; when the app is ready the first
  /// cool breeze comes and he laughs by a big fire.
  winterWait,

  /// Every open 16:00 to 17:59 for someone with a walking or steps habit,
  /// and an anytime scene for everyone, weighed up (the "Every step"
  /// board): he runs on his treadmill, stepping and sweating, the belt
  /// running under him; when the app is ready he springs off it. No
  /// footprints since 2026-10-01 (Aziz: "it should be animation running on
  /// the treadmill, and the sweating").
  walk,
}

/// The one line under Doum in each scene (Aziz, 2026-09-29: one short
/// English sentence from the pose's own idea, landing on "Grow Daily", no
/// "... and Grow Daily", some "you" and some "we"; English for everyone).
/// The launch lasts a second or two, so one sentence and no more. Ramadan
/// and Eid say their greeting instead, in the easy words everyone knows,
/// over the green "Grow Daily" (Aziz, 2026-10-01: "don't use lantern and
/// these hard words, like Ramadan Kareem").
///
/// The admin's splash page can rewrite any of them (LaunchSettings.line).
String launchLine(LaunchScene scene) => switch (scene) {
      LaunchScene.morningCoffee => 'Sip by sip you Grow Daily',
      LaunchScene.dayRing => 'Small steps help you Grow Daily',
      LaunchScene.turnaround => 'Let’s Grow Daily',
      LaunchScene.eveningChecklist => 'With every tick you Grow Daily',
      LaunchScene.nightAsleep => 'Even asleep we Grow Daily',
      LaunchScene.ramadanLantern => 'Ramadan Kareem Grow Daily',
      LaunchScene.welcomeBack => 'Back on the path to Grow Daily',
      LaunchScene.firstOpen => 'Are you ready to Grow Daily?',
      LaunchScene.eid => 'Eid Mubarak Grow Daily',
      LaunchScene.fullDay => 'Square by square you Grow Daily',
      LaunchScene.saturday => 'Ready to Grow Daily?',
      LaunchScene.update => 'Bright ideas help you Grow Daily',
      LaunchScene.stepsGoal => 'On the move you Grow Daily',
      LaunchScene.summerNoon => 'Under the sun we Grow Daily',
      LaunchScene.winterWait => 'Missing winter while we Grow Daily',
      LaunchScene.walk => 'Every step helps us Grow Daily',
    };

/// The line once a slow load has him looking with his magnifier (see
/// LaunchCurtain.slowAfter).
const kLaunchSlowLine = 'Slow or fast we Grow Daily';

/// Where the launch day turns: an open at 01:00 still belongs to the night
/// before, so the first open after it in the morning is the day's first.
const int kLaunchDayStartsHour = 4;

/// The presets that are walks: the one the steps link was built for (see
/// IslamicHabitCatalog's daily_walk).
const kWalkingCatalogIds = {'daily_walk'};

/// Whether any of [habits] is a walk: linked to the phone's step count
/// (stepGoal, which step_auto_complete settles), the walking preset, or a
/// name the steps offer reads as walking (looksLikeStepHabit, the same test
/// that offers the link in Add Habit, in either language). A false yes
/// only means the walking scene for someone who does not walk.
bool hasWalkingHabit(Iterable<IslamicHabitTemplate> habits) {
  for (final h in habits) {
    if (h.stepGoal != null || kWalkingCatalogIds.contains(h.id)) return true;
    if (looksLikeStepHabit(h.name)) return true;
    final ar = h.nameAr;
    if (ar != null && looksLikeStepHabit(ar)) return true;
  }
  return false;
}

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
/// launch (nothing seen yet), and [installedAt] when that was, so the seed
/// stays owed for a few days if something else took it. [updated] is a new
/// version whose bulb has not played yet, noticed at [updateSince].
/// [lastFullDay] and [lastStepsGoal] are the last days seen with every owed
/// habit done and with the steps goal reached (LaunchMemory). [walker] is
/// whether this account has a walking habit (hasWalkingHabit); pass false
/// when the habits are not known yet, since a wrong false only means an
/// ordinary scene. [lastShown] is when each scene last played on this
/// phone and [lastScene] the scene the last launch played.
///
/// The rules and their order are the admin's splash page's
/// ([LaunchSettings]); built in, in order: the very first launch, back after
/// days away, a new version (not at night), Ramadan, night, Eid, yesterday
/// full, yesterday's steps goal, Saturday's recap, the morning's mug (never
/// with a fast on the plan or near Ramadan), a summer noon, the evening, a
/// walker's late afternoon, an afternoon missing winter; and otherwise the
/// anytime list. The summer noon, the evening and the walk play once a day
/// (kSplashOnceADay), so the day's other opens go to the anytime list.
///
/// A moment that plays once (the seed, the bulb, yesterday full, the steps
/// goal, Saturday, the mug, missing winter) is owed until it has played,
/// not only on the day's first open: when two fall on one morning, the
/// second plays on the next open instead of being lost (Aziz, 2026-10-01:
/// "make sure no conflict, like morning coffee and first open, or first
/// update, or first full day").
LaunchScene pickLaunchScene({
  required DateTime now,
  required DateTime? lastOpen,
  required bool fastingPlanned,
  bool freshInstall = false,
  DateTime? installedAt,
  bool updated = false,
  DateTime? updateSince,
  DateTime? lastFullDay,
  DateTime? lastStepsGoal,
  bool walker = false,
  Map<LaunchScene, DateTime> lastShown = const {},
  LaunchScene? lastScene,
  math.Random? random,
  LaunchSettings? settings,
}) {
  final rules = settings ?? LaunchSettings.current;
  // The admin's one scene for everyone, between its two days.
  final forced = rules.forcedOn(now);
  if (forced != null) return forced;

  final today = launchDayOf(now);
  final date = DateTime(now.year, now.month, now.day);
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  bool playedToday(LaunchScene scene) {
    final at = lastShown[scene];
    return at != null && launchDayOf(at) == today;
  }

  // Whether the rule only the scene itself knows holds (its hours, months
  // and switch were checked first, by the settings).
  bool holds(LaunchScene scene) {
    switch (scene) {
      case LaunchScene.firstOpen:
        if (freshInstall) return true;
        return installedAt != null &&
            lastShown[scene] == null &&
            today.difference(launchDayOf(installedAt)).inDays <
                rules.firstOpenDays;
      case LaunchScene.welcomeBack:
        return lastOpen != null &&
            today.difference(launchDayOf(lastOpen)).inDays >= rules.awayDays;
      case LaunchScene.update:
        return updated &&
            (updateSince == null ||
                today.difference(launchDayOf(updateSince)).inDays <
                    rules.updateDays);
      case LaunchScene.ramadanLantern:
        return isRamadanDay(date);
      case LaunchScene.eid:
        return isEidDay(date);
      case LaunchScene.fullDay:
        return _sameDate(lastFullDay, yesterday) && !playedToday(scene);
      case LaunchScene.stepsGoal:
        return _sameDate(lastStepsGoal, yesterday) && !playedToday(scene);
      case LaunchScene.saturday:
        // From the hour the recap is ready, which is the hour the scene
        // starts from, once.
        final recapReady = DateTime(
          now.year,
          now.month,
          now.day,
          rules.hours[scene]?.from ?? 10,
        );
        return now.weekday == DateTime.saturday &&
            !now.isBefore(recapReady) &&
            !playedToday(scene);
      case LaunchScene.morningCoffee:
        return !playedToday(scene) &&
            !fastingPlanned &&
            !isNearRamadanDay(date);
      case LaunchScene.winterWait:
        // Once a day, as Saturday's recap: his worried wait is a treat, not
        // what every open that afternoon shows. Later opens may still draw
        // it from the anytime list.
        return !playedToday(scene);
      case LaunchScene.walk:
        return walker && (rules.walkerHours?.contains(now.hour) ?? false);
      case LaunchScene.nightAsleep:
      case LaunchScene.summerNoon:
      case LaunchScene.eveningChecklist:
      case LaunchScene.dayRing:
      case LaunchScene.turnaround:
        return true;
    }
  }

  for (final scene in rules.order) {
    if (!rules.allows(scene, now)) continue;
    // An every-open moment the admin keeps to once a day.
    if (rules.onceADay.contains(scene) && playedToday(scene)) continue;
    // A day this moment steps aside for the anytime list.
    if (!rules.playsOn(scene, today)) continue;
    if (holds(scene)) return scene;
  }
  return pickAnytimeScene(
    now: now,
    rules: rules,
    lastShown: lastShown,
    lastScene: lastScene,
    random: random,
  );
}

/// The anytime list's pick: among its scenes on at [now] (their hours and
/// months), one this phone has never shown when there is one and the admin
/// wants new ones first, never the scene the last launch played when
/// another can play, and otherwise by share. The ring when nothing can.
LaunchScene pickAnytimeScene({
  required DateTime now,
  required LaunchSettings rules,
  Map<LaunchScene, DateTime> lastShown = const {},
  LaunchScene? lastScene,
  math.Random? random,
}) {
  var candidates = anytimeScenesAt(now, rules);
  if (candidates.isEmpty) return LaunchScene.dayRing;
  if (rules.newFirst) {
    final unseen = [
      for (final s in candidates)
        if (lastShown[s] == null) s,
    ];
    if (unseen.isNotEmpty) candidates = unseen;
  }
  if (rules.noRepeat && candidates.length > 1) {
    candidates = [
      for (final s in candidates)
        if (s != lastScene) s,
    ];
  }
  final total = candidates.fold<int>(0, (sum, s) => sum + rules.pool[s]!);
  var roll = (random ?? math.Random()).nextInt(total);
  for (final scene in candidates) {
    roll -= rules.pool[scene]!;
    if (roll < 0) return scene;
  }
  return candidates.last;
}

/// The anytime scenes that can play at [now]: in the list, switched on,
/// inside their hours and months; in [LaunchScene]'s order.
List<LaunchScene> anytimeScenesAt(DateTime now, LaunchSettings rules) => [
      for (final scene in LaunchScene.values)
        if (rules.pool.containsKey(scene) && rules.allows(scene, now)) scene,
    ];

/// Set with `--dart-define=GD_LAUNCH_CYCLE=true` to see every scene on a
/// device without waiting for the hour: each cold start then plays the next
/// scene in [LaunchScene]'s order, missing winter and the walk last. Off in
/// every normal build, where the compiler drops it.
const bool kLaunchSceneCycle = bool.fromEnvironment('GD_LAUNCH_CYCLE');

/// Set with `--dart-define=GD_LAUNCH_SCENE=<name>` (a [LaunchScene] value's
/// name, as `winterWait` or `walk`) to play that one scene on every launch
/// of a debug build, without waiting for its date, hour or habits. Wins
/// over [kLaunchSceneCycle]. Null in a profile or release build, and for a
/// name that is not a scene's.
final LaunchScene? kLaunchSceneForced = launchSceneNamed(
  const String.fromEnvironment('GD_LAUNCH_SCENE'),
  debug: kDebugMode,
);

/// The scene called [name], only in a [debug] build (see
/// [kLaunchSceneForced]).
LaunchScene? launchSceneNamed(String name, {required bool debug}) {
  if (!debug || name.isEmpty) return null;
  for (final scene in LaunchScene.values) {
    if (scene.name == name) return scene;
  }
  return null;
}

/// The scene a build's switch fixes for this launch instead of
/// [pickLaunchScene]'s choice: [kLaunchSceneForced], then the cycle's next
/// ([kLaunchSceneCycle]). Null in every normal build.
LaunchScene? launchSceneFixed() =>
    kLaunchSceneForced ?? (kLaunchSceneCycle ? LaunchMemory.cycledScene : null);

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
  static const _installedKey = 'launch_installed_v1';
  static const _newVersionKey = 'launch_new_version_v1';
  static const _updateShownKey = 'launch_update_shown_v1';
  static const _shownKey = 'launch_scene_shown_v1';
  static const _lastSceneKey = 'launch_last_scene_v1';

  static DateTime? _lastOpen;
  static DateTime? _lastFullDay;
  static DateTime? _lastStepsGoal;
  static String? _lastVersion;
  static String? _version;
  static DateTime? _installedAt;
  static String? _newVersion;
  static DateTime? _newVersionSince;
  static String? _updateShown;
  static Map<LaunchScene, DateTime> _shown = {};
  static LaunchScene? _lastScene;
  static bool _loaded = false;
  static int _cycle = 0;

  /// The open before this one, or null (fresh install, or never loaded).
  static DateTime? get lastOpen => _lastOpen;

  /// The last day seen with every owed habit done, or null.
  static DateTime? get lastFullDay => _lastFullDay;

  /// The last day seen with the steps goal reached, or null.
  static DateTime? get lastStepsGoal => _lastStepsGoal;

  /// Whether a new version's bulb is owed: the running version is known,
  /// was first opened after another one (not a fresh install), and its bulb
  /// has not played. False when the version cannot be read. How long it
  /// stays owed is the picker's ([updateSince], the settings' updateDays).
  static bool get updated =>
      _version != null && _newVersion == _version && _updateShown != _version;

  /// When this version was first opened after another one, or null.
  static DateTime? get updateSince =>
      _newVersion == _version ? _newVersionSince : null;

  /// When the very first launch on this phone was, or null when it was
  /// before this was kept (every phone that had the app already).
  static DateTime? get installedAt => _installedAt;

  /// When each scene last played on this phone.
  static Map<LaunchScene, DateTime> get lastShown => Map.unmodifiable(_shown);

  /// The scene the last curtain played, or null.
  static LaunchScene? get lastScene => _lastScene;

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
      _installedAt = read(_installedKey);
      final nv = box.get(_newVersionKey);
      if (nv is String && nv.contains('|')) {
        final cut = nv.lastIndexOf('|');
        _newVersion = nv.substring(0, cut);
        _newVersionSince = DateTime.tryParse(nv.substring(cut + 1));
      }
      final us = box.get(_updateShownKey);
      _updateShown = us is String ? us : null;
      _shown = _readShown(box.get(_shownKey));
      final ls = box.get(_lastSceneKey);
      _lastScene = ls is String ? LaunchScene.values.asNameMap()[ls] : null;
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
    // A version opened for the first time after another: its bulb is owed
    // from now until it plays (or the settings' updateDays pass).
    final version = _version;
    if (_loaded &&
        version != null &&
        _lastVersion != null &&
        _lastVersion != version &&
        _newVersion != version) {
      _newVersion = version;
      _newVersionSince = DateTime.now();
      try {
        final box = await LocalStoreService.settingsBox();
        await box.put(
          _newVersionKey,
          '$version|${_newVersionSince!.toIso8601String()}',
        );
      } catch (_) {}
    }
  }

  static Map<LaunchScene, DateTime> _readShown(Object? raw) {
    if (raw is! String) return {};
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return {};
      final scenes = LaunchScene.values.asNameMap();
      return {
        for (final e in data.entries)
          if (scenes[e.key] != null && e.value is String)
            if (DateTime.tryParse(e.value as String) case final at?)
              scenes[e.key]!: at,
      };
    } catch (_) {
      return {};
    }
  }

  /// Notes that [scene] played at [now]: what the picker reads as owed,
  /// played today, never seen, and the last launch's scene. The bulb's
  /// version counts as seen once it has played.
  static void recordShown(LaunchScene scene, DateTime now) {
    _shown = {..._shown, scene: now};
    _lastScene = scene;
    if (scene == LaunchScene.update && _version != null) {
      _updateShown = _version;
    }
    if (!_loaded) return;
    final shown = jsonEncode({
      for (final e in _shown.entries) e.key.name: e.value.toIso8601String(),
    });
    final updateShown = _updateShown;
    LocalStoreService.settingsBox().then((box) async {
      await box.put(_shownKey, shown);
      await box.put(_lastSceneKey, scene.name);
      if (updateShown != null) await box.put(_updateShownKey, updateShown);
    }).catchError((Object _) {});
  }

  /// Notes the very first launch on this phone, once, so its seed stays
  /// owed if another scene took that open.
  static void recordInstall(DateTime now) {
    if (_installedAt != null) return;
    _installedAt = now;
    _write(_installedKey, now);
  }

  /// Stores [now] as the last open, and this version as the one last
  /// opened. A no-op unless [load] ran, which keeps widget tests (no boxes
  /// open) off the disk.
  static void recordOpen(DateTime now) {
    if (!_loaded) return;
    LocalStoreService.settingsBox().then((box) async {
      await box.put(_key, now.toIso8601String());
      // The version is stored even when [load] ran out of time reading it
      // (300 ms, a slow cold start): left unstored, the next launch took
      // this same version for a new one and played the bulb a launch late.
      final version = _version ?? await _readVersion();
      if (version != null) await box.put(_versionKey, version);
    }).catchError((Object _) {});
  }

  /// Makes the next scene a return's, not the launch's: [lastOpen] becomes
  /// [since], the moment the app left the screen. A bulb still owed stays
  /// owed: it plays on the return if the launch could not. Called by
  /// main.dart just before a long return plays the
  /// curtain again (see kLaunchReplayAfter).
  ///
  /// Without it the return would choose from what the launch knew: the open
  /// before this PROCESS, which can be days old (the welcome back to someone
  /// who used the app an hour ago). [recordOpen] only writes the disk, for
  /// the next launch, so it cannot answer that. The bulb plays once
  /// ([recordShown]), so a return no longer needs to mark the version.
  static void beginReturn({required DateTime since}) {
    _lastOpen = since;
    if (kLaunchSceneCycle) _cycle++;
  }

  static Future<String?> _readVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return _version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      return null;
    }
  }

  /// Notes [day] as a day with every owed habit done (the Grid's day card
  /// says so). Only ever moves forward.
  static void recordFullDay(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    if (_lastFullDay != null && !date.isAfter(_lastFullDay!)) return;
    _lastFullDay = date;
    _write(_fullDayKey, date);
  }

  /// Takes [day] back when it stops being full: a square undone, or a habit
  /// owed today added after the last tick. Only [day] itself, so an older
  /// full day is never touched, and nothing is written unless it changes.
  static void clearFullDay(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    if (_lastFullDay != date) return;
    _lastFullDay = null;
    if (!_loaded) return;
    LocalStoreService.settingsBox()
        .then((box) => box.delete(_fullDayKey))
        .catchError((Object _) {});
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
    DateTime? installedAt,
    String? newVersion,
    DateTime? newVersionSince,
    String? updateShown,
    Map<LaunchScene, DateTime> shown = const {},
    LaunchScene? lastScene,
  }) {
    _installedAt = installedAt;
    _newVersion = newVersion;
    _newVersionSince = newVersionSince;
    _updateShown = updateShown;
    _shown = {...shown};
    _lastScene = lastScene;
    _lastOpen = lastOpen;
    _loaded = loaded;
    _lastFullDay = lastFullDay;
    _lastStepsGoal = lastStepsGoal;
    _lastVersion = lastVersion;
    _version = version;
  }
}
