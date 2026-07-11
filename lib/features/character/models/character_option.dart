/// Which of the two character sets a [CharacterOption] belongs to — purely
/// a catalog grouping so the closet screen can show "male" and "female"
/// tabs/sections. Not tied to any account field; the user just picks
/// whichever character they like.
enum CharacterGender { male, female }

/// A single selectable character. All six are available from the start —
/// unlike accessories, characters themselves are never gold-gated, so
/// switching your look is always free and instant.
class CharacterOption {
  final String id;
  final String assetPath;
  final CharacterGender gender;
  final String nameEn;
  final String nameAr;

  const CharacterOption({
    required this.id,
    required this.assetPath,
    required this.gender,
    required this.nameEn,
    required this.nameAr,
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
  );

  static const male3 = CharacterOption(
    id: 'male_shmagh_red',
    assetPath: 'assets/images/character/male_shmagh_red.png',
    gender: CharacterGender.male,
    nameEn: 'Red Shemagh',
    nameAr: 'الشماغ الأحمر',
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
  );

  static const List<CharacterOption> males = [male1, male2, male3];
  static const List<CharacterOption> females = [female1, female2, female3];
  static const List<CharacterOption> all = [...males, ...females];

  static List<CharacterOption> forGender(CharacterGender gender) =>
      gender == CharacterGender.male ? males : females;

  /// Falls back to [male1] when [id] is null/unknown, so a fresh account (or
  /// one whose saved id has gone stale) always has something valid to render
  /// rather than the caller needing its own null-handling at every call site.
  static CharacterOption findByIdOrDefault(String? id) {
    if (id == null) return male1;
    for (final c in all) {
      if (c.id == id) return c;
    }
    return male1;
  }
}
