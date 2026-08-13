import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';
import '../../features/dashboard/notifiers/dashboard_notifier.dart';

/// The "you're back" moment: shown once after a gap, offering either a
/// streak restore (if a freeze is banked) or a clean restart, and making the
/// point that nothing was erased.
///
/// This used to live inside the Today screen — which was reachable only by
/// tapping a notification, and by no route inside the app at all. So the one
/// screen that welcomed someone back was the one screen they could not
/// navigate to. It lives on the Grid now, the app's real home, which is where
/// a returning person actually lands.
///
/// Renders nothing unless [DashboardState.showComebackBonus] is true, so
/// callers can drop it in unconditionally.
class ComebackCard extends ConsumerWidget {
  final DashboardState state;
  const ComebackCard({super.key, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!state.showComebackBonus) return const SizedBox.shrink();
    final gp = context.gp;
    final s = S.of(context);
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.email?.split('@').first ?? 'Warrior';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: GameColors.iconXp.withOpacity(0.35), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: GameColors.iconXp.withOpacity(0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.wb_twilight_rounded,
                      color: GameColors.iconXp, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.welcomeBack(name),
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: gp.textPrimary,
                              letterSpacing: -0.2)),
                      const SizedBox(height: 2),
                      Text(s.comebackNoErase,
                          style: TextStyle(fontSize: 12.5, color: gp.textSec)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: GameColors.iconXp.withOpacity(0.1),
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded, size: 14, color: GameColors.iconXp),
                  const SizedBox(width: 6),
                  Text(s.comebackBonusHint,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: GameColors.iconXp)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (state.streakFreezes > 0 && state.previousStreak > 0) ...[
              Text(
                s.restoreStreakOffer(state.previousStreak),
                style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.4),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        ref.read(dashboardProvider.notifier).useStreakFreeze();
                      },
                      icon: const Icon(Icons.ac_unit_rounded, size: 16),
                      label: Text(s.restoreStreakCta(state.streakFreezes)),
                      style: FilledButton.styleFrom(
                          backgroundColor: GameColors.iconXp,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ref.read(dashboardProvider.notifier).acknowledgeComeback();
                  },
                  child: Text(s.freshStreakInstead),
                ),
              ),
            ] else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    ref.read(dashboardProvider.notifier).acknowledgeComeback();
                  },
                  child: Text(s.claimComeback),
                ),
              ),
          ],
        ),
      ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.08, curve: Curves.easeOut),
    );
  }
}
