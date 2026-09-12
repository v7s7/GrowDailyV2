// A weekly quota carries its share of every day of a closed week.
//
// weeklyQuotaScheduledDays answers a BINARY question: which days of the week
// is a "4x a week, any days" habit answerable for. On a plan that mixes it
// with daily habits that reads wrong, and Aziz said so on 2026-09-12 after a
// week of 1 of 4 sessions scored 6.0 of 7: the quota habit was counted only
// on the days it could still be blamed for and excused entirely on the rest,
// so the two daily habits beside it carried the week to near-full.
//
// The ruling: per day of a CLOSED week, the habit demands target/D and earns
// sessions/D, D being the days it was actually in the plan for. Measured over
// every room before it shipped, the whole live effect was four members in two
// rooms: ELQVF8 Aziz 82.6 -> 79.0, Hoor 69.7 -> 69.2, and BKWVN9 exactly
// neutral, its weeks moving +1.2, +2.0 and -3.2 and cancelling.
//
// This is the arithmetic on its own. It lives as a top-level function because
// the first version of it sat inline in the grader's pass 1, where no test
// could reach it, and an unreachable rule is one that drifts from the surface
// drawing it.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

void main() {
  group('a met quota still reads as a full week', () {
    test('4 of 4 over 7 days demands and earns the same 4/7', () {
      final s = weeklyShareFor(target: 4, presentDays: 7, sessions: 4);
      expect(s.demand, closeTo(4 / 7, 1e-12));
      expect(s.credit, closeTo(4 / 7, 1e-12));
      // The property weeklyQuotaScheduledDays' own doc exists to protect: the
      // same commitment written as four named weekdays scores 100%, and this
      // must not quietly go back to scoring it 57%.
      expect(s.credit / s.demand, closeTo(1.0, 1e-12));
    });

    test('doing MORE than the target banks nothing extra', () {
      // An extra session is not a surplus to spend on the days that went
      // unused; it cannot push a day above full.
      final s = weeklyShareFor(target: 4, presentDays: 7, sessions: 6);
      expect(s.credit, closeTo(4 / 7, 1e-12));
      expect(s.credit, s.demand);
    });
  });

  group('a short week is where the ruling bites', () {
    test('1 of 4 demands 4/7 and earns 1/7, every day of the week', () {
      final s = weeklyShareFor(target: 4, presentDays: 7, sessions: 1);
      expect(s.demand, closeTo(4 / 7, 1e-12));
      expect(s.credit, closeTo(1 / 7, 1e-12));
      // A quarter of the habit, on all seven days, instead of one whole habit
      // on some days and nothing at all on the others.
      expect(s.credit / s.demand, closeTo(0.25, 1e-12));
    });

    test('a جزئي session is half a session, as it is everywhere else', () {
      final s = weeklyShareFor(target: 4, presentDays: 7, sessions: 1.5);
      expect(s.credit, closeTo(1.5 / 7, 1e-12));
    });

    test('a week with nothing done earns nothing but still demands', () {
      final s = weeklyShareFor(target: 4, presentDays: 7, sessions: 0);
      expect(s.demand, closeTo(4 / 7, 1e-12));
      expect(s.credit, 0);
    });
  });

  group('the clamps', () {
    test('target cannot exceed the days the week actually had', () {
      // A room's short first or last week, and the case that makes ELQVF8's
      // 1st to 4th credit-neutral: target 4 over 4 present days is a whole
      // habit every day, exactly what the counts already said.
      final s = weeklyShareFor(target: 4, presentDays: 4, sessions: 1.5);
      expect(s.demand, 1.0);
      expect(s.credit, closeTo(1.5 / 4, 1e-12));
    });

    test('a target of zero still asks for one session', () {
      final s = weeklyShareFor(target: 0, presentDays: 7, sessions: 0);
      expect(s.demand, closeTo(1 / 7, 1e-12));
    });

    test('a week with no present days is worth nothing at all', () {
      // Never a division by zero: a slot that joined after the week ended.
      final s = weeklyShareFor(target: 4, presentDays: 0, sessions: 0);
      expect(s.demand, 0);
      expect(s.credit, 0);
    });

    test('negative sessions cannot happen, and cannot pay if they do', () {
      final s = weeklyShareFor(target: 4, presentDays: 7, sessions: -3);
      expect(s.credit, 0);
    });
  });

  group('what the week totals to', () {
    test('demand over the whole week is exactly the target', () {
      for (final target in [1, 2, 4, 7]) {
        final s = weeklyShareFor(
          target: target,
          presentDays: 7,
          sessions: 0,
        );
        expect(s.demand * 7, closeTo(target.toDouble(), 1e-12),
            reason: 'target $target');
      }
    });

    test('credit over the whole week is exactly what was banked', () {
      for (final sessions in [0.0, 0.5, 1.0, 2.5, 4.0]) {
        final s = weeklyShareFor(
          target: 4,
          presentDays: 7,
          sessions: sessions,
        );
        expect(s.credit * 7, closeTo(sessions, 1e-12),
            reason: 'sessions $sessions');
      }
    });
  });

  // The anti-backdating ceiling, in weighted units. It exists because the
  // quota's share is derived from the whole WEEK's sessions, so a square
  // back-painted onto one day lifts the share on days that square is not even
  // on. With kWeeklyShareEnabled off the grader's write is gated, so this rule
  // is unreachable anywhere except from here.
  group('a settled day may be lowered, never raised', () {
    test('an open day is never clamped', () {
      expect(
        clampedWeightedCredit(
          creditWeight: 4 / 7,
          demandWeight: 4 / 7,
          held: false,
          alreadyWeighted: 0,
          storedRatio: 0,
          stoodDown: false,
        ),
        closeTo(4 / 7, 1e-12),
      );
    });

    test('a recorded weight is the ceiling, compared like for like', () {
      // The 2026-09-11 bug in one line: clamping the weighted number against
      // the whole-habit fallback stripped the quota's share from every held
      // day, and on Aziz's 2026-09-10 that one day was the whole gap between
      // the model's 8.69 of 11 and the app's 8.6.
      expect(
        clampedWeightedCredit(
          creditWeight: 2.5,
          demandWeight: 2 + 4 / 7,
          held: true,
          alreadyWeighted: 2 + 2 / 7,
          storedRatio: 1,
          stoodDown: false,
        ),
        closeTo(2 + 2 / 7, 1e-12),
      );
    });

    test('un-ticking a held day still lowers it', () {
      // The correcting direction has to keep working, or a day wrongly
      // claimed could never be handed back.
      expect(
        clampedWeightedCredit(
          creditWeight: 1.0,
          demandWeight: 2 + 4 / 7,
          held: true,
          alreadyWeighted: 2 + 2 / 7,
          storedRatio: 1,
          stoodDown: false,
        ),
        closeTo(1.0, 1e-12),
      );
    });

    test('the FIRST pass cannot pay for a back-painted session', () {
      // y.almehza101, YW68B9, 2026-08-22: a green تمرين square painted after
      // that day had closed, in a room whose only habit is a 4x quota. On the
      // first weighted pass nothing is stored, so the clamp above is inert
      // and this ceiling is the only thing between that square and the week's
      // share. The room paid 0 for the day, so 0 is the ceiling.
      expect(
        clampedWeightedCredit(
          creditWeight: 2 / 7,
          demandWeight: 4 / 7,
          held: true,
          alreadyWeighted: null,
          storedRatio: 0,
          stoodDown: false,
        ),
        0,
      );
    });

    test('...but the first pass may still LOWER a day', () {
      // The point of the whole ruling, and why the ceiling is a ratio rather
      // than a freeze: a day a met quota excused reads 1.0 today, and the
      // weighting is allowed to bring it down to what the week actually
      // banked. Without this, switching the flag on would change nothing at
      // all on settled days.
      expect(
        clampedWeightedCredit(
          creditWeight: 1 / 7,
          demandWeight: 4 / 7,
          held: true,
          alreadyWeighted: null,
          storedRatio: 1,
          stoodDown: false,
        ),
        closeTo(1 / 7, 1e-12),
      );
    });

    test('a stood-down day is left alone', () {
      // creditFor returns 0 for a paused day, and that 0 means "not scored",
      // not "earned nothing". As a ceiling it would write a weight claiming
      // the day asked for something and paid nothing.
      expect(
        clampedWeightedCredit(
          creditWeight: 4 / 7,
          demandWeight: 4 / 7,
          held: true,
          alreadyWeighted: null,
          storedRatio: 0,
          stoodDown: true,
        ),
        closeTo(4 / 7, 1e-12),
      );
    });

    test('a day that demands nothing is left alone', () {
      expect(
        clampedWeightedCredit(
          creditWeight: 0.5,
          demandWeight: 0,
          held: true,
          alreadyWeighted: null,
          storedRatio: 0,
          stoodDown: false,
        ),
        0.5,
      );
    });
  });
}
