import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';
import '../../features/premium/notifiers/premium_notifier.dart';

/// Whether the current account can use voice notes. A single bool check —
/// call this before showing a mic button at all, not just before recording,
/// so free users see a locked affordance rather than a working one that
/// then gates on tap.
bool hasVoiceNoteAccess(WidgetRef ref) => ref.read(premiumProvider);

/// Shows the Premium upsell for voice notes.
///
/// Unlike showHabitLimitGate, there's no guest/signed-in branch here:
/// PremiumNotifier tracks premium locally for guests too, so "not premium"
/// means the same thing — and gets the same upsell — for everyone. Voice
/// notes are gated as a whole feature (like the extended heatmap), not a
/// numeric cap, so there's no "limit" number to show, just what the feature
/// does and that Premium unlocks it.
void showVoiceNoteGate(BuildContext context, WidgetRef ref) {
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
                borderRadius: BorderRadius.circular(100),
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
              child: Icon(Icons.mic_rounded, size: 28, color: GameColors.gold),
            ),
            const SizedBox(height: 16),
            Text(
              s.voiceNoteGateTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.voiceNoteGateBody,
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
