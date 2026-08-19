import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/extensions/datetime_ext.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';
import '../../core/utils/western_digits.dart';
import 'choice_chip_grid.dart';

/// Pick a week directly, instead of stepping one arrow-tap at a time.
///
/// The Grid's own week arrows move exactly seven days per tap, so last
/// month is four taps away and last spring is thirty. Worse, the arrows
/// alone never say how far back the board even goes — someone looking for
/// a week they know they filled in has no way to aim at it.
///
/// Same shape as [showMonthPicker], deliberately: month headings over a
/// grid of chips, newest first, the current one marked. A week's label is
/// its date span rather than a number, because nobody thinks in ISO week
/// numbers — «١٥ – ٢١ أغسطس» is the thing you actually remember.
///
/// Returns the chosen week's start (always a Saturday, normalised through
/// [startOfDisplayWeek]), or null if dismissed.
Future<DateTime?> showWeekPicker(
  BuildContext context, {
  /// Newest first. Every entry must already be a week start.
  required List<DateTime> weeks,
  required DateTime selected,
  /// Weeks with nothing recorded still render and stay tappable — an empty
  /// week is a real week you are allowed to look at. This only decides
  /// which ones get the brighter treatment.
  required bool Function(DateTime weekStart) hasData,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _WeekPickerSheet(
      weeks: weeks,
      selected: selected,
      hasData: hasData,
    ),
  );
}

/// Every week start from [earliest] up to and including the week holding
/// [latest], newest first.
///
/// Both ends are normalised to their Saturday through [startOfDisplayWeek]
/// (which is exactly what the Grid's own startOfGridWeek wraps), so a
/// caller can pass any day in a week and get a list that lines up with the
/// Grid's weeks without this shared widget importing a feature notifier.
/// Capped at [maxWeeks] (about eight years) for the same reason the month
/// list is capped: a corrupt or absurd earliest date must not build a list
/// long enough to hang the sheet.
List<DateTime> weeksBetween(
  DateTime earliest,
  DateTime latest, {
  int maxWeeks = 416,
}) {
  final first = earliest.startOfDisplayWeek;
  var cursor = latest.startOfDisplayWeek;
  final out = <DateTime>[];
  while (!cursor.isBefore(first) && out.length < maxWeeks) {
    out.add(cursor);
    cursor = cursor.subtract(const Duration(days: 7));
  }
  return out;
}

/// "11 – 17 يوليو", or "29 أغسطس – 4 سبتمبر" when the week straddles two
/// months — the label for one Saturday-anchored week.
///
/// Day before month, and ASCII digits, in both languages. Not
/// `DateFormat('MMM d')`: that pattern is wrong twice over in Arabic, which
/// reads "19 يوليو" rather than "يوليو 19" and does not use Arabic-Indic
/// digits anywhere else in this app (see westernDate's own doc comment).
/// The month is named once inside a single month and twice across a
/// boundary, because «29 أغسطس – 4» reads as a four-day week.
String weekSpanLabel(DateTime weekStart, String locale) {
  final end = weekStart.add(const Duration(days: 6));
  final startDay = toWesternDigits(weekStart.day.toString());
  final endDay = toWesternDigits(end.day.toString());
  if (weekStart.month == end.month) {
    return '$startDay – $endDay ${westernDate(weekStart, 'MMM', locale)}';
  }
  return '$startDay ${westernDate(weekStart, 'MMM', locale)} – '
      '$endDay ${westernDate(end, 'MMM', locale)}';
}

class _WeekPickerSheet extends StatelessWidget {
  final List<DateTime> weeks;
  final DateTime selected;
  final bool Function(DateTime weekStart) hasData;

  const _WeekPickerSheet({
    required this.weeks,
    required this.selected,
    required this.hasData,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final thisWeek = DateTime.now().startOfDisplayWeek;

    // Grouped by the month the week STARTS in. A week that straddles two
    // months lands under its Saturday's month, which is the same rule the
    // Grid's own header uses when it labels the span.
    final groups = <DateTime, List<DateTime>>{};
    for (final w in weeks) {
      groups.putIfAbsent(DateTime(w.year, w.month), () => []).add(w);
    }
    final orderedMonths = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a));

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
              s.weekPickerTitle,
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
                  for (final month in orderedMonths) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${westernDate(month, 'MMMM', locale)} '
                        '${toWesternDigits(month.year.toString())}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: gp.textTert,
                        ),
                      ),
                    ),
                    ChoiceChipGrid(
                      columns: 2,
                      items: [
                        for (final week in groups[month]!)
                          _WeekChip(
                            weekStart: week,
                            locale: locale,
                            selected: week.isSameDayAs(selected),
                            isThisWeek: week.isSameDayAs(thisWeek),
                            hasData: hasData(week),
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

/// One week cell, labelled by its span.
///
/// Two columns rather than the month picker's three: «١٥ – ٢١ أغسطس» is
/// roughly twice the width of «أغسطس», and squeezing it into three would
/// ellipsise the very digits that identify the week.
class _WeekChip extends StatelessWidget {
  final DateTime weekStart;
  final String locale;
  final bool selected;
  final bool isThisWeek;
  final bool hasData;

  const _WeekChip({
    required this.weekStart,
    required this.locale,
    required this.selected,
    required this.isThisWeek,
    required this.hasData,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final label = weekSpanLabel(weekStart, locale);

    final chip = PlainChoiceChip(
      selected: selected,
      label: isThisWeek ? s.gridThisWeek : label,
      // The span is spoken even for the current week, where the visible
      // label is the word "this week" and would otherwise tell a screen
      // reader nothing about which dates it covers.
      semanticsLabel: isThisWeek ? '${s.gridThisWeek}, $label' : label,
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.pop(context, weekStart);
      },
    );
    if (selected || hasData) return chip;
    // A week you never filled in is still a week you may look at, so it
    // stays fully tappable and is only dimmed — same call the month
    // picker's empty months make.
    return Opacity(opacity: 0.55, child: chip);
  }
}
