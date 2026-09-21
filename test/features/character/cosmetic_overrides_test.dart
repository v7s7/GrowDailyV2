// The admin's character/accessory-text edits, laid over the built-in name
// and description every character and closet item ships with.
//
// Same invariants as achievement_overrides_test.dart, for the same reasons:
// a malformed document costs an entry, never a screen; an edit reaches only
// the id and language it names; and CharacterOption.name/Accessory.name/
// Accessory.description/AccessoryCategory.label — what the app actually
// reads — are what this file pins.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grow_daily_v2/features/achievements/models/achievement_model.dart'
    show AchievementRarity;
import 'package:grow_daily_v2/features/character/models/accessory.dart';
import 'package:grow_daily_v2/features/character/models/character_option.dart';
import 'package:grow_daily_v2/features/character/models/cosmetic_overrides.dart';
import 'package:grow_daily_v2/features/character/models/prestige_tier.dart';

void main() {
  tearDown(CosmeticOverridesStore.reset);

  group('reading the document', () {
    test('anything that is not a document is no edits at all', () {
      for (final junk in [null, 'text', 42, <Object?>[], <String, Object?>{}]) {
        expect(CosmeticOverrides.fromData(junk).isEmpty, isTrue, reason: '$junk');
      }
    });

    test('a bad entry costs that entry and nothing else', () {
      final overrides = CosmeticOverrides.fromData(const {
        'characters': {
          'male_ghutra_blue': {'name': 'The Blue Ghutra', 'nameAr': 7},
          'male_bisht_gold': 'not a map',
        },
      });
      expect(overrides.characterName('male_ghutra_blue', false), 'The Blue Ghutra');
      expect(overrides.characterName('male_ghutra_blue', true), isNull);
      expect(overrides.characterName('male_bisht_gold', false), isNull);
    });

    test('characters, accessories and categories never share a namespace',
        () {
      final overrides = CosmeticOverrides.fromData(const {
        'characters': {
          'misbah': {'name': 'Should not apply to the category'},
        },
        'categories': {
          'misbah': {'label': 'Prayer Beads'},
        },
      });
      expect(overrides.characterName('misbah', false),
          'Should not apply to the category');
      expect(overrides.categoryLabel('misbah', false), 'Prayer Beads');
      expect(overrides.accessoryName('misbah', false), isNull);
    });

    test('round-trips through toJson', () {
      final original = CosmeticOverrides.fromData(const {
        'characters': {
          'male_ghutra_blue': {'name': 'The Blue Ghutra'},
        },
        'accessories': {
          'misbah_amber': {'description': 'A shinier one'},
        },
        'categories': {
          'misbah': {'labelAr': 'سبحة'},
        },
        'version': 4,
      });
      final rebuilt = CosmeticOverrides.fromData(original.toJson());
      expect(rebuilt.characterName('male_ghutra_blue', false), 'The Blue Ghutra');
      expect(rebuilt.accessoryDescription('misbah_amber', false), 'A shinier one');
      expect(rebuilt.categoryLabel('misbah', true), 'سبحة');
      expect(rebuilt.version, 4);
    });
  });

  group('CharacterOption.name reads the store', () {
    const character = CharacterOption(
      id: 'male_ghutra_blue',
      assetPath: 'assets/images/character/male_ghutra_blue.png',
      gender: CharacterGender.male,
      nameEn: 'Blue Ghutra',
      nameAr: 'الغترة الزرقاء',
    );

    test('no override: the built-in name', () {
      expect(character.name(false), 'Blue Ghutra');
      expect(character.name(true), 'الغترة الزرقاء');
    });

    test('an edit changes only the language it names', () {
      CosmeticOverridesStore.debugPublish(CosmeticOverrides.fromData({
        'characters': {
          'male_ghutra_blue': {'name': 'The Blue Ghutra'},
        },
      }));
      expect(character.name(false), 'The Blue Ghutra');
      expect(character.name(true), 'الغترة الزرقاء');
    });

    test('an edit for a different character never reaches this one', () {
      CosmeticOverridesStore.debugPublish(CosmeticOverrides.fromData({
        'characters': {
          'male_bisht_gold': {'name': 'Edited'},
        },
      }));
      expect(character.name(false), 'Blue Ghutra');
    });
  });

  group('Accessory.name / description read the store', () {
    const accessory = Accessory(
      id: 'misbah_amber',
      category: AccessoryCategory.misbah,
      nameEn: 'Amber Tasbih',
      nameAr: 'مسباح كهرمان',
      descriptionEn: 'A calm companion.',
      descriptionAr: 'رفيق هادئ.',
      imagePath: 'assets/images/accessories/misbah_amber.png',
      color: Color(0xFFD69A2D),
      rarity: AchievementRarity.common,
      goldCost: 0,
    );

    test('no override: the built-in name and description', () {
      expect(accessory.name(false), 'Amber Tasbih');
      expect(accessory.description(false), 'A calm companion.');
    });

    test('name and description edit independently', () {
      CosmeticOverridesStore.debugPublish(CosmeticOverrides.fromData({
        'accessories': {
          'misbah_amber': {'description': 'A shinier one'},
        },
      }));
      expect(accessory.description(false), 'A shinier one');
      expect(accessory.name(false), 'Amber Tasbih',
          reason: 'only the description field was edited');
    });
  });

  group('AccessoryCategory.label reads the store', () {
    test('no override: the built-in label', () {
      expect(AccessoryCategory.misbah.label(false), 'Tasbih');
      expect(AccessoryCategory.misbah.label(true), 'مسباح');
    });

    test('an edited label overrides only the language it names', () {
      CosmeticOverridesStore.debugPublish(CosmeticOverrides.fromData({
        'categories': {
          'misbah': {'label': 'Prayer Beads'},
        },
      }));
      expect(AccessoryCategory.misbah.label(false), 'Prayer Beads');
      expect(AccessoryCategory.misbah.label(true), 'مسباح');
      expect(AccessoryCategory.umbrella.label(false), 'Umbrella',
          reason: 'a different category must be untouched');
    });
  });

  group('PrestigeTier.title reads the store', () {
    test('no override: the built-in title', () {
      final tier = PrestigeCatalog.findById('resolute')!;
      expect(tier.title(false), 'Persistent');
      expect(tier.title(true), 'المثابر');
    });

    test('an edited title overrides only the language it names', () {
      CosmeticOverridesStore.debugPublish(CosmeticOverrides.fromData({
        'prestige': {
          'resolute': {'title': 'Committed'},
        },
      }));
      final tier = PrestigeCatalog.findById('resolute')!;
      expect(tier.title(false), 'Committed');
      expect(tier.title(true), 'المثابر');
      expect(PrestigeCatalog.findById('radiant')!.title(false), 'Steadfast',
          reason: 'a different tier must be untouched');
    });
  });
}
