import 'package:flutter/material.dart';

import '../../../core/theme/game_theme.dart';

/// A single selectable language row — used by both the first-launch
/// language picker screen and the Settings language sheet, so the two
/// entry points feel like the same picker. Deliberately typography-only
/// (native script + a checkmark on selection), no flag emojis.
class LanguageOptionCard extends StatelessWidget {
  final String nativeName;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;
  final TextDirection textDirection;

  const LanguageOptionCard({
    super.key,
    required this.nativeName,
    required this.selected,
    required this.onTap,
    this.dimmed = false,
    this.textDirection = TextDirection.ltr,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return AnimatedScale(
      scale: selected ? 1.03 : 1.0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: dimmed ? 0.4 : 1.0,
        duration: const Duration(milliseconds: 220),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: selected ? GameColors.gold.withOpacity(0.12) : gp.surface,
                borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                border: Border.all(
                  color: selected ? GameColors.gold : gp.border,
                  width: selected ? 1.4 : 0.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Directionality(
                      textDirection: textDirection,
                      child: Text(
                        nativeName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: gp.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.check_circle_rounded,
                        size: 22, color: GameColors.gold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
