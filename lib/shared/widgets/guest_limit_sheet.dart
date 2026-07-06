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
                borderRadius: BorderRadius.circular(100),
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
              child: const Icon(Icons.lock_open_rounded,
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
            const SizedBox(height: 22),
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
