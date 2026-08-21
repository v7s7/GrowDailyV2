// The rule that decides whether somebody's recorded history gets corrected
// or quietly rewritten.
//
// ── Why this exists ──────────────────────────────────────────────────────
// `habit_history` is a CACHE. `daily/{date}` is the truth, and three
// fire-and-forget writers keep the mirror in step. Any of those writes can be
// lost: the app is killed mid-batch, a queued offline write is dropped, two
// devices race. Nothing put it back, because the one-time backfill is stamped
// and never runs again once an account is stamped.
//
// Found on a real account: the Grid read 25 squares for a week while the
// report read 21, because four completions on one settled day had never
// reached the mirror. It was invisible until the day settled, since the
// reports resolve TODAY from live state and only consult the mirror for days
// that have stopped moving.
//
// The repair re-derives a bounded recent window and corrects the difference.
// This file pins the comparison at the centre of it, because a repair that
// gets this wrong does not fail loudly, it edits history.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/grid/models/square_state.dart';
import 'package:grow_daily_v2/features/milestones/notifiers/habit_history_notifier.dart';

void main() {
  // A window of settled days, newest first, exactly as the repair builds it.
  const window = [
    '2026-08-20',
    '2026-08-19',
    '2026-08-18',
    '2026-08-17',
  ];

  MirrorWindowDiff diff({
    Map<String, SquareState> want = const {},
    Map<String, SquareState> have = const {},
    List<String> keys = window,
  }) =>
      mirrorWindowDiff(windowKeys: keys, want: want, have: have);

  group('an account in step', () {
    test('identical mirror and truth changes nothing', () {
      final d = diff(
        want: const {
          '2026-08-20': SquareState.complete,
          '2026-08-18': SquareState.skipped,
        },
        have: const {
          '2026-08-20': SquareState.complete,
          '2026-08-18': SquareState.skipped,
        },
      );
      expect(d.isEmpty, isTrue,
          reason: 'an account that never drifted must cost zero writes');
    });

    test('two empty sides change nothing', () {
      expect(diff().isEmpty, isTrue);
    });
  });

  group('the bug this was written for: a lost write', () {
    test('a day the daily docs have and the mirror lost is restored', () {
      // Exactly the shape found on the real account: the completion is in
      // the daily document, absent from the mirror.
      final d = diff(
        want: const {'2026-08-20': SquareState.complete},
        have: const {},
      );
      expect(d.write, {'2026-08-20': SquareState.complete});
      expect(d.remove, isEmpty);
    });

    test('four lost days on one habit all come back', () {
      final d = diff(
        want: const {
          '2026-08-20': SquareState.complete,
          '2026-08-19': SquareState.complete,
          '2026-08-18': SquareState.complete,
          '2026-08-17': SquareState.complete,
        },
        have: const {'2026-08-18': SquareState.complete},
      );
      expect(d.write.keys, containsAll(['2026-08-20', '2026-08-19', '2026-08-17']));
      expect(d.write, isNot(contains('2026-08-18')),
          reason: 'a day already correct is not rewritten');
    });
  });

  group('the other direction, which a merge-only repair would have missed', () {
    test('a day the mirror claims and the truth does not is removed', () {
      // A lost DELETE: the user un-did the day, uncompleteHabit's mirror
      // delete never landed. Merge-only repair could never fix this, which
      // is why the repair uses FieldValue.delete() rather than merging.
      final d = diff(
        want: const {},
        have: const {'2026-08-19': SquareState.complete},
      );
      expect(d.remove, {'2026-08-19'});
      expect(d.write, isEmpty);
    });

    test('a changed mark is rewritten, not duplicated', () {
      final d = diff(
        want: const {'2026-08-17': SquareState.partial},
        have: const {'2026-08-17': SquareState.complete},
      );
      expect(d.write, {'2026-08-17': SquareState.partial});
      expect(d.remove, isEmpty);
    });

    test('all six states round-trip through the comparison', () {
      // Nothing here may treat a rest or a fail as "absent": تخطّي and فشل
      // are recorded states, and collapsing either into a blank would change
      // what the reports say about a person's month.
      for (final state in SquareState.values) {
        final d = diff(
          want: {'2026-08-20': state},
          have: const {},
        );
        if (state == SquareState.none) continue;
        expect(d.write['2026-08-20'], state, reason: 'state $state');
      }
    });
  });

  group('the window is a boundary, not a suggestion', () {
    test('days older than the window are never touched', () {
      // The repair only READ the window. Rewriting anything outside it would
      // be acting on data it never looked at.
      final d = diff(
        want: const {'2026-08-20': SquareState.complete},
        have: const {
          '2026-01-04': SquareState.complete,
          '2025-11-30': SquareState.failed,
        },
      );
      expect(d.remove, isEmpty,
          reason: 'old history is outside the window and stays as it is');
      expect(d.write, {'2026-08-20': SquareState.complete});
    });

    test('a day newer than the window is not touched either', () {
      // Today is deliberately excluded by the caller, because the live
      // writers own it and re-deriving could resurrect an un-done day.
      final d = diff(
        want: const {'2026-08-21': SquareState.complete},
        have: const {},
      );
      expect(d.isEmpty, isTrue,
          reason: 'today is not in the window, so the repair ignores it');
    });

    test('an empty window is a no-op whatever the two sides hold', () {
      final d = diff(
        keys: const [],
        want: const {'2026-08-20': SquareState.complete},
        have: const {'2026-08-19': SquareState.failed},
      );
      expect(d.isEmpty, isTrue);
    });
  });

  group('the default window', () {
    test('covers two weeks of settled days', () {
      expect(kMirrorRepairWindowDays, 14);
    });
  });
}
