// The ideas page's search (lib/features/habits/catalog/idea_search.dart),
// over the real built-in list, the way people type: «صلاه» without its
// hamza, «القران», a typo, a word the idea never says («سجائر» for «بدون
// تدخين»), a whole sentence («ابي اترك التدخين»), Gulf letters («گهوة»).
//
// Each case names the idea that must come FIRST, and where it matters what
// must stay out: a fuzzy search that finds everything is no search. Run
// against assets/data/habit_ideas.json, so an edit to an idea's name that
// breaks how it is found shows here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/habits/catalog/habit_ideas.dart';
import 'package:grow_daily_v2/features/habits/catalog/idea_search.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';

void main() {
  final all = resolveIdeas(
    parseHabitIdeas(File('assets/data/habit_ideas.json').readAsStringSync()),
    null,
  );
  // The page searches one side at a time, as here.
  final build = IdeaSearch([
    for (final i in all)
      if (i.idea.type == GoalType.build) i,
  ]);
  final quit = IdeaSearch([
    for (final i in all)
      if (i.idea.type == GoalType.quit) i,
  ]);

  List<String> ids(IdeaSearch s, String q) =>
      [for (final i in s.search(q)) i.idea.id];

  void first(IdeaSearch s, String q, String id) {
    final got = ids(s, q);
    expect(got, isNotEmpty, reason: '«$q» finds nothing');
    expect(got.first, id, reason: '«$q» → $got');
  }

  void lacks(IdeaSearch s, String q, String id) =>
      expect(ids(s, q), isNot(contains(id)), reason: '«$q» → ${ids(s, q)}');

  group('Arabic the way it is typed', () {
    test('no hamza, no taa marbuta, no harakat, any article', () {
      first(build, 'صلاه الضحي', 'duha_prayer');
      first(build, 'القران', 'daily_quran');
      first(build, 'قرأن', 'daily_quran');
      first(build, 'الاستغفار', 'istighfar');
      first(build, 'استغفر', 'istighfar');
      first(build, 'اذكار الصباح', 'morning_athkar');
      first(build, 'صَدَقَة', 'daily_charity');
      expect(ids(quit, 'بالتلفون'), ids(quit, 'تلفون'));
      expect(ids(quit, 'تلفون'), contains('no_phone_before_bed'));
    });

    test('Gulf letters and Arabic-Indic digits', () {
      first(quit, 'گهوة', ids(quit, 'قهوة').first);
      expect(ids(quit, 'گهوة'), ids(quit, 'قهوة'));
      expect(ids(build, '١٠'), ids(build, '10'));
      expect(ids(build, '١٠'), contains('walk_10_minutes'));
    });

    test('a letter held down is one letter', () {
      expect(normalizeSearchText('صلااااة'), normalizeSearchText('صلاة'));
      expect(normalizeSearchText('sleeep'), 'slep');
      expect(normalizeSearchText('100'), '100',
          reason: 'digits are never folded',);
    });

    test('words in any order, and the name as it is being typed', () {
      first(build, 'الملك سورة', 'mulk_before_sleep');
      first(build, 'قران قبل النوم', 'mulk_before_sleep');
      first(build, 'صلاة الض', 'duha_prayer');
      first(build, 'صد', 'daily_charity');
    });
  });

  group('other words for the same thing', () {
    test('quitting smoking, however it is said', () {
      for (final q in [
        'سجائر', 'سيجاره', 'شيشة', 'دخان', 'التدخين', 'vape', 'cigarettes',
        'ابي اترك التدخين', 'quit smoking',
      ]) {
        first(quit, q, 'no_smoking');
      }
    });

    test('Arabic finds the English-named idea and back', () {
      first(build, 'جيم', 'gym_session');
      first(build, 'gym', 'gym_session');
      first(build, 'انجليزي', 'practice_language');
      first(build, 'english', 'practice_language');
      first(build, 'مويه', 'drink_water');
      expect(ids(quit, 'انستا'), unorderedEquals([
        'no_social_media_in_bed', 'reduce_scrolling',
        'no_scrolling_while_studying',
      ]),);
      expect(ids(quit, 'tiktok'), contains('reduce_scrolling'));
      expect(ids(quit, 'تيك توك'), contains('no_social_media_in_bed'));
      first(quit, 'talabat', 'reduce_delivery_orders');
      first(quit, 'fast food', 'no_junk_food');
      first(quit, 'حلويات', 'no_added_sugar');
    });

    test('a feeling finds the ideas that help it', () {
      expect(ids(build, 'قلق'),
          containsAll(['meditate_5_minutes', 'breathing_exercise']),);
      expect(ids(build, 'anxiety'),
          containsAll(['meditate_5_minutes', 'breathing_exercise']),);
    });

    test('a category answers to its name', () {
      final sleep = ids(build, 'نوم');
      expect(sleep, containsAll(['sleep_by_11pm', 'wake_up_early']));
      expect(ids(build, 'money'),
          containsAll(['track_spending', 'save_daily', 'compare_prices']),);
    });

    test('a word that also names something else does not drag it in', () {
      lacks(build, 'sleep', 'make_bed'); // the made bed is not sleep
      lacks(build, 'نوم', 'make_bed');
      lacks(build, 'phone', 'call_family'); // a call is not the phone
      lacks(build, 'جيم', 'stretch'); // «تمارين إطالة» is not the gym
      lacks(build, 'exam', 'review_budget'); // «مراجعة» the budget
      first(build, 'water', 'drink_water'); // before the plants
    });
  });

  group('typos', () {
    test('forgiven in a longer word', () {
      first(quit, 'smokng', 'no_smoking');
      first(build, 'meditaion', 'meditate_5_minutes');
      expect(ids(build, 'excercise'), contains('gym_session'));
      expect(ids(build, 'سيام'), contains('fast_mon_thu'));
    });

    test('only when nothing matches without one', () {
      expect(ids(build, 'صيام'), ['fast_mon_thu'],
          reason: '«قيام الليل» is one letter away and another thing',);
      lacks(build, 'قيام', 'fast_mon_thu');
    });

    test('never across a short word into another meaning', () {
      lacks(quit, 'صدقة', 'no_lying'); // charity is not «صدق»
      expect(ids(build, 'smoking'), isEmpty,
          reason: 'not "seeking" forgiveness',);
      lacks(build, 'clean', 'walk_10_minutes'); // "clear", not clean
      expect(ids(quit, 'whatsapp'), ['less_group_chats'],
          reason: 'not every idea with "what" in it',);
    });

    test('numbers are exact', () {
      lacks(build, '10', 'morning_athkar'); // its «100»
      expect(ids(build, '10'),
          containsAll(['walk_10_minutes', 'read_10_pages', 'tidy_10_minutes']),);
      expect(ids(build, '11'), contains('sleep_by_11pm'));
    });
  });

  group('the words that say nothing', () {
    test('are dropped while another word is left', () {
      first(build, 'ابي عادة للصلاة', ids(build, 'صلاة').first);
      first(quit, 'بدون سكر', 'no_added_sugar');
      first(build, 'daily quran', 'daily_quran');
    });

    test('but are searched when they are all there is', () {
      expect(ids(quit, 'تقليل'),
          containsAll(['reduce_caffeine', 'reduce_scrolling']),);
      expect(ids(quit, 'less'), contains('less_group_chats'));
    });
  });

  group('what comes back', () {
    test('nothing for nonsense, everything for no word at all', () {
      expect(ids(build, 'zzqqxx'), isEmpty);
      expect(build.search('؟ ، .'), hasLength(
          all.where((i) => i.idea.type == GoalType.build).length,),);
    });

    test('a hit only in the text behind an idea counts when nothing '
        'nearer does', () {
      // «الجنة» is on the sunnah prayers' card line, and in other ideas'
      // hadith text only: the card line wins alone.
      expect(ids(build, 'جنة'), ['sunnah_prayers']);
    });

    test('when no idea has every word, the ones with the most', () {
      expect(ids(build, 'قران رمضان'), contains('daily_quran'));
    });

    test('is quick enough to run on every key', () {
      final sw = Stopwatch()..start();
      for (var k = 0; k < 20; k++) {
        build.search('excercise');
        quit.search('ابي اترك التدخين');
      }
      expect(sw.elapsedMilliseconds / 40, lessThan(16),
          reason: 'one search inside a frame',);
    });
  });
}
