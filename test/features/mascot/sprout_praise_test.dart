// The sprout's praise: which list a habit draws from, how it addresses the
// reader (and that it never gets that wrong), and that nothing repeats until
// the lists run out. See sprout_praise.dart and sprout_signals.dart.
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/character/models/character_option.dart';
import 'package:grow_daily_v2/features/character/notifiers/character_notifier.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/mascot/sprout_praise.dart';
import 'package:grow_daily_v2/features/mascot/sprout_signals.dart';

void main() {
  const ar = S(Locale('ar'));
  const en = S(Locale('en'));

  setUp(() => PraisePicker.persist = false);

  IslamicHabitTemplate habit(HabitCategory category,
          {GoalType goal = GoalType.build}) =>
      IslamicHabitTemplate(
        id: category.name,
        name: category.name,
        description: '',
        category: category,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        scheduledWeekdays: const [],
        hasTimer: false,
        xpReward: 10,
        goldReward: 5,
        goalType: goal,
        createdAt: DateTime(2026, 9),
      );

  List<String> lines(PraiseGroup group, PraiseForm form, [S s = ar]) =>
      praiseLines(s, group, form: form);

  group('which list a habit draws from', () {
    test('every category has its group, and custom has the general one', () {
      final expected = {
        HabitCategory.faith: PraiseGroup.faith,
        HabitCategory.quran: PraiseGroup.quran,
        HabitCategory.athkar: PraiseGroup.athkar,
        HabitCategory.fasting: PraiseGroup.fasting,
        HabitCategory.sadaqah: PraiseGroup.sadaqah,
        HabitCategory.fitness: PraiseGroup.sport,
        HabitCategory.health: PraiseGroup.health,
        HabitCategory.learning: PraiseGroup.learning,
        HabitCategory.focus: PraiseGroup.focus,
        HabitCategory.sleep: PraiseGroup.sleep,
        HabitCategory.money: PraiseGroup.money,
        HabitCategory.mind: PraiseGroup.mind,
        HabitCategory.social: PraiseGroup.social,
        HabitCategory.custom: PraiseGroup.general,
      };
      expect(expected.keys.toSet(), HabitCategory.values.toSet());
      expected.forEach((category, group) {
        expect(praiseGroupFor(habit(category)), group, reason: '$category');
      });
    });

    test('a quit habit kept clean gets the general praise, not its '
        "category's", () {
      expect(
        praiseGroupFor(habit(HabitCategory.health, goal: GoalType.quit)),
        PraiseGroup.general,
      );
    });

    test('Tahajjud is filed under athkar but praised as the prayer it is',
        () {
      final tahajjud = IslamicHabitCatalog.findById('tahajjud')!;
      expect(tahajjud.category, HabitCategory.athkar,
          reason: 'its icon and stats still file it under athkar');
      expect(praiseGroupFor(tahajjud), PraiseGroup.faith);
      expect(praiseGroupFor(IslamicHabitCatalog.findById('morning_athkar')!),
          PraiseGroup.athkar);
    });

    test('a Quran page can hear faith praise too', () {
      final picker = PraisePicker(random: Random(3), memory: 100);
      final quran = lines(PraiseGroup.quran, PraiseForm.man);
      final faith = lines(PraiseGroup.faith, PraiseForm.man);
      final said = {
        for (var i = 0; i < quran.length + faith.length; i++)
          pickPraise(ar, picker, PraiseGroup.quran, form: PraiseForm.man),
      };
      expect(said, {...quran, ...faith},
          reason: 'its own lines and faith\'s, before any general one');
    });
  });

  group('never the same line twice', () {
    test('its own lines first, then the general ones, then the oldest', () {
      final picker = PraisePicker(random: Random(7), memory: 100);
      final sleep = lines(PraiseGroup.sleep, PraiseForm.man);
      final general = lines(PraiseGroup.general, PraiseForm.man);
      final said = [
        for (var i = 0; i < sleep.length + general.length; i++)
          pickPraise(ar, picker, PraiseGroup.sleep, form: PraiseForm.man),
      ];
      expect(said.take(sleep.length).toSet(), sleep.toSet());
      expect(said.skip(sleep.length).toSet(), general.toSet());
      expect(said.toSet().length, said.length, reason: 'no repeats');
      expect(pickPraise(ar, picker, PraiseGroup.sleep, form: PraiseForm.man),
          said.first,
          reason: 'everything said: the one said longest ago comes round');
    });

    test('a short memory still never repeats the line just said', () {
      final picker = PraisePicker(random: Random(1), memory: 3);
      String? last;
      for (var i = 0; i < 40; i++) {
        final line =
            pickPraise(ar, picker, PraiseGroup.faith, form: PraiseForm.man);
        expect(line, isNot(last));
        last = line;
      }
    });
  });

  group('never wrong about who is reading', () {
    // Words that only fit a man, and their women's forms. Checked word by
    // word, punctuation dropped, in every list of every group.
    const onlyMen = [
      'عليك', 'فيك', 'يوفقك', 'منك', 'حسناتك', 'قلبك', 'صيامك', 'مالك',
      'جسمك', 'يشكرك', 'صحتك', 'ذهنك', 'رزقك', 'بالك', 'يجزاك', 'يحفظك',
      'يثبتك', 'يسعدك', 'يريّحك', 'لمستقبلك', 'لك', 'قدرك', 'راحتك', 'يعطيك',
      'زادك', 'سويت', 'ركزت', 'خلّصت', 'حصّنت', 'صفّيت', 'الصايم', 'يعافيك',
      'تعبت', 'بترتاح', 'نفسك', 'خلصت',
    ];
    const onlyWomen = [
      'عليج', 'فيج', 'يوفقج', 'منج', 'حسناتج', 'قلبج', 'صيامج', 'مالج',
      'جسمج', 'يشكرج', 'صحتج', 'ذهنج', 'رزقج', 'بالج', 'يجزاج', 'يحفظج',
      'يثبتج', 'يسعدج', 'يريّحج', 'لمستقبلج', 'لج', 'قدرج', 'راحتج', 'يعطيج',
      'زادج', 'سويتي', 'ركزتي', 'خلّصتي', 'حصّنتي', 'صفّيتي', 'الصايمة',
      'يعافيج', 'تعبتي', 'بترتاحين', 'نفسج', 'خلصتي',
    ];
    List<String> words(String line) => [
          for (final w in line.split(RegExp(r'\s+')))
            w.replaceAll(RegExp(r'[!؟،.]'), ''),
        ];

    for (final group in PraiseGroup.values) {
      test('${group.name}: a woman never hears a man\'s word, a man never a '
          "woman's, and a reader nobody knows hears neither", () {
        for (final line in lines(group, PraiseForm.woman)) {
          for (final w in words(line)) {
            expect(onlyMen, isNot(contains(w)), reason: 'F list: $line');
          }
        }
        for (final line in lines(group, PraiseForm.man)) {
          for (final w in words(line)) {
            expect(onlyWomen, isNot(contains(w)), reason: 'M list: $line');
          }
        }
        for (final line in lines(group, PraiseForm.unknown)) {
          for (final w in words(line)) {
            expect([...onlyMen, ...onlyWomen], isNot(contains(w)),
                reason: 'said to anyone: $line');
          }
        }
      });
    }

    test('a reader nobody knows hears only lines written the same in both '
        'lists, and there are always some to say', () {
      for (final group in PraiseGroup.values) {
        final shared = lines(group, PraiseForm.unknown);
        final m = lines(group, PraiseForm.man);
        final f = lines(group, PraiseForm.woman);
        expect(shared, isNotEmpty, reason: '$group');
        for (final line in shared) {
          expect(m, contains(line));
          expect(f, contains(line));
        }
      }
      expect(lines(PraiseGroup.general, PraiseForm.unknown).length,
          greaterThanOrEqualTo(4),
          reason: 'the fallback for everyone nobody knows');
    });

    test('whatever it picks for a reader nobody knows is a shared line', () {
      final picker = PraisePicker(random: Random(5), memory: 200);
      final shared = {
        ...lines(PraiseGroup.sport, PraiseForm.unknown),
        ...lines(PraiseGroup.health, PraiseForm.unknown),
        ...lines(PraiseGroup.general, PraiseForm.unknown),
      };
      for (var i = 0; i < 60; i++) {
        expect(
          shared,
          contains(pickPraise(ar, picker, PraiseGroup.sport,
              form: PraiseForm.unknown)),
        );
      }
    });

    group('who the app thinks is reading', () {
      String someone(CharacterGender gender) => CharacterCatalog.forGender(
              gender)
          .firstWhere((c) => c.id != const CharacterState().characterId)
          .id;

      CharacterState wearing(String id, {bool loading = false}) =>
          CharacterState(characterId: id, isLoading: loading);

      test('a woman\'s character: a woman (nobody starts in one)', () {
        expect(praiseFormFor(wearing(someone(CharacterGender.female))),
            PraiseForm.woman);
      });

      test('a man\'s character someone chose: a man', () {
        expect(praiseFormFor(wearing(someone(CharacterGender.male))),
            PraiseForm.man);
      });

      test('any man\'s skin, the one every account starts in included: a '
          'man (Aziz: "take it from the skin chosen")', () {
        expect(praiseFormFor(wearing(const CharacterState().characterId)),
            PraiseForm.man);
      });

      test('not loaded yet, or an id the catalog does not know: unknown', () {
        expect(
          praiseFormFor(
              wearing(someone(CharacterGender.female), loading: true)),
          PraiseForm.unknown,
        );
        expect(praiseFormFor(wearing('no_such_character')),
            PraiseForm.unknown);
      });
    });

    test('the progress line: «خلصت» to a man, «خلصتي» to a woman, «خلصنا» '
        'to anyone else, always Arabic first', () {
      expect(ar.sproutProgress(5, 10), 'خلصت 5 من 10');
      expect(ar.sproutProgressF(5, 10), 'خلصتي 5 من 10');
      expect(ar.sproutProgressWe(5, 10), 'خلصنا 5 من 10');
      for (final line in [
        ar.sproutProgress(5, 10),
        ar.sproutProgressF(5, 10),
        ar.sproutProgressWe(5, 10),
      ]) {
        expect(RegExp(r'^[؀-ۿ]').hasMatch(line), isTrue,
            reason: 'an Arabic letter first fixes the line\'s direction');
      }
      expect(en.sproutProgress(5, 10), '5 of 10 done');
    });
  });

  test('no exclamation mark anywhere in what the sprout says (Aziz: it reads '
      'as machine-written)', () {
    for (final s in [ar, en]) {
      final said = [
        s.sproutMorning,
        s.sproutHello,
        s.sproutFirstDone,
        s.sproutProgress(2, 5),
        s.sproutProgressF(2, 5),
        s.sproutProgressWe(2, 5),
        s.sproutStreakPoint,
        s.sproutPerfectDay,
        s.sproutPerfectDayBlessing,
        s.sproutGoodNight,
        s.sproutLateNight,
        s.sproutRestDay,
        s.sproutTickle,
        s.perfectDayMsg,
        for (final group in PraiseGroup.values)
          for (final form in PraiseForm.values)
            ...praiseLines(s, group, form: form),
      ];
      for (final line in said) {
        expect(line, isNot(contains('!')), reason: line);
      }
    }
  });

  test('a full day says «ما شاء الله تبارك الله»', () {
    expect(ar.sproutPerfectDayBlessing, 'ما شاء الله تبارك الله');
  });

  group('the lists', () {
    for (final group in PraiseGroup.values) {
      test('${group.name}: both forms, both languages', () {
        final m = lines(group, PraiseForm.man);
        final f = lines(group, PraiseForm.woman);
        expect(m.length, greaterThanOrEqualTo(3));
        expect(f.length, m.length, reason: 'the F list mirrors the M one');
        expect(lines(group, PraiseForm.man, en).length, m.length);
        expect(lines(group, PraiseForm.woman, en),
            lines(group, PraiseForm.man, en),
            reason: 'English has one form');
      });
    }

    test('none says full or perfect: they also play at the 80% streak point',
        () {
      for (final s in [ar, en]) {
        for (final group in PraiseGroup.values) {
          for (final form in PraiseForm.values) {
            for (final line in praiseLines(s, group, form: form)) {
              expect(line, isNot(contains('كامل')), reason: line);
              expect(line, isNot(contains('مثالي')), reason: line);
              expect(line.toLowerCase(), isNot(contains('full day')),
                  reason: line);
              expect(line.toLowerCase(), isNot(contains('perfect')),
                  reason: line);
            }
          }
        }
      }
    });

    test('worship is prayed for, never declared accepted (Aziz, 2026-09-28): '
        'a line about acceptance or the scale is a du\'a or says «إن شاء الله»',
        () {
      for (final group in PraiseGroup.values) {
        for (final form in PraiseForm.values) {
          for (final line in lines(group, form)) {
            if (!line.contains('مقبول') && !line.contains('ميزان')) continue;
            expect(
              line.contains('إن شاء الله') || line.startsWith('جعلها الله'),
              isTrue,
              reason: line,
            );
          }
        }
      }
    });

    test('short enough for the bubble, and no line twice in one pool (a '
        'group with its parent)', () {
      for (final group in PraiseGroup.values) {
        for (final form in PraiseForm.values) {
          final parent = praiseParentOf(group);
          final pool = [
            ...lines(group, form),
            if (parent != null) ...lines(parent, form),
          ];
          expect(pool.toSet().length, pool.length, reason: '$group');
          for (final line in pool) {
            expect(line.length, lessThanOrEqualTo(30), reason: line);
          }
        }
      }
    });
  });
}
