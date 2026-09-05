// What one tap on Add Habit's reminder grid MEANS.
//
// The grid used to be single-choice: a habit had exactly one shift, and
// picking «قبل ١٥ د» replaced whatever was there. It is a stack now, the same
// one the Tasks sheet has had. The whole risk of that change lands on one
// question — what does a tap do? — and the answer is different on the two
// tiers:
//
//  * Free still means "change my reminder", because a habit's shift IS its
//    reminder. Someone who cannot stack must still be able to MOVE the one
//    they have, so free stays single-choice and never meets a paywall for
//    using the control normally. Getting this backwards would take an ability
//    away from every free user, silently.
//  * Premium means "add another".
//
// Everything else here is the small print that decides whether a tap is
// honest: the last reminder cannot be deleted, a full stack says so instead
// of trying to sell something Premium already has, and removing the primary
// promotes a survivor rather than renumbering the slots around a hole.
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/habits/models/habit_reminder_stack.dart';
import 'package:grow_daily_v2/features/premium/notifiers/premium_notifier.dart';

void main() {
  HabitReminderStack stack(int primary, [Set<int> extras = const {}]) =>
      HabitReminderStack(primary: primary, extras: extras);

  group('free', () {
    test('tapping another chip MOVES the one reminder, no paywall', () {
      final out = stack(0).toggle(-15, isPremium: false);
      expect(out.outcome, HabitOffsetTap.replaced,
          reason: 'a paywall here would take away the only thing free users '
              'could already do with this control');
      expect(out.stack.all, const [-15]);
      expect(out.stack.extras, isEmpty);
    });

    test('a free habit never quietly grows a second reminder', () {
      final out = stack(0).toggle(-15, isPremium: false);
      expect(out.stack.length, 1);
    });

    test('a stack kept through a lapsed subscription is what opens the gate',
        () {
      // The gate is on ADDING, and only once there is genuinely something to
      // add to — see kFreeHabitReminders.
      final inherited = stack(0, {-15});
      expect(inherited.toggle(30, isPremium: false).outcome,
          HabitOffsetTap.locked);
    });

    test('and that inherited stack can still be trimmed', () {
      // Never gated: stranding someone with reminders they can only clear
      // wholesale would be the worst way to find out a subscription expired.
      final out = stack(0, {-15}).toggle(-15, isPremium: false);
      expect(out.outcome, HabitOffsetTap.removed);
      expect(out.stack.all, const [0]);
    });
  });

  group('premium', () {
    test('tapping another chip ADDS it', () {
      final out = stack(0).toggle(-15, isPremium: true);
      expect(out.outcome, HabitOffsetTap.added);
      expect(out.stack.all, const [-15, 0]);
      expect(out.stack.primary, 0,
          reason: 'slot 0 is a live notification id; adding around it must '
              'not move what it stands for');
    });

    test('a selected chip comes back off', () {
      final out = stack(0, {-15, 30}).toggle(30, isPremium: true);
      expect(out.outcome, HabitOffsetTap.removed);
      expect(out.stack.all, const [-15, 0]);
    });

    test('removing the primary promotes the earliest survivor', () {
      final out = stack(0, {-15, 30}).toggle(0, isPremium: true);
      expect(out.outcome, HabitOffsetTap.removed);
      expect(out.stack.primary, -15);
      expect(out.stack.extras, {30});
      expect(out.stack.all, const [-15, 30]);
    });

    test('the ceiling explains itself rather than selling anything', () {
      final full = stack(0, {-5, -10, -15});
      expect(full.length, kMaxHabitReminders);
      final out = full.toggle(-30, isPremium: true);
      expect(out.outcome, HabitOffsetTap.refusedFull,
          reason: 'offering to sell Premium a limit Premium also has is the '
              'worst possible answer here');
      expect(out.stack.all, full.all, reason: 'a refused tap changes nothing');
    });
  });

  group('the last reminder', () {
    test('cannot be tapped away, on either tier', () {
      for (final premium in const [true, false]) {
        final out = stack(-15).toggle(-15, isPremium: premium);
        expect(out.outcome, HabitOffsetTap.refusedLast,
            reason: 'a habit with no shift at all is not a state Add Habit '
                'can express — the cue would still resolve and nothing would '
                'fire. "Never remind me" is a custom-text cue.');
        expect(out.stack.all, const [-15]);
      }
    });
  });

  group('a hand-typed shift', () {
    test('adds, like a chip tap', () {
      final out = stack(0).addTyped(-45, isPremium: true);
      expect(out.outcome, HabitOffsetTap.added);
      expect(out.stack.all, const [-45, 0]);
    });

    test('does NOT toggle off one the habit already has', () {
      // The one place typing differs from tapping: nobody types 45 into a
      // field and presses Add meaning "remove my 45-minute reminder".
      final existing = stack(0, {-45});
      final out = existing.addTyped(-45, isPremium: true);
      expect(out.outcome, HabitOffsetTap.added);
      expect(out.stack.all, existing.all);
    });

    test('replaces on free, same as a chip', () {
      final out = stack(0).addTyped(-45, isPremium: false);
      expect(out.outcome, HabitOffsetTap.replaced);
      expect(out.stack.all, const [-45]);
    });
  });

  group('the set itself', () {
    test('is always sorted and never repeats the primary', () {
      final s = stack(30, {-15, 0});
      expect(s.all, const [-15, 0, 30]);
      expect(s.extras.contains(30), isFalse);
    });

    test('is never empty', () {
      expect(stack(0).all, isNotEmpty);
      expect(stack(0).toggle(0, isPremium: true).stack.all, isNotEmpty);
    });
  });
}
