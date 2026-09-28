// The day card sprout's mood, as pure rules: which pose, which line, for a
// day's numbers and the wall clock. See sprout_mood.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';
import 'package:grow_daily_v2/features/mascot/sprout_mood.dart';

void main() {
  DayCardMood mood(int greens, int owed, int hour, {bool? perfect}) =>
      dayCardMoodFor(
        greens: greens,
        owed: owed,
        perfectDay: perfect ?? (owed > 0 && greens >= owed),
        hour: hour,
      );

  group('a day that asks for nothing', () {
    test('sleeps and says it is a rest day, at any hour', () {
      for (final hour in [0, 3, 8, 13, 22]) {
        expect(mood(0, 0, hour),
            const DayCardMood(SproutPose.sleeping, DayCardLine.restDay));
      }
    });
  });

  group('nothing done yet', () {
    test('waves good morning before noon', () {
      expect(mood(0, 5, 4),
          const DayCardMood(SproutPose.frontWave, DayCardLine.morning));
      expect(mood(0, 5, 11),
          const DayCardMood(SproutPose.frontWave, DayCardLine.morning));
    });

    test('waves hello from noon, never «صباح الخير» in the evening', () {
      expect(mood(0, 5, 12),
          const DayCardMood(SproutPose.frontWave, DayCardLine.hello));
      expect(mood(0, 5, 23),
          const DayCardMood(SproutPose.frontWave, DayCardLine.hello));
    });

    test('sleeps on a new day that has only just begun, midnight to 4am', () {
      for (final hour in [0, 1, 3]) {
        expect(mood(0, 5, hour),
            const DayCardMood(SproutPose.sleeping, DayCardLine.lateNight));
      }
    });
  });

  group('part of the day done', () {
    test('the first square is a sweet start', () {
      expect(mood(1, 5, 9),
          const DayCardMood(SproutPose.threeQuarterWave, DayCardLine.firstDone));
    });

    test('two or more say where the day stands', () {
      expect(mood(3, 5, 15),
          const DayCardMood(SproutPose.threeQuarterWave, DayCardLine.progress));
    });

    test('80% is still progress on the card: «يوم كامل» is only said on the '
        'tap that earns it, never as the standing mood', () {
      expect(mood(4, 5, 15).line, DayCardLine.progress);
    });

    test('an unfinished evening keeps it awake, never asleep on the day', () {
      expect(mood(3, 5, 22).pose, SproutPose.threeQuarterWave);
      expect(mood(3, 5, 2).pose, SproutPose.threeQuarterWave);
    });
  });

  group('every square green', () {
    test('delighted by day, «يوم مثالي»', () {
      expect(mood(5, 5, 14),
          const DayCardMood(SproutPose.happySparkles, DayCardLine.perfectDay));
      expect(mood(5, 5, 20).pose, SproutPose.happySparkles);
    });

    test('asleep from bedtime until it wakes', () {
      for (final hour in [kSproutBedtimeHour, 23, 0, kSproutWakeHour - 1]) {
        expect(mood(5, 5, hour),
            const DayCardMood(SproutPose.sleeping, DayCardLine.goodNight));
      }
      expect(mood(5, 5, kSproutWakeHour).pose, SproutPose.happySparkles);
    });
  });

  test('it never shows a pose that could read as sad or cross at the reader',
      () {
    const allowed = {
      SproutPose.frontWave,
      SproutPose.threeQuarterWave,
      SproutPose.happySparkles,
      SproutPose.sleeping,
    };
    for (var owed = 0; owed <= 8; owed++) {
      for (var greens = 0; greens <= owed; greens++) {
        for (var hour = 0; hour < 24; hour++) {
          final m = mood(greens, owed, hour);
          expect(allowed, contains(m.pose), reason: '$greens/$owed at $hour');
          if (m.pose == SproutPose.sleeping) {
            // Asleep only on a rest day, a finished day, or an empty new
            // day in the small hours: never on a day still being lived.
            final finished = owed > 0 && greens >= owed;
            expect(
              owed == 0 || finished || (greens == 0 && hour < kSproutWakeHour),
              isTrue,
              reason: 'asleep on $greens/$owed at $hour',
            );
          }
        }
      }
    }
  });
}
