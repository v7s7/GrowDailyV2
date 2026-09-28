// Doum's settings (pet_settings.dart): the built-in values, the admin's
// edits laid over them, and every place Doum reads them. The cases in
// scripts/admin_lookup/test/fixtures/pet_cases.json are also run by the
// admin page's own rules (test/pet.test.js there), so the page shows before
// Save what phones do after it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/wording_edits.dart';
import 'package:grow_daily_v2/features/habits/catalog/islamic_habit_catalog.dart';
import 'package:grow_daily_v2/features/habits/models/habit_model.dart';
import 'package:grow_daily_v2/features/mascot/pet_settings.dart';
import 'package:grow_daily_v2/features/mascot/sprout.dart';
import 'package:grow_daily_v2/features/mascot/sprout_mood.dart';
import 'package:grow_daily_v2/features/mascot/sprout_praise.dart';

void main() {
  tearDown(() => WordingEditsStore.debugPublish(WordingEdits.empty));

  group('the cases the admin page also runs', () {
    final fixture = jsonDecode(
      File('scripts/admin_lookup/test/fixtures/pet_cases.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final c in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final inForce = PetSettings.from(PetEdits.fromData(c['edits']));
        final shown = inForce.describe();
        (c['expect'] as Map<String, dynamic>).forEach((key, value) {
          expect(shown[key], value, reason: key);
        });
      });
    }
  });

  test('the built-in values are the ones Doum had before the admin page', () {
    final s = PetSettings.builtIn;
    expect(s.praiseEvery, const Duration(seconds: 20));
    expect(s.bubbleFor, const Duration(seconds: 3));
    expect(s.rememberLines, 30);
    expect(
      [s.morningUntilHour, s.bedtimeHour, s.wakeHour],
      [12, kSproutBedtimeHour, kSproutWakeHour],
    );
  });

  test('the edits survive this device\'s cached copy of wording/live', () {
    final data = {
      'pet': {
        'praiseEverySeconds': 5,
        'presets': {'tahajjud': ''},
        'alsoHears': {'quran': ''},
        'quit': 'social',
      },
    };
    final once = WordingEdits.fromData(data);
    final again = WordingEdits.fromData(jsonDecode(jsonEncode(once.toJson())));
    expect(again.pet!.toJson(), once.pet!.toJson());
    expect(again.pet!.presets, {'tahajjud': ''});
    expect(WordingEdits.fromData({'pet': <String, Object>{}}).pet, isNull,
        reason: 'an empty field is no edit at all');
  });

  group('Doum follows a save on the admin page without a restart', () {
    void publish(PetEdits pet) =>
        WordingEditsStore.debugPublish(WordingEdits(pet: pet));

    test('the settings in force change with the edits, and go back', () {
      publish(const PetEdits(
        numbers: {'praiseEverySeconds': 5, 'rememberLines': 12},
      ));
      expect(PetSettings.current.praiseEvery, const Duration(seconds: 5));
      expect(PraisePicker().memory, 12);
      WordingEditsStore.debugPublish(WordingEdits.empty);
      expect(PetSettings.current.praiseEvery, const Duration(seconds: 20));
      expect(PraisePicker().memory, 30);
    });

    test('which list a habit hears: its own list first, then the quit list, '
        'then its category\'s', () {
      final prayer = IslamicHabitCatalog.templates.firstWhere((t) =>
          t.category == HabitCategory.faith && t.goalType != GoalType.quit);
      final walk = IslamicHabitCatalog.templates
          .firstWhere((t) => t.category == HabitCategory.fitness);
      final gaze = IslamicHabitCatalog.templates
          .firstWhere((t) => t.goalType == GoalType.quit);
      final tahajjud = IslamicHabitCatalog.findById('tahajjud')!;

      expect(praiseGroupFor(walk), PraiseGroup.sport);
      expect(praiseGroupFor(gaze), PraiseGroup.general);
      expect(praiseGroupFor(tahajjud), PraiseGroup.faith);

      publish(PetEdits(
        presets: {gaze.id: 'faith', tahajjud.id: ''},
        categories: const {'fitness': 'health'},
        quit: 'social',
      ));
      expect(praiseGroupFor(walk), PraiseGroup.health);
      expect(praiseGroupFor(gaze), PraiseGroup.faith,
          reason: 'a habit\'s own list wins over the quit rule');
      expect(praiseGroupFor(tahajjud), PraiseGroup.athkar,
          reason: 'sent back to its category');
      expect(praiseGroupFor(prayer), PraiseGroup.faith);
    });

    test('what a list also draws on', () {
      expect(praiseParentOf(PraiseGroup.quran), PraiseGroup.faith);
      publish(const PetEdits(alsoHears: {'quran': '', 'learning': 'focus'}));
      expect(praiseParentOf(PraiseGroup.quran), isNull);
      expect(praiseParentOf(PraiseGroup.learning), PraiseGroup.focus);
    });

    test('the hours Doum sleeps and says «صباح الخير»', () {
      DayCardMood at(int hour, {int greens = 5}) => dayCardMoodFor(
            greens: greens,
            owed: 5,
            perfectDay: greens == 5,
            hour: hour,
          );
      expect(at(21).pose, SproutPose.sleeping);
      expect(at(11, greens: 0).line, DayCardLine.morning);
      expect(at(3, greens: 0).pose, SproutPose.sleeping);

      publish(const PetEdits(
        numbers: {'bedtimeHour': 23, 'morningUntilHour': 10, 'wakeHour': 2},
      ));
      expect(at(21).pose, SproutPose.happySparkles,
          reason: 'a finished day stays awake until 23:00 now');
      expect(at(23).pose, SproutPose.sleeping);
      expect(at(11, greens: 0).line, DayCardLine.hello);
      expect(at(3, greens: 0).line, DayCardLine.morning,
          reason: 'awake from 2:00');
    });
  });
}
