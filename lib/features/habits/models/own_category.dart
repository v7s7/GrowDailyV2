import 'package:flutter/material.dart';

import '../catalog/islamic_habit_catalog.dart';
import 'habit_model.dart';

/// A category the person made for their own habits: a name they typed and
/// one icon from [kOwnCategoryIcons] (Aziz, 2026-10-01: "let the user choose
/// the custom category, and it be saved so he can use it later").
///
/// Underneath it is still [HabitCategory.custom]. Points, achievements,
/// rooms, charts and the admin tool all keep reading that, so a habit in a
/// category of its own pays and counts exactly as «مخصص» always has; only
/// the name and the icon a person sees are theirs.
///
/// There is no separate list to sync. The person's categories are read
/// back from their habits ([ownCategoriesFrom]), which already reach every
/// phone they sign in on, guest and account alike.
@immutable
class OwnCategory {
  /// What the person typed, trimmed.
  final String name;

  /// A key of [kOwnCategoryIcons].
  final String icon;

  const OwnCategory({required this.name, required this.icon});

  IconData get iconData => ownCategoryIcon(icon);

  /// Two categories are the same one when their names are, whatever the
  /// spaces or letter case: «رياضة» typed twice is one category.
  String get _key => name.trim().toLowerCase();

  @override
  bool operator ==(Object other) => other is OwnCategory && other._key == _key;

  @override
  int get hashCode => _key.hashCode;
}

/// The icons a category of one's own can carry, by stored key. Keys, never
/// code points, are what is saved, so an icon can be redrawn later without
/// touching a single habit.
const Map<String, IconData> kOwnCategoryIcons = {
  'star': Icons.star_rounded,
  'heart': Icons.favorite_rounded,
  'gym': Icons.fitness_center_rounded,
  'run': Icons.directions_run_rounded,
  'calm': Icons.self_improvement_rounded,
  'spa': Icons.spa_rounded,
  'book': Icons.menu_book_rounded,
  'school': Icons.school_rounded,
  'work': Icons.work_rounded,
  'code': Icons.code_rounded,
  'art': Icons.brush_rounded,
  'music': Icons.music_note_rounded,
  'food': Icons.restaurant_rounded,
  'coffee': Icons.local_cafe_rounded,
  'water': Icons.water_drop_rounded,
  'sleep': Icons.bedtime_rounded,
  'family': Icons.family_restroom_rounded,
  'pets': Icons.pets_rounded,
  'savings': Icons.savings_rounded,
  'home': Icons.home_rounded,
  'nature': Icons.eco_rounded,
  'give': Icons.volunteer_activism_rounded,
  'mosque': Icons.mosque_rounded,
  'idea': Icons.lightbulb_rounded,
};

/// The icon for a stored key, or the star «مخصص» has always used for a key
/// this build does not know.
IconData ownCategoryIcon(String? key) =>
    kOwnCategoryIcons[key] ?? Icons.star_rounded;

/// The longest name a category of one's own can have: it has to fit a pill
/// and the line «الفئة: …» under the name box.
const int kOwnCategoryNameMax = 20;

/// The person's own categories, read from [habits] (archived ones too, so a
/// category outlives the one habit that used it), one per name, in the
/// order the habits were made.
List<OwnCategory> ownCategoriesFrom(Iterable<IslamicHabitTemplate> habits) {
  final sorted = [...habits]..sort((a, b) {
      final x = a.createdAt, y = b.createdAt;
      if (x == null || y == null) return 0;
      return x.compareTo(y);
    });
  final seen = <OwnCategory>{};
  return [
    for (final h in sorted)
      if (h.ownCategory case final OwnCategory c)
        if (seen.add(c)) c,
  ];
}
