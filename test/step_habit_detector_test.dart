import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/utils/step_habit_detector.dart';

void main() {
  group('looksLikeStepHabit: English', () {
    test('plain forms match', () {
      expect(looksLikeStepHabit('Walk'), isTrue);
      expect(looksLikeStepHabit('walking'), isTrue);
      expect(looksLikeStepHabit('Morning walk'), isTrue);
      expect(looksLikeStepHabit('10000 steps'), isTrue);
      expect(looksLikeStepHabit('daily jog'), isTrue);
      expect(looksLikeStepHabit('go running'), isTrue);
      expect(looksLikeStepHabit('treadmill session'), isTrue);
    });

    test('one-letter typos and transpositions match', () {
      expect(looksLikeStepHabit('wakling every day'), isTrue);
      expect(looksLikeStepHabit('10k stpes'), isTrue);
      expect(looksLikeStepHabit('runing in the park'), isTrue);
      expect(looksLikeStepHabit('morning walkk'), isTrue);
      expect(looksLikeStepHabit('walkin after dinner'), isTrue);
    });

    test('words one edit from a keyword but real in their own right do not', () {
      expect(looksLikeStepHabit('waking up early'), isFalse);
      expect(looksLikeStepHabit('deep work'), isFalse);
      expect(looksLikeStepHabit('working out'), isFalse);
      expect(looksLikeStepHabit('talking to mom'), isFalse);
      expect(looksLikeStepHabit('no coffee stops'), isFalse);
    });

    test('unrelated habits do not match', () {
      expect(looksLikeStepHabit('Read 10 pages'), isFalse);
      expect(looksLikeStepHabit('drink water'), isFalse);
      expect(looksLikeStepHabit('قراءه القران'), isFalse);
      expect(looksLikeStepHabit(''), isFalse);
    });
  });

  group('looksLikeStepHabit: Arabic', () {
    test('spoken forms match', () {
      expect(looksLikeStepHabit('مشي'), isTrue);
      expect(looksLikeStepHabit('المشي اليومي'), isTrue);
      expect(looksLikeStepHabit('امشي نص ساعه'), isTrue);
      expect(looksLikeStepHabit('امش بعد الفجر'), isTrue);
      expect(looksLikeStepHabit('تمشيه العصر'), isTrue);
      expect(looksLikeStepHabit('٨٠٠٠ خطوه'), isTrue);
      expect(looksLikeStepHabit('خطوات اليوم'), isTrue);
      expect(looksLikeStepHabit('جري خفيف'), isTrue);
      expect(looksLikeStepHabit('اركض ٥ دقايق'), isTrue);
    });

    test('spelling variants fold to the same entry', () {
      // ة/ه and آ/ا variants, plus diacritics.
      expect(looksLikeStepHabit('خطوة'), isTrue);
      expect(looksLikeStepHabit('تمشية'), isTrue);
      expect(looksLikeStepHabit('مَشْي'), isTrue);
    });

    test('lookalike stems do not match', () {
      expect(looksLikeStepHabit('مشروع جديد'), isFalse);
      expect(looksLikeStepHabit('مشاهده اقل'), isFalse);
      expect(looksLikeStepHabit('خطه الاسبوع'), isFalse);
    });
  });

  group('parseStepGoal', () {
    test('explicit step counts parse', () {
      expect(parseStepGoal('walk 8000 steps'), 8000);
      expect(parseStepGoal('٨٠٠٠ خطوه'), 8000);
      expect(parseStepGoal('امشي ٥٠٠٠'), 5000);
      expect(parseStepGoal('10k steps'), 10000);
      expect(parseStepGoal('٥ الاف خطوه'), 5000);
      expect(parseStepGoal('الف خطوه'), 1000);
      expect(parseStepGoal('500 steps'), 500);
    });

    test('time and distance goals are not step goals', () {
      expect(parseStepGoal('walk 30 min'), isNull);
      expect(parseStepGoal('امش 30 دقيقه'), isNull);
      expect(parseStepGoal('walk 5 km'), isNull);
      expect(parseStepGoal('امشي ٥ كيلو'), isNull);
      expect(parseStepGoal('مشي نص ساعه'), isNull);
    });

    test('small bare numbers are not step goals', () {
      expect(parseStepGoal('walk 30'), isNull);
      expect(parseStepGoal('مشي ٤٥'), isNull);
    });

    test('absurd values are treated as unstated', () {
      expect(parseStepGoal('walk 999999 steps'), isNull);
      expect(parseStepGoal('walk 5 steps'), isNull);
    });

    test('no number means no goal', () {
      expect(parseStepGoal('المشي اليومي'), isNull);
      expect(parseStepGoal('walk'), isNull);
    });
  });
}
