import 'accessory.dart';

/// Which of the two character sets a [CharacterOption] belongs to — purely
/// a catalog grouping so the closet screen can show "male" and "female"
/// tabs/sections. Not tied to any account field; the user just picks
/// whichever character they like.
enum CharacterGender { male, female }

/// A single selectable character.
///
/// Characters are never GOLD-gated: money buys accessories, progress buys
/// characters. The distinction is deliberate. The character is the loudest
/// thing about your avatar, it is what other people see on a room
/// leaderboard, and giving all fifteen away at once made the single most
/// visible choice in the app the only one you never earned.
///
/// [unlock] null means free from the start. Only the plainest looks are:
/// a head covering and nothing over it. Every bisht and every daglah is
/// earned, the gold bisht included.
///
/// GATING A PREVIOUSLY FREE LOOK IS NOT RETROACTIVE. The picker never
/// locks the character somebody is currently wearing (see the `!selected`
/// term in its lock test), so an existing account keeps what it has. It
/// can, however, lose access by switching away and back, which is the
/// accepted cost of moving the gold bisht behind level 20.
class CharacterOption {
  final String id;
  final String assetPath;
  final CharacterGender gender;
  final String nameEn;
  final String nameAr;

  /// What this look costs in PROGRESS. Null for the founding six.
  final UnlockRequirement? unlock;

  const CharacterOption({
    required this.id,
    required this.assetPath,
    required this.gender,
    required this.nameEn,
    required this.nameAr,
    this.unlock,
  });

  String name(bool isAr) => isAr ? nameAr : nameEn;
}

/// Static catalog of every character — three male, three female. Ids and
/// asset paths match the art shipped under assets/images/character/.
abstract final class CharacterCatalog {
  static const male1 = CharacterOption(
    id: 'male_ghutra_blue',
    assetPath: 'assets/images/character/male_ghutra_blue.png',
    gender: CharacterGender.male,
    nameEn: 'Blue Ghutra',
    nameAr: 'الغترة الزرقاء',
  );

  static const male2 = CharacterOption(
    id: 'male_bisht_gold',
    assetPath: 'assets/images/character/male_bisht_gold.png',
    gender: CharacterGender.male,
    nameEn: 'Gold Bisht',
    nameAr: 'البشت الذهبي',
    unlock: const UnlockRequirement(UnlockMetric.level, 20),
  );

  static const female1 = CharacterOption(
    id: 'female_hijab_pink',
    assetPath: 'assets/images/character/female_hijab_pink.png',
    gender: CharacterGender.female,
    nameEn: 'Pink Hijab',
    nameAr: 'الحجاب الوردي',
  );

  static const female2 = CharacterOption(
    id: 'female_niqab',
    assetPath: 'assets/images/character/female_niqab.png',
    gender: CharacterGender.female,
    nameEn: 'Niqab',
    nameAr: 'النقاب',
  );

  static const female3 = CharacterOption(
    id: 'female_hijab_teal',
    assetPath: 'assets/images/character/female_hijab_teal.png',
    gender: CharacterGender.female,
    nameEn: 'Embroidered Look',
    nameAr: 'الزي المطرز',
    unlock: const UnlockRequirement(UnlockMetric.level, 8),
  );


  static const male4 = CharacterOption(
    id: 'male_bisht_black',
    assetPath: 'assets/images/character/male_bisht_black.png',
    gender: CharacterGender.male,
    nameEn: 'Black Bisht',
    nameAr: 'البشت الأسود',
    unlock: const UnlockRequirement(UnlockMetric.level, 24),
  );

  static const male5 = CharacterOption(
    id: 'male_bisht_grey',
    assetPath: 'assets/images/character/male_bisht_grey.png',
    gender: CharacterGender.male,
    nameEn: 'Grey Bisht',
    nameAr: 'البشت الرمادي',
    unlock: const UnlockRequirement(UnlockMetric.level, 10),
  );

  static const male6 = CharacterOption(
    id: 'male_thobe_cream',
    assetPath: 'assets/images/character/male_thobe_cream.png',
    gender: CharacterGender.male,
    nameEn: 'Cream Thobe',
    nameAr: 'الثوب الكريمي',
  );

  static const male7 = CharacterOption(
    id: 'male_daglah_brown',
    assetPath: 'assets/images/character/male_daglah_brown.png',
    gender: CharacterGender.male,
    nameEn: 'Brown Daglah',
    nameAr: 'الدقلة البنية',
    unlock: const UnlockRequirement(UnlockMetric.level, 16),
  );

  static const male8 = CharacterOption(
    id: 'male_daglah_navy',
    assetPath: 'assets/images/character/male_daglah_navy.png',
    gender: CharacterGender.male,
    nameEn: 'Navy Daglah',
    nameAr: 'الدقلة الكحلية',
    unlock: const UnlockRequirement(UnlockMetric.level, 18),
  );

  static const male9 = CharacterOption(
    id: 'male_daglah_maroon',
    assetPath: 'assets/images/character/male_daglah_maroon.png',
    gender: CharacterGender.male,
    nameEn: 'Maroon Daglah',
    nameAr: 'الدقلة العنابية',
    unlock: const UnlockRequirement(UnlockMetric.level, 21),
  );

  static const male10 = CharacterOption(
    id: 'male_daglah_olive',
    assetPath: 'assets/images/character/male_daglah_olive.png',
    gender: CharacterGender.male,
    nameEn: 'Olive Daglah',
    nameAr: 'الدقلة الزيتية',
    unlock: const UnlockRequirement(UnlockMetric.level, 23),
  );

  static const female4 = CharacterOption(
    id: 'female_abaya_navy',
    assetPath: 'assets/images/character/female_abaya_navy.png',
    gender: CharacterGender.female,
    nameEn: 'Navy Abaya',
    nameAr: 'العباءة الكحلية',
    unlock: const UnlockRequirement(UnlockMetric.level, 12),
  );

  static const female5 = CharacterOption(
    id: 'female_hijab_olive',
    assetPath: 'assets/images/character/female_hijab_olive.png',
    gender: CharacterGender.female,
    nameEn: 'Olive Look',
    nameAr: 'الزي الزيتي',
    unlock: const UnlockRequirement(UnlockMetric.level, 14),
  );

  static const male11 = CharacterOption(
    id: 'male_daglah_black',
    assetPath: 'assets/images/character/male_daglah_black.png',
    gender: CharacterGender.male,
    nameEn: 'Black Daglah',
    nameAr: 'الدقلة السوداء',
    unlock: const UnlockRequirement(UnlockMetric.level, 25),
  );

  // The daglah and farwa looks are winter dress from Najd: a long robe
  // with a front opening, long sleeves and a high collar, worn over the
  // thobe. Deliberately distinct from a bisht, which is a loose open
  // cloak with wide sleeves and chest tassels.
  static const List<CharacterOption> males = [
    male1, male2, male4, male5, male6, male7, male8, male9, male10, male11,
  ];
  static const List<CharacterOption> females = [
    female1, female2, female3, female4, female5,
  ];
  static const List<CharacterOption> all = [...males, ...females];

  static List<CharacterOption> forGender(CharacterGender gender) =>
      gender == CharacterGender.male ? males : females;

  /// Falls back to [male1] when [id] is null/unknown, so a fresh account (or
  /// one whose saved id has gone stale) always has something valid to render
  /// rather than the caller needing its own null-handling at every call site.
  static CharacterOption findByIdOrDefault(String? id) {
    return findById(id) ?? male1;
  }

  /// The character [id] names, or null when it names none.
  ///
  /// The nullable counterpart to [findByIdOrDefault], for the one place the
  /// distinction matters: **somebody else's** avatar. Falling back to [male1]
  /// is right for your own account — you always have something to render and
  /// the closet will correct it the moment you open it. It is wrong for a
  /// room leaderboard, because male1 is a real character somebody may
  /// genuinely have chosen, so an unknown or missing id renders as a
  /// specific person's look with nothing to say it's a guess. Two members
  /// then appear identical, and the row shows a face that isn't theirs.
  ///
  /// Callers rendering another member use this and draw a neutral
  /// placeholder on null — see _LeaderboardRow.
  static CharacterOption? findById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }
}
