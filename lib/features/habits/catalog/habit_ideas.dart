import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../../core/l10n/wording_edits.dart';
import '../models/habit_model.dart';
import 'habit_plans.dart';

/// Add Habit's habit ideas (Aziz, 2026-10-01: "show the benefit of it ...
/// like charity each day «اللهم أعط منفقًا خلفًا», or surat almulk"). One
/// idea is one habit someone can add in a tap: its name, the one line on its
/// card that says why it is worth doing, the full text behind it (a hadith
/// with its source for a faith habit, plain words for the rest), two easy
/// ways to start, and the schedule and reminder it is suggested with.
///
/// The built-in list is [kHabitIdeasAsset], one JSON file the app and the
/// admin tool both read, so the two can never hold different lists. The
/// admin's edits (wording/live `ideas`, see ideas_edits.dart) are laid over
/// it by [resolveIdeas].
const String kHabitIdeasAsset = 'assets/data/habit_ideas.json';

/// The schedule an idea suggests, read from its `often` string: "daily",
/// "weekly:3" (three times a week, any days) or "days:1,4" (Monday and
/// Thursday, ISO weekdays).
@immutable
class IdeaOften {
  const IdeaOften.daily()
      : type = HabitFrequencyType.daily,
        target = 1,
        weekdays = const [];
  const IdeaOften.weekly(this.target)
      : type = HabitFrequencyType.weekly,
        weekdays = const [];
  IdeaOften.days(List<int> days)
      : type = HabitFrequencyType.weekly,
        weekdays = List.unmodifiable(days),
        target = days.length;

  final HabitFrequencyType type;

  /// Times a week for [IdeaOften.weekly]; the number of days for set days.
  final int target;

  /// The set days, empty unless the idea names them.
  final List<int> weekdays;

  bool get isDaily => type == HabitFrequencyType.daily;
  bool get isSetDays => weekdays.isNotEmpty;

  static IdeaOften? parse(Object? raw) {
    if (raw is! String) return null;
    final v = raw.trim();
    if (v == 'daily') return const IdeaOften.daily();
    if (v.startsWith('weekly:')) {
      final n = int.tryParse(v.substring(7));
      if (n == null || n < 1 || n > 6) return null;
      return IdeaOften.weekly(n);
    }
    if (v.startsWith('days:')) {
      final days = <int>{};
      for (final part in v.substring(5).split(',')) {
        final d = int.tryParse(part.trim());
        if (d == null || d < DateTime.monday || d > DateTime.sunday) {
          return null;
        }
        days.add(d);
      }
      if (days.isEmpty) return null;
      return IdeaOften.days(days.toList()..sort());
    }
    return null;
  }
}

/// One habit idea. Built only through [HabitIdea.fromJson], which refuses
/// an idea missing anything a card or its detail would show.
@immutable
class HabitIdea {
  const HabitIdea._({
    required this.id,
    required this.type,
    required this.category,
    required this.nameAr,
    required this.nameEn,
    required this.shortAr,
    required this.shortEn,
    required this.benefitAr,
    required this.benefitEn,
    required this.sourceAr,
    required this.sourceEn,
    required this.waysAr,
    required this.waysEn,
    required this.often,
    required this.timesPerDay,
    required this.reminderPrayer,
    required this.reminderHour,
    required this.reminderMinute,
    required this.limitAmount,
    required this.limitUnit,
    required this.featured,
  });

  final String id;
  final GoalType type;
  final HabitCategory category;
  final String nameAr;
  final String nameEn;
  final String shortAr;
  final String shortEn;
  final String benefitAr;
  final String benefitEn;
  final String? sourceAr;
  final String? sourceEn;
  final List<String> waysAr;
  final List<String> waysEn;
  final IdeaOften often;

  /// Times a day, for a daily build habit counted more than once; 1 else.
  final int timesPerDay;

  /// The prayer the suggested reminder rides on («fajr»…), or null.
  final String? reminderPrayer;

  /// The suggested reminder's clock time, or null.
  final int? reminderHour;
  final int? reminderMinute;

  /// A quit idea's daily limit, or null for quitting it fully.
  final int? limitAmount;
  final LimitUnit? limitUnit;

  /// Shown under «مختارة لك» unless the admin says otherwise.
  final bool featured;

  String name(bool isAr) => isAr ? nameAr : nameEn;
  String short(bool isAr) => isAr ? shortAr : shortEn;
  String benefit(bool isAr) => isAr ? benefitAr : benefitEn;
  String? source(bool isAr) => isAr ? sourceAr : sourceEn;
  List<String> ways(bool isAr) => isAr ? waysAr : waysEn;

  bool get hasReminder => reminderPrayer != null || reminderHour != null;

  static const _prayers = {'fajr', 'dhuhr', 'asr', 'maghrib', 'isha'};

  /// The nine categories an idea can be in: the ones Add Habit offers. The
  /// enum's older names (quran, fitness ...) are only ever read off old
  /// habits, so an idea naming one is refused here as in the admin tool.
  static const _categories = {
    'faith', 'health', 'learning', 'focus', 'sleep', 'money', 'mind',
    'social', 'custom',
  };

  /// The idea in [json], or null when anything it needs is missing or
  /// malformed: an idea is shown whole or not at all.
  static HabitIdea? fromJson(Map<String, Object?> json, {String? id}) {
    String? text(String key, {int max = 400}) {
      final v = json[key];
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty || t.length > max ? null : t;
    }

    List<String>? list(String key) {
      final v = json[key];
      if (v is! List) return null;
      final out = [
        for (final w in v)
          if (w is String && w.trim().isNotEmpty) w.trim(),
      ];
      return out.isEmpty || out.length > 4 ? null : out;
    }

    final ideaId = id ?? text('id', max: 64);
    final type = switch (json['type']) {
      'build' => GoalType.build,
      'quit' => GoalType.quit,
      _ => null,
    };
    final categoryName = json['category'];
    final category = categoryName is String && _categories.contains(categoryName)
        ? HabitCategory.fromJson(categoryName)
        : null;
    final nameAr = text('nameAr', max: 60);
    final nameEn = text('nameEn', max: 60);
    final shortAr = text('shortAr', max: 120);
    final shortEn = text('shortEn', max: 160);
    final benefitAr = text('benefitAr');
    final benefitEn = text('benefitEn');
    final waysAr = list('waysAr');
    final waysEn = list('waysEn');
    final often = IdeaOften.parse(json['often']);
    if (ideaId == null ||
        type == null ||
        category == null ||
        nameAr == null ||
        nameEn == null ||
        shortAr == null ||
        shortEn == null ||
        benefitAr == null ||
        benefitEn == null ||
        waysAr == null ||
        waysEn == null ||
        often == null) {
      return null;
    }

    final times = json['timesPerDay'];
    final timesPerDay = times is int &&
            times >= 2 &&
            times <= 12 &&
            often.isDaily &&
            type == GoalType.build
        ? times
        : 1;

    String? prayer;
    int? hour;
    int? minute;
    final reminder = json['reminder'];
    if (reminder is String) {
      if (reminder.startsWith('prayer:') &&
          _prayers.contains(reminder.substring(7))) {
        prayer = reminder.substring(7);
      } else if (reminder.startsWith('time:')) {
        final parts = reminder.substring(5).split(':');
        if (parts.length == 2) {
          final h = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          if (h != null && m != null && h >= 0 && h < 24 && m >= 0 && m < 60) {
            hour = h;
            minute = m;
          }
        }
      }
    }

    int? limitAmount;
    LimitUnit? limitUnit;
    final limit = json['limit'];
    if (type == GoalType.quit && limit is Map) {
      final amount = limit['amount'];
      final unit = limit['unit'];
      if (amount is int &&
          amount >= 1 &&
          unit is String &&
          const ['minutes', 'times', 'cups', 'money'].contains(unit)) {
        limitAmount = amount;
        limitUnit = LimitUnit.fromJson(unit);
      }
    }

    return HabitIdea._(
      id: ideaId,
      type: type,
      category: category,
      nameAr: nameAr,
      nameEn: nameEn,
      shortAr: shortAr,
      shortEn: shortEn,
      benefitAr: benefitAr,
      benefitEn: benefitEn,
      sourceAr: text('sourceAr', max: 80),
      sourceEn: text('sourceEn', max: 80),
      waysAr: List.unmodifiable(waysAr),
      waysEn: List.unmodifiable(waysEn),
      often: often,
      timesPerDay: timesPerDay,
      reminderPrayer: prayer,
      reminderHour: hour,
      reminderMinute: minute,
      limitAmount: limitAmount,
      limitUnit: limitUnit,
      featured: json['featured'] == true,
    );
  }

  /// The JSON this idea was read from, for laying edits over it.
  Map<String, Object?> toJson() => {
        'id': id,
        'type': type == GoalType.quit ? 'quit' : 'build',
        'category': category.name,
        'nameAr': nameAr,
        'nameEn': nameEn,
        'shortAr': shortAr,
        'shortEn': shortEn,
        'benefitAr': benefitAr,
        'benefitEn': benefitEn,
        if (sourceAr != null) 'sourceAr': sourceAr,
        if (sourceEn != null) 'sourceEn': sourceEn,
        'waysAr': waysAr,
        'waysEn': waysEn,
        'often': often.isDaily
            ? 'daily'
            : (often.isSetDays
                ? 'days:${often.weekdays.join(',')}'
                : 'weekly:${often.target}'),
        if (timesPerDay > 1) 'timesPerDay': timesPerDay,
        if (reminderPrayer != null) 'reminder': 'prayer:$reminderPrayer',
        if (reminderHour != null)
          'reminder': 'time:${reminderHour.toString().padLeft(2, '0')}:'
              '${reminderMinute.toString().padLeft(2, '0')}',
        if (limitAmount != null)
          'limit': {'amount': limitAmount, 'unit': limitUnit!.name},
        'featured': featured,
      };

  /// The fields the admin can edit, in the one order they are applied:
  /// a schedule before the times a day that only a daily habit keeps, so
  /// the result never depends on the order a document lists them in
  /// (Firestore on iOS does not keep it).
  static const _editOrder = [
    'category', 'nameAr', 'nameEn', 'shortAr', 'shortEn', 'benefitAr',
    'benefitEn', 'sourceAr', 'sourceEn', 'waysAr', 'waysEn', 'often',
    'timesPerDay', 'reminder', 'limit',
  ];

  /// The optional fields an edit of null takes away: the only way the admin
  /// can remove a built-in idea's source, reminder, limit or extra times.
  static const _clearable = {
    'sourceAr', 'sourceEn', 'timesPerDay', 'reminder', 'limit',
  };

  /// This idea with the admin's edited [fields] laid over it, field by
  /// field in [_editOrder]: null takes away an optional field, and a value
  /// the idea could not use (the wrong type, a blank, an unknown schedule)
  /// keeps the idea's own. A times a day or a limit that no longer fits the
  /// idea's schedule or type is dropped, as [HabitIdea.fromJson] drops it.
  HabitIdea withText(Map<String, Object?> fields) {
    var json = toJson();
    for (final key in _editOrder) {
      if (!fields.containsKey(key)) continue;
      final value = fields[key];
      if (value == null) {
        if (_clearable.contains(key)) json = {...json}..remove(key);
        continue;
      }
      final next = HabitIdea.fromJson({...json, key: value}, id: id);
      if (next == null || !_fieldTook(key, value, next)) continue;
      json = next.toJson();
    }
    return HabitIdea.fromJson(json, id: id) ?? this;
  }

  /// Whether [value] for [key] actually landed in [next]: an optional field
  /// the parser could not read is dropped there rather than refused, and
  /// must not erase the one the idea had.
  static bool _fieldTook(String key, Object? value, HabitIdea next) {
    switch (key) {
      case 'sourceAr':
        return value is String && next.sourceAr != null;
      case 'sourceEn':
        return value is String && next.sourceEn != null;
      case 'reminder':
        return value is String && next.hasReminder;
      case 'limit':
        return value is Map && next.limitAmount != null;
      case 'timesPerDay':
        return value is int && next.timesPerDay == value;
      default:
        return true;
    }
  }
}

/// One idea as the page shows it: the idea and whether it is featured.
@immutable
class ShownIdea {
  const ShownIdea(this.idea, {required this.featured});
  final HabitIdea idea;
  final bool featured;
}

/// The ideas list after the admin's [edits] (see ideas_edits.dart):
///
/// 1. The built-ins in file order, each with its edited fields laid over
///    it, without the hidden ones.
/// 2. Then each valid added idea (an id starting «a-»), by id.
/// 3. Ordered by [IdeasEdits.order] for the ids it names that exist, then
///    every other idea in the order of 1 and 2.
/// 4. Featured by [IdeasEdits.featured] where it names the idea, else the
///    idea's own flag.
///
/// The admin tool's wording/ideas_rules.js does the same; both are held to
/// scripts/admin_lookup/test/fixtures/ideas_cases.json.
List<ShownIdea> resolveIdeas(List<HabitIdea> builtIn, IdeasEdits? edits) {
  final e = edits ?? const IdeasEdits();
  final hidden = e.hidden.toSet();
  final ideas = <HabitIdea>[
    for (final idea in builtIn)
      if (!hidden.contains(idea.id))
        e.text[idea.id] == null ? idea : idea.withText(e.text[idea.id]!),
  ];
  final known = {for (final i in builtIn) i.id};
  // By id: a map's key order is not one both sides can count on.
  for (final key in e.added.keys.toList()..sort()) {
    if (!key.startsWith('a-') || known.contains(key)) continue;
    final idea = HabitIdea.fromJson(e.added[key]!, id: key);
    if (idea != null) {
      ideas.add(idea);
      known.add(key);
    }
  }
  final byId = {for (final i in ideas) i.id: i};
  final ordered = <HabitIdea>[];
  final placed = <String>{};
  for (final id in e.order ?? const <String>[]) {
    final idea = byId[id];
    if (idea != null && placed.add(id)) ordered.add(idea);
  }
  for (final idea in ideas) {
    if (placed.add(idea.id)) ordered.add(idea);
  }
  return [
    for (final idea in ordered)
      ShownIdea(idea, featured: e.featured[idea.id] ?? idea.featured),
  ];
}

/// The ideas in a built-in list's JSON text, skipping any it cannot read.
List<HabitIdea> parseHabitIdeas(String source) {
  final Object? data;
  try {
    data = jsonDecode(source);
  } catch (_) {
    return const [];
  }
  final list = data is Map ? data['ideas'] : null;
  if (list is! List) return const [];
  final seen = <String>{};
  return [
    for (final raw in list)
      if (raw is Map)
        if (HabitIdea.fromJson(Map<String, Object?>.from(raw))
            case final HabitIdea idea)
          if (!idea.id.startsWith('a-') && seen.add(idea.id)) idea,
  ];
}

List<HabitIdea>? _builtIn;

/// The built-in ideas, read once from [kHabitIdeasAsset].
Future<List<HabitIdea>> loadBuiltInIdeas([AssetBundle? bundle]) async {
  final cached = _builtIn;
  if (cached != null) return cached;
  final source = await (bundle ?? rootBundle).loadString(kHabitIdeasAsset);
  return _builtIn = parseHabitIdeas(source);
}

/// The ideas as the page shows them now: the built-ins with the admin's
/// edits in force laid over them.
Future<List<ShownIdea>> loadShownIdeas([AssetBundle? bundle]) async =>
    resolveIdeas(
      await loadBuiltInIdeas(bundle),
      WordingEditsStore.current.ideas,
    );

/// One ready-made plan as it is shown: the plan and its words after the
/// admin's edits.
@immutable
class ShownPlan {
  const ShownPlan(
    this.plan, {
    required this.nameAr,
    required this.nameEn,
    required this.descAr,
    required this.descEn,
  });
  final HabitPlan plan;
  final String nameAr;
  final String nameEn;
  final String descAr;
  final String descEn;

  String name(bool isAr) => isAr ? nameAr : nameEn;
  String desc(bool isAr) => isAr ? descAr : descEn;
}

/// The plans after the admin's [edits]: the hidden ones taken off, the
/// order by [PlansEdits.order] for the ids it names and code order for the
/// rest, and each plan's edited words over its own.
List<ShownPlan> resolvePlans(List<HabitPlan> plans, PlansEdits? edits) {
  final e = edits ?? const PlansEdits();
  final hidden = e.hidden.toSet();
  final shown = [
    for (final p in plans)
      if (!hidden.contains(p.id)) p,
  ];
  final byId = {for (final p in shown) p.id: p};
  final ordered = <HabitPlan>[];
  final placed = <String>{};
  for (final id in e.order ?? const <String>[]) {
    final p = byId[id];
    if (p != null && placed.add(id)) ordered.add(p);
  }
  for (final p in shown) {
    if (placed.add(p.id)) ordered.add(p);
  }
  return [
    for (final p in ordered)
      ShownPlan(
        p,
        nameAr: e.text[p.id]?['nameAr'] ?? p.nameAr,
        nameEn: e.text[p.id]?['nameEn'] ?? p.nameEn,
        descAr: e.text[p.id]?['descAr'] ?? p.descAr,
        descEn: e.text[p.id]?['descEn'] ?? p.descEn,
      ),
  ];
}

/// The plans as shown now, with the admin's edits in force.
List<ShownPlan> shownPlans() =>
    resolvePlans(habitPlans, WordingEditsStore.current.plans);
