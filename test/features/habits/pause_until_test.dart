// Booked returns: the opt-in half of pausing.
//
// Pausing itself is unchanged, one tap and manual. This covers the date a
// person can attach to it, which is stored locally (see
// LocalStoreService.habitResumeDatesKey for why it is not a field on the
// habit) and acted on when the app next has a loaded habit list.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:grow_daily_v2/core/constants/game_constants.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/local_store_service.dart';
import 'package:grow_daily_v2/features/habits/notifiers/habit_resume_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pause_until_test_');
    Hive.init(tmp.path);
    await Hive.openBox<dynamic>(GameConstants.boxSettings);
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  group('presets', () {
    // Anchored to a fixed date so these never drift with the wall clock.
    final from = DateTime(2026, 8, 25, 23, 40);

    test('a week lands seven days out, at the start of that day', () {
      final at = ResumePreset.week.dateFrom(from);
      expect(at.day, 1);
      expect(at.month, 9);
      // Picked at 23:40, but "أسبوع" does not mean "in a week at 23:40" — the
      // time is dropped. "Start of that day" is the day CUTOFF (6am), not
      // calendar midnight: a 00:00 booking belongs to the previous effective
      // day (see ResumePreset.dateFrom), which would let the habit come back a
      // day early for anyone opening the app in the small hours.
      expect(at.hour, kDayCutoffHour);
      expect(at.minute, 0);
    });

    test('two weeks lands fourteen days out', () {
      final at = ResumePreset.twoWeeks.dateFrom(from);
      expect(at.difference(from.effectiveDay).inDays, 14);
    });

    test('a month is a calendar month, not thirty days', () {
      // Noon, not midnight: presets resolve against effectiveDay, and this
      // app's day starts at kDayCutoffHour (6am), so 31 January at 00:00 is
      // still the 30th here. Using midnight would quietly test the cutoff
      // instead of the month arithmetic this test is about.
      final at = ResumePreset.month.dateFrom(DateTime(2026, 1, 31, 12));
      // "A month" from 31 January is understood as the end of February.
      // February 2026 has 28 days, so DateTime normalises the overflow
      // rather than producing an invalid 31 February.
      expect(at.month, 3);
      expect(at.day, 3);
    });
  });

  group('the schedule', () {
    test('a booking survives being written and read back', () async {
      final schedule = HabitResumeSchedule();
      final at = DateTime(2026, 10, 6, 6, 0);
      await schedule.schedule('h-train', at);
      expect(schedule.forHabit('h-train'), at);

      // A second instance reads the same store, which is what a relaunch
      // actually does.
      final reloaded = HabitResumeSchedule();
      await reloaded.ready;
      expect(reloaded.forHabit('h-train'), at);
    });

    test('a manual pause clears any date left from a previous pause', () async {
      // The trap: pause with a date, resume by hand, pause again choosing
      // "أنا أقرر". Without the clear, the old date is still armed and would
      // resume the habit out of nowhere weeks later.
      final schedule = HabitResumeSchedule();
      await schedule.schedule('h-train', DateTime(2026, 10, 6));
      await schedule.schedule('h-train', null);
      expect(schedule.forHabit('h-train'), isNull);
    });

    test('only bookings whose time has arrived are due', () async {
      final schedule = HabitResumeSchedule();
      final now = DateTime(2026, 9, 1, 12, 0);
      await schedule.schedule('past', DateTime(2026, 8, 30));
      await schedule.schedule('now', now);
      await schedule.schedule('future', DateTime(2026, 9, 2));

      expect(schedule.dueBy(now), ['past', 'now'],
          reason: 'oldest first, and the exact moment counts as arrived');
    });

    test('a time of day is respected, not rounded to the day', () async {
      // "back on Tuesday at 6am" must not arrive on Monday evening.
      final schedule = HabitResumeSchedule();
      await schedule.schedule('h-train', DateTime(2026, 9, 1, 6, 0));
      expect(schedule.dueBy(DateTime(2026, 9, 1, 5, 59)), isEmpty);
      expect(schedule.dueBy(DateTime(2026, 9, 1, 6, 0)), ['h-train']);
    });

    test('bookings for habits that no longer exist are swept', () async {
      final schedule = HabitResumeSchedule();
      await schedule.schedule('still-here', DateTime(2026, 10, 6));
      await schedule.schedule('long-gone', DateTime(2026, 10, 6));
      await schedule.pruneMissing({'still-here'});
      expect(schedule.forHabit('still-here'), isNotNull);
      expect(schedule.forHabit('long-gone'), isNull);
    });

    test('pruning nothing does not rewrite the store', () async {
      final schedule = HabitResumeSchedule();
      await schedule.schedule('a', DateTime(2026, 10, 6));
      final before = schedule.state;
      await schedule.pruneMissing({'a'});
      expect(identical(schedule.state, before), isTrue,
          reason: 'a no-op prune should not churn state or storage');
    });

    test('bookings are isolated per account, even for a shared preset id',
        () async {
      // A catalog preset id ('tahajjud') is the same const string on every
      // account, so a device-global store let one account's booking resolve —
      // and pruneMissing sweep — against another account's own paused copy.
      // Per-identity keys keep each account's bookings to itself.
      final accountA =
          HabitResumeSchedule(LocalStoreService.habitResumeDatesKeyFor('uid-A'));
      await accountA.schedule('tahajjud', DateTime(2026, 9, 1, 6, 0));

      final accountB =
          HabitResumeSchedule(LocalStoreService.habitResumeDatesKeyFor('uid-B'));
      await accountB.ready;
      expect(accountB.forHabit('tahajjud'), isNull,
          reason: "another account's booking for the same id is not visible");

      final guest =
          HabitResumeSchedule(LocalStoreService.habitResumeDatesKeyFor(null));
      await guest.ready;
      expect(guest.forHabit('tahajjud'), isNull,
          reason: 'a guest session gets its own bucket too');

      // A's own booking is untouched by either of the other sessions loading.
      final accountAReloaded =
          HabitResumeSchedule(LocalStoreService.habitResumeDatesKeyFor('uid-A'));
      await accountAReloaded.ready;
      expect(accountAReloaded.forHabit('tahajjud'), DateTime(2026, 9, 1, 6, 0));
    });
  });
}
