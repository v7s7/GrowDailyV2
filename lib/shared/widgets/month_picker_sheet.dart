import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';
import '../../core/utils/western_digits.dart';
import 'choice_chip_grid.dart';
import 'history_locked_snackbar.dart';

/// Pick a month directly, instead of stepping one arrow-tap at a time.
///
/// Arrows alone are fine over three or four months. Over a year they are
/// eleven taps to reach last January, and — worse — they say nothing about
/// how far back the range even goes. A screen whose range had silently
/// collapsed to a single month looked, through arrows alone, exactly like a
/// screen that was working: two dim chevrons and no explanation. Showing
/// every month at once makes the range itself visible, which is the real
/// reason this exists rather than convenience.
///
/// Returns the chosen month (normalised to the 1st), or null if dismissed.
/// A locked month does NOT return: it shows the same history-locked
/// snackbar every other history surface uses and leaves the sheet open, so
/// someone who taps a Premium month can immediately pick a free one instead
/// of being bounced out and having to reopen the picker.
Future<DateTime?> showMonthPicker(
  BuildContext context, {
  required List<DateTime> months,
  required DateTime selected,
  required bool Function(DateTime month) isUnlocked,
  required bool Function(DateTime month) hasStory,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MonthPickerSheet(
      months: months,
      selected: selected,
      isUnlocked: isUnlocked,
      hasStory: hasStory,
    ),
  );
}

class _MonthPickerSheet extends StatelessWidget {
  final List<DateTime> months;
  final DateTime selected;
  final bool Function(DateTime month) isUnlocked;
  final bool Function(DateTime month) hasStory;

  const _MonthPickerSheet({
    required this.months,
    required this.selected,
    required this.isUnlocked,
    required this.hasStory,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;

    // Newest year first, matching the newest-first month list itself.
    final years = <int, List<DateTime>>{};
    for (final m in months) {
      (years[m.year] ??= []).add(m);
    }
    final orderedYears = years.keys.toList()..sort((a, b) => b.compareTo(a));

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
              ),
            ),
            Text(
              s.monthPickerTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                children: [
                  for (final year in orderedYears) ...[
                    // The year is its own heading rather than part of every
                    // chip: "أغسطس ٢٠٢٦" twelve times over would not fit a
                    // three-column grid without ellipsising the month name,
                    // which is the only part that distinguishes the cells.
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        toWesternDigits(year.toString()),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: gp.textTert,
                        ),
                      ),
                    ),
                    ChoiceChipGrid(
                      columns: 3,
                      items: [
                        for (final month in years[year]!)
                          _MonthChip(
                            month: month,
                            locale: locale,
                            selected: month.year == selected.year &&
                                month.month == selected.month,
                            unlocked: isUnlocked(month),
                            hasStory: hasStory(month),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One month cell, in one of four states: selected, has-a-story, empty, or
/// locked.
///
/// Empty is dimmed less than locked (0.55 against 0.35) and keeps its full
/// tap behaviour, because an empty month is a real month you are allowed to
/// look at — it is just where your history has not started yet. Telling the
/// two apart at a glance is what stops a long run of months you never used
/// from reading as a broken picker.
class _MonthChip extends StatelessWidget {
  final DateTime month;
  final String locale;
  final bool selected;
  final bool unlocked;
  final bool hasStory;

  const _MonthChip({
    required this.month,
    required this.locale,
    required this.selected,
    required this.unlocked,
    required this.hasStory,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final label = westernDate(month, 'MMMM', locale);
    final year = toWesternDigits(month.year.toString());
    final chip = PlainChoiceChip(
      selected: selected,
      label: label,
      // Spelled out, because a screen reader hearing "أغسطس" alone learns
      // neither the year (the grid's year heading is a separate node) nor
      // that this one is out of reach.
      semanticsLabel:
          unlocked ? '$label $year' : '$label $year, ${s.monthPickerLocked}',
      icon: unlocked
          ? null
          : Icon(Icons.lock_rounded, size: 13, color: context.gp.textTert),
      onTap: () {
        if (!unlocked) {
          // Deliberately does NOT pop. See showMonthPicker's doc comment.
          showHistoryLockedSnackBar(context);
          return;
        }
        HapticFeedback.selectionClick();
        Navigator.pop(context, month);
      },
    );
    if (selected || (unlocked && hasStory)) return chip;
    // Dimmed but still tappable, deliberately — the same call
    // ReminderPicker's out-of-reach offsets make. An IgnorePointer here
    // would make a locked month silently swallow taps, which reads as a
    // broken control rather than a locked one.
    return Opacity(opacity: unlocked ? 0.55 : 0.35, child: chip);
  }
}
