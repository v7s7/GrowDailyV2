import 'package:flutter/material.dart';

import '../../features/habits/models/habit_model.dart';
import '../../features/habits/models/own_category.dart';

/// Drop-in replacement for `Icon(category.icon, size: x, color: y)` that
/// prefers the custom-drawn glyph art in assets/images/ (tinted to match
/// whatever color the call site wants, via [BlendMode.srcIn]) and falls
/// back to the Material icon for any category that doesn't have custom art
/// yet (currently just [HabitCategory.custom]).
///
/// [ownIcon] is a [HabitCategory.custom] habit's own category icon key (see
/// OwnCategory); it wins over the star whenever there is one.
class CategoryIcon extends StatelessWidget {
  final HabitCategory category;
  final double size;
  final Color color;
  final String? ownIcon;

  const CategoryIcon({
    super.key,
    required this.category,
    required this.size,
    required this.color,
    this.ownIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (category == HabitCategory.custom && ownIcon != null) {
      return Icon(ownCategoryIcon(ownIcon), size: size, color: color);
    }
    final asset = category.iconAsset;
    if (asset == null) {
      return Icon(category.icon, size: size, color: color);
    }
    return Image.asset(
      asset,
      width: size,
      height: size,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
    );
  }
}
