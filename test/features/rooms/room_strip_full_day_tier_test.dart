import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/grid/screens/monthly_heatmap_screen.dart'
    show heatColor, heatLevel;
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_model.dart';
import 'package:grow_daily_v2/features/rooms/models/room_strip_day.dart';
import 'package:grow_daily_v2/features/rooms/notifiers/rooms_notifier.dart'
    show heatmapLevelFor, roomRaceDayCode;
import 'package:grow_daily_v2/features/rooms/screens/room_detail_screen.dart'
    show roomStripCellFill;

/// The darkest square on a room's strip, its member calendar and the Room
/// Race widget means a COMPLETE day (heatmapLevelFor, rooms_notifier.dart).
///
/// Found on the simulator 2026-09-27: Aziz's 17 September in ELQVF8 «Being
/// Better» was 2.5 of 3 (تمرين جزئي) and his 25 September in PBYAS5 was 6
/// of 7, and both were drawn exactly like the finished days around them,
/// because the level rounded every day past three quarters up into the top
/// tier. Tapping the 25th opened a day card saying «أُنجز جزئيًا» over a
/// square that said done. The Grid's own heatmap never did this: heatLevel
/// keeps level 4 for 100% alone.
void main() {
  group('heatmapLevelFor', () {
    test('only a whole day reaches the top tier', () {
      expect(heatmapLevelFor(1), 4);
      // Past the top of the scale (a habit done beyond what was asked) is
      // still a whole day.
      expect(heatmapLevelFor(1.2), 4);
      for (final part in [2.5 / 3, 6 / 7, 0.8, 0.75, 0.99]) {
        expect(heatmapLevelFor(part), 3, reason: '$part');
      }
    });

    test('the lower tiers are unchanged', () {
      expect(heatmapLevelFor(0), 0);
      expect(heatmapLevelFor(-1), 0);
      expect(heatmapLevelFor(0.1), 1);
      expect(heatmapLevelFor(0.25), 1);
      expect(heatmapLevelFor(1 / 3), 2);
      expect(heatmapLevelFor(0.5), 2);
      expect(heatmapLevelFor(2 / 3), 3);
    });

    test('a whole day built from weighted sums still reads whole', () {
      expect(heatmapLevelFor(1 - 1e-12), 4);
    });

    test('agrees with the Grid heatmap about which days are whole', () {
      // Every fraction a plan of up to ten habits can land on: the top tier
      // in one is the top tier in the other, and nowhere else.
      for (var total = 1; total <= 10; total++) {
        for (var done = 1; done <= total; done++) {
          expect(
            heatmapLevelFor(done / total) == 4,
            heatLevel(done, total) == 4,
            reason: '$done of $total',
          );
        }
      }
    });
  });

  group('a real part day, through the room model', () {
    // ELQVF8, Aziz, 2026-09-17: صلاة الوتر and قراءة القرآن done, تمرين
    // جزئي, three asked.
    final room = RoomModel(
      code: 'ELQVF8',
      name: 'Being Better',
      createdBy: 'aziz',
      createdByName: 'Aziz',
      createdAt: DateTime(2026, 9, 1),
      habitMode: RoomHabitMode.shared,
      duration: RoomDuration.fixed,
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 30),
    );
    RoomParticipant aziz({int done = 2, int partial = 1}) => RoomParticipant(
          uid: 'aziz',
          displayName: 'Aziz',
          characterId: 'male_ghutra_blue',
          joinedAt: DateTime(2026, 9, 1),
          linkedHabitIds: const ['tamreen', 'witr', 'quran'],
          dailyDoneCount: {'2026-09-17': done},
          dailyPartialCount: {if (partial > 0) '2026-09-17': partial},
          habitRules: const {
            'tamreen': [
              RoomHabitRule(
                from: '2026-09-01',
                frequencyType: HabitFrequencyType.weekly,
                frequencyTarget: 4,
              ),
            ],
            'witr': [
              RoomHabitRule(
                from: '2026-09-01',
                frequencyType: HabitFrequencyType.daily,
                frequencyTarget: 1,
              ),
            ],
            'quran': [
              RoomHabitRule(
                from: '2026-09-01',
                frequencyType: HabitFrequencyType.daily,
                frequencyTarget: 1,
              ),
            ],
          },
          lastUpdated: DateTime(2026, 9, 27),
        );
    final day = DateTime(2026, 9, 17);
    final now = DateTime(2026, 9, 27, 11);

    RoomStripDay stripDay(RoomParticipant p) =>
        roomStripDayOf(room, p, day, now: now);
    Color fill(RoomStripDay d) => roomStripCellFill(
          credit: d.credit,
          isRest: d.isRest,
          isMissed: d.isMissed,
          dark: true,
          backdrop: const Color(0xFF11161C),
          isDeclaredRest: d.isDeclaredRest,
          isStoodDown: d.isStoodDown,
          isPending: d.isPending,
        );

    test('2.5 of 3 is drawn one tier under a whole day', () {
      final part = stripDay(aziz());
      final whole = stripDay(aziz(done: 3, partial: 0));
      expect(part.credit, closeTo(2.5 / 3, 1e-9));
      expect(whole.credit, 1);
      expect(roomRaceDayCode(part), '3');
      expect(roomRaceDayCode(whole), '4');
      expect(fill(part), isNot(fill(whole)));
      expect(
        fill(part),
        Color.alphaBlend(heatColor(3, true), const Color(0xFF11161C)),
      );
    });
  });
}
