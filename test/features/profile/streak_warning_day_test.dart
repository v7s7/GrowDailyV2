// The streak-at-risk banner warns about ONE day, and after midnight that day
// is yesterday.
//
// Reported live (Aziz, 2026-09-22): he finished Monday at 00:06, marking its
// last habit in the grace window, and Profile still said «سلسلة الـ2 يومًا على
// المحك». His account had earned the point (lastActiveDay 2026-09-21). The
// banner was asking DashboardState.streakEarnedToday, and since the day rolls
// at midnight "today" was Tuesday, a day with nothing done yet because it had
// only just begun.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/profile/screens/profile_screen.dart'
    show streakAtRiskBannerShows;

DashboardState _dash({
  int streak = 2,
  DateTime? lastStreakDay,
  bool streakEarnedToday = false,
}) =>
    DashboardState(
      level: 1,
      currentLevelXp: 0,
      cumulativeXp: 0,
      gold: 0,
      streak: streak,
      completions: const {},
      lastStreakDay: lastStreakDay,
      streakEarnedToday: streakEarnedToday,
    );

void main() {
  final monday = DateTime(2026, 9, 21);
  final tuesday = DateTime(2026, 9, 22);
  final sunday = DateTime(2026, 9, 20);
  bool asksSomething(DateTime _) => true;

  group('streakNudgeDay, the day the evening nudge is about', () {
    test('today from 18:00 to midnight', () {
      expect(DateTime(2026, 9, 21, 18).streakNudgeDay, monday);
      expect(DateTime(2026, 9, 21, 23, 59).streakNudgeDay, monday);
    });

    test('yesterday from midnight until the nudge cutoff', () {
      expect(DateTime(2026, 9, 22).streakNudgeDay, monday);
      expect(DateTime(2026, 9, 22, 0, 6).streakNudgeDay, monday,
          reason: 'the minute Aziz finished Monday');
      expect(
          DateTime(2026, 9, 22, kEveningNudgeCutoffHour - 1, 59).streakNudgeDay,
          monday);
      expect(DateTime(2026, 10, 1, 0, 30).streakNudgeDay, DateTime(2026, 9, 30),
          reason: 'across a month boundary');
    });

    test('nothing outside the window', () {
      expect(DateTime(2026, 9, 22, kEveningNudgeCutoffHour).streakNudgeDay,
          isNull);
      expect(DateTime(2026, 9, 22, 12).streakNudgeDay, isNull);
      expect(DateTime(2026, 9, 22, 17, 59).streakNudgeDay, isNull);
    });
  });

  group('streakAtRiskBannerShows', () {
    test('after midnight, a finished yesterday is not on the line', () {
      // Aziz's account at 00:06: Monday earned in its grace window, Tuesday
      // not started, streak 2.
      expect(
        streakAtRiskBannerShows(
          dash: _dash(lastStreakDay: monday),
          now: DateTime(2026, 9, 22, 0, 6),
          dayAsksForHabits: asksSomething,
        ),
        isFalse,
      );
    });

    test('after midnight, an unfinished yesterday still is', () {
      // The case the after-midnight window exists for: yesterday is payable
      // until 10:00, and the last point was the day before.
      expect(
        streakAtRiskBannerShows(
          dash: _dash(lastStreakDay: sunday),
          now: DateTime(2026, 9, 22, 1),
          dayAsksForHabits: asksSomething,
        ),
        isTrue,
      );
    });

    test('after midnight it judges yesterday, not today', () {
      final asked = <DateTime>[];
      streakAtRiskBannerShows(
        dash: _dash(lastStreakDay: sunday),
        now: DateTime(2026, 9, 22, 1),
        dayAsksForHabits: (day) {
          asked.add(day);
          return true;
        },
      );
      expect(asked, [monday]);
    });

    test('in the evening, today until its point is earned', () {
      expect(
        streakAtRiskBannerShows(
          dash: _dash(lastStreakDay: sunday),
          now: DateTime(2026, 9, 21, 21),
          dayAsksForHabits: asksSomething,
        ),
        isTrue,
      );
      expect(
        streakAtRiskBannerShows(
          dash: _dash(lastStreakDay: monday, streakEarnedToday: true),
          now: DateTime(2026, 9, 21, 21),
          dayAsksForHabits: asksSomething,
        ),
        isFalse,
        reason: 'the moment 80% is reached',
      );
    });

    test("today's own flag is enough in the evening", () {
      // A state whose marker was never loaded (an older guest store, say)
      // still hides the banner once today has earned its point.
      expect(
        streakAtRiskBannerShows(
          dash: _dash(streakEarnedToday: true),
          now: DateTime(2026, 9, 21, 21),
          dayAsksForHabits: asksSomething,
        ),
        isFalse,
      );
    });

    test('a new day already earned after midnight is safe too', () {
      expect(
        streakAtRiskBannerShows(
          dash: _dash(lastStreakDay: tuesday, streakEarnedToday: true),
          now: DateTime(2026, 9, 22, 2),
          dayAsksForHabits: asksSomething,
        ),
        isFalse,
      );
    });

    test('a day that asked for no habit cannot cost the streak', () {
      expect(
        streakAtRiskBannerShows(
          dash: _dash(lastStreakDay: sunday),
          now: DateTime(2026, 9, 21, 21),
          dayAsksForHabits: (_) => false,
        ),
        isFalse,
      );
    });

    test('no live streak, or outside the window, nothing to say', () {
      expect(
        streakAtRiskBannerShows(
          dash: _dash(streak: 0),
          now: DateTime(2026, 9, 21, 21),
          dayAsksForHabits: asksSomething,
        ),
        isFalse,
      );
      expect(
        streakAtRiskBannerShows(
          dash: _dash(lastStreakDay: sunday),
          now: DateTime(2026, 9, 21, 12),
          dayAsksForHabits: asksSomething,
        ),
        isFalse,
      );
    });
  });

  group('streakMarkerReached', () {
    test('reached on the marker day and every day before it', () {
      final dash = _dash(lastStreakDay: monday);
      expect(dash.streakMarkerReached(monday), isTrue);
      expect(dash.streakMarkerReached(sunday), isTrue);
      expect(dash.streakMarkerReached(tuesday), isFalse);
      expect(dash.streakMarkerReached(DateTime(2026, 9, 21, 23, 30)), isTrue,
          reason: 'a time of day on the marker day is still that day');
    });

    test('never reached before the first point', () {
      expect(_dash().streakMarkerReached(monday), isFalse);
    });
  });
}
