import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';
import '../../features/auth/notifiers/auth_notifier.dart';

/// Shown when a guest tries to add a habit beyond [kGuestHabitLimit].
/// Offers a clear way forward (create an account) instead of just blocking.
void showGuestLimitSheet(BuildContext context, WidgetRef ref) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // Without this, the sheet ignores the iPhone home-indicator inset and
    // its footer button can render flush with (or under) the gesture bar.
    useSafeArea: true,
    builder: (_) => const _GuestLimitSheet(),
  );
}

class _GuestLimitSheet extends ConsumerWidget {
  const _GuestLimitSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: GameColors.gold.withOpacity(0.35)),
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
            const SizedBox(height: 22),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: GameColors.gold.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_open_rounded,
                  size: 28, color: GameColors.gold),
            ),
            const SizedBox(height: 18),
            Text(
              s.guestLimitTitle,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              s.guestLimitBody,
              style: TextStyle(fontSize: 14, color: gp.textSec, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            // The durability fact, stated where it's actually actionable -
            // see S.guestDataWarning. Given its own bordered panel rather
            // than appended to the body text above so it reads as
            // information about their data, not as more sales copy for the
            // button underneath.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: gp.surface,
                borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
                border: Border.all(color: gp.border, width: 0.5),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 15, color: gp.textTert),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      // Two facts, same panel: the data lives here only,
                      // AND creating an account will not move it. The
                      // second used to be implied AWAY by the body copy
                      // ("keep your progress synced"), which promised a
                      // migration that does not exist.
                      '${s.guestDataWarning}\n\n${s.guestFreshStartWarning}',
                      style: TextStyle(
                          fontSize: 12, color: gp.textSec, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(context);
                  await setGuestMode(ref, false);
                  if (!context.mounted) return;
                  Navigator.pushNamedAndRemoveUntil(
                      context, '/', (_) => false);
                },
                child: Text(s.guestLimitCta),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.guestLimitMaybeLater),
            ),
          ],
        ),
      ),
    );
  }
}
