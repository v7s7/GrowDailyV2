// What a room counts once a habit has been paused AND resumed.
//
// A habit carries one window on itself: createdAt and archivedAt. That window
// cannot describe a habit that was stood down and picked back up, and grading
// off it got the answer wrong in OPPOSITE directions depending on the kind of
// habit:
//
//   * A resumed CATALOG habit re-stamps its activation to the resume day, so
//     every day before it read as "never existed", left the denominator, and
//     paid full credit. Pause everything, resume, collect 100%.
//   * A resumed CUSTOM habit kept its original createdAt with archivedAt
//     cleared, so it claimed to have been running the whole time and the
//     paused days it had been correctly excused from became misses.
//
// habitCountedOn answers from the habit's real stints instead, so the same
// question gets the same answer whichever kind of habit it is, and resuming
// changes nothing about a day that has already been lived.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/habits/notifiers/custom_habits_notifier.dart';

void main() {
  _repairTests();

  DateTime d(int day) => DateTime(2026, 8, day);

  // Never consulted unless the stint list is empty; a loud default makes an
  // accidental fallback obvious rather than silently plausible.
  bool noFallback() =>
      throw StateError('fallback must not be reached when stints exist');

  group('a habit paused and resumed', () {
    // Active 1-10 August, paused, active again from the 20th.
    final stints = <(DateTime?, DateTime?)>[
      (d(1), d(10)),
      (d(20), null),
    ];

    test('the days before the pause still count', () {
      // The catalog bug: these were dropped entirely and paid full credit.
      for (final day in [1, 5, 10]) {
        expect(habitCountedOn(stints, d(day), fallback: noFallback), isTrue,
            reason: 'August $day was inside the first stint');
      }
    });

    test('the paused days do not count, before OR after resuming', () {
      // The custom bug: resuming turned these into misses.
      for (final day in [11, 15, 19]) {
        expect(habitCountedOn(stints, d(day), fallback: noFallback), isFalse,
            reason: 'August $day was paused, so it is excused either way');
      }
    });

    test('the days after resuming count again', () {
      for (final day in [20, 25]) {
        expect(habitCountedOn(stints, d(day), fallback: noFallback), isTrue);
      }
    });

    test('days before it ever existed never count', () {
      expect(habitCountedOn(stints, DateTime(2026, 7, 31), fallback: noFallback),
          isFalse);
    });

    test('the archive day itself still counts', () {
      // Pinned by paused_habit_grading_rule_test: pausing on a day does not
      // retroactively erase that day.
      expect(habitCountedOn(stints, d(10), fallback: noFallback), isTrue);
    });
  });

  group('degrading safely', () {
    test('no stint history at all falls back to the old rule', () {
      // Every account that has never paused anything. The old single-window
      // answer has to survive verbatim, or the first launch after this ships
      // would re-grade history that nobody touched.
      expect(habitCountedOn(null, d(5), fallback: () => true), isTrue);
      expect(habitCountedOn(const [], d(5), fallback: () => false), isFalse);
    });

    test('an open stint has no upper bound', () {
      final running = <(DateTime?, DateTime?)>[(d(1), null)];
      expect(habitCountedOn(running, d(999 % 28 + 1), fallback: noFallback),
          isTrue);
      expect(habitCountedOn(running, DateTime(2027, 1, 1), fallback: noFallback),
          isTrue);
    });

    test('an unknown start means it always existed', () {
      // Matches isScheduledFor's reading of a null createdAt.
      final unknown = <(DateTime?, DateTime?)>[(null, d(10))];
      expect(habitCountedOn(unknown, DateTime(2020, 1, 1), fallback: noFallback),
          isTrue);
      expect(habitCountedOn(unknown, d(11), fallback: noFallback), isFalse);
    });

    test('a same-day pause and resume is one window, not two', () {
      // CustomHabitsNotifier.unarchive records nothing when the pause ended
      // today, so the day is claimed exactly once.
      final sameDay = <(DateTime?, DateTime?)>[(d(1), null)];
      expect(habitCountedOn(sameDay, d(1), fallback: noFallback), isTrue);
    });
  });

  group('several stints', () {
    test('every window counts, and the gaps between them do not', () {
      final many = <(DateTime?, DateTime?)>[
        (d(1), d(3)),
        (d(6), d(8)),
        (d(12), null),
      ];
      for (final day in [1, 2, 3, 6, 7, 8, 12, 28]) {
        expect(habitCountedOn(many, d(day), fallback: noFallback), isTrue,
            reason: 'August $day is inside a stint');
      }
      for (final day in [4, 5, 9, 10, 11]) {
        expect(habitCountedOn(many, d(day), fallback: noFallback), isFalse,
            reason: 'August $day is a gap between stints');
      }
    });
  });
}

// ── The repair for accounts already damaged ────────────────────────────────
//
// A habit whose birth date was overwritten by a resume (see
// CustomHabitsNotifier.unarchive) claims to be YOUNGER than the room's own
// frozen record of it. syncLinkedHabitsProgress treats the room's stamp as a
// floor and widens the habit's window backwards to it — but only backwards,
// only up to the damaged start, and never past a pause. These pin the shape of
// that rule, so a future change cannot quietly turn a repair into an amnesty.
//
// The rule itself lives inside syncLinkedHabitsProgress (it needs Firestore),
// so this mirrors its arithmetic exactly rather than calling it.
bool repairedCountedOn({
  required DateTime day,
  required DateTime? floor,
  required DateTime? damagedStart,
  required DateTime? archivedAt,
}) {
  if (floor == null || damagedStart == null) return false;
  final d = DateTime(day.year, day.month, day.day);
  if (d.isBefore(floor) || !d.isBefore(damagedStart)) return false;
  if (archivedAt != null &&
      d.isAfter(DateTime(archivedAt.year, archivedAt.month, archivedAt.day))) {
    return false;
  }
  return true;
}

void _repairTests() {
  final roomStart = DateTime(2026, 7, 28);
  final damaged = DateTime(2026, 8, 20); // the day the resume stamped
  final paused = DateTime(2026, 8, 24);

  group('the damaged-birth-date repair', () {
    test('days between the room start and the damaged start come back', () {
      for (final day in [DateTime(2026, 7, 28), DateTime(2026, 8, 5), DateTime(2026, 8, 19)]) {
        expect(
          repairedCountedOn(
              day: day, floor: roomStart, damagedStart: damaged, archivedAt: paused),
          isTrue,
          reason: '$day is history the room itself attests to',
        );
      }
    });

    test('it never reaches before the room existed', () {
      expect(
        repairedCountedOn(
            day: DateTime(2026, 7, 27), floor: roomStart, damagedStart: damaged, archivedAt: paused),
        isFalse,
        reason: 'the room has no record of this member before its own start',
      );
    });

    test('it stops at the damaged start, which the real window already covers',
        () {
      expect(
        repairedCountedOn(
            day: damaged, floor: roomStart, damagedStart: damaged, archivedAt: paused),
        isFalse,
        reason: 'from here on the habit\'s own stint answers, so this must not '
            'double up',
      );
    });

    test('it never reaches past a pause', () {
      expect(
        repairedCountedOn(
            day: DateTime(2026, 8, 25), floor: roomStart, damagedStart: damaged, archivedAt: paused),
        isFalse,
        reason: 'a stood-down day is not a tracked day, and letting the repair '
            'cover it would hand back the pause-everything amnesty',
      );
    });

    test('an undamaged account never enters the branch at all', () {
      expect(
        repairedCountedOn(
            day: DateTime(2026, 8, 5), floor: null, damagedStart: null, archivedAt: null),
        isFalse,
        reason: 'no floor is set unless the habit claims to be younger than the '
            'room, so nothing re-grades on first launch',
      );
    });
  });
}
