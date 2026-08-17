import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';
import '../../features/premium/notifiers/premium_notifier.dart';

/// Whether another reminder can be added to a task that already has
/// [current] of them. Thin wrapper over [canAddReminder] so widgets read
/// the entitlement without duplicating the rule — the pure function stays
/// testable without Riverpod, this handles the ref.
///
/// Watches rather than reads (unlike hasVoiceNoteAccess, which is called
/// from a tap handler): this one is called from `build` to decide whether
/// the add row renders locked, and the sheet stays open across the whole
/// upsell — tap the lock, buy Premium, come back. With a read, the lock
/// would still be sitting there afterwards until something unrelated
/// happened to rebuild the sheet.
bool canAddAnotherReminder(WidgetRef ref, int current) =>
    canAddReminder(current: current, isPremium: ref.watch(premiumProvider));

/// Shows the Premium upsell for stacking more than one reminder on a task.
///
/// Modelled on showVoiceNoteGate rather than showHabitLimitGate: there's no
/// guest/signed-in branch, because PremiumNotifier tracks premium locally
/// for guests too, so "not premium" means the same thing for everyone.
/// Unlike voice notes though, this gates a *cap* rather than a whole
/// feature — free users already get one reminder — so the copy names what
/// free includes instead of implying reminders are locked outright.
void showReminderLimitGate(BuildContext context, WidgetRef ref) {
  final gp = context.gp;
  final s = S.of(context);
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding:
          EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(ctx).padding.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: GameColors.gold.withOpacity(0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: gp.border,
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: GameColors.gold.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_active_rounded,
                size: 28,
                color: GameColors.gold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              s.reminderGateTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.reminderGateBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: gp.textSec, height: 1.4),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/premium');
              },
              icon: const Icon(Icons.workspace_premium_rounded, size: 18),
              label: Text(s.premiumCta),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.guestLimitMaybeLater),
            ),
          ],
        ),
      ),
    ),
  );
}
