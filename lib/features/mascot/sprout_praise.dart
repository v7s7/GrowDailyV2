import 'dart:math';

import 'package:hive/hive.dart';

import '../../core/constants/game_constants.dart';
import '../../core/l10n/app_strings.dart';
import '../habits/catalog/islamic_habit_catalog.dart';
import '../habits/models/habit_model.dart';
import 'pet_settings.dart';

/// What the day card's sprout says when a square turns green: praise that
/// fits the habit, a prayer «تقبّل الله», a workout «يعطيك العافية», in the
/// reader's own form, and never the same line twice until its lists run out.
///
/// Aziz, 2026-09-28: "if something in faith, it says like that, if in sport
/// diff, so we need to do a list for male and female, and in each category,
/// and the one that can be sent in any category, so if user didn't set, or
/// so not duplicates", and then "so smart that never a mistake". So every
/// group has two lists (S.sproutPraise<Group> and its F twin, one line per
/// row, editable on the admin wording page), the general list serves a habit
/// with no category of its own and any habit once its own lines have all
/// been said lately, and when the app cannot tell who is reading
/// ([PraiseForm.unknown]) only the lines written the same in both lists are
/// said.
enum PraiseGroup {
  faith,
  quran,
  athkar,
  fasting,
  sadaqah,
  sport,
  health,
  learning,
  focus,
  sleep,
  money,
  mind,
  social,
  general,
}

/// How the sprout may address the reader. [unknown] is not a third gender:
/// it is the app admitting it does not know, and it says only lines that
/// fit anyone.
enum PraiseForm { man, woman, unknown }

/// The praise a habit gets, read from what is saved on the habit (its
/// catalog id, goal type and category) and never guessed from its name:
/// the list set for that ready-made habit, else the quit list for a quit
/// habit, else its category's. Which list each of those is lives in
/// pet_settings.dart, and the admin's «دوم» page can change every one.
PraiseGroup praiseGroupFor(
  IslamicHabitTemplate habit, [
  PetSettings? settings,
]) {
  final s = settings ?? PetSettings.current;
  final preset = s.presetLists[habit.id];
  if (preset != null) return preset;
  if (habit.goalType == GoalType.quit) return s.quitList;
  return s.categoryLists[habit.category] ?? PraiseGroup.general;
}

/// The wider group a narrow one also draws on, so a Quran page can hear
/// «تقبّل الله» too (see kPetAlsoHears).
PraiseGroup? praiseParentOf(PraiseGroup group, [PetSettings? settings]) =>
    (settings ?? PetSettings.current).alsoHears[group];

/// A group's lines in the reader's form, one per row of its S list. Blank
/// rows are dropped, so a list edited on the admin page with a stray empty
/// line still works. For [PraiseForm.unknown] it is the lines found in BOTH
/// lists, by text rather than by position, so an edit that adds a line to
/// one list only can never let a gendered line through.
List<String> praiseLines(S s, PraiseGroup group, {required PraiseForm form}) {
  if (form == PraiseForm.unknown) {
    final women = praiseLines(s, group, form: PraiseForm.woman).toSet();
    return [
      for (final line in praiseLines(s, group, form: PraiseForm.man))
        if (women.contains(line)) line,
    ];
  }
  final woman = form == PraiseForm.woman;
  final raw = switch (group) {
    PraiseGroup.faith => woman ? s.sproutPraiseFaithF : s.sproutPraiseFaith,
    PraiseGroup.quran => woman ? s.sproutPraiseQuranF : s.sproutPraiseQuran,
    PraiseGroup.athkar => woman ? s.sproutPraiseAthkarF : s.sproutPraiseAthkar,
    PraiseGroup.fasting =>
      woman ? s.sproutPraiseFastingF : s.sproutPraiseFasting,
    PraiseGroup.sadaqah =>
      woman ? s.sproutPraiseSadaqahF : s.sproutPraiseSadaqah,
    PraiseGroup.sport => woman ? s.sproutPraiseSportF : s.sproutPraiseSport,
    PraiseGroup.health => woman ? s.sproutPraiseHealthF : s.sproutPraiseHealth,
    PraiseGroup.learning =>
      woman ? s.sproutPraiseLearningF : s.sproutPraiseLearning,
    PraiseGroup.focus => woman ? s.sproutPraiseFocusF : s.sproutPraiseFocus,
    PraiseGroup.sleep => woman ? s.sproutPraiseSleepF : s.sproutPraiseSleep,
    PraiseGroup.money => woman ? s.sproutPraiseMoneyF : s.sproutPraiseMoney,
    PraiseGroup.mind => woman ? s.sproutPraiseMindF : s.sproutPraiseMind,
    PraiseGroup.social => woman ? s.sproutPraiseSocialF : s.sproutPraiseSocial,
    PraiseGroup.general =>
      woman ? s.sproutPraiseGeneralF : s.sproutPraiseGeneral,
  };
  return _lines(raw);
}

List<String> _lines(String raw) => [
      for (final line in raw.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];

/// What a tap on the sprout can say, one per row of S.sproutTickle
/// («هههه», «اوبس»), blank rows dropped like the praise lists.
List<String> tickleLines(S s) => _lines(s.sproutTickle);

/// One tap's line, picked at random (Aziz, 2026-09-29: the same word can
/// come twice in a row). Never empty: a list blanked on the admin page
/// falls back to the built-in one.
String pickTickle(S s, [Random? random]) {
  var lines = tickleLines(s);
  if (lines.isEmpty) lines = _lines(S(s.locale).sproutTickle);
  return lines[(random ?? Random()).nextInt(lines.length)];
}

/// Picks the praise, remembering what it said so nothing repeats: a fresh
/// line from the habit's own group (and its parent) first, then a fresh
/// general one, and only once every line has been said lately, the one said
/// longest ago.
///
/// The memory lives in the settings box, so it carries across launches. It
/// is written only while that box is already open and [persist] is on; the
/// widget-test harnesses turn it off, because a Hive write still in flight
/// inside testWidgets hangs the next test's box (see LandingHarness).
class PraisePicker {
  PraisePicker({Random? random, int? memory})
      : _random = random ?? Random(),
        _memory = memory;

  final Random _random;
  final int? _memory;

  /// How many recent lines it avoids repeating: more than any single
  /// group's two lists together, so a full day of prayers never hears the
  /// same line twice. The admin's «دوم» page sets it (kPetRememberLines).
  int get memory => _memory ?? PetSettings.current.rememberLines;

  /// Whether the memory is saved to the settings box (off in tests).
  static bool persist = true;

  static const _key = 'sprout_praise_recent_v1';

  List<String>? _recent;

  List<String> get _said => _recent ??= _load();

  List<String> _load() {
    if (!persist || !Hive.isBoxOpen(GameConstants.boxSettings)) return [];
    try {
      final raw = Hive.box<dynamic>(GameConstants.boxSettings).get(_key);
      return raw is List ? raw.whereType<String>().toList() : [];
    } catch (_) {
      return [];
    }
  }

  void _save() {
    if (!persist || !Hive.isBoxOpen(GameConstants.boxSettings)) return;
    try {
      Hive.box<dynamic>(GameConstants.boxSettings).put(_key, List.of(_said));
    } catch (_) {}
  }

  String pick({required List<String> own, required List<String> general}) {
    for (final pool in [own, general]) {
      final fresh = [
        for (final line in pool)
          if (!_said.contains(line)) line,
      ];
      if (fresh.isNotEmpty) {
        return _remember(fresh[_random.nextInt(fresh.length)]);
      }
    }
    final all = {...own, ...general}.toList();
    if (all.isEmpty) return '';
    all.sort((a, b) => _said.indexOf(a).compareTo(_said.indexOf(b)));
    return _remember(all.first);
  }

  String _remember(String line) {
    _said
      ..remove(line)
      ..add(line);
    while (_said.length > memory) {
      _said.removeAt(0);
    }
    _save();
    return line;
  }
}

/// The praise for [group] in the reader's form, through [picker]: its own
/// lines and its parent's first, the general ones after.
String pickPraise(
  S s,
  PraisePicker picker,
  PraiseGroup group, {
  required PraiseForm form,
}) {
  final parent = praiseParentOf(group);
  final general = praiseLines(s, PraiseGroup.general, form: form);
  final own = group == PraiseGroup.general
      ? general
      : [
          ...praiseLines(s, group, form: form),
          if (parent != null) ...praiseLines(s, parent, form: form),
        ];
  return picker.pick(own: own, general: general);
}
