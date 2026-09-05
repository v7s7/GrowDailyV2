// What the bottom bar's badges mean, pinned as unit tests.
//
// Each badge is a promise ("this needs you") and each one has a rule that
// could quietly drift from the screen it points at. The Tasks count is
// computed by the Matrix screen's own Today-lens helper, so the badge and
// the board a tap lands on cannot disagree; the Rooms count and the Night
// Review dot have their rules here, beside the hint's timing.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/core/providers/nav_bar_hint_provider.dart';
import 'package:grow_daily_v2/features/matrix/models/matrix_task.dart';
import 'package:grow_daily_v2/features/matrix/screens/matrix_screen.dart';
import 'package:grow_daily_v2/features/night_review/notifiers/night_review_notifier.dart';
import 'package:grow_daily_v2/shared/providers/nav_badges_provider.dart';

void main() {
  group('Tasks badge', () {
    final now = DateTime(2026, 9, 6, 14);
    MatrixTask task(
      String id, {
      required DateTime createdAt,
      bool isDone = false,
      List<DateTime> reminders = const [],
    }) =>
        MatrixTask(
          id: id,
          title: id,
          quadrant: MatrixQuadrant.doFirst,
          isDone: isDone,
          createdAt: createdAt,
          reminderAts: reminders,
          order: 0,
        );

    test('counts only open tasks anchored to today', () {
      final tasks = [
        task('today', createdAt: now.subtract(const Duration(hours: 3))),
        task('done', createdAt: now, isDone: true),
        task('yesterday', createdAt: now.subtract(const Duration(days: 1))),
        task('next week',
            createdAt: now,
            reminders: [now.add(const Duration(days: 7))]),
      ];
      // Yesterday's is carried over (the chip's job, not Today's) and next
      // week's is upcoming; neither belongs on a badge that says "today".
      expect(matrixOpenTodayCount(tasks, now), 1);
    });

    test('an empty board has no badge', () {
      expect(matrixOpenTodayCount(const [], now), 0);
    });
  });

  group('Rooms badge', () {
    test('counts live rooms whose day is not finished', () {
      expect(
        roomsWaitingToday([
          (isLive: true, todayCredit: 0.0),
          (isLive: true, todayCredit: 0.5),
          (isLive: true, todayCredit: 1.0),
          (isLive: false, todayCredit: 0.0),
        ]),
        2,
        reason: 'the finished room and the room that is not live do not '
            'need anyone',
      );
    });
  });

  group('Night Review dot', () {
    const open = NightReviewState(isLoading: false);
    test('only in the evening window, only until saved', () {
      expect(nightReviewPending(open, DateTime(2026, 9, 6, 21)), isTrue);
      expect(nightReviewPending(open, DateTime(2026, 9, 6, 14)), isFalse);
      expect(
          nightReviewPending(
              const NightReviewState(isLoading: false, saved: true),
              DateTime(2026, 9, 6, 21)),
          isFalse);
      // Still loading is not "pending": a dot that flashes on every cold
      // start while the entry loads would be noise.
      expect(nightReviewPending(const NightReviewState(), DateTime(2026, 9, 6, 21)),
          isFalse);
    });
  });

  group('the one-time hint', () {
    bool show({
      bool premium = true,
      bool seen = false,
      bool customised = false,
      bool lessonActive = false,
      int completions = kNavBarHintAfterCompletions,
    }) =>
        shouldShowNavBarHint(
          premium: premium,
          seen: seen,
          customised: customised,
          lessonActive: lessonActive,
          completions: completions,
        );

    test('shows once, to Premium, a few days in, with nothing else up', () {
      expect(show(), isTrue);
      expect(show(premium: false), isFalse, reason: 'points at a paid feature');
      expect(show(seen: true), isFalse, reason: 'once');
      expect(show(customised: true), isFalse, reason: 'they already found it');
      expect(show(lessonActive: true), isFalse, reason: 'one spotlight at a time');
      expect(show(completions: kNavBarHintAfterCompletions - 1), isFalse,
          reason: 'not on day one');
    });
  });
}
