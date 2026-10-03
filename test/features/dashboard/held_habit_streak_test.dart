// Ticking today before yesterday, while yesterday is still open.
//
// Between midnight and kDayCutoffHour both days can be marked, and the
// natural order at 05:00 is today first: the Fajr habit gets done, last
// night's habit gets remembered a few minutes later. The tap on today measured
// a gap of two days and restarted the habit's streak at 1, which is fair for
// the moment. The tap on yesterday then measured a gap of MINUS one, went
// through the same restart, and the run that had been interrupted was gone:
// a 5-day streak with every day done read 1, for good.
//
// The pure rules are pinned first, then the whole round trip against real
// storage, guest (Hive) and signed in (a fake Firestore through the
// notifier's `firestore:` seam), at a fixed 05:00 so the grace window is
// open whatever time the suite runs.
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/auth/notifiers/auth_notifier.dart';
import 'package:grow_daily_v2/features/dashboard/models/held_habit_streak.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';
import 'package:grow_daily_v2/features/habits/models/habit_schedule.dart';

import '../../helpers/never_bonus_random.dart';
import '../../helpers/wait_until.dart';

DateTime _d(int y, int m, int d) => DateTime(y, m, d);

int _daily(DateTime from, DateTime to) =>
    scheduledGap(last: from, day: to, weekdays: const {});

void main() {
  group('heldStreakForOpenYesterday', () {
    // Thursday 2026-10-01; yesterday Wednesday 09-30; last done Tuesday 09-29.
    final today = _d(2026, 10, 1);

    test('keeps the run when yesterday is the only day missing and open', () {
      final held = heldStreakForOpenYesterday(
        day: today,
        last: _d(2026, 9, 29),
        previousStreak: 12,
        yesterdayOpen: true,
        gapBetween: _daily,
      );
      expect(
        held,
        const HeldHabitStreak(
          streak: 12,
          lastKey: '2026-09-29',
          cutOnKey: '2026-10-01',
        ),
      );
    });

    test('keeps nothing once yesterday has closed', () {
      expect(
        heldStreakForOpenYesterday(
          day: today,
          last: _d(2026, 9, 29),
          previousStreak: 12,
          yesterdayOpen: false,
          gapBetween: _daily,
        ),
        isNull,
      );
    });

    test('keeps nothing when more than yesterday is missing', () {
      // Monday is missed as well: yesterday alone cannot rejoin anything.
      expect(
        heldStreakForOpenYesterday(
          day: today,
          last: _d(2026, 9, 28),
          previousStreak: 12,
          yesterdayOpen: true,
          gapBetween: _daily,
        ),
        isNull,
      );
    });

    test('keeps nothing when the tap continues the streak anyway', () {
      expect(
        heldStreakForOpenYesterday(
          day: today,
          last: _d(2026, 9, 30),
          previousStreak: 12,
          yesterdayOpen: true,
          gapBetween: _daily,
        ),
        isNull,
      );
    });

    test('keeps nothing for a habit never done or with no streak', () {
      expect(
        heldStreakForOpenYesterday(
          day: today,
          last: null,
          previousStreak: 0,
          yesterdayOpen: true,
          gapBetween: _daily,
        ),
        isNull,
      );
      expect(
        heldStreakForOpenYesterday(
          day: today,
          last: _d(2026, 9, 29),
          previousStreak: 0,
          yesterdayOpen: true,
          gapBetween: _daily,
        ),
        isNull,
      );
    });

    test("measures on the habit's own days", () {
      // A Sunday/Tuesday/Wednesday habit (weekdays 7, 2, 3), last done
      // Tuesday 09-29 and done again today, Thursday 10-01 (a completion on
      // any day counts). Yesterday, Wednesday, is one of its days and the
      // only one missing, so the run is held.
      int gap(DateTime from, DateTime to) =>
          scheduledGap(last: from, day: to, weekdays: const {7, 2, 3});
      expect(
        heldStreakForOpenYesterday(
          day: today,
          last: _d(2026, 9, 29),
          previousStreak: 4,
          yesterdayOpen: true,
          gapBetween: gap,
        ),
        isNotNull,
      );
      // A Monday/Thursday habit done Monday: Tuesday and Wednesday are rest
      // days, so Thursday continues the streak and nothing is held.
      int monThu(DateTime from, DateTime to) =>
          scheduledGap(last: from, day: to, weekdays: const {1, 4});
      expect(
        heldStreakForOpenYesterday(
          day: today,
          last: _d(2026, 9, 28),
          previousStreak: 4,
          yesterdayOpen: true,
          gapBetween: monThu,
        ),
        isNull,
      );
    });
  });

  group('habitStreakForEarlierDay', () {
    final today = _d(2026, 10, 1);
    final yesterday = _d(2026, 9, 30);
    const held = HeldHabitStreak(
      streak: 12,
      lastKey: '2026-09-29',
      cutOnKey: '2026-10-01',
    );

    test('yesterday joins the held run and today: 12 + 1 + 1', () {
      final r = habitStreakForEarlierDay(
        day: yesterday,
        last: today,
        currentStreak: 1,
        held: held,
        gapBetween: _daily,
      );
      expect(r.streak, 14);
      expect(r.joinedHeld, isTrue);
      expect(r.alreadyPaidThrough, 12);
    });

    test('with no held run yesterday and today still make two, never one', () {
      final r = habitStreakForEarlierDay(
        day: yesterday,
        last: today,
        currentStreak: 1,
        held: null,
        gapBetween: _daily,
      );
      expect(r.streak, 2);
      expect(r.joinedHeld, isFalse);
    });

    test('a held run for another day is not joined', () {
      const stale = HeldHabitStreak(
        streak: 12,
        lastKey: '2026-09-28',
        cutOnKey: '2026-09-30',
      );
      final r = habitStreakForEarlierDay(
        day: yesterday,
        last: today,
        currentStreak: 1,
        held: stale,
        gapBetween: _daily,
      );
      expect(r.streak, 2);
      expect(r.joinedHeld, isFalse);
    });

    test('a held run that ended before the day missing is not joined', () {
      // The held run ended on 09-28 but was cut on today: 09-29 is missing
      // as well, so yesterday does not reach it.
      const gapped = HeldHabitStreak(
        streak: 12,
        lastKey: '2026-09-28',
        cutOnKey: '2026-10-01',
      );
      final r = habitStreakForEarlierDay(
        day: yesterday,
        last: today,
        currentStreak: 1,
        held: gapped,
        gapBetween: _daily,
      );
      expect(r.streak, 2);
    });

    test('a longer run ending today is left exactly as it is', () {
      // Yesterday was a rest day the run already stepped over, or is already
      // inside it: marking it can only ever lengthen, never shorten.
      final r = habitStreakForEarlierDay(
        day: yesterday,
        last: today,
        currentStreak: 9,
        held: held,
        gapBetween: _daily,
      );
      expect(r.streak, 9);
      expect(r.joinedHeld, isFalse);
      expect(r.alreadyPaidThrough, 9);
    });
  });

  group('habitMilestoneCrossed', () {
    test('a join that steps over a threshold still pays it', () {
      // 6 + 1 + 1 = 8: an ordinary tap would have landed on 7 and paid it.
      expect(habitMilestoneCrossed(from: 6, to: 8),
          (milestone: 7, bonusXp: 25));
    });

    test('a join that lands on one pays it', () {
      expect(habitMilestoneCrossed(from: 5, to: 7),
          (milestone: 7, bonusXp: 25));
    });

    test('nothing already passed is paid again', () {
      expect(habitMilestoneCrossed(from: 7, to: 9), isNull);
      expect(habitMilestoneCrossed(from: 1, to: 2), isNull);
    });
  });

  group('HeldHabitStreak storage', () {
    test('round trips and refuses junk', () {
      const held = HeldHabitStreak(
        streak: 5,
        lastKey: '2026-09-29',
        cutOnKey: '2026-10-01',
      );
      expect(HeldHabitStreak.fromJson(held.toJson()), held);
      expect(HeldHabitStreak.fromJson(null), isNull);
      expect(HeldHabitStreak.fromJson(7), isNull);
      expect(
        HeldHabitStreak.fromJson({'streak': 0, 'last': '2026-09-29',
            'cutOn': '2026-10-01'}),
        isNull,
      );
      expect(
        HeldHabitStreak.fromJson({'streak': 5, 'last': 'nope',
            'cutOn': '2026-10-01'}),
        isNull,
      );
    });
  });

  // ── Against real storage ────────────────────────────────────────────

  /// 05:00 on today's real date: inside the grace window whatever time the
  /// suite runs. The DATE stays real because the guest store keys today's
  /// day document off the real clock (see grace_window_completion_test).
  DateTime fiveAm() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 5);
  }

  DateTime elevenAm() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 11);
  }

  final today = DateTime.now().effectiveDay.startOfDay;
  final yesterday = dayPlus(today, -1);
  final twoDaysAgo = dayPlus(today, -2);

  group('guest, end to end', () {
    late Directory tmp;
    final containers = <ProviderContainer>[];

    Future<DashboardNotifier> launch({DateTime Function()? clock}) async {
      final container = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        dashboardProvider.overrideWith(
          (ref) => DashboardNotifier(
            null,
            random: NeverBonusRandom(),
            clock: clock ?? fiveAm,
          ),
        ),
      ]);
      containers.add(container);
      await container.read(authStateProvider.future);
      container.read(dashboardProvider);
      await waitUntil(
        () => !container.read(dashboardProvider).isLoading,
        describe: 'the dashboard to finish its initial load',
      );
      final notifier = container.read(dashboardProvider.notifier);
      await notifier.ready;
      return notifier;
    }

    Future<void> seedFiveDayStreak() => LocalStoreService.putSettingsMap(
          LocalStoreService.guestDashboardKey,
          {
            'habitStreakCounts': {'h1': 5},
            'habitLongestStreaks': {'h1': 5},
            'habitTotalCompletions': {'h1': 5},
            'habitLastCompletedDate': {'h1': twoDaysAgo.toDateKey()},
          },
        );

    Future<bool> mark(DashboardNotifier n, {DateTime? day}) => n.completeHabit(
          habitId: 'h1',
          xpReward: 10,
          goldReward: 5,
          frequencyTarget: 1,
          allHabitsDoneAfter: false,
          day: day,
        );

    Future<void> unmark(DashboardNotifier n, {DateTime? day}) =>
        n.uncompleteHabit(
          habitId: 'h1',
          xpReward: 10,
          goldReward: 5,
          day: day,
        );

    setUp(() async {
      NotificationService.instance.celebrationsEnabled = false;
      tmp = await Directory.systemTemp.createTemp('held_streak_');
      Hive.init(tmp.path);
    });

    tearDown(() async {
      for (final c in containers) {
        c.dispose();
      }
      containers.clear();
      await LocalStoreService.settleDailyWrites();
      await Hive.deleteFromDisk();
      await tmp.delete(recursive: true);
    });

    test('today then yesterday: the streak is 7, not 1', () async {
      await seedFiveDayStreak();
      final n = await launch();

      expect(await mark(n), isTrue);
      expect(n.state.habitStreakCounts['h1'], 1,
          reason: 'yesterday is not done yet, so this much is fair');
      expect(n.state.heldHabitStreaks['h1']?.streak, 5);

      expect(await mark(n, day: yesterday), isTrue);
      expect(n.state.habitStreakCounts['h1'], 7,
          reason: 'five days, then yesterday, then today');
      expect(n.state.habitLongestStreaks['h1'], 7);
      expect(n.state.habitLastCompletedDate['h1'], today.toDateKey(),
          reason: 'marking yesterday never drags the last day back');
      expect(n.state.heldHabitStreaks.containsKey('h1'), isFalse,
          reason: 'spent by the join');
      expect(n.state.habitMilestoneCelebration?.milestone, 7,
          reason: 'the join reached 7 and pays it like a landing would');

      // And it is what the store holds.
      final after = await launch();
      expect(after.state.habitStreakCounts['h1'], 7);
      expect(after.state.heldHabitStreaks.containsKey('h1'), isFalse);
    });

    test('the held run survives a restart between the two taps', () async {
      await seedFiveDayStreak();
      final first = await launch();
      await mark(first);

      final second = await launch();
      expect(second.state.heldHabitStreaks['h1']?.streak, 5);
      await mark(second, day: yesterday);
      expect(second.state.habitStreakCounts['h1'], 7);
    });

    test('undoing today puts the five days back, same session', () async {
      await seedFiveDayStreak();
      final n = await launch();
      await mark(n);
      await unmark(n);

      expect(n.state.habitStreakCounts['h1'], 5);
      expect(n.state.habitLastCompletedDate['h1'], twoDaysAgo.toDateKey());
      expect(n.state.heldHabitStreaks.containsKey('h1'), isFalse);

      // Then the natural order: yesterday, today.
      await mark(n, day: yesterday);
      await mark(n);
      expect(n.state.habitStreakCounts['h1'], 7);
    });

    test('undoing today after a restart puts the five days back too',
        () async {
      await seedFiveDayStreak();
      final first = await launch();
      await mark(first);

      // No same-session snapshot now; the held run is the record.
      final second = await launch();
      await unmark(second);
      expect(second.state.habitStreakCounts['h1'], 5);
      expect(second.state.habitLastCompletedDate['h1'], twoDaysAgo.toDateKey());
      expect(second.state.heldHabitStreaks.containsKey('h1'), isFalse);

      // Yesterday alone now continues the old run, and does not claim a
      // today that was taken back.
      await mark(second, day: yesterday);
      expect(second.state.habitStreakCounts['h1'], 6);
      expect(second.state.habitLastCompletedDate['h1'], yesterday.toDateKey());
    });

    test('undoing yesterday after the join, then redoing it', () async {
      await seedFiveDayStreak();
      final n = await launch();
      await mark(n);
      await mark(n, day: yesterday);
      expect(n.state.habitStreakCounts['h1'], 7);

      await unmark(n, day: yesterday);
      expect(n.state.habitStreakCounts['h1'], 1);
      expect(n.state.heldHabitStreaks['h1']?.streak, 5,
          reason: 'the held run comes back with the undo');

      await mark(n, day: yesterday);
      expect(n.state.habitStreakCounts['h1'], 7);
    });

    test('after 10:00 nothing is held: yesterday has closed', () async {
      await seedFiveDayStreak();
      final n = await launch(clock: elevenAm);
      await mark(n);
      expect(n.state.habitStreakCounts['h1'], 1);
      expect(n.state.heldHabitStreaks.containsKey('h1'), isFalse);
      expect(await mark(n, day: yesterday), isFalse,
          reason: 'a closed day cannot be bought');
    });
  });

  group('signed in, end to end', () {
    const uid = 'held-streak-user';
    late FakeFirebaseFirestore db;
    final containers = <ProviderContainer>[];

    DocumentReference<Map<String, dynamic>> userDoc() =>
        db.collection('users').doc(uid);

    setUp(() {
      NotificationService.instance.celebrationsEnabled = false;
      db = FakeFirebaseFirestore();
    });

    tearDown(() {
      for (final c in containers) {
        c.dispose();
      }
      containers.clear();
    });

    Future<DashboardNotifier> launch() async {
      final c = ProviderContainer(overrides: [
        dashboardProvider.overrideWith(
          (ref) => DashboardNotifier(
            uid,
            random: NeverBonusRandom(),
            clock: fiveAm,
            firestore: db,
          ),
        ),
      ]);
      containers.add(c);
      final n = c.read(dashboardProvider.notifier);
      await n.ready;
      expect(n.state.loadFailed, isFalse);
      return n;
    }

    Future<Map<String, dynamic>> stored() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return (await userDoc().get()).data()!;
    }

    Future<bool> mark(DashboardNotifier n, {DateTime? day}) => n.completeHabit(
          habitId: 'h1',
          xpReward: 10,
          goldReward: 5,
          frequencyTarget: 1,
          allHabitsDoneAfter: false,
          day: day,
        );

    test('the held run is written, survives a reload, and is deleted when '
        'yesterday joins it', () async {
      await userDoc().set({
        'level': 3,
        'currentLevelXp': 0,
        'cumulativeXp': 300,
        'gold': 0,
        'levelGrantPaidThrough': 3,
        'habitStreakCounts': {'h1': 5, 'h2': 3},
        'habitLongestStreaks': {'h1': 5, 'h2': 3},
        'habitTotalCompletions': {'h1': 5, 'h2': 3},
        'habitLastCompletedDate': {
          'h1': twoDaysAgo.toDateKey(),
          'h2': yesterday.toDateKey(),
        },
      });

      final first = await launch();
      await mark(first);
      final afterToday = await stored();
      expect(
        (afterToday['heldHabitStreaks'] as Map)['h1'],
        {
          'streak': 5,
          'last': twoDaysAgo.toDateKey(),
          'cutOn': today.toDateKey(),
        },
      );
      expect((afterToday['habitStreakCounts'] as Map)['h1'], 1);

      final second = await launch();
      expect(second.state.heldHabitStreaks['h1']?.streak, 5);
      await mark(second, day: yesterday);

      final afterYesterday = await stored();
      expect((afterYesterday['habitStreakCounts'] as Map)['h1'], 7);
      expect((afterYesterday['habitStreakCounts'] as Map)['h2'], 3,
          reason: 'another habit is never touched');
      expect(
        (afterYesterday['heldHabitStreaks'] as Map?)?.containsKey('h1') ??
            false,
        isFalse,
        reason: 'deleted by key, not left behind by a merge',
      );
    });
  });
}
