// Which sentence a room shows about a linked habit it cannot resolve.
//
// The bug this pins: pausing a habit archives it, and archiving drops it
// out of habitListProvider immediately, exactly as deleting does. Room
// Detail resolved its linked ids against that single list, so a paused
// habit was indistinguishable from a deleted one and got the deleted
// habit's message:
//
//   "A linked habit no longer exists in your Grid. Leaving and rejoining
//    relinks it, but also resets your progress in this room."
//
// For a paused habit that is wrong twice over. It is not gone, and the fix
// it recommends is the one action that destroys what the member was trying
// to protect: leaveRoom deletes the participant doc. Someone who paused a
// training habit for a broken leg was being pointed at wiping a 90-day
// room to repair something that repairs itself on Resume.
//
// Grading is deliberately NOT part of this split. A paused habit stays in
// the room's denominator on purpose (see paused_habit_room_grading_test),
// so these tests only assert which explanation is chosen.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/app_strings.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart';

IslamicHabitTemplate _habit(
  String id, {
  required String name,
  required String nameAr,
  DateTime? archivedAt,
}) =>
    IslamicHabitTemplate(
      id: id,
      name: name,
      nameAr: nameAr,
      description: '',
      category: HabitCategory.custom,
      frequencyType: HabitFrequencyType.daily,
      frequencyTarget: 1,
      hasTimer: false,
      xpReward: 10,
      goldReward: 5,
      archivedAt: archivedAt,
    );

RoomParticipant _participant(List<String> linkedHabitIds) => RoomParticipant(
      uid: 'member-uid',
      displayName: 'Aziz',
      characterId: 'male_ghutra_blue',
      joinedAt: DateTime(2026, 8, 19),
      linkedHabitIds: linkedHabitIds,
      dailyDoneCount: const {},
      dailyScheduledCount: const {},
      lastUpdated: DateTime(2026, 8, 25),
    );

void main() {
  final training = _habit('h-train', name: 'Exercise', nameAr: 'تمرين');
  final witr = _habit('h-witr', name: 'Witr', nameAr: 'صلاة الوتر');
  final pausedTraining = _habit(
    'h-train',
    name: 'Exercise',
    nameAr: 'تمرين',
    archivedAt: DateTime(2026, 8, 25),
  );

  group('a paused linked habit', () {
    test('is reported as paused, never as deleted', () {
      final split = roomUnresolvedLinks(
        _participant(['h-train', 'h-witr']),
        [witr], // the active board: training has left it
        [pausedTraining],
        isAr: true,
      );

      expect(split.hasDeleted, isFalse,
          reason: 'it is paused, and pause is not deletion');
      expect(split.pausedNames, ['تمرين'],
          reason: 'named, so it is obvious which habit is meant');
    });

    test('is named in the reader\'s own language', () {
      final split = roomUnresolvedLinks(
        _participant(['h-train']),
        const [],
        [pausedTraining],
        isAr: false,
      );
      expect(split.pausedNames, ['Exercise']);
    });
  });

  test('a genuinely deleted linked habit still gets the red warning', () {
    final split = roomUnresolvedLinks(
      _participant(['h-gone']),
      [training],
      const [], // nothing paused, so 'h-gone' is really gone
      isAr: true,
    );
    expect(split.hasDeleted, isTrue);
    expect(split.pausedNames, isEmpty);
  });

  test('one paused and one deleted are reported independently', () {
    final split = roomUnresolvedLinks(
      _participant(['h-train', 'h-gone']),
      const [],
      [pausedTraining],
      isAr: true,
    );
    expect(split.pausedNames, ['تمرين']);
    expect(split.hasDeleted, isTrue,
        reason: 'the paused one must not mask the deleted one');
  });

  test('a fully resolvable plan says nothing at all', () {
    final split = roomUnresolvedLinks(
      _participant(['h-train', 'h-witr']),
      [training, witr],
      const [],
      isAr: true,
    );
    expect(split.pausedNames, isEmpty);
    expect(split.hasDeleted, isFalse);
  });

  test('a declined slot is not mistaken for a missing habit', () {
    // kDeclinedSlot is a placeholder, never a real habit id. Counting it
    // here would pin a permanent warning to anyone who skipped a slot.
    final split = roomUnresolvedLinks(
      _participant([kDeclinedSlot, 'h-train']),
      [training],
      const [],
      isAr: true,
    );
    expect(split.hasDeleted, isFalse);
    expect(split.pausedNames, isEmpty);
  });

  group('the copy itself', () {
    test('never repeats the deleted habit\'s destructive advice', () {
      for (final locale in [const Locale('ar'), const Locale('en')]) {
        final s = S(locale);
        final paused = s.roomLinkedHabitPausedHint(['تمرين']);
        expect(paused, contains('تمرين'));
        expect(paused, isNot(equals(s.roomLinkedHabitDeletedHint)));
        // The exact clause that made the old message dangerous to follow:
        // it offered wiping this room's progress as the repair. Asserted
        // against the deleted copy too, so this test fails loudly if that
        // wording ever moves rather than passing vacuously.
        final destructive = s.isAr ? 'يصفّر تقدمك' : 'resets your progress';
        expect(s.roomLinkedHabitDeletedHint, contains(destructive),
            reason: 'the deleted message is where that advice belongs');
        expect(paused, isNot(contains(destructive)),
            reason: 'a paused habit needs no repair, so it is never offered one');
      }
    });

    test('the sole-habit case warns instead of reassuring', () {
      // The lie this split exists to stop: with one linked habit there is
      // no "rest of your habits" to be graded on, so the reassuring copy
      // would promise a softening that does not happen.
      for (final locale in [const Locale('ar'), const Locale('en')]) {
        final s = S(locale);
        final sole = s.roomSoleLinkedHabitPausedHint('تمرين');
        expect(sole, contains('تمرين'));
        // It must say the days score zero, and must NOT claim the score
        // comes from other habits.
        expect(sole, contains(s.isAr ? 'صفر' : 'zero'));
        expect(sole, isNot(contains(s.isAr ? 'باقي عاداتك' : 'you can still do')));
        // And it must still name the remedy.
        expect(sole, contains(s.isAr ? 'استئنافها' : 'Resume it'));
      }
    });

    test('the multi-habit case still reassures', () {
      final many = S(const Locale('ar')).roomLinkedHabitPausedHint(['تمرين']);
      expect(many, contains('باقي عاداتك'));
      expect(many, isNot(contains('صفر')));
    });

    test('the all-paused plural case names every habit and still warns', () {
      // When several linked habits are ALL paused there is no "rest" either,
      // so this must warn like the sole case — but name every paused habit,
      // not just the first, which is what the old singular chooser did wrong.
      final ar = S(const Locale('ar'))
          .roomLinkedHabitAllPausedHint(['تمرين', 'صلاة الضحى']);
      expect(ar, contains('تمرين'));
      expect(ar, contains('صلاة الضحى'));
      expect(ar, contains('صفر'));
      expect(ar, isNot(contains('باقي عاداتك')),
          reason: 'nothing is left to be graded on');
      final en = S(const Locale('en'))
          .roomLinkedHabitAllPausedHint(['Exercise', 'Duha']);
      expect(en, contains('Exercise'));
      expect(en, contains('Duha'));
      expect(en, contains('zero'));
      expect(en, isNot(contains('you can still do')));
    });

    test('the pause dialog has its own sole-habit warning', () {
      for (final locale in [const Locale('ar'), const Locale('en')]) {
        final s = S(locale);
        final sole = s.habitPauseSoleRoomHabitBody(['دو الإلتزام']);
        expect(sole, contains('دو الإلتزام'));
        expect(sole, contains(s.isAr ? 'صفر' : 'zero'));
        expect(sole, isNot(equals(s.habitPauseLinkedRoomBody(['دو الإلتزام']))));
      }
    });

    test('points at the one action that actually fixes it', () {
      expect(S(const Locale('ar')).roomLinkedHabitPausedHint(['تمرين']),
          contains('استئنافها'));
      expect(S(const Locale('en')).roomLinkedHabitPausedHint(['Exercise']),
          contains('Resume it'));
    });

    test('reads as plural when more than one habit is paused', () {
      final ar = S(const Locale('ar')).roomLinkedHabitPausedHint(['تمرين', 'صلاة الضحى']);
      expect(ar, contains('تمرين'));
      expect(ar, contains('صلاة الضحى'));
      final en = S(const Locale('en')).roomLinkedHabitPausedHint(['Exercise', 'Duha']);
      expect(en, contains('are paused'),
          reason: 'two habits are, not is');
    });
  });
}
