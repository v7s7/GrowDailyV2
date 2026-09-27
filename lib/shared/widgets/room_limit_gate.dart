import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/analytics_service.dart';
import '../../core/theme/game_theme.dart';
import '../../features/premium/notifiers/premium_notifier.dart';
import '../../features/premium/screens/premium_screen.dart';

/// Shows the Premium invitation to a free account that already holds
/// [kFreeRoomLimit] rooms (canTakeAnotherRoom, room_limit.dart). Opened from
/// both doors into a new room: Create on RoomsHubScreen, before the form, and
/// Join on JoinRoomSheet, after the room's preview, which is also where an
/// invite link lands.
///
/// No guest branch, unlike showHabitLimitGate: a guest never reaches Rooms
/// (RoomsHubScreen's guest gate, and main.dart sends an invite link to that
/// same screen). The body names leaving a room as well as Premium, because
/// leaving is the free way out and it is often the one wanted: somebody
/// whose challenge is winding down should not read this as "pay or nothing".
void showRoomLimitGate(BuildContext context, WidgetRef ref) {
  AnalyticsService.instance
      .track('premium_gate_hit', props: {'gate': 'room_limit'});
  final gp = context.gp;
  final s = S.of(context);
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    // Three sentences of body, the longest of the gate sheets: sized to its
    // content rather than stopped at the default 9/16 of the screen, like
    // the voice note gate after its body grew a line.
    isScrollControlled: true,
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
              child:
                  Icon(Icons.groups_rounded, size: 28, color: context.gp.goldInk),
            ),
            const SizedBox(height: 16),
            Text(
              s.roomLimitTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.roomLimitBody(kFreeRoomLimit),
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
                    builder: (_) => const PremiumScreen(
                      source: 'room_limit',
                      reason: PremiumReason.rooms,
                    ),
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
