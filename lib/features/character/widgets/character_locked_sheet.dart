import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../models/character_option.dart';
import 'accessory_detail_sheet.dart' show RequirementBar;

/// What a locked character says when you tap it.
///
/// This replaced a snackbar. A snackbar was the wrong shape for the
/// message twice over: it is gone in two seconds, and it can only carry a
/// sentence, so the one thing the user actually wants — to see the look
/// they cannot have yet, up close, and how far off it is — had nowhere to
/// go. A locked item should sell itself, not just refuse.
///
/// Deliberately only shown for LOCKED characters. Tapping an unlocked one
/// still selects it in a single tap; putting a sheet in front of every
/// selection would tax the common case to serve the rare one.
Future<void> showCharacterLockedSheet(
  BuildContext context,
  CharacterOption option,
) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CharacterLockedSheet(option: option),
  );
}

class _CharacterLockedSheet extends ConsumerWidget {
  final CharacterOption option;
  const _CharacterLockedSheet({required this.option});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final dash = ref.watch(dashboardProvider);
    final req = option.unlock;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: gp.surfaceHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: gp.border, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        10,
        22,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: gp.border,
              borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
            ),
          ),
          const SizedBox(height: 16),
          // The whole point of the sheet: the look, big, so it reads as
          // something worth reaching for rather than a greyed-out row.
          SizedBox(
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        GameColors.rarityEpic.withOpacity(0.16),
                        GameColors.rarityEpic.withOpacity(0),
                      ],
                    ),
                  ),
                ),
                Image.asset(option.assetPath, fit: BoxFit.contain),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            option.name(s.isAr),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: gp.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            s.closetCharacterEarned,
            style: TextStyle(fontSize: 13.5, height: 1.6, color: gp.textSec),
            textAlign: TextAlign.center,
          ),
          if (req != null) ...[
            const SizedBox(height: 16),
            RequirementBar(
              requirement: req,
              level: dash.level,
              streak: dash.streak,
              completions: dash.totalCompletions,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: gp.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: gp.border, width: 0.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_rounded, size: 15, color: gp.textTert),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      s.closetCharacterLocked(req.label(s.isAr)),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: gp.textTert,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
