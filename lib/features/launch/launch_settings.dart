import 'package:flutter/foundation.dart';

import '../../core/l10n/wording_edits.dart';
import 'launch_scene.dart';

// ─── Built-in ───────────────────────────────────────────────────────────────
//
// When each launch scene plays and how long the curtain stays, as the app has
// it when nothing is edited on the admin tool's splash page (Aziz,
// 2026-10-01: "he can control when each appear and etc"). The page reads
// these values out of this file (scripts/admin_lookup/lib/splash_admin.js),
// so keep each one on a line of its own in this exact shape:
// `const int kSplashX = N;` for a number, `'scene',` for an order entry,
// `'scene': (from, to),` for hours, `'scene': '6,7',` for months and
// `'scene': N,` for a share. Its test fails the moment it stops finding
// them all.

/// The shortest the curtain stays, in milliseconds: long enough for Doum's
/// scene to read. Four seconds since 2026-10-01 (Aziz: "make the timing
/// longer a little bit, add 1 sec for each screen"); three before.
const int kSplashMinShowMs = 4000;

/// The longest it stays, ready or not, in milliseconds (a second more with
/// the minimum).
const int kSplashMaxShowMs = 9000;

/// Minutes away before a return plays the curtain again (a new app day plays
/// it whatever the gap).
const int kSplashReplayAfterMinutes = 30;

/// Days away that count as coming back (the welcome-back scene).
const int kSplashAwayDays = 3;

/// Days the very first launch's scene (the seed) stays owed when something
/// else took the first open, so it is never lost to an admin's forced scene
/// or a reordered list.
const int kSplashFirstOpenDays = 3;

/// Days a new version's scene (the bulb) stays owed: it waits out the night
/// and a welcome back, and is dropped after this rather than shown for a
/// version that is old news.
const int kSplashUpdateDays = 7;

/// 1: a scene from the anytime list this phone has never shown wins the
/// anytime pick, so a new scene is seen soon after it ships (Aziz,
/// 2026-10-01: "I love users to see new ones"). 0: shares only.
const int kSplashNewFirst = 1;

/// The walkers' hour: from this hour up to, not including, the next, every
/// open plays the walk for someone with a walking or steps habit. The walk's
/// own hours (none built in) are where it may play at all, the anytime list
/// included. The same hour twice is no walkers' hour.
const int kSplashWalkerFromHour = 16;
const int kSplashWalkerToHour = 18;

/// 1: the anytime pick never repeats the scene the last launch played, when
/// another can play. 0: it may.
const int kSplashNoRepeat = 1;

/// The range the admin page allows each number, and the one this build
/// accepts: outside it an edit is dropped for the built-in value. The same
/// ranges as scripts/admin_lookup/wording/splash_rules.js, held to one set of
/// cases (test/fixtures/splash_cases.json there).
const Map<String, (int, int)> kSplashNumberRanges = {
  'minShowMs': (1000, 10000),
  'maxShowMs': (3000, 20000),
  'replayAfterMinutes': (1, 1440),
  'awayDays': (1, 60),
  'firstOpenDays': (1, 14),
  'updateDays': (1, 30),
  'newFirst': (0, 1),
  'noRepeat': (0, 1),
  'walkerFromHour': (0, 23),
  'walkerToHour': (0, 24),
};

/// The scenes in the order they take precedence: the first whose rule holds
/// wins. When none holds, the anytime list plays ([kSplashPoolWeights]).
///
/// The very first launch leads (a new person's welcome is the seed, not
/// Doum asleep); a new version's bulb comes before Ramadan, which takes every
/// open of the month, and keeps out of the night by its hours instead. A
/// walker's afternoon is the walk's before missing winter's (Aziz,
/// 2026-10-01: "the walking and the steps should be more").
const List<String> kSplashSceneOrder = [
  'firstOpen',
  'welcomeBack',
  'update',
  'ramadanLantern',
  'nightAsleep',
  'eid',
  'fullDay',
  'stepsGoal',
  'saturday',
  'morningCoffee',
  'summerNoon',
  'eveningChecklist',
  'walk',
  'winterWait',
];

/// The hours a scene plays in: from this hour up to, not including, that one.
/// A first hour after the second wraps past midnight, 24 is midnight. Saturday
/// plays from the hour its recap is ready. A scene not here has no hours.
const Map<String, (int, int)> kSplashSceneHours = {
  'update': (4, 22),
  'nightAsleep': (22, 4),
  'saturday': (10, 24),
  'morningCoffee': (4, 11),
  'summerNoon': (12, 16),
  'eveningChecklist': (18, 22),
  'winterWait': (15, 18),
};

/// The months a scene plays in (1 is January), as a comma list. A scene not
/// here plays in every month.
///
/// Missing winter plays every month but Bahrain's winter, December to
/// February, when it has come (Aziz, 2026-10-01: "all months but not in
/// winter").
const Map<String, String> kSplashSceneMonths = {
  'summerNoon': '6,7,8,9',
  'winterWait': '3,4,5,6,7,8,9,10,11',
};

/// The anytime list: what plays when no rule in [kSplashSceneOrder] holds,
/// each scene's share of the pick (0 leaves it out), inside its own hours
/// and months. Only these scenes may be in it: the others say something
/// that is only true at their moment (yesterday full, Saturday's recap,
/// Eid). Walking and steps weigh most (Aziz, 2026-10-01: "the walking and
/// the steps should be more"); the seed is the first launch's plant.
const Map<String, int> kSplashPoolWeights = {
  'dayRing': 2,
  'turnaround': 2,
  'walk': 4,
  'stepsGoal': 4,
  'firstOpen': 2,
  'winterWait': 2,
  'update': 0,
};

/// The moments that play on every open of their hours, and whether each
/// plays only once a day instead (1) or on every open (0). Once a day hands
/// the day's other opens to the anytime list, so more scenes are seen
/// (Aziz, 2026-10-01: "I love users to see new ones"). Night, Ramadan and
/// Eid keep every open: the quiet of the night, the month and the feast.
/// The other moments play once by their nature (the mug, the squares, the
/// page, missing winter) and are not here.
const Map<String, int> kSplashOnceADay = {
  'nightAsleep': 0,
  'ramadanLantern': 0,
  'eid': 0,
  'summerNoon': 1,
  'eveningChecklist': 1,
  'walk': 1,
};

/// How often a moment plays: the percent of days it takes its open, the
/// rest of its days handing that open to the anytime list. A scene not here
/// plays every day it can (100). Which days is fixed per scene and day
/// ([launchDayRoll]), so a day that skips the evening checklist skips it on
/// every open, and the admin page's preview knows which.
///
/// The everyday moments step aside some days so walking, steps and the rest
/// of the anytime list come up more (Aziz, 2026-10-01: "the walking and the
/// steps should be more ... I love users to see new ones").
const Map<String, int> kSplashDailyChance = {
  'morningCoffee': 70,
  'summerNoon': 60,
  'eveningChecklist': 60,
  'winterWait': 50,
};

/// The most share one anytime scene may have.
const int kSplashPoolWeightMax = 10;

/// The longest line the admin may write under Doum.
const int kSplashLineMaxLength = 60;

/// A number from 0 to 99 fixed for [scene] on the launch day [day]: the
/// scene plays that day when it is below its chance. The same on every
/// phone, so the admin page's preview can say which days a moment steps
/// aside; scripts/admin_lookup/wording/splash_rules.js computes it the same
/// way (Park and Miller's generator over the scene's name and the date).
int launchDayRoll(LaunchScene scene, DateTime day) {
  const m = 2147483647;
  var h = 0;
  for (final c in scene.name.codeUnits) {
    h = (h * 31 + c) % m;
  }
  h = (h + day.year * 372 + day.month * 31 + day.day) % m;
  for (var i = 0; i < 3; i++) {
    h = (h * 48271) % m;
  }
  return h % 100;
}

/// What a scene's own hours are, as a window of the day.
@immutable
class LaunchWindow {
  const LaunchWindow(this.from, this.to);

  final int from;
  final int to;

  bool contains(int hour) =>
      from < to ? hour >= from && hour < to : hour >= from || hour < to;
}

/// The launch splash's settings in force: the built-in values with the
/// admin's edits laid over them, every edit checked and dropped when this
/// build cannot use it, like [PetSettings].
@immutable
class LaunchSettings {
  const LaunchSettings._({
    required this.numbers,
    required this.order,
    required this.off,
    required this.hours,
    required this.months,
    required this.forceScene,
    required this.forceFrom,
    required this.forceTo,
    required this.pool,
    required this.onceADay,
    required this.chance,
    required this.lines,
    required this.slowLine,
  });

  /// Every number in force, by name (the names of [kSplashNumberRanges]).
  final Map<String, int> numbers;

  int get minShowMs => numbers['minShowMs']!;
  int get maxShowMs {
    // The cap always leaves room after the minimum, or a ready load could
    // never lift before it.
    final cap = numbers['maxShowMs']!;
    return cap < minShowMs + 1000 ? minShowMs + 1000 : cap;
  }

  int get replayAfterMinutes => numbers['replayAfterMinutes']!;
  int get awayDays => numbers['awayDays']!;
  int get firstOpenDays => numbers['firstOpenDays']!;
  int get updateDays => numbers['updateDays']!;
  bool get newFirst => numbers['newFirst'] == 1;
  bool get noRepeat => numbers['noRepeat'] == 1;

  /// The walkers' hour, or null when the admin set none.
  LaunchWindow? get walkerHours {
    final from = numbers['walkerFromHour']!;
    final to = numbers['walkerToHour']!;
    return from == to ? null : LaunchWindow(from, to);
  }

  Duration get minShow => Duration(milliseconds: minShowMs);
  Duration get maxShow => Duration(milliseconds: maxShowMs);

  /// The scenes in precedence order, those switched off left in (see [off]).
  final List<LaunchScene> order;

  /// Scenes switched off.
  final Set<LaunchScene> off;

  /// A scene's hours, when it has any.
  final Map<LaunchScene, LaunchWindow> hours;

  /// A scene's months, when it has any limit.
  final Map<LaunchScene, Set<int>> months;

  /// The scene played for everyone, between [forceFrom] and [forceTo] (local
  /// days, either may be null for open).
  final LaunchScene? forceScene;
  final DateTime? forceFrom;
  final DateTime? forceTo;

  /// The anytime list: each scene's share, only those above 0.
  final Map<LaunchScene, int> pool;

  /// The every-open moments set to play once a day.
  final Set<LaunchScene> onceADay;

  /// The percent of days each moment plays, those below 100 only.
  final Map<LaunchScene, int> chance;

  /// Whether [scene] plays on [day] by its [chance].
  bool playsOn(LaunchScene scene, DateTime day) {
    final percent = chance[scene];
    return percent == null || launchDayRoll(scene, day) < percent;
  }

  /// Lines the admin rewrote, by scene.
  final Map<LaunchScene, String> lines;

  /// The slow load's line, as the admin wrote it or the app's.
  final String slowLine;

  /// The line under Doum in [scene].
  String line(LaunchScene scene) => lines[scene] ?? launchLine(scene);

  /// Whether [scene] plays at [now] by its switch, hours and months alone.
  bool allows(LaunchScene scene, DateTime now) {
    if (off.contains(scene)) return false;
    final window = hours[scene];
    if (window != null && !window.contains(now.hour)) return false;
    final inMonths = months[scene];
    if (inMonths != null && !inMonths.contains(now.month)) return false;
    return true;
  }

  /// The scene played for everyone on [now]'s day, or null.
  LaunchScene? forcedOn(DateTime now) {
    final scene = forceScene;
    if (scene == null) return null;
    final day = DateTime(now.year, now.month, now.day);
    if (forceFrom != null && day.isBefore(forceFrom!)) return null;
    if (forceTo != null && day.isAfter(forceTo!)) return null;
    return scene;
  }

  /// Nothing edited.
  static final LaunchSettings builtIn = LaunchSettings.from(null);

  factory LaunchSettings.from(SplashEdits? edits) {
    final scenes = LaunchScene.values.asNameMap();

    final numbers = <String, int>{
      for (final e in kSplashNumberRanges.entries)
        e.key: switch (edits?.numbers[e.key]) {
          final int v when v >= e.value.$1 && v <= e.value.$2 => v,
          _ => _builtInNumbers[e.key]!,
        },
    };

    // The built-in order, or the edited one: every name that is a scene of
    // the order, once; a scene the edit leaves out follows in its built-in
    // place order, so a stale edit never drops a scene this build gained.
    final builtInOrder = [for (final n in kSplashSceneOrder) scenes[n]!];
    final order = <LaunchScene>[];
    for (final name in edits?.order ?? const <String>[]) {
      final scene = scenes[name];
      if (scene != null && builtInOrder.contains(scene) && !order.contains(scene)) {
        order.add(scene);
      }
    }
    for (final scene in builtInOrder) {
      if (!order.contains(scene)) order.add(scene);
    }

    final off = {
      for (final name in edits?.off ?? const <String>[])
        if (scenes[name] != null) scenes[name]!,
    };

    final hours = <LaunchScene, LaunchWindow>{
      for (final e in kSplashSceneHours.entries)
        scenes[e.key]!: LaunchWindow(e.value.$1, e.value.$2),
    };
    edits?.hours.forEach((name, pair) {
      final scene = scenes[name];
      if (scene == null || pair.length != 2) return;
      final from = pair[0];
      final to = pair[1];
      // 0 to 24 is the whole day: the same as no hours.
      if (from < 0 || from > 23 || to < 0 || to > 24 || from == to) return;
      hours[scene] = LaunchWindow(from, to);
    });

    final months = <LaunchScene, Set<int>>{
      for (final e in kSplashSceneMonths.entries)
        scenes[e.key]!: _monthSet(e.value),
    };
    edits?.months.forEach((name, list) {
      final scene = scenes[name];
      if (scene == null) return;
      final valid = {
        for (final m in list)
          if (m >= 1 && m <= 12) m,
      };
      // An empty list is every month, as for a scene with no limit.
      if (valid.isEmpty) {
        months.remove(scene);
      } else {
        months[scene] = valid;
      }
    });

    LaunchScene? forceScene = scenes[edits?.forceScene ?? ''];
    final from = _day(edits?.forceFrom);
    final to = _day(edits?.forceTo);
    if (forceScene != null && from != null && to != null && to.isBefore(from)) {
      forceScene = null;
    }

    final pool = <LaunchScene, int>{
      for (final e in kSplashPoolWeights.entries) scenes[e.key]!: e.value,
    };
    edits?.pool.forEach((name, weight) {
      final scene = scenes[name];
      if (scene == null || !pool.containsKey(scene)) return;
      if (weight < 0 || weight > kSplashPoolWeightMax) return;
      pool[scene] = weight;
    });
    pool.removeWhere((_, weight) => weight == 0);

    final onceADay = <LaunchScene>{
      for (final e in kSplashOnceADay.entries)
        if (e.value == 1) scenes[e.key]!,
    };
    edits?.onceADay.forEach((name, value) {
      final scene = scenes[name];
      if (scene == null || !kSplashOnceADay.containsKey(name)) return;
      if (value == 1) onceADay.add(scene);
      if (value == 0) onceADay.remove(scene);
    });

    final chance = <LaunchScene, int>{
      for (final e in kSplashDailyChance.entries) scenes[e.key]!: e.value,
    };
    edits?.chance.forEach((name, percent) {
      final scene = scenes[name];
      if (scene == null || percent < 0 || percent > 100) return;
      chance[scene] = percent;
    });
    chance.removeWhere((_, percent) => percent == 100);

    final lines = <LaunchScene, String>{};
    edits?.lines.forEach((name, text) {
      final scene = scenes[name];
      final line = _cleanLine(text);
      if (scene != null && line != null) lines[scene] = line;
    });

    return LaunchSettings._(
      pool: Map.unmodifiable(pool),
      onceADay: Set.unmodifiable(onceADay),
      chance: Map.unmodifiable(chance),
      lines: Map.unmodifiable(lines),
      slowLine: _cleanLine(edits?.slowLine) ?? kLaunchSlowLine,
      numbers: Map.unmodifiable(numbers),
      order: List.unmodifiable(order),
      off: Set.unmodifiable(off),
      hours: Map.unmodifiable(hours),
      months: Map.unmodifiable(months),
      forceScene: forceScene,
      forceFrom: from,
      forceTo: to,
    );
  }

  static const Map<String, int> _builtInNumbers = {
    'minShowMs': kSplashMinShowMs,
    'maxShowMs': kSplashMaxShowMs,
    'replayAfterMinutes': kSplashReplayAfterMinutes,
    'awayDays': kSplashAwayDays,
    'firstOpenDays': kSplashFirstOpenDays,
    'updateDays': kSplashUpdateDays,
    'newFirst': kSplashNewFirst,
    'noRepeat': kSplashNoRepeat,
    'walkerFromHour': kSplashWalkerFromHour,
    'walkerToHour': kSplashWalkerToHour,
  };

  /// A line the admin wrote, trimmed, or null when it is empty or too long
  /// to sit under him.
  static String? _cleanLine(String? text) {
    if (text == null) return null;
    final line = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (line.isEmpty || line.length > kSplashLineMaxLength) return null;
    return line;
  }

  static Set<int> _monthSet(String list) =>
      {for (final m in list.split(',')) int.parse(m)};

  /// A local day from yyyy-mm-dd, or null for anything else.
  static DateTime? _day(String? text) {
    if (text == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (m == null) return null;
    final y = int.parse(m[1]!);
    final mo = int.parse(m[2]!);
    final d = int.parse(m[3]!);
    final day = DateTime(y, mo, d);
    // 02-31 rolls over to March: not a day.
    return day.month == mo && day.day == d ? day : null;
  }

  static SplashEdits? _seen;
  static LaunchSettings _inForce = builtIn;

  /// The settings in force now: read at the moment of use, so a save on the
  /// admin page reaches the next launch (and a stay-open phone's next
  /// return) within a second or two.
  static LaunchSettings get current {
    final edits = WordingEditsStore.current.splash;
    if (!identical(edits, _seen)) {
      _seen = edits;
      _inForce = edits == null ? builtIn : LaunchSettings.from(edits);
    }
    return _inForce;
  }

  /// Every value in force by name, the shape test/fixtures/splash_cases.json
  /// expects (the admin page resolves the same cases).
  @visibleForTesting
  Map<String, Object?> describe() => {
        ...numbers,
        'order': [for (final s in order) s.name],
        'off': [for (final s in LaunchScene.values) if (off.contains(s)) s.name],
        'hours': {
          for (final e in hours.entries) e.key.name: [e.value.from, e.value.to],
        },
        'months': {
          for (final e in months.entries) e.key.name: ([...e.value]..sort()),
        },
        'pool': {
          for (final s in LaunchScene.values)
            if (pool.containsKey(s)) s.name: pool[s],
        },
        'onceADay': [
          for (final s in LaunchScene.values)
            if (onceADay.contains(s)) s.name,
        ],
        'chance': {
          for (final s in LaunchScene.values)
            if (chance.containsKey(s)) s.name: chance[s],
        },
        'lines': {
          for (final s in LaunchScene.values)
            if (lines.containsKey(s)) s.name: lines[s],
        },
        'slowLine': slowLine,
        'force': forceScene == null
            ? null
            : {
                'scene': forceScene!.name,
                'from': forceFrom == null ? null : _ymd(forceFrom!),
                'to': forceTo == null ? null : _ymd(forceTo!),
              },
      };

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
