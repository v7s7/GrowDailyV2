// The 24-hour arithmetic behind a habit counted several times a day.
//
// A habit set for "2x a day" used to be able to carry exactly ONE time, and
// the scheduler filled exactly one notification slot, so the second ping
// simply did not exist. Now each time owns a slot, and every case that can
// break that is clock arithmetic: a list spanning midnight, an offset pushing
// a time across it, a time landing exactly on now, the slot a time occupies
// staying put as the day passes.
//
// None of that is reachable from a widget test, which is why
// NotificationService.resolveClockSlots is a pure static: times and a
// simulated `now` in, slots and fire times out. No device, no plugin, no
// network, and `now` is a value rather than the wall clock, so these assert
// real answers instead of whatever time the suite happened to run at.
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/habits/models/habit_cue.dart';
// Through the parent library: kMaxTimesPerDay lives in a `part of` file that
// cannot be imported on its own.
import 'package:grow_daily_v2/features/habits/widgets/add_habit_sheet.dart'
    show kMaxTimesPerDay;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    // Bahrain: no DST, which is deliberate for these tests. The +1 day rolls
    // below are absolute Duration arithmetic, so in a DST zone they would
    // shift the wall clock across a transition. That is a real property of
    // TZDateTime.add and not something this feature should paper over — see
    // the note on the rolls in resolveClockSlots.
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
  });

  tz.TZDateTime at(int hour, int minute, {int day = 15}) =>
      tz.TZDateTime(tz.local, 2026, 8, day, hour, minute);

  List<TimeOfDay> times(List<(int, int)> hhmm) =>
      [for (final (h, m) in hhmm) TimeOfDay(hour: h, minute: m)];

  group('one slot per time', () {
    test('midnight and noon both resolve, each in its own slot', () {
      // Aziz's protein case, the one this whole feature exists for.
      final out = NotificationService.resolveClockSlots(
        times([(0, 0), (12, 0)]),
        const [0, 0, 0],
        at(11, 30),
      );
      expect(out.length, 2, reason: 'two times means two reminders');
      expect(out[0].slot, 0);
      expect(out[1].slot, 1);
      // 00:00 already passed today, so it is tomorrow's midnight.
      expect(out[0].fireTime, at(0, 0, day: 16));
      // 12:00 is still ahead, so it stays today.
      expect(out[1].fireTime, at(12, 0));
    });

    test('a time exactly equal to now rolls forward, never fires in the past',
        () {
      final out = NotificationService.resolveClockSlots(
        times([(9, 0)]),
        const [0, 0, 0],
        at(9, 0),
      );
      expect(out.single.fireTime, at(9, 0, day: 16));
    });

    test('an empty list schedules nothing', () {
      expect(NotificationService.resolveClockSlots(const [], const [0], at(9, 0)),
          isEmpty);
    });
  });

  group('per-time shifts', () {
    test('each slot is shifted by its own number, not a shared one', () {
      // 08:00 fifteen minutes early, 20:00 on the dot.
      final out = NotificationService.resolveClockSlots(
        times([(8, 0), (20, 0)]),
        const [-15, 0],
        at(6, 0),
      );
      expect(out[0].fireTime, at(7, 45));
      expect(out[1].fireTime, at(20, 0));
    });

    test('a short offset list reads as zero past its end', () {
      final out = NotificationService.resolveClockSlots(
        times([(8, 0), (20, 0)]),
        const [-15],
        at(6, 0),
      );
      expect(out[0].fireTime, at(7, 45));
      expect(out[1].fireTime, at(20, 0));
    });
  });

  group('offsets across midnight', () {
    test('a negative offset pulls an early time back into yesterday, and rolls',
        () {
      // 00:10 with "15 minutes before" is 23:55 the night before. It has
      // already passed at 11:30, so the answer is tomorrow night.
      final out = NotificationService.resolveClockSlots(
        times([(0, 10)]),
        const [-15, -15, -15],
        at(11, 30),
      );
      expect(out.single.fireTime, at(23, 55, day: 15),
          reason: 'tonight at 23:55 is still ahead of 11:30 today');
    });

    test('a positive offset pushes a late time into tomorrow', () {
      // 23:50 with "+30 minutes" is 00:20 the next day.
      final out = NotificationService.resolveClockSlots(
        times([(23, 50)]),
        const [30, 30, 30],
        at(11, 30),
      );
      expect(out.single.fireTime, at(0, 20, day: 16));
    });

    test('a recompute inside an "after" window keeps today\'s reminder', () {
      // 09:00 with "+30 minutes" recomputed at 09:10 (the app was opened
      // right around the habit's time — the normal case). The reminder is
      // still ahead: today 09:30, not tomorrow's. Rolling the bare time
      // before applying the shift used to lose it.
      final out = NotificationService.resolveClockSlots(
        times([(9, 0)]),
        const [30],
        at(9, 10),
      );
      expect(out.single.fireTime, at(9, 30),
          reason: 'today 09:30 has not happened yet at 09:10');
    });

    test('an offset that drags an imminent time into the past rolls a day', () {
      // The case the single-time path already documented: it is 8:58, the
      // habit is set for 9:00, the offset is -15, so 8:45 is behind us.
      final out = NotificationService.resolveClockSlots(
        times([(9, 0)]),
        const [-15, -15, -15],
        at(8, 58),
      );
      expect(out.single.fireTime, at(8, 45, day: 16));
    });
  });

  group('slot stability', () {
    // The property that keeps already-scheduled notifications cancellable. A
    // slot's id is hash('habitId#slot') and the OS has no other handle on it,
    // so if a time's slot moved during the day, the next cancel would aim at
    // the wrong id and strand a live reminder nothing could call back.
    test('a time keeps its slot as the day passes it', () {
      final list = times([(0, 0), (12, 0)]);
      final morning = NotificationService.resolveClockSlots(list, const [0, 0], at(1, 0));
      final afternoon =
          NotificationService.resolveClockSlots(list, const [0, 0], at(13, 0));

      // Fire ORDER differs between the two: at 01:00 the next reminder is
      // today's noon, at 13:00 it is tomorrow's midnight. The slots must not
      // follow that.
      expect(morning[0].fireTime.isAfter(morning[1].fireTime), isTrue,
          reason: "tomorrow's midnight is later than today's noon");
      expect(afternoon[0].fireTime.isBefore(afternoon[1].fireTime), isTrue,
          reason: 'from 13:00 both are tomorrow, midnight first');

      // ...and yet 00:00 is slot 0 in both, because slot is the index in the
      // canonical time list, not the position in fire order.
      expect(morning.map((e) => e.slot), [0, 1]);
      expect(afternoon.map((e) => e.slot), [0, 1]);
      expect(morning[0].fireTime.hour, 0);
      expect(afternoon[0].fireTime.hour, 0);
    });
  });

  group('bounds', () {
    test('never resolves more slots than the id scheme has', () {
      // 24 hourly times, clamped to the 12 slots the id band can hold.
      final many = times([for (var h = 0; h < 24; h++) (h, 0)]);
      final out = NotificationService.resolveClockSlots(many, const [], at(11, 30));
      expect(out.length, kMaxTimesPerDay);
      expect(out.last.slot, kMaxTimesPerDay - 1);
    });

    test('the stepper cap and the slot cap are the same number', () {
      // They cannot import each other — kMaxTimesPerDay lives inside a
      // `part of` a widget file — so the equality is asserted here instead.
      // A habit allowed more times than there are slots would silently lose
      // its tail.
      expect(kMaxTimesPerDay, 12);
      expect(HabitCue.times([for (var h = 0; h < 20; h++) TimeOfDay(hour: h, minute: 0)])
          .clockTimes.length, kMaxTimesPerDay);
    });
  });

  group('the cue that feeds it', () {
    test('a two-time cue round-trips through storage', () {
      final cue = HabitCue.times(times([(0, 0), (12, 0)]));
      expect(cue.toStorageValue(), 'custom_time:00:00,12:00');
      final back = HabitCue.fromStoredValue(cue.toStorageValue());
      expect(back.clockTimes.length, 2);
      expect(back.clockTimes.first, const TimeOfDay(hour: 0, minute: 0));
      expect(back.clockTimes.last, const TimeOfDay(hour: 12, minute: 0));
    });

    test('a single time is byte-identical to what shipped before', () {
      // The backward-compatibility guarantee: nothing already on disk moves.
      final cue = HabitCue.fromStoredValue('custom_time:07:30');
      expect(cue.toStorageValue(), 'custom_time:07:30');
      expect(cue.clockTime, const TimeOfDay(hour: 7, minute: 30));
      expect(cue.clockTimes, [const TimeOfDay(hour: 7, minute: 30)]);
    });

    test('the shipped catalog cues still resolve', () {
      for (final stored in ['custom_time:22:30', 'custom_time:05:30']) {
        expect(HabitCue.fromStoredValue(stored).clockTime, isNotNull,
            reason: '$stored is a real habit in the catalog');
      }
    });

    test('times are sorted and deduped into one canonical spelling', () {
      // Both orderings must produce the same stored string, or a habit edited
      // back to its catalog default would keep writing a phantom override
      // (AddHabitSheet compares cue strings raw).
      expect(HabitCue.times(times([(12, 0), (0, 0)])).toStorageValue(),
          'custom_time:00:00,12:00');
      expect(HabitCue.times(times([(12, 0), (12, 0)])).toStorageValue(),
          'custom_time:12:00');
    });

    test('freeform text containing a comma is never split', () {
      // The split is gated on the custom_time: prefix precisely because real
      // cues contain commas.
      const raw = 'after lunch, before gym';
      final cue = HabitCue.fromStoredValue(raw);
      expect(cue.clockTimes, isEmpty);
      expect(cue.labelForLocale(false), raw);
    });

    test('a damaged custom_time value resolves to empty, not to freeform', () {
      // Falling through to freeform is what would make the damage invisible:
      // isEmpty would be false, so every screen would render the raw token as
      // if the person had typed it.
      for (final bad in [
        'custom_time:',
        'custom_time:99:99',
        'custom_time:12:00,',
        'custom_time:12:00,xx:yy',
      ]) {
        final cue = HabitCue.fromStoredValue(bad);
        expect(cue.isEmpty, isTrue, reason: '$bad must not become text');
        expect(cue.labelForLocale(false), isNot(contains('custom_time')));
      }
    });

    test('each time carries its own shift, through storage and back', () {
      final cue = HabitCue.timesWithOffsets([
        (const TimeOfDay(hour: 8, minute: 0), -15),
        (const TimeOfDay(hour: 20, minute: 0), 0),
      ]);
      expect(cue.toStorageValue(), 'custom_time:08:00-15,20:00');
      final back = HabitCue.fromStoredValue(cue.toStorageValue());
      expect(back.clockOffsets, [-15, 0]);
      expect(back.offsetsAreOwn, isTrue,
          reason: 'with its own shifts the habit-level field must not apply');
    });

    test('a shift rides with its time through the sort, never onto another',
        () {
      // Entered latest-first. The sort has to carry each shift with the time
      // it belongs to, or every reminder after the reorder fires on somebody
      // else's number.
      final cue = HabitCue.timesWithOffsets([
        (const TimeOfDay(hour: 20, minute: 0), 30),
        (const TimeOfDay(hour: 8, minute: 0), -15),
      ]);
      expect(cue.toStorageValue(), 'custom_time:08:00-15,20:00+30');
      expect(cue.clockTimes.first, const TimeOfDay(hour: 8, minute: 0));
      expect(cue.offsetForSlot(0), -15);
      expect(cue.offsetForSlot(1), 30);
    });

    test('a single time never claims its own shift', () {
      // The backward-compatible half: one time keeps answering from the
      // habit's own reminderOffsetMinutes, exactly as it always has.
      final cue = HabitCue.fromStoredValue('custom_time:07:30');
      expect(cue.offsetsAreOwn, isFalse);
      expect(cue.toStorageValue(), 'custom_time:07:30');
    });

    test('a damaged shift resolves to empty, like a damaged time', () {
      for (final bad in ['custom_time:08:00-', 'custom_time:08:00-9999']) {
        expect(HabitCue.fromStoredValue(bad).isEmpty, isTrue, reason: bad);
      }
    });

    test('a multi-time label reads as a sentence, not a list', () {
      // It is dropped into «بعد {cue}، سأقوم بـ {name}», where a trailing
      // comma would collide with the template's own.
      final cue = HabitCue.times(times([(0, 0), (12, 0)]));
      expect(cue.labelForLocale(false), '12:00 AM and 12:00 PM');
      expect(cue.labelForLocale(true), contains('و'));
    });
  });
}
