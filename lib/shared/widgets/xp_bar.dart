import 'package:flutter/material.dart';

import '../../core/theme/game_theme.dart';

class XpBar extends StatelessWidget {
  final double progress;
  const XpBar({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fillWidth =
            (constraints.maxWidth * progress.clamp(0.0, 1.0));
        return ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: Stack(
            children: [
              Container(
                height: 6,
                width: constraints.maxWidth,
                color: GameColors.surfaceElevated,
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                height: 6,
                width: fillWidth,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [GameColors.xpBlueDim, GameColors.xpBlue],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
