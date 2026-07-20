import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';

/// The one shared "history beyond 3 months is Premium" nudge — used by
/// every month-paginated history surface (Night Review calendar, Habit
/// Notes journal) when a free account tries to browse past its window, so
/// the app tells the same story with the same words everywhere. A snackbar
/// with an Unlock action rather than a blocking sheet: the user was
/// mid-browse, not mid-purchase, and a full-screen interruption for a
/// back-arrow tap would punish curiosity.
void showHistoryLockedSnackBar(BuildContext context) {
  HapticFeedback.lightImpact();
  final gp = context.gp;
  final s = S.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(Icons.lock_clock_rounded, color: GameColors.gold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.historyLockedBody,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: gp.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
      action: SnackBarAction(
        label: s.historyLockedCta,
        textColor: GameColors.gold,
        onPressed: () => Navigator.pushNamed(context, '/premium'),
      ),
      backgroundColor: gp.surfaceHigh,
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
