// Add Habit's habit ideas: the built-in list (assets/data/habit_ideas.json)
// and the admin's edits laid over it (wording/live `ideas` and `plans`, see
// lib/core/l10n/ideas_edits.dart and habit_ideas.dart's resolveIdeas /
// resolvePlans).
//
// The list is content people read as advice, a hadith for every faith habit,
// so it is held here to the app's copy rules and to its own shape: an idea
// the app cannot read is silently left out, which would hide a mistake in
// the file rather than show it.
//
// The resolution is the admin tool's too (scripts/admin_lookup/wording/
// ideas_rules.js); both run scripts/admin_lookup/test/fixtures/
// ideas_cases.json, so what the admin previews is what phones show.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/l10n/ideas_edits.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_ideas.dart';
import 'package:grow_daily_v2/features/habits/catalog/habit_plans.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

Map<String, Object?> _idea(
  String id, {
  String type = 'build',
  String category = 'faith',
  bool featured = false,
  Map<String, Object?> extra = const {},
}) =>
    {
      'id': id,
      'type': type,
      'category': category,
      'nameAr': 'اسم $id',
      'nameEn': 'Name $id',
      'shortAr': 'سطر',
      'shortEn': 'Line',
      'benefitAr': 'فائدة',
      'benefitEn': 'Benefit',
      'waysAr': ['طريقة'],
      'waysEn': ['Way'],
      'often': 'daily',
      'featured': featured,
      ...extra,
    };

List<HabitIdea> _ideas(List<Map<String, Object?>> raw) =>
    [for (final r in raw) HabitIdea.fromJson(r)!];

void main() {
  group('the built-in list', () {
    final source = File('assets/data/habit_ideas.json').readAsStringSync();
    final raw = (jsonDecode(source) as Map)['ideas'] as List;
    final ideas = parseHabitIdeas(source);

    test('every idea in the file is one the app can show', () {
      final unreadable = [
        for (final r in raw)
          if (HabitIdea.fromJson(Map<String, Object?>.from(r as Map)) == null)
            r['id'],
      ];
      expect(unreadable, isEmpty);
      expect(ideas.length, raw.length, reason: 'ids are unique too');
    });

    test('ids are snake_case and never the admin tool\'s «a-»', () {
      for (final i in ideas) {
        expect(i.id, matches(RegExp(r'^[a-z0-9_]{2,40}$')), reason: i.id);
      }
    });

    test('both languages say the same: names, lines, text and ways', () {
      for (final i in ideas) {
        expect(i.waysAr.length, i.waysEn.length, reason: i.id);
        expect(i.waysAr.length, inInclusiveRange(1, 3), reason: i.id);
        expect(i.sourceAr == null, i.sourceEn == null,
            reason: '${i.id}: a source in one language is one in both');
      }
    });

    test('a faith habit to build says where its text comes from', () {
      for (final i in ideas) {
        if (i.category != HabitCategory.faith || i.type != GoalType.build) {
          continue;
        }
        expect(i.sourceAr, isNotNull, reason: i.id);
      }
    });

    test('lines fit their places', () {
      for (final i in ideas) {
        expect(i.nameAr.length, lessThanOrEqualTo(32), reason: i.id);
        expect(i.shortAr.length, lessThanOrEqualTo(60), reason: i.id);
        expect(i.shortEn.length, lessThanOrEqualTo(60), reason: i.id);
        expect(i.benefitAr.length, lessThanOrEqualTo(220), reason: i.id);
        for (final w in [...i.waysAr, ...i.waysEn]) {
          expect(w.length, lessThanOrEqualTo(80), reason: '${i.id}: $w');
        }
      }
    });

    test('the copy rules: no «!», no dashes, never «كذا»', () {
      for (final r in raw) {
        final text = jsonEncode(r);
        expect(text.contains('!'), isFalse, reason: '${(r as Map)['id']}');
        expect(text.contains('—') || text.contains('–'), isFalse,
            reason: '${r['id']}');
        expect(RegExp(r'(^|[^ه])كذا').hasMatch(text), isFalse,
            reason: '${r['id']}');
      }
    });

    test('«مختارة لك» stays a short list: at most 2 per category per side',
        () {
      final count = <String, int>{};
      for (final i in ideas.where((i) => i.featured)) {
        final key = '${i.category.name}/${i.type.name}';
        count[key] = (count[key] ?? 0) + 1;
      }
      for (final e in count.entries) {
        expect(e.value, lessThanOrEqualTo(2), reason: e.key);
      }
    });

    test('every set-days idea names real weekdays', () {
      for (final i in ideas.where((i) => i.often.isSetDays)) {
        expect(i.often.weekdays, everyElement(inInclusiveRange(1, 7)));
      }
    });
  });

  group('reading one idea', () {
    test('the schedules it can suggest', () {
      expect(IdeaOften.parse('daily')!.isDaily, isTrue);
      expect(IdeaOften.parse('weekly:3')!.target, 3);
      expect(IdeaOften.parse('days:4,1')!.weekdays, [1, 4]);
      expect(IdeaOften.parse('weekly:7'), isNull,
          reason: 'seven a week is every day');
      expect(IdeaOften.parse('days:0'), isNull);
      expect(IdeaOften.parse(3), isNull);
    });

    test('a reminder on a prayer or a clock time, nothing else', () {
      expect(
        HabitIdea.fromJson(_idea('a', extra: {'reminder': 'prayer:isha'}))!
            .reminderPrayer,
        'isha',
      );
      final timed =
          HabitIdea.fromJson(_idea('a', extra: {'reminder': 'time:21:30'}))!;
      expect([timed.reminderHour, timed.reminderMinute], [21, 30]);
      expect(
        HabitIdea.fromJson(_idea('a', extra: {'reminder': 'prayer:duha'}))!
            .hasReminder,
        isFalse,
      );
    });

    test('a limit only on a quit idea', () {
      final quit = HabitIdea.fromJson(_idea('q', type: 'quit', extra: {
        'limit': {'amount': 2, 'unit': 'cups'},
      }))!;
      expect([quit.limitAmount, quit.limitUnit], [2, LimitUnit.cups]);
      final build = HabitIdea.fromJson(_idea('b', extra: {
        'limit': {'amount': 2, 'unit': 'cups'},
      }))!;
      expect(build.limitAmount, isNull);
    });

    test('an idea missing what a card shows is not read at all', () {
      expect(HabitIdea.fromJson({..._idea('x'), 'shortAr': ''}), isNull);
      expect(HabitIdea.fromJson({..._idea('x'), 'waysEn': []}), isNull);
      expect(HabitIdea.fromJson({..._idea('x'), 'category': 'cars'}), isNull);
      expect(HabitIdea.fromJson({..._idea('x'), 'often': 'sometimes'}), isNull);
    });
  });

  group('the admin\'s edits', () {
    final builtIn = _ideas([
      _idea('one', featured: true),
      _idea('two'),
      _idea('three', type: 'quit'),
    ]);
    List<String> ids(List<ShownIdea> list) => [for (final i in list) i.idea.id];

    test('none: the file\'s order and flags', () {
      final shown = resolveIdeas(builtIn, null);
      expect(ids(shown), ['one', 'two', 'three']);
      expect([for (final i in shown) i.featured], [true, false, false]);
    });

    test('hidden, ordered, featured both ways', () {
      final shown = resolveIdeas(
        builtIn,
        const IdeasEdits(
          order: ['three', 'nobody', 'one'],
          hidden: ['two'],
          featured: {'one': false, 'three': true},
        ),
      );
      expect(ids(shown), ['three', 'one']);
      expect([for (final i in shown) i.featured], [true, false]);
    });

    test('an edited field lands; one of the wrong type keeps the idea\'s', () {
      final shown = resolveIdeas(
        builtIn,
        const IdeasEdits(text: {
          'one': {
            'nameAr': 'اسم جديد',
            'often': 'weekly:2',
            'shortEn': 7,
            'reminder': 'prayer:nowhere',
          },
        }),
      );
      final one = shown.first.idea;
      expect(one.nameAr, 'اسم جديد');
      expect(one.often.target, 2);
      expect(one.shortEn, 'Line');
      expect(one.hasReminder, isFalse);
    });

    test('an added idea joins after the built-ins; a broken one does not',
        () {
      final shown = resolveIdeas(
        builtIn,
        IdeasEdits(added: {
          'a-new': _idea('ignored'),
          'a-broken': {..._idea('x'), 'nameAr': ''},
          'no-prefix': _idea('y'),
        }),
      );
      expect(ids(shown), ['one', 'two', 'three', 'a-new']);
    });

    test('the plans: hidden, ordered and their words edited', () {
      final shown = resolvePlans(
        habitPlans,
        PlansEdits(
          order: [habitPlans.last.id],
          hidden: [habitPlans.first.id],
          text: {
            habitPlans[1].id: {'nameAr': 'اسم آخر'},
          },
        ),
      );
      expect(shown.first.plan.id, habitPlans.last.id);
      expect(shown.any((p) => p.plan.id == habitPlans.first.id), isFalse);
      expect(
        shown.firstWhere((p) => p.plan.id == habitPlans[1].id).nameAr,
        'اسم آخر',
      );
      expect(shown.length, habitPlans.length - 1);
    });

    test('a document shape it does not know reads as no edits', () {
      expect(IdeasEdits.fromData('nonsense'), isNull);
      final e = IdeasEdits.fromData({
        'order': 'one',
        'hidden': [1, 'two'],
        'featured': {'one': 'yes', 'two': true},
      })!;
      expect(e.order, isNull);
      expect(e.hidden, ['two']);
      expect(e.featured, {'two': true});
    });
  });
}
