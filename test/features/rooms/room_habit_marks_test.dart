// The per-habit marks a room day carries beside its counts, and the wall that
// keeps them from paying.
//
// A day's counts (done, جزئي, asked) are what a room ranks and pays on, and
// they never said WHICH habit each one was, so the tapped-day card could only
// name habits on a day where every habit landed the same way. Aziz,
// 2026-09-11: "why some times it says the habit that done, and sometimes the
// name is not mention? lets make it mention all the time". The sync now
// writes RoomParticipant.dailyHabitMarks beside the counts.
//
// Pinned here: the marks are trusted only where they agree with the counts,
// the sync keeps or drops them the way the anti-backdating clamp needs, and
// nothing that produces a score can see them.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

const _d = RoomHabitMark.done;
const _p = RoomHabitMark.partial;
const _s = RoomHabitMark.skipped;
const _m = RoomHabitMark.missed;
const _r = RoomHabitMark.rest;

const _day = '2026-09-09';

RoomParticipant _member({
  Map<String, int> done = const {},
  Map<String, int> partial = const {},
  Map<String, int> scheduled = const {},
  Map<String, Map<String, RoomHabitMark>> marks = const {},
}) =>
    RoomParticipant(
      uid: 'aziz',
      displayName: 'Aziz',
      characterId: 'none',
      joinedAt: DateTime(2026, 8),
      linkedHabitIds: const ['t', 'w', 'q'],
      dailyDoneCount: done,
      dailyPartialCount: partial,
      dailyScheduledCount: scheduled,
      dailyHabitMarks: marks,
      lastUpdated: DateTime(2026, 9, 11),
    );

void main() {
  group('habitMarksAgree', () {
    test('the same number done, جزئي and asked', () {
      expect(
        habitMarksAgree(
          {'t': _m, 'w': _d, 'q': _d},
          done: 2,
          partial: 0,
          scheduled: 3,
        ),
        isTrue,
      );
    });

    test('a rest is not asked, a تخطّي is', () {
      expect(
        habitMarksAgree(
          {'t': _r, 'w': _d, 'q': _d},
          done: 2,
          partial: 0,
          scheduled: 2,
        ),
        isTrue,
      );
      expect(
        habitMarksAgree({'t': _s, 'w': _d}, done: 1, partial: 0, scheduled: 2),
        isTrue,
      );
    });

    test('any count that differs is a different day', () {
      final marks = {'t': _p, 'w': _d, 'q': _m};
      expect(habitMarksAgree(marks, done: 1, partial: 1, scheduled: 3), isTrue);
      expect(
        habitMarksAgree(marks, done: 2, partial: 1, scheduled: 3),
        isFalse,
      );
      expect(
        habitMarksAgree(marks, done: 1, partial: 0, scheduled: 3),
        isFalse,
      );
      expect(
        habitMarksAgree(marks, done: 1, partial: 1, scheduled: 2),
        isFalse,
      );
    });
  });

  group('habitMarksFor: trusted only where the counts agree', () {
    test('a day graded with its marks returns them', () {
      final p = _member(
        done: {_day: 2},
        marks: {
          _day: {'t': _m, 'w': _d, 'q': _d},
        },
      );
      expect(p.habitMarksFor(_day), {'t': _m, 'w': _d, 'q': _d});
    });

    test('a stored scheduled count is honoured, so a quota rest agrees', () {
      final p = _member(
        done: {_day: 2},
        scheduled: {_day: 2},
        marks: {
          _day: {'t': _r, 'w': _d, 'q': _d},
        },
      );
      expect(p.habitMarksFor(_day), isNotNull);
    });

    test('counts an older build moved without the marks are not named', () {
      // A current build wrote two done; an older build on another device
      // then regraded the day to one. The marks still say two, so the card
      // must not name either of them.
      final p = _member(
        done: {_day: 1},
        marks: {
          _day: {'t': _m, 'w': _d, 'q': _d},
        },
      );
      expect(p.habitMarksFor(_day), isNull);
    });

    test('a day with no marks has none', () {
      expect(_member(done: {_day: 2}).habitMarksFor(_day), isNull);
    });
  });

  group('reconciledHabitMarks: what the sync stores', () {
    test('an ordinary day stores what the squares say', () {
      final fresh = {'t': _m, 'w': _d, 'q': _d};
      expect(
        reconciledHabitMarks(
          fresh: fresh,
          stored: null,
          held: false,
          done: 2,
          partial: 0,
          scheduled: 3,
        ),
        fresh,
      );
    });

    test('un-ticking a habit on a past day moves its mark with the count', () {
      // The clamp lets a count FALL. The stored marks say two done; the
      // squares and the lowered count both say one.
      final stored = {'t': _d, 'w': _d};
      final fresh = {'t': _m, 'w': _d};
      expect(
        reconciledHabitMarks(
          fresh: fresh,
          stored: stored,
          held: true,
          done: 1,
          partial: 0,
          scheduled: 2,
        ),
        fresh,
      );
    });

    test('a back-painted square on a held day never draws a tick', () {
      // وتر painted onto a closed, observed Tuesday: the squares say two done,
      // the clamp keeps the count at one, and there is no earlier record to
      // say which one the room paid.
      expect(
        reconciledHabitMarks(
          fresh: {'t': _d, 'w': _d},
          stored: null,
          held: true,
          done: 1,
          partial: 0,
          scheduled: 2,
        ),
        isNull,
      );
    });

    test('a held day keeps the record made while it was on time', () {
      // One habit un-ticked and the other back-painted: the count cannot tell
      // (still one) and the squares would name the late one. The on-time
      // record wins.
      final stored = {'t': _d, 'w': _m};
      expect(
        reconciledHabitMarks(
          fresh: {'t': _m, 'w': _d},
          stored: stored,
          held: true,
          done: 1,
          partial: 0,
          scheduled: 2,
        ),
        stored,
      );
    });

    test('stale stored marks are never kept on a day that was not held', () {
      expect(
        reconciledHabitMarks(
          fresh: {'t': _d, 'w': _d},
          stored: {'t': _d, 'w': _m},
          held: false,
          done: 1,
          partial: 0,
          scheduled: 2,
        ),
        isNull,
      );
    });

    test('a day nothing was present on stores nothing', () {
      // gradedScheduledCount: the plan never reached the day, so it keeps the
      // plain total with no habit behind it to name.
      expect(
        reconciledHabitMarks(
          fresh: const {},
          stored: null,
          held: false,
          done: 0,
          partial: 0,
          scheduled: 3,
        ),
        isNull,
      );
    });
  });

  group('sameHabitMarks', () {
    test('absent and empty are the same', () {
      expect(sameHabitMarks(null, const {}), isTrue);
      expect(sameHabitMarks(const {}, null), isTrue);
    });

    test('any different mark is a change', () {
      expect(sameHabitMarks({'t': _d}, {'t': _d}), isTrue);
      expect(sameHabitMarks({'t': _d}, {'t': _m}), isFalse);
      expect(sameHabitMarks({'t': _d}, {'t': _d, 'w': _m}), isFalse);
      expect(sameHabitMarks({'t': _d}, null), isFalse);
    });
  });

  group('the stored shape', () {
    test('one letter per habit per day, and back', () {
      final marks = {
        _day: {'t': _m, 'w': _d, 'q': _p},
        '2026-09-10': {'t': _r, 'w': _s},
      };
      final wire = RoomParticipant.habitMarksToFirestore(marks);
      expect(wire, {
        _day: {'t': 'm', 'w': 'd', 'q': 'p'},
        '2026-09-10': {'t': 'r', 'w': 's'},
      });
      expect(RoomParticipant.habitMarksFrom(wire), marks);
    });

    test('anything unreadable is dropped, not guessed', () {
      final parsed = RoomParticipant.habitMarksFrom({
        _day: {'t': 'd', 'w': 'x', 'q': 3},
        '2026-09-10': 'd',
        '2026-09-11': {'t': 'zz'},
      });
      expect(parsed, {
        _day: {'t': _d},
      });
      expect(RoomParticipant.habitMarksFrom(null), isEmpty);
      expect(RoomParticipant.habitMarksFrom('d'), isEmpty);
    });

    test('a participant with no marks writes no field', () {
      expect(_member().toFirestore().containsKey('dailyHabitMarks'), isFalse);
      expect(
        _member(
          marks: {
            _day: {'t': _d},
          },
        ).toFirestore()['dailyHabitMarks'],
        {
          _day: {'t': 'd'},
        },
      );
    });

    test('copyWith carries them', () {
      final p = _member(
        marks: {
          _day: {'t': _d},
        },
      );
      expect(
        p.copyWith(dailyDoneCount: const {_day: 1}).dailyHabitMarks,
        {
          _day: {'t': _d},
        },
      );
    });
  });

  group('THE WALL: dailyHabitMarks may never move a score', () {
    // An ended room, so lastCountedDay is its end date and nothing below
    // depends on the day the suite happens to run.
    final room = RoomModel(
      code: 'ELQVF8',
      name: 'Being Better',
      createdBy: 'aziz',
      createdByName: 'Aziz',
      createdAt: DateTime(2026, 8),
      habitMode: RoomHabitMode.shared,
      sharedHabits: const [
        RoomHabitTemplate(
          name: 'تمرين',
          category: HabitCategory.health,
          frequencyType: HabitFrequencyType.weekly,
          frequencyTarget: 4,
        ),
        RoomHabitTemplate(
          name: 'صلاة الوتر',
          category: HabitCategory.faith,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
        ),
        RoomHabitTemplate(
          name: 'قراءة القرآن',
          category: HabitCategory.faith,
          frequencyType: HabitFrequencyType.daily,
          frequencyTarget: 1,
        ),
      ],
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 8),
      endDate: DateTime(2026, 8, 7),
    );
    final bare = _member(
      done: const {
        '2026-08-01': 1,
        '2026-08-02': 3,
        '2026-08-03': 2,
        '2026-08-05': 3,
        '2026-08-06': 2,
      },
      partial: const {'2026-08-03': 1},
      scheduled: const {'2026-08-06': 2},
    );
    // Marks that contradict the counts every way they could: more done,
    // fewer asked, a rest where the count says asked. If any score read
    // them, some number below would move.
    final marked = bare.copyWith(
      dailyHabitMarks: {
        for (var d = 1; d <= 7; d++) '2026-08-0$d': {'t': _d, 'w': _d, 'q': _r},
      },
    );
    final days = [for (var d = 1; d <= 7; d++) '2026-08-0$d'];

    test('each day\'s own numbers are unmoved', () {
      for (final day in days) {
        expect(marked.creditFor(day), bare.creditFor(day), reason: day);
        expect(
          marked.scheduledCountFor(day),
          bare.scheduledCountFor(day),
          reason: day,
        );
        expect(marked.isFullyDone(day), bare.isFullyDone(day), reason: day);
        expect(marked.isRestDay(day), bare.isRestDay(day), reason: day);
        expect(
          marked.roomCreditFor(room, day),
          bare.roomCreditFor(room, day),
          reason: day,
        );
      }
    });

    test('daysCompleted and progressRatio are unmoved', () {
      expect(marked.daysCompleted(room), bare.daysCompleted(room));
      expect(marked.progressRatio(room), bare.progressRatio(room));
    });

    test('the room score the board SORTS on is unmoved', () {
      expect(marked.roomDaysCompleted(room), bare.roomDaysCompleted(room));
      expect(marked.roomProgressRatio(room), bare.roomProgressRatio(room));
    });

    test('currentStreak is unmoved', () {
      final now = DateTime(2026, 8, 8, 12);
      expect(
        marked.currentStreak(room, now: now),
        bare.currentStreak(room, now: now),
      );
    });
  });
}
