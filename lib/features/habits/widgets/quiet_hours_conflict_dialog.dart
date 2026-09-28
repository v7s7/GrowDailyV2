import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';

/// The person's answer when a habit they are saving rings inside their quiet
/// hours. See [showQuietHoursConflict].
enum QuietHoursConflictAnswer {
  /// «إيه، وقّفها»: quiet hours go off, for every reminder.
  turnOff,

  /// «خلّ هذا التذكير يوصل»: only this habit rings through them, the same
  /// per-habit choice as the «اسمح به على أي حال» line under the time.
  allowThis,

  /// «لا، خلّها»: saved as it is, and the times inside quiet hours stay
  /// silent.
  keep,
}

/// Asked as a habit is saved, when a time it rings at falls inside quiet
/// hours and would never arrive (Aziz, 2026-09-28: a reminder there has to
/// say so, and ask whether to turn them off). Only ever while quiet hours
/// are on: off, every reminder rings and there is nothing to say.
///
/// [times] are the moments that would go quiet and [start] / [end] the
/// window, all already written for the reader. Closing the card without an
/// answer (a tap outside it, back) returns null: nothing is saved and the
/// form stays open, so a time picked by mistake can still be changed.
Future<QuietHoursConflictAnswer?> showQuietHoursConflict(
  BuildContext context, {
  required String times,
  required String start,
  required String end,
}) =>
    showDialog<QuietHoursConflictAnswer>(
      context: context,
      builder: (_) =>
          QuietHoursConflictCard(times: times, start: start, end: end),
    );

/// The card itself, in the shape of the daily reminder's question
/// (DailyReminderPromptCard). Public so a widget test can pump it.
class QuietHoursConflictCard extends StatelessWidget {
  const QuietHoursConflictCard({
    super.key,
    required this.times,
    required this.start,
    required this.end,
  });

  final String times;
  final String start;
  final String end;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final gp = context.gp;

    void answer(QuietHoursConflictAnswer a) {
      HapticFeedback.selectionClick();
      Navigator.pop(context, a);
    }

    return Dialog(
      backgroundColor: gp.surfaceHigh,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: gp.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: gp.goldInk.withValues(alpha: 0.14),
                ),
                child:
                    Icon(Icons.bedtime_rounded, color: gp.goldInk, size: 28),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              s.quietConflictTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.quietConflictBody(times, start, end),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.6, color: gp.textSec),
            ),
            const SizedBox(height: 4),
            Text(
              s.quietConflictQuestion,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            // Sizes on the labels, never as the button's textStyle: that
            // replaces the theme's whole style, typeface included, and the
            // label falls back to the phone's own font.
            FilledButton(
              onPressed: () => answer(QuietHoursConflictAnswer.turnOff),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                s.quietConflictTurnOff,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => answer(QuietHoursConflictAnswer.allowThis),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                s.quietConflictAllowThis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => answer(QuietHoursConflictAnswer.keep),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                foregroundColor: gp.textSec,
              ),
              child: Text(
                s.quietConflictKeep,
                style: const TextStyle(fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
