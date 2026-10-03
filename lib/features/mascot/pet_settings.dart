import 'package:flutter/widgets.dart';

import '../../core/l10n/wording_edits.dart';
import '../../shared/widgets/victory_burst.dart';
import '../habits/models/habit_model.dart';
import 'sprout_praise.dart';

// ─── Built-in ───────────────────────────────────────────────────────────────
//
// What Doum does when nothing is edited on the admin tool's «دوم» page, and
// what that page shows beside each setting (Aziz, 2026-09-28: "make
// everything changeable in the admin page", then "add the confetti sizes
// too"). The page reads these values out
// of this file (scripts/admin_lookup/lib/pet_admin.js), so keep each one on
// a line of its own in this exact shape: `const int kPetX = N;` for a number,
// `'key': 'value',` for a map entry. Its test fails the moment it stops
// finding them all.

/// Seconds between two praise lines. Every square done still hops at once;
/// only the words wait (Aziz, 2026-09-28: five prayers ticked in a row
/// flashed five lines nobody could read). 0 lets every square speak.
const int kPetPraiseEverySeconds = 20;

/// Seconds a bubble stays before it fades.
const int kPetBubbleSeconds = 3;

/// Lines remembered, so none is said again until the lists run out: more
/// than any group's two lists together.
const int kPetRememberLines = 30;

/// Before this hour an empty day says «صباح الخير»; from it, «هلا».
const int kPetMorningUntilHour = 12;

/// From this hour a finished day sleeps.
const int kPetBedtimeHour = 21;

/// Until this hour an empty new day sleeps: a wave asking «نبدأ؟» at 1am
/// would be the wrong thing to say.
const int kPetWakeHour = 4;

// The confetti of the day's three moments, each bigger than the one before
// (Aziz, 2026-09-28): a habit's square finishing its day, the streak point,
// and every habit done, which fires two bursts. For each: how many pieces
// (0 fires none), how far they fly in points, and how long they last in
// milliseconds.

const int kPetSquareConfettiPieces = 16;
const int kPetSquareConfettiSpread = 72;
const int kPetSquareConfettiMs = 650;

const int kPetStreakConfettiPieces = 16;
const int kPetStreakConfettiSpread = 72;
const int kPetStreakConfettiMs = 650;

const int kPetFullDayConfettiPieces = 30;
const int kPetFullDayConfettiSpread = 130;
const int kPetFullDayConfettiMs = 1000;

const int kPetFullDaySecondConfettiPieces = 22;
const int kPetFullDaySecondConfettiSpread = 170;
const int kPetFullDaySecondConfettiMs = 1100;

/// The list each category hears (HabitCategory name: list name). A typed
/// habit only ever has one of Add Habit's chips (faith, health, learning,
/// focus, sleep, money, mind, social, custom); the finer five belong to
/// ready-made habits.
const Map<String, String> kPetCategoryLists = {
  'faith': 'faith',
  'quran': 'quran',
  'athkar': 'athkar',
  'fasting': 'fasting',
  'sadaqah': 'sadaqah',
  'fitness': 'sport',
  'health': 'health',
  'learning': 'learning',
  'focus': 'focus',
  'sleep': 'sleep',
  'money': 'money',
  'mind': 'mind',
  'social': 'social',
  'custom': 'general',
};

/// Ready-made habits whose category is right for their icon and stats but
/// not for praise (catalog id: list name). Tahajjud is filed under athkar,
/// yet it is a night prayer, so it hears the prayer lines. The rest are
/// filed under custom, or are a quit habit, and would hear only the general
/// list, though the app knows exactly what they are (Aziz, 2026-10-03: the
/// words must fit the habit). «استيقظ قبل الساعة 6» stays general: no list
/// fits waking early.
const Map<String, String> kPetPresetLists = {
  'tahajjud': 'faith',
  'marriage_dua': 'faith',
  'lower_gaze': 'faith',
  'marriage_gratitude': 'social',
  'marriage_checkin': 'social',
  'marriage_read': 'learning',
  'deep_work_block': 'focus',
  'inbox_zero': 'focus',
  'daily_planning': 'focus',
  'no_phone_morning': 'mind',
  'cold_shower': 'health',
  'no_sugar': 'health',
};

/// The wider list a narrow one also draws on, so a Quran page can hear
/// «تقبّل الله» too (list name: list name). One step only: a list's own
/// lines and this one's, never the general ones (Aziz, 2026-10-03: the
/// words must fit the habit).
const Map<String, String> kPetAlsoHears = {
  'quran': 'faith',
  'athkar': 'faith',
  'fasting': 'faith',
  'sadaqah': 'faith',
  'sport': 'health',
};

/// The list every quit habit hears: its green square is a day kept clean,
/// not a thing done, and a day off TikTok hearing the focus list's
/// «شغل مرتب» would be odd.
const String kPetQuitList = 'general';

/// The range the admin page allows each number, and the one this build
/// accepts: outside it an edit is dropped for the built-in value. The same
/// ranges as scripts/admin_lookup/wording/pet_rules.js, held to one set of
/// cases (test/fixtures/pet_cases.json there).
const Map<String, (int, int)> kPetNumberRanges = {
  'praiseEverySeconds': (0, 300),
  'bubbleSeconds': (1, 10),
  'rememberLines': (0, 100),
  'morningUntilHour': (1, 23),
  'bedtimeHour': (12, 23),
  'wakeHour': (0, 11),
  'squareConfettiPieces': (0, 80),
  'squareConfettiSpread': (20, 300),
  'squareConfettiMs': (200, 3000),
  'streakConfettiPieces': (0, 80),
  'streakConfettiSpread': (20, 300),
  'streakConfettiMs': (200, 3000),
  'fullDayConfettiPieces': (0, 80),
  'fullDayConfettiSpread': (20, 300),
  'fullDayConfettiMs': (200, 3000),
  'fullDaySecondConfettiPieces': (0, 80),
  'fullDaySecondConfettiSpread': (20, 300),
  'fullDaySecondConfettiMs': (200, 3000),
};

/// Each number's built-in value, by the same names.
const Map<String, int> _builtInNumbers = {
  'praiseEverySeconds': kPetPraiseEverySeconds,
  'bubbleSeconds': kPetBubbleSeconds,
  'rememberLines': kPetRememberLines,
  'morningUntilHour': kPetMorningUntilHour,
  'bedtimeHour': kPetBedtimeHour,
  'wakeHour': kPetWakeHour,
  'squareConfettiPieces': kPetSquareConfettiPieces,
  'squareConfettiSpread': kPetSquareConfettiSpread,
  'squareConfettiMs': kPetSquareConfettiMs,
  'streakConfettiPieces': kPetStreakConfettiPieces,
  'streakConfettiSpread': kPetStreakConfettiSpread,
  'streakConfettiMs': kPetStreakConfettiMs,
  'fullDayConfettiPieces': kPetFullDayConfettiPieces,
  'fullDayConfettiSpread': kPetFullDayConfettiSpread,
  'fullDayConfettiMs': kPetFullDayConfettiMs,
  'fullDaySecondConfettiPieces': kPetFullDaySecondConfettiPieces,
  'fullDaySecondConfettiSpread': kPetFullDaySecondConfettiSpread,
  'fullDaySecondConfettiMs': kPetFullDaySecondConfettiMs,
};

/// One confetti burst's size: its pieces, how far they fly (logical points)
/// and how long they last.
@immutable
class PetBurst {
  const PetBurst({
    required this.pieces,
    required this.spread,
    required this.duration,
  });

  final int pieces;
  final double spread;
  final Duration duration;

  /// Fires it from [at], a point on the screen. No pieces, no burst.
  void fire(BuildContext context, Offset at) {
    if (pieces <= 0) return;
    showVictoryBurst(
      context,
      at,
      particleCount: pieces,
      spread: spread,
      duration: duration,
    );
  }
}

// ─── In force ───────────────────────────────────────────────────────────────

/// Doum's settings in force: the built-in values above with the admin's
/// edits (wording/live's `pet`, see pet_edits.dart) laid over them. An edit
/// this build cannot use (a number outside its range, a name it does not
/// know) is dropped for the built-in value, the rule every edit in
/// wording/live follows.
@immutable
class PetSettings {
  const PetSettings._({
    required this.numbers,
    required this.presetLists,
    required this.categoryLists,
    required this.alsoHears,
    required this.quitList,
  });

  /// Every number in force, by name (the names of [kPetNumberRanges]).
  final Map<String, int> numbers;

  int get praiseEverySeconds => numbers['praiseEverySeconds']!;
  int get bubbleSeconds => numbers['bubbleSeconds']!;
  int get rememberLines => numbers['rememberLines']!;
  int get morningUntilHour => numbers['morningUntilHour']!;
  int get bedtimeHour => numbers['bedtimeHour']!;
  int get wakeHour => numbers['wakeHour']!;

  /// A ready-made habit's own list, by catalog id; it wins over the quit
  /// rule and the category, the most particular choice there is.
  final Map<String, PraiseGroup> presetLists;
  final Map<HabitCategory, PraiseGroup> categoryLists;
  final Map<PraiseGroup, PraiseGroup> alsoHears;
  final PraiseGroup quitList;

  Duration get praiseEvery => Duration(seconds: praiseEverySeconds);
  Duration get bubbleFor => Duration(seconds: bubbleSeconds);

  /// A habit's square finishing its day.
  PetBurst get squareBurst => _burst('square');

  /// The streak point.
  PetBurst get streakBurst => _burst('streak');

  /// Every habit done: the first burst, then the second a beat later.
  PetBurst get fullDayBurst => _burst('fullDay');
  PetBurst get fullDaySecondBurst => _burst('fullDaySecond');

  PetBurst _burst(String moment) => PetBurst(
        pieces: numbers['${moment}ConfettiPieces']!,
        spread: numbers['${moment}ConfettiSpread']!.toDouble(),
        duration: Duration(milliseconds: numbers['${moment}ConfettiMs']!),
      );

  /// Nothing edited.
  static final PetSettings builtIn = PetSettings.from(null);

  factory PetSettings.from(PetEdits? edits) {
    final numbers = <String, int>{
      for (final e in kPetNumberRanges.entries)
        e.key: switch (edits?.numbers[e.key]) {
          final int v when v >= e.value.$1 && v <= e.value.$2 => v,
          _ => _builtInNumbers[e.key]!,
        },
    };

    final lists = PraiseGroup.values.asNameMap();
    final categories = HabitCategory.values.asNameMap();

    final presetLists = <String, PraiseGroup>{
      for (final e in kPetPresetLists.entries) e.key: lists[e.value]!,
    };
    edits?.presets.forEach((id, name) {
      if (id.isEmpty) return;
      // Empty: this habit follows its category, even one with a list of its
      // own built in.
      if (name.isEmpty) {
        presetLists.remove(id);
        return;
      }
      final list = lists[name];
      if (list != null) presetLists[id] = list;
    });

    final categoryLists = <HabitCategory, PraiseGroup>{
      for (final e in kPetCategoryLists.entries)
        categories[e.key]!: lists[e.value]!,
    };
    edits?.categories.forEach((name, listName) {
      final category = categories[name];
      final list = lists[listName];
      if (category != null && list != null) categoryLists[category] = list;
    });

    final alsoHears = <PraiseGroup, PraiseGroup>{
      for (final e in kPetAlsoHears.entries) lists[e.key]!: lists[e.value]!,
    };
    edits?.alsoHears.forEach((name, wider) {
      final list = lists[name];
      if (list == null) return;
      if (wider.isEmpty) {
        alsoHears.remove(list);
        return;
      }
      final widerList = lists[wider];
      if (widerList != null && widerList != list) alsoHears[list] = widerList;
    });
    // The general list is for a habit with no list of its own (and a list
    // left empty); it draws on nothing.
    alsoHears.remove(PraiseGroup.general);

    return PetSettings._(
      numbers: Map.unmodifiable(numbers),
      presetLists: Map.unmodifiable(presetLists),
      categoryLists: Map.unmodifiable(categoryLists),
      alsoHears: Map.unmodifiable(alsoHears),
      quitList: lists[edits?.quit ?? ''] ?? lists[kPetQuitList]!,
    );
  }

  static PetEdits? _seen;
  static PetSettings _inForce = builtIn;

  /// The settings in force now: read at the moment of use, so a save on the
  /// admin page reaches Doum within a second or two, like his words.
  static PetSettings get current {
    final edits = WordingEditsStore.current.pet;
    if (!identical(edits, _seen)) {
      _seen = edits;
      _inForce = edits == null ? builtIn : PetSettings.from(edits);
    }
    return _inForce;
  }

  /// Every value in force by name, the shape test/fixtures/pet_cases.json
  /// expects (the admin page resolves the same cases).
  @visibleForTesting
  Map<String, Object?> describe() => {
        ...numbers,
        'presets': {
          for (final e in presetLists.entries) e.key: e.value.name,
        },
        'categories': {
          for (final e in categoryLists.entries) e.key.name: e.value.name,
        },
        'alsoHears': {
          for (final e in alsoHears.entries) e.key.name: e.value.name,
        },
        'quit': quitList.name,
      };
}
