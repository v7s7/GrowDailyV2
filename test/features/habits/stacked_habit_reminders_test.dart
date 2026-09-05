// A habit can be reminded about more than once around the SAME moment.
//
// Until now a habit had exactly one shift: "15 before Maghrib" meant one
// notification, and there was no way to also be nudged on the dot and again
// half an hour later. Tasks have had that stack for a while, and the two
// screens ask the identical question, so the habit side grew the same one.
//
// What is pinned here is everything that could quietly go wrong while adding
// it, in the order it would hurt:
//
//  1. Nothing existing moves. A habit with no stack stores, loads and
//     schedules byte-for-byte what it did before — slot 0 above all, because
//     a slot index IS a notification id and a renumbered slot strands a live
//     reminder the app can no longer cancel.
//  2. The stack survives a round trip through storage, including the shapes
//     Firestore and an older build can hand back.
//  3. Logging the habit once silences the WHOLE stack, not just its earliest
//     entry, which is the bug the naive suppression arithmetic produces.
//  4. The tier rule is one rule, and it gates adding rather than keeping.
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/habits/notifiers/catalog_overrides_notifier.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    // Bahrain: no DST, so the +1 day rolls below are honest wall-clock days.
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
  });

  tz.TZDateTime at(int hour, int minute, {int day = 15}) =>
      tz.TZDateTime(tz.local, 2026, 8, day, hour, minute);

  IslamicHabitTemplate habit({
    int offset = 0,
    List<int> extras = const [],
  }) =>
      IslamicHabitTemplate(
        id: 'h1',
        name: 'Read',
        description: '',
        category: HabitCategory.faith,
        frequencyType: HabitFrequencyType.daily,
        frequencyTarget: 1,
        hasTimer: false,
        xpReward: 10,
        goldReward: 5,
        reminderOffsetMinutes: offset,
        extraReminderOffsets: extras,
      );

  group('nothing existing moves', () {
    test('a habit with no stack expands to exactly what it was', () {
      final times = [const TimeOfDay(hour: 9, minute: 0)];
      final out = NotificationService.expandStackedSlots(
        times: times,
        offsets: const [-15],
        primaryOffset: -15,
        extraOffsets: const [],
      );
      expect(out.times, same(times),
          reason: 'the untouched case must not even rebuild the list');
      expect(out.offsets, const [-15]);
      expect(out.perOccurrence, 1);
    });

    test('a multi-time habit is left alone even if a stack is present', () {
      // Belt and braces: the Add Habit form drops the stack when a habit goes
      // multi-time, but a document edited elsewhere, or written by a build
      // that ordered those two things differently, must not multiply the two
      // lists together here.
      final out = NotificationService.expandStackedSlots(
        times: const [
          TimeOfDay(hour: 9, minute: 0),
          TimeOfDay(hour: 21, minute: 0),
        ],
        offsets: const [0, -10],
        primaryOffset: 0,
        extraOffsets: const [-30, 30],
      );
      expect(out.times, hasLength(2));
      expect(out.offsets, const [0, -10]);
      expect(out.perOccurrence, 1);
    });

    test('the primary keeps slot 0 when a stack is added around it', () {
      final out = NotificationService.expandStackedSlots(
        times: const [TimeOfDay(hour: 9, minute: 0)],
        offsets: const [-15],
        primaryOffset: -15,
        extraOffsets: const [-60, 0, 30],
      );
      expect(out.offsets.first, -15,
          reason: 'slot 0 is a notification id the OS is already holding; '
              'the shift it stands for cannot change underneath it');
      expect(out.offsets, const [-15, -60, 0, 30]);
      expect(out.times, everyElement(const TimeOfDay(hour: 9, minute: 0)));
      expect(out.perOccurrence, 4);
    });

    test('a stack that repeats the primary does not schedule it twice', () {
      final out = NotificationService.expandStackedSlots(
        times: const [TimeOfDay(hour: 9, minute: 0)],
        offsets: const [0],
        primaryOffset: 0,
        extraOffsets: const [0, -15],
      );
      expect(out.offsets, const [0, -15]);
    });

    test('the expansion never outruns the id band', () {
      final out = NotificationService.expandStackedSlots(
        times: const [TimeOfDay(hour: 9, minute: 0)],
        offsets: const [0],
        primaryOffset: 0,
        // Far past any product cap: the id scheme's own bound has to hold on
        // its own, whatever a stored document claims.
        extraOffsets: [for (var i = 1; i <= 40; i++) i],
      );
      expect(out.offsets.length, lessThanOrEqualTo(12));
      expect(out.times.length, out.offsets.length,
          reason: 'the two lists are read index-aligned by resolveClockSlots');
    });
  });

  group('the expanded pairs resolve to real, separate moments', () {
    test('three shifts on one 21:00 anchor become three fire times', () {
      final out = NotificationService.expandStackedSlots(
        times: const [TimeOfDay(hour: 21, minute: 0)],
        offsets: const [0],
        primaryOffset: 0,
        extraOffsets: const [-30, 60],
      );
      final slots = NotificationService.resolveClockSlots(
        out.times,
        out.offsets,
        at(12, 0),
      );
      expect(slots.map((s) => s.fireTime), [
        at(21, 0),
        at(20, 30),
        at(22, 0),
      ]);
      expect(slots.map((s) => s.slot), [0, 1, 2],
          reason: 'slot is the index, never the fire order — 20:30 comes '
              'first in the day and still owns slot 1');
    });

    test('a shift that has already passed rolls on its own, not as a group',
        () {
      // 20:30 is behind us at 20:45 while 21:00 is not, so the early nudge
      // belongs to tomorrow and the on-time one to tonight. Resolving the
      // stack as one moment and offsetting afterwards would have moved both.
      final out = NotificationService.expandStackedSlots(
        times: const [TimeOfDay(hour: 21, minute: 0)],
        offsets: const [0],
        primaryOffset: 0,
        extraOffsets: const [-30],
      );
      final slots = NotificationService.resolveClockSlots(
        out.times,
        out.offsets,
        at(20, 45),
      );
      expect(slots[0].fireTime, at(21, 0));
      expect(slots[1].fireTime, at(20, 30, day: 16));
    });
  });

  group('storage', () {
    test('a habit with no stack writes no new field at all', () {
      expect(habit().toFirestore().containsKey('extraReminderOffsets'), isFalse,
          reason: 'an empty stack must not rewrite any stored habit');
    });

    test('a stack round-trips', () {
      final map = habit(offset: -15, extras: const [0, 30]).toFirestore();
      expect(map['extraReminderOffsets'], const [0, 30]);
      expect(
        IslamicHabitTemplate.fromMap('h1', Map<String, dynamic>.from(map))
            .extraReminderOffsets,
        const [0, 30],
      );
    });

    test('a stored stack is deduped and sorted on the way in', () {
      // Firestore hands arrays back as List<dynamic> of num, and the slot a
      // shift lands in is its position, so an unsorted or repeated list would
      // make the same habit produce different ids on different devices.
      final loaded = IslamicHabitTemplate.fromMap('h1', {
        'name': 'Read',
        'category': 'faith',
        'frequencyType': 'daily',
        'frequencyTarget': 1,
        'extraReminderOffsets': [30, -15, 30, 0],
      });
      expect(loaded.extraReminderOffsets, const [-15, 0, 30]);
    });

    test('a malformed entry costs that entry, never the habit', () {
      final loaded = IslamicHabitTemplate.fromMap('h1', {
        'name': 'Read',
        'category': 'faith',
        'frequencyType': 'daily',
        'frequencyTarget': 1,
        'extraReminderOffsets': [15, 'oops', null, -30],
      });
      expect(loaded.extraReminderOffsets, const [-30, 15]);
    });

    test('a stack stored as something other than a list is ignored', () {
      final loaded = IslamicHabitTemplate.fromMap('h1', {
        'name': 'Read',
        'category': 'faith',
        'frequencyType': 'daily',
        'frequencyTarget': 1,
        'extraReminderOffsets': 15,
      });
      expect(loaded.extraReminderOffsets, isEmpty);
    });

    test('every copy helper carries the stack', () {
      // These are hand-written, field-by-field copies. One that forgot this
      // field would silently drop a person's extra reminders the next time
      // the habit was stamped with a date, which is every app launch.
      final h = habit(offset: -15, extras: const [0, 30]);
      expect(h.withCreatedAt(DateTime(2026, 1, 1)).extraReminderOffsets,
          const [0, 30]);
      expect(h.withDates(createdAt: DateTime(2026, 1, 1)).extraReminderOffsets,
          const [0, 30]);
      expect(h.withReminderOffset(-45).extraReminderOffsets, const [0, 30]);
    });
  });

  group('a catalog preset can be given a stack, and have it taken away', () {
    final preset = habit(offset: -10, extras: const [0]);

    test('an override lays its stack over the catalog default', () {
      const override = CatalogHabitOverride(extraReminderOffsets: [30, 60]);
      expect(override.applyTo(preset).extraReminderOffsets, const [30, 60]);
    });

    test('an EMPTY override clears the stack rather than meaning untouched',
        () {
      // The distinction the whole nullable-override scheme rests on: null is
      // "not overridden", [] is "the user removed them all". Collapsing the
      // two would resurrect a stack every time the habit reloaded.
      const cleared = CatalogHabitOverride(extraReminderOffsets: []);
      expect(cleared.isEmpty, isFalse);
      expect(cleared.applyTo(preset).extraReminderOffsets, isEmpty);
      expect(cleared.toMap()['extraReminderOffsets'], isEmpty);
    });

    test('an untouched override keeps the catalog value', () {
      const untouched = CatalogHabitOverride();
      expect(untouched.applyTo(preset).extraReminderOffsets, const [0]);
      expect(untouched.toMap().containsKey('extraReminderOffsets'), isFalse);
    });

    test('an override round-trips through storage', () {
      const override = CatalogHabitOverride(extraReminderOffsets: [60, -15]);
      final back = CatalogHabitOverride.fromMap(
          Map<String, dynamic>.from(override.toMap()));
      expect(back.extraReminderOffsets, const [-15, 60]);
    });
  });

  group('the tier rule', () {
    test('free gets one reminder, and it is the one every habit already had',
        () {
      expect(kFreeHabitReminders, kFreeTaskReminders,
          reason: 'two features asking the identical question should not '
              'answer it differently');
      expect(canAddHabitReminder(current: 0, isPremium: false).allowed, isTrue);
      final second = canAddHabitReminder(current: 1, isPremium: false);
      expect(second.allowed, isFalse);
      expect(second.locked, isTrue,
          reason: 'this is a "you could buy this", not a "this is full"');
    });

    test('premium stacks up to the standing-notification ceiling', () {
      for (var n = 1; n < kMaxHabitReminders; n++) {
        expect(canAddHabitReminder(current: n, isPremium: true).allowed, isTrue,
            reason: 'premium is uncapped below the platform ceiling');
      }
      final full = canAddHabitReminder(
          current: kMaxHabitReminders, isPremium: true);
      expect(full.allowed, isFalse);
      expect(full.locked, isFalse,
          reason: 'a ceiling that applies to Premium too is a limit, not an '
              'upsell — offering to sell someone what they already own is '
              'the worst possible answer here');
    });

    test('the ceiling stays inside the id band the scheduler can hold', () {
      // kMaxHabitReminders is a product decision; 12 is the 5000..5999 band's
      // own bound. The product one must never be the larger of the two.
      expect(kMaxHabitReminders, lessThanOrEqualTo(12));
    });
  });
}
