// The admin's achievement-text edits, laid over the built-in name and
// description every achievement ships with.
//
// What has to hold:
//   - a malformed document costs an entry, never a screen: nothing blank,
//     nothing thrown, and the built-in text wherever an edit is unusable;
//   - an edit reaches the achievement (or family) it names, in the one
//     language it names, and never bleeds into the other language or a
//     different id;
//   - an empty or all-space edit reads as no edit, same as the built-in text
//     showing through;
//   - AchievementModel.localName/localDescription and
//     AchievementFamily.localTitle are what the whole app reads, so they are
//     what this file pins rather than the store's internals alone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/achievements/models/achievement_model.dart';
import 'package:grow_daily_v2/features/achievements/models/achievement_overrides.dart';

void main() {
  tearDown(AchievementOverridesStore.reset);

  group('reading the document', () {
    test('anything that is not a document is no edits at all', () {
      for (final junk in [null, 'text', 42, <Object?>[], <String, Object?>{}]) {
        expect(AchievementOverrides.fromData(junk).isEmpty, isTrue,
            reason: '$junk');
      }
    });

    test('a bad entry costs that entry and nothing else', () {
      final overrides = AchievementOverrides.fromData(const {
        'achievements': {
          'streak_7': {'name': 'One Full Week', 'nameAr': 7},
          'streak_30': 'not a map',
          'streak_100': {'name': '   '},
        },
        'version': 3.0,
      });
      expect(overrides.name('streak_7', false), 'One Full Week');
      expect(overrides.name('streak_7', true), isNull,
          reason: 'a non-string value costs that field, not the row');
      expect(overrides.name('streak_30', false), isNull);
      expect(overrides.name('streak_100', false), isNull,
          reason: 'all-space is the same as no edit');
      expect(overrides.version, 3);
    });

    test('a name edit does not leak into descriptions or another id', () {
      final overrides = AchievementOverrides.fromData(const {
        'achievements': {
          'streak_7': {'name': 'One Full Week'},
        },
      });
      expect(overrides.description('streak_7', false), isNull);
      expect(overrides.name('streak_30', false), isNull);
    });

    test('family titles live separately from achievement fields', () {
      final overrides = AchievementOverrides.fromData(const {
        'families': {
          'streak': {'title': 'No Breaks', 'titleAr': 'بدون توقف'},
        },
      });
      expect(overrides.familyTitle('streak', false), 'No Breaks');
      expect(overrides.familyTitle('streak', true), 'بدون توقف');
      expect(overrides.name('streak', false), isNull,
          reason: 'families and achievements never share a namespace here');
    });

    test('round-trips through toJson', () {
      final original = AchievementOverrides.fromData(const {
        'achievements': {
          'streak_7': {'name': 'One Full Week', 'description': 'Seven days'},
        },
        'families': {
          'streak': {'titleAr': 'بدون توقف'},
        },
        'version': 5,
      });
      final rebuilt = AchievementOverrides.fromData(original.toJson());
      expect(rebuilt.name('streak_7', false), 'One Full Week');
      expect(rebuilt.description('streak_7', false), 'Seven days');
      expect(rebuilt.familyTitle('streak', true), 'بدون توقف');
      expect(rebuilt.version, 5);
    });
  });

  group('AchievementModel.localName / localDescription read the store', () {
    const model = AchievementModel(
      id: 'streak_7',
      familyId: 'streak',
      name: 'A Full Week',
      nameAr: 'أسبوع كامل',
      description: 'A 7-day streak',
      descriptionAr: 'سلسلة 7 أيام متواصلة',
      tier: AchievementTier.bronze,
      trigger: AchievementTrigger.streak,
      threshold: 7,
      xpReward: 100,
      goldReward: 25,
    );

    test('no override at all: the built-in text, in either language', () {
      expect(model.localName(false), 'A Full Week');
      expect(model.localName(true), 'أسبوع كامل');
      expect(model.localDescription(false), 'A 7-day streak');
      expect(model.localDescription(true), 'سلسلة 7 أيام متواصلة');
    });

    test('an English edit changes only the English reading', () {
      AchievementOverridesStore.debugPublish(AchievementOverrides.fromData({
        'achievements': {
          'streak_7': {'name': 'One Full Week'},
        },
      }));
      expect(model.localName(false), 'One Full Week');
      expect(model.localName(true), 'أسبوع كامل',
          reason: 'the Arabic name has no edit of its own');
    });

    test('an Arabic edit changes only the Arabic reading', () {
      AchievementOverridesStore.debugPublish(AchievementOverrides.fromData({
        'achievements': {
          'streak_7': {'nameAr': 'أسبوع واحد كامل'},
        },
      }));
      expect(model.localName(true), 'أسبوع واحد كامل');
      expect(model.localName(false), 'A Full Week');
    });

    test('an edit for a different achievement never reaches this one', () {
      AchievementOverridesStore.debugPublish(AchievementOverrides.fromData({
        'achievements': {
          'streak_30': {'name': 'A Month Straight, Edited'},
        },
      }));
      expect(model.localName(false), 'A Full Week');
    });

    test('description edits are independent of name edits', () {
      AchievementOverridesStore.debugPublish(AchievementOverrides.fromData({
        'achievements': {
          'streak_7': {'description': 'Seven days in a row'},
        },
      }));
      expect(model.localDescription(false), 'Seven days in a row');
      expect(model.localName(false), 'A Full Week',
          reason: 'the name field was never touched');
    });
  });

  group('AchievementFamily.localTitle reads the store', () {
    const family = AchievementFamily(
      id: 'streak',
      title: 'Unbroken',
      titleAr: 'بدون انقطاع',
      icon: Icons.local_fire_department_rounded,
    );

    test('no override: the built-in title', () {
      expect(family.localTitle(false), 'Unbroken');
      expect(family.localTitle(true), 'بدون انقطاع');
    });

    test('an edited title overrides only the language it names', () {
      AchievementOverridesStore.debugPublish(AchievementOverrides.fromData({
        'families': {
          'streak': {'title': 'No Breaks'},
        },
      }));
      expect(family.localTitle(false), 'No Breaks');
      expect(family.localTitle(true), 'بدون انقطاع');
    });
  });
}
