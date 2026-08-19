import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/extensions/datetime_ext.dart';
import '../../core/theme/game_theme.dart';
import '../../core/utils/western_digits.dart';
import '../../features/grid/notifiers/weekly_grid_notifier.dart'
    show startOfGridWeek;

/// Saturday-through-Friday column headings for a month grid.
///
/// Lifted out of monthly_heatmap_screen.dart, which is one of *three*
/// near-verbatim copies of this row in the app (the others live in
/// matrix_history_screen.dart and night_review_history_screen.dart). They
/// differ only cosmetically, and each one separately re-derives the Arabic
/// fix below — so a fourth copy for the Rooms calendar was not worth
/// writing. Collapsing the existing three onto this is worth doing, but
/// deliberately isn't part of this change.
class CalendarWeekdayHeaderRow extends StatelessWidget {
  const CalendarWeekdayHeaderRow({super.key});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final locale = Localizations.localeOf(context).languageCode;
    // Any real Saturday works as a labelling anchor — today's own grid week
    // start is guaranteed to be one.
    final saturday = startOfGridWeek(DateTime.now());
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: Text(
                // 'EEEEE' (narrow), not E().substring(0, 1). Arabic's short
                // weekday names are الأحد/الاثنين/الثلاثاء/… — every one of
                // the seven starts with ا, so taking the first character
                // printed the same letter across all seven columns and there
                // was no way to tell Friday from Saturday. The narrow form is
                // seven distinct letters (ح ن ث ر خ ج س), and is unchanged
                // for English (S M T W T F S).
                DateFormat('EEEEE', locale)
                    .format(saturday.add(Duration(days: i))),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: gp.textTert,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Month title with prev/next arrows, disabled past the ends of the range
/// the caller actually has data for.
///
/// The arrows are [Icons.chevron_left_rounded] / [chevron_right_rounded]
/// laid out in a plain [Row], so Flutter mirrors both the icons and their
/// order under RTL — "previous" stays on the side an Arabic reader expects
/// without this widget knowing which side that is.
class CalendarMonthHeader extends StatelessWidget {
  final DateTime month;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;

  /// Makes the title itself a button that opens a month picker.
  ///
  /// Optional because stepping is enough when a screen only spans a few
  /// months. Past that, arrows alone mean tapping eleven times to reach
  /// last January, and nothing on screen says how far back you may go —
  /// which is exactly how a range that was silently one month wide went
  /// unnoticed. When this is set the title gains a chevron so it reads as
  /// a control rather than a caption.
  final VoidCallback? onTapMonth;

  const CalendarMonthHeader({
    super.key,
    required this.month,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    this.onTapMonth,
  });

  Widget _title(BuildContext context, String locale) {
    final gp = context.gp;
    // westernDate, not DateFormat directly: this header rendered "أغسطس
    // ٢٠٢٦" in Arabic-Indic digits while every number underneath it — the
    // counts, the day numbers — stayed ASCII. Arabic month name, Western
    // year, the same call Habit Notes already settled on.
    final label = westernDate(month, 'MMMM yyyy', locale);
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: gp.textPrimary,
      ),
    );
    if (onTapMonth == null) return text;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTapMonth!();
      },
      borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: text),
            const SizedBox(width: 4),
            // Vertical, so RTL mirroring has nothing to do to it.
            Icon(Icons.expand_more_rounded, size: 18, color: gp.textSec),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final locale = Localizations.localeOf(context).languageCode;
    return Row(
      children: [
        IconButton(
          onPressed: canGoBack ? onBack : null,
          // MaterialLocalizations, not a new string pair: Flutter already
          // ships "Previous month" / "الشهر السابق" in every locale this
          // app supports. Without a tooltip a disabled arrow announces
          // that something is unavailable without ever saying what.
          tooltip: MaterialLocalizations.of(context).previousMonthTooltip,
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 22,
          color: gp.textSec,
          disabledColor: gp.textTert.withOpacity(0.3),
          visualDensity: VisualDensity.compact,
        ),
        Expanded(
          child: _title(context, locale),
        ),
        IconButton(
          onPressed: canGoForward ? onForward : null,
          tooltip: MaterialLocalizations.of(context).nextMonthTooltip,
          icon: const Icon(Icons.chevron_right_rounded),
          iconSize: 22,
          color: gp.textSec,
          disabledColor: gp.textTert.withOpacity(0.3),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

/// A real month grid: Saturday-anchored weeks, the day number inside every
/// cell, and a full-size tap target per day.
///
/// This is the surface that makes a 9pt contribution strip inspectable. The
/// strip's own cells can never be tapped — at a 11.5pt pitch they fail
/// HIG's 44pt, Material's 48dp and even WCAG 2.2's 24px spacing exception,
/// and they sit inside a vertical scroller that would win most of those
/// gestures anyway. So the strip opens this, where a day is ~40pt square
/// and tapping one is unambiguous.
///
/// [fillFor] returns the cell colour for a day inside the range, or null
/// for a day the caller has nothing to say about (outside the room window,
/// or a future date). [markerFor] lets the caller ring specific days —
/// start and today — using whatever treatment it already uses elsewhere.
class CalendarMonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime? selected;
  final Color? Function(DateTime day) fillFor;
  final BoxBorder? Function(DateTime day) markerFor;
  final void Function(DateTime day) onTapDay;

  const CalendarMonthGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.fillFor,
    required this.markerFor,
    required this.onTapDay,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final locale = Localizations.localeOf(context).languageCode;
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Same (weekday + 1) % 7 mapping the Grid and Matrix history both use,
    // so a date lands in the same column here as it does there.
    final lead = (first.weekday + 1) % 7;
    final numberFmt = NumberFormat.decimalPattern(locale);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: lead + daysInMonth,
      itemBuilder: (context, index) {
        if (index < lead) return const SizedBox.shrink();
        final day = DateTime(month.year, month.month, index - lead + 1);
        final fill = fillFor(day);
        final isSelected = selected != null && day.isSameDayAs(selected!);
        return GestureDetector(
          onTap: fill == null ? null : () => onTapDay(day),
          behavior: HitTestBehavior.opaque,
          child: Container(
            decoration: BoxDecoration(
              color: fill ?? Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: isSelected
                  ? Border.all(color: gp.textPrimary, width: 1.6)
                  : markerFor(day),
            ),
            alignment: Alignment.center,
            child: Text(
              numberFmt.format(index - lead + 1),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                // A day outside the range is present for calendar shape only
                // — dimmed so the month still reads as a month without
                // implying there's data behind it.
                color: fill == null ? gp.textTert.withOpacity(0.45) : null,
              ),
            ),
          ),
        );
      },
    );
  }
}
