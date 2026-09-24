import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';

/// The person's answer to «متى يناسبك التذكير؟». See daily_reminder_prompt.dart.
sealed class DailyReminderPromptAnswer {
  const DailyReminderPromptAnswer();
}

/// They picked a time: the daily reminder is set to it.
final class DailyReminderPromptPicked extends DailyReminderPromptAnswer {
  const DailyReminderPromptPicked(this.time);
  final TimeOfDay time;
}

/// «بعدين»: asked again in three days, once.
final class DailyReminderPromptLater extends DailyReminderPromptAnswer {
  const DailyReminderPromptLater();
}

/// «لا، شكرًا»: never asked again.
final class DailyReminderPromptNever extends DailyReminderPromptAnswer {
  const DailyReminderPromptNever();
}

/// The time offered first, marked «بعد العشاء». 21:00 is after Isha all
/// year in Bahrain's official table (Isha falls between 18:06 and 20:04 in
/// 2026), late enough that the day's habits have had their chance, early
/// enough to still do one.
const TimeOfDay kDailyReminderSuggestedTime = TimeOfDay(hour: 21, minute: 0);

/// The ready times, in the order they are laid out: one tap sets one.
const List<TimeOfDay> kDailyReminderPromptTimes = [
  TimeOfDay(hour: 20, minute: 30),
  kDailyReminderSuggestedTime,
  TimeOfDay(hour: 22, minute: 0),
];

/// Shows the question and returns the answer. The person closing it without
/// a choice (a tap outside the card, back) answers «بعدين»; null means the
/// app closed it, not the person (a link from outside clears the screen),
/// and nothing was answered.
///
/// Design ج of the canvas Aziz picked on 2026-09-24
/// (https://claude.ai/artifact/4cevfZ7WPfYCaTALXbed5k): the app's
/// announcement card with three ready times and «وقت ثاني», one tap to set.
/// [lastAsk] is the second and final time: no «بعدين» (one that meant
/// "never" would say one thing and do another), and a line that says so.
Future<DailyReminderPromptAnswer?> showDailyReminderPrompt(
  BuildContext context, {
  bool lastAsk = false,
}) =>
    showDialog<DailyReminderPromptAnswer>(
      context: context,
      builder: (_) => DailyReminderPromptCard(lastAsk: lastAsk),
    );

/// The card itself. Public so a widget test can pump it.
class DailyReminderPromptCard extends StatelessWidget {
  const DailyReminderPromptCard({super.key, this.lastAsk = false});

  final bool lastAsk;

  Future<void> _otherTime(BuildContext context) async {
    HapticFeedback.selectionClick();
    final picked = await showTimePicker(
      context: context,
      initialTime: kDailyReminderSuggestedTime,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    // Backing out of the clock returns to the card, not to a «بعدين».
    if (picked != null && context.mounted) {
      Navigator.pop(context, DailyReminderPromptPicked(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final gp = context.gp;

    Widget timeChoice(TimeOfDay time) {
      final suggested = time == kDailyReminderSuggestedTime;
      return _Choice(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.pop(context, DailyReminderPromptPicked(time));
        },
        highlighted: suggested,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              time.format(context),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: gp.textPrimary,
              ),
            ),
            if (suggested)
              Text(
                s.dailyReminderPromptAfterIsha,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: gp.goldInk,
                ),
              ),
          ],
        ),
      );
    }

    // Closed by the person without a choice: that is «بعدين» (on the last
    // ask, the same as a second one). The app closing it pops past this
    // with no answer, and the caller keeps nothing (see
    // showDailyReminderPrompt).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, const DailyReminderPromptLater());
      },
      child: Dialog(
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
                  child: Icon(Icons.notifications_rounded,
                      color: gp.goldInk, size: 28),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                s.dailyReminderPromptTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.dailyReminderPromptBody,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.6, color: gp.textSec),
              ),
              if (lastAsk) ...[
                const SizedBox(height: 4),
                Text(
                  s.dailyReminderPromptLastAsk,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: gp.textPrimary,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.3,
                children: [
                  for (final time in kDailyReminderPromptTimes)
                    timeChoice(time),
                  _Choice(
                    onTap: () => _otherTime(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.schedule_rounded,
                            size: 18, color: gp.textSec),
                        const SizedBox(width: 6),
                        Text(
                          s.dailyReminderPromptOtherTime,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: gp.textSec,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!lastAsk) ...[
                    TextButton(
                      onPressed: () => Navigator.pop(
                          context, const DailyReminderPromptLater()),
                      style: TextButton.styleFrom(
                        foregroundColor: gp.textPrimary,
                        minimumSize: const Size(88, 44),
                      ),
                      child: Text(
                        s.dailyReminderPromptLater,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  TextButton(
                    onPressed: () => Navigator.pop(
                        context, const DailyReminderPromptNever()),
                    style: TextButton.styleFrom(
                      foregroundColor: gp.textSec,
                      minimumSize: const Size(88, 44),
                    ),
                    child: Text(
                      s.dailyReminderPromptNever,
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                ],
              ),
              Text(
                lastAsk
                    ? s.dailyReminderPromptLastHint
                    : s.dailyReminderPromptSettingsHint,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: gp.textTert),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tappable choice in the grid: a ready time or «وقت ثاني».
class _Choice extends StatelessWidget {
  const _Choice({
    required this.onTap,
    required this.child,
    this.highlighted = false,
  });

  final VoidCallback onTap;
  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Material(
      color: gp.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: highlighted ? gp.goldEdge : gp.border,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}
