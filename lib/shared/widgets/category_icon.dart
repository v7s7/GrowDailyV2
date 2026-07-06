import 'package:flutter/material.dart';

import '../../features/habits/models/habit_model.dart';

/// Drop-in replacement for `Icon(category.icon, size: x, color: y)` that
/// prefers the custom-drawn glyph art in assets/images/ (tinted to match
/// whatever color the call site wants, via [BlendMode.srcIn]) and falls
/// back to the Material icon for any category that doesn't have custom art
/// yet (currently just [HabitCategory.custom]).
class CategoryIcon extends StatelessWidget {
  final HabitCategory category;
  final double size;
  final Color color;

  const CategoryIcon({
    super.key,
    required this.category,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
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
