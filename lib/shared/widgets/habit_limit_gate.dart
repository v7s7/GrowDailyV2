import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/analytics_service.dart';
import '../../core/theme/game_theme.dart';
import '../../features/auth/notifiers/auth_notifier.dart';
import '../../features/habits/catalog/habit_plans.dart'
    show activeCatalogProvider;
import '../../features/habits/notifiers/custom_habits_notifier.dart';
import '../../features/premium/notifiers/premium_notifier.dart';
import '../../features/premium/screens/premium_screen.dart';
import 'guest_limit_sheet.dart';
import 'overlay_notice.dart';

/// One gate for every "add habit" entry point. Guests who hit their trial
/// cap are asked to create an account (existing flow); signed-in free users
/// who hit the free cap get the Premium invitation.
void showHabitLimitGate(BuildContext context, WidgetRef ref) {
  // canAddHabits says no without a count too (habitCountIsKnown), and that
  // is not a limit: the habits have not reached this phone. Say so rather
  // than sell Premium, and ask the server again for a read that failed,
  // which otherwise only the next launch would, so "try again" works.
  if (!habitCountIsKnown(ref)) {
    if (!ref.read(habitsStillLoadingProvider)) {
      if (ref.read(customHabitsProvider.notifier).loadFailed) {
        ref.invalidate(customHabitsProvider);
      }
      if (ref.read(activeCatalogProvider.notifier).loadFailed) {
        ref.invalidate(activeCatalogProvider);
      }
    }
    showOverlayNotice(
      context,
      S.of(context).habitsNotLoadedNotice,
      icon: Icons.cloud_off_rounded,
    );
    return;
  }
  AnalyticsService.instance.track('premium_gate_hit', props: {
    'gate': 'habit_limit',
    'tier': ref.read(guestModeProvider) ? 'guest' : 'free',
  });
  if (ref.read(guestModeProvider)) {
    showGuestLimitSheet(context, ref);
    return;
  }
  final gp = context.gp;
  final s = S.of(context);
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 24 + MediaQuery.of(ctx).padding.bottom),
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
              child: Icon(Icons.workspace_premium_rounded,
                  size: 28, color: context.gp.goldInk),
            ),
            const SizedBox(height: 16),
            Text(
              s.habitLimitTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.habitLimitBody(kFreeHabitLimit),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: gp.textSec, height: 1.4),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PremiumScreen(source: 'habit_limit'),
                  ),
                );
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
