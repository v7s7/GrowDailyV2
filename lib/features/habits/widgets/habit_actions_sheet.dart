import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';

/// What long-pressing a habit offers: edit, pause, delete.
///
/// Long-press used to start multi-select, which meant the three things
/// people actually want to do to ONE habit each took a different route —
/// and pausing, the most important of them, had no route at all: the only
/// removal was labelled "remove", soft-archived under the hood, and left
/// no way back once its six-second Undo expired. Multi-select moved to an
/// explicit header control, since selecting several habits is the rare
/// case and acting on one is the common one.
///
/// Pause is presented first among the destructive-ish options and worded
/// as the reversible one, because it is what most people reaching for
/// "remove" actually mean.
enum HabitAction { edit, pause, resume, deleteForever }

Future<HabitAction?> showHabitActions(
  BuildContext context, {
  required String habitName,
  /// Presets can be paused (switched off) but never permanently deleted —
  /// they belong to the catalog, not to this account, and would simply
  /// reappear in Plans. Offering Delete for them would be a button that
  /// lies about what it does.
  required bool canDeleteForever,

  /// True for a habit paused EARLIER TODAY, whose row stays on the board
  /// until the day is over so the squares it already earned don't blank
  /// out mid-day. That row is long-pressable like any other, and offering
  /// it Pause and Edit was actively wrong in both directions: Pause on a
  /// preset runs ActiveCatalogNotifier.toggle, which on an inactive id
  /// RE-ACTIVATES it while the confirmation says "paused"; Edit opens the
  /// full sheet and saves into CustomHabitsNotifier.state, which no longer
  /// holds this habit, so every change is silently dropped. A paused row
  /// gets Resume instead, and no Edit until it is back on the board.
  bool isPaused = false,
}) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<HabitAction>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _HabitActionsSheet(
      habitName: habitName,
      canDeleteForever: canDeleteForever,
      isPaused: isPaused,
    ),
  );
}

class _HabitActionsSheet extends StatelessWidget {
  final String habitName;
  final bool canDeleteForever;
  final bool isPaused;
  const _HabitActionsSheet({
    required this.habitName,
    required this.canDeleteForever,
    required this.isPaused,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
              ),
            ),
            Text(
              habitName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            if (isPaused)
              _ActionRow(
                icon: Icons.play_arrow_rounded,
                label: s.habitResume,
                subtitle: s.habitResumeHint,
                onTap: () => Navigator.pop(context, HabitAction.resume),
              )
            else ...[
              _ActionRow(
                icon: Icons.edit_outlined,
                label: s.habitEdit,
                onTap: () => Navigator.pop(context, HabitAction.edit),
              ),
              Divider(color: gp.divider, height: 1),
              _ActionRow(
                icon: Icons.pause_circle_outline_rounded,
                label: s.habitPause,
                subtitle: s.habitPauseHint,
                onTap: () => Navigator.pop(context, HabitAction.pause),
              ),
            ],
            if (canDeleteForever) ...[
              Divider(color: gp.divider, height: 1),
              _ActionRow(
                icon: Icons.delete_outline_rounded,
                label: s.habitDeleteForever,
                destructive: true,
                onTap: () =>
                    Navigator.pop(context, HabitAction.deleteForever),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool destructive;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final tint = destructive ? GameColors.error : gp.textPrimary;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: tint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tint,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: gp.textSec,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one confirmation in this flow, and the reason Pause can be
/// one-tap: deleting forever names the habit, says the history goes with
/// it, and points at pausing as the alternative.
Future<bool> confirmDeleteForever(
  BuildContext context, {
  required String habitName,
}) async {
  final gp = context.gp;
  final s = S.of(context);
  HapticFeedback.heavyImpact();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: gp.surfaceHigh,
      title: Text(
        s.habitDeleteForever,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: gp.textPrimary,
        ),
      ),
      content: Text(
        s.habitDeleteForeverBody(habitName),
        style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(s.habitActionsCancel,
              style: TextStyle(fontSize: 13, color: gp.textSec)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            s.habitDeleteForeverConfirm,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: GameColors.error,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
