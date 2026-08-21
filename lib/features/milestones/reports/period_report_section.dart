import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../../shared/widgets/history_demo_gate.dart';
import '../../../shared/widgets/milestone_tally_chip.dart';
import '../../../shared/widgets/month_picker_sheet.dart';
import '../../../shared/widgets/week_picker_sheet.dart';
import '../../../shared/widgets/segmented_tabs.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitTemplate;
import '../../habits/models/habit_model.dart' show GoalType;
import '../../grid/notifiers/weekly_grid_notifier.dart' show startOfGridWeek;
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../../grid/models/square_state.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart' show weeklyGridProvider;
import '../models/milestone_event.dart';
import '../notifiers/habit_history_notifier.dart';
import '../notifiers/milestone_notifier.dart';
import 'monthly_story_math.dart'
    show MonthlyStoryData, computeMonthlyStory, earliestStoryMonth;
import 'habit_day_marks.dart';
import 'habit_detail_sheet.dart';
import 'report_period.dart';
import 'report_sections.dart';
import 'year_strip.dart' show YearStripPainter, yearStripDayAt;

/// The أسبوعي / شهري / سنوي report, and the whole of what used to be two
/// separate destinations.
///
/// Before this, "قصة الشهر" (an aggregate month summary) and "سجل السنة"
/// (per-habit year strips) were two rows in Profile leading to two screens
/// that answered the same question at two zooms, with no way to get from
/// one to the other and no weekly grain at all. They are one control now:
/// the same period stepper, the same summary row, the same premium floor,
/// three windows.
///
/// Everything on screen is computed from two sources that are already
/// paid for: [DashboardState.dailyGreenCounts] (in memory, zero reads) for
/// day totals, and [habitYearHistoryProvider] (a handful of mirror docs for
/// the whole account) for per-habit day presence. Stepping a period or
/// switching a tab costs no reads at all.
class PeriodReportSection extends ConsumerStatefulWidget {
  const PeriodReportSection({super.key});

  @override
  ConsumerState<PeriodReportSection> createState() =>
      _PeriodReportSectionState();
}

class _PeriodReportSectionState extends ConsumerState<PeriodReportSection> {
  ReportScope _scope = ReportScope.week;

  /// Any day inside the period being viewed. [reportWindow] normalises it
  /// per scope, so switching tabs keeps you in the same stretch of time
  /// rather than throwing you back to today: someone reading last March's
  /// month who taps سنوي wants last March's year.
  late DateTime _anchor;

  /// Which way the last change moved time: 1 forward, -1 back, 0 for a tab
  /// switch (which changes zoom, not position).
  ///
  /// The transition reads this so a step actually looks like a step. Motion
  /// that always plays the same way is decoration; motion that carries the
  /// direction you just travelled is the only thing on screen telling you
  /// whether that swipe went backwards or forwards, which matters on a
  /// gesture with no arrow attached to it.
  int _moveDirection = 0;

  /// Owned here so a tab switch can return to the top of the report.
  ///
  /// The chrome is pinned, so the tab control stays reachable at any scroll
  /// offset, which means it is perfectly possible to switch tabs while
  /// parked in the footer three screens down. Without this, tapping شهري
  /// from there swapped the report far above the viewport and the visible
  /// pixels did not change at all, which reads as a dead control.
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // effectiveDay, not DateTime.now(): the app's day rolls over at 6am, so
    // between midnight and 06:00 the raw calendar would open a brand new,
    // guaranteed-empty week while the habits just finished sat one step
    // back. Same reasoning MonthlyStoryScreen documents for its own open.
    _anchor = DateTime.now().effectiveDay;
  }

  void _setScope(ReportScope scope) {
    setState(() {
      _scope = scope;
      _moveDirection = 0;
    });
    if (!_scroll.hasClients || _scroll.offset <= 0) return;
    // Animated rather than jumped: a report that teleports gives no sense
    // of having moved, and the distance travelled is what tells someone
    // they had scrolled at all.
    _scroll.animateTo(
      0,
      duration: GameMotion.relaxed,
      curve: Curves.easeOutCubic,
    );
  }

  /// Steps the period by [delta] windows, refusing to cross the free floor.
  ///
  /// Refuses with the demo gate rather than a disabled arrow, the same
  /// choice every other history surface in this app makes: a greyed-out
  /// control that explains nothing is how months of real data became
  /// unreachable on the old Monthly Story with nothing on screen to say why.
  void _step(int delta, {required DateTime today, required bool isPremium}) {
    final next = switch (_scope) {
      ReportScope.week =>
        DateTime(_anchor.year, _anchor.month, _anchor.day + 7 * delta),
      ReportScope.month => DateTime(_anchor.year, _anchor.month + delta),
      ReportScope.year => DateTime(_anchor.year + delta),
    };
    // One rule, in one place, per grain: see [reportPeriodUnlocked] for why
    // the week is free, the month is gated and the year is muted instead.
    if (!reportPeriodUnlocked(
      scope: _scope,
      anchor: next,
      now: today,
      isPremium: isPremium,
    )) {
      showHistoryDemoGate(context);
      return;
    }
    setState(() {
      _anchor = next;
      _moveDirection = delta;
    });
  }

  /// Opens one habit's own page. Wired to every place a habit's NAME
  /// appears in the three tabs, so the detail is always one tap from the
  /// thing being asked about.
  void _openHabit(IslamicHabitTemplate habit) =>
      showHabitDetailSheet(context, habit);

  /// The day sheet behind every cell in every grid.
  ///
  /// The one interaction a report can offer that the Grid does not already
  /// own: tapping here says what happened on a day, it never changes it.
  void _showDay({
    required DateTime day,
    required List<HabitPeriodStat> stats,
    required int doneCount,
  }) {
    HapticFeedback.selectionClick();
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final key = day.toDateKey();
    // Recorded marks first, then the habits that owed the day and recorded
    // nothing. Naming the state is the whole point of the sheet: it is the
    // one place the six squares stop being colours and become words, which
    // is what makes a رست day legible as a choice rather than a gap.
    final recorded = [
      for (final stat in stats)
        if (stat.marks.containsKey(key)) stat,
    ];
    // Archived habits are NEVER listed as مطلوب. Nothing is required of a
    // habit someone has put away, and the grid above already folds them out
    // of sight, so listing one here as still-owed had the sheet contradicting
    // the grid it was opened from.
    //
    // Routed through the same [splitArchived] the three grids use rather than
    // an inline archivedAt check, so "what counts as archived" has exactly
    // one definition and one set of tests.
    //
    // An archived habit still appears in [recorded] above if it actually did
    // something that day: that is history, and hiding it would be a different
    // kind of lie.
    final silent = [
      for (final stat in splitArchived(stats).active)
        if (!stat.marks.containsKey(key) &&
            missIsAttributable(stat.habit) &&
            stat.habit.isScheduledFor(day))
          stat,
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final gp = context.gp;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: BoxDecoration(
              color: gp.surface,
              borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
              border: Border.all(color: gp.border, width: 0.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        westernDate(day, 'EEEE d MMMM', locale),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: gp.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      s.reportsDayDone(doneCount),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: GameColors.emerald,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (recorded.isEmpty && silent.isEmpty)
                  Text(
                    s.reportsDayNothing,
                    style: TextStyle(fontSize: 12.5, color: gp.textTert),
                  ),
                for (final stat in recorded)
                  _DayRow(stat: stat, mark: stat.marks[key]!),
                for (final stat in silent)
                  _DayRow(stat: stat, mark: SquareState.none),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final dash = ref.watch(dashboardProvider);
    final isPremium = ref.watch(premiumProvider);
    final today = DateTime.now().effectiveDay;
    final historyAsync = ref.watch(habitYearHistoryProvider);

    // allHabitsEver, not the live list: archiving a habit must not erase
    // its history from a report, the same rule the Year Record and the
    // Monthly Heatmap already follow. Deduped by id because that provider
    // emits one synthetic template per catalog stint, which would otherwise
    // render as identical twin rows.
    final habits = <IslamicHabitTemplate>[];
    final seen = <String>{};
    for (final h in ref.watch(allHabitsEverProvider)) {
      if (seen.add(h.id)) habits.add(h);
    }

    final window = reportWindow(_scope, _anchor);
    final days = elapsedDaysIn(
      start: window.start,
      end: window.end,
      today: today,
    );
    // The earliest day anything was recorded. Bounds how far back the
    // stepper may walk, which matters more now that the weekly tab is
    // ungated: without a floor, the back arrow would happily march a free
    // account into 1990 through empty weeks. Cheap, the mirror is already
    // in memory.
    final mirrored =
        historyAsync.valueOrNull ?? const <String, Map<String, SquareState>>{};
    // TODAY comes from live state, never from the mirror. See [withLiveToday]
    // for why, and for why the gridKnowsToday guard is not optional.
    final grid = ref.watch(weeklyGridProvider);
    final history = withLiveToday(
      mirrored: mirrored,
      habitIds: habits.map((h) => h.id),
      squareToday: (id) => grid.squareFor(id, today),
      completionsToday: (id) => dash.completions[id] ?? 0,
      todayKey: today.toDateKey(),
      gridKnowsToday: !grid.isLoading && grid.isCurrentWeek,
    );

    // The earliest day anything was recorded. Bounds how far back the
    // stepper may walk: without a floor, the back arrow would march through
    // empty weeks forever. Cheap, the history is already in memory.
    String? earliestKey;
    for (final marks in history.values) {
      for (final key in marks.keys) {
        if (earliestKey == null || key.compareTo(earliestKey) < 0) {
          earliestKey = key;
        }
      }
    }
    final earliestData =
        earliestKey == null ? null : DateTime.tryParse(earliestKey);
    // Every day anything was DONE on, so the pickers can mark which periods
    // actually hold something.
    final allDoneKeys = <String>{
      for (final marks in history.values)
        for (final entry in marks.entries)
          if (markIsDone(entry.value)) entry.key,
    };

    // The free-history floor this period is drawn against, or null when
    // nothing on screen is walled. [historyFloorFor] carries the "only
    // meaningful where it actually bites" rule that stops a floor nothing
    // predates from drawing lock icons over a fully visible month, and it is
    // the same function the per-habit detail sheet's year strip reads, so
    // the two surfaces cannot disagree about which days are walled.
    //
    // Scoped to skip the WEEKLY tab outright. The week is deliberately never
    // gated (see [reportPeriodUnlocked]), and unlike the other two grains it
    // can be navigated freely into the walled past, so a floor here would
    // both mute a free surface and, worse, empty out the aggregates below.
    final lockedBefore = _scope == ReportScope.week
        ? null
        : historyFloorFor(
            windowStart: window.start,
            today: today,
            isPremium: isPremium,
          );

    // Bounded by the DATA, never by Premium: a live arrow that answers with
    // the demo sheet sells the upgrade, a dead one just looks broken. This
    // floor is a different thing, an honest "there is nothing before this".
    final canGoBack = earliestData == null || window.start.isAfter(earliestData);

    final canGoForward = switch (_scope) {
      ReportScope.week => window.end.isBefore(today),
      ReportScope.month => DateTime(_anchor.year, _anchor.month)
          .isBefore(DateTime(today.year, today.month)),
      ReportScope.year => _anchor.year < today.year,
    };

    // The tab control and the period stepper are PINNED above the scroll
    // view, not scrolled with it. The per-habit sections below run to
    // several screens on a real account, and a control that has scrolled
    // out of reach makes switching period a scroll-to-top-first chore. It
    // also keeps the label answering "which month am I reading" at every
    // scroll position, which is the question a long grid keeps raising.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedTabs(
          labels: [s.reportsWeekly, s.reportsMonthly, s.reportsYearly],
          selected: _scope.index,
          onChanged: (i) => _setScope(ReportScope.values[i]),
        ),
        const SizedBox(height: 2),
        ReportPeriodHeader(
          label: _periodLabel(locale),
          canGoBack: canGoBack,
          canGoForward: canGoForward,
          onBack: () => _step(-1, today: today, isPremium: isPremium),
          onForward: () => _step(1, today: today, isPremium: isPremium),
          // Every grain's label is a control, not a caption, which is the
          // convention the rest of this app already settled on. Stepping
          // alone means eleven taps to reach last January and never says
          // how far back the record goes.
          onTapLabel: () => _pickPeriod(
            allDoneKeys: allDoneKeys,
            counts: dash.dailyGreenCounts,
            accountCreatedAt: dash.accountCreatedAt,
            earliestData: earliestData,
            today: today,
            isPremium: isPremium,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          // Swipe the body sideways to step the period, with the pinned
          // stepper staying in sync. The arrows remain the discoverable
          // control; this is the shortcut for the thing people do most on
          // a report, which is walk backwards through it.
          //
          // Direction follows the content, not the arrows: dragging right
          // pulls in whatever sits to the left, and in Arabic the period
          // to the left is the LATER one, so the same gesture means
          // opposite periods in the two locales.
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              // Below this, a slightly diagonal vertical scroll would
              // start teleporting people through months.
              if (velocity.abs() < 240) return;
              final forward = isRtl ? velocity > 0 : velocity < 0;
              if (forward && !canGoForward) return;
              if (!forward && !canGoBack) return;
              _step(forward ? 1 : -1, today: today, isPremium: isPremium);
            },
            child: ListView(
              controller: _scroll,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _ReportTransition(
                  // A new key per period AND per grain, so stepping August
                  // to July animates and a rebuild from new data does not.
                  bodyKey: ValueKey('${_scope.name}|${window.start}'),
                  direction: _moveDirection,
                  isRtl: isRtl,
                  // Order matters, and it is the same trap the old Monthly
                  // Story documented: an empty state is an assertion about
                  // the USER, and a dashboard that failed to load produces
                  // exactly the zeros that trigger it. Both load states are
                  // checked before any sentence claiming nothing was
                  // recorded is allowed on screen.
                  child: dash.isLoading || historyAsync.isLoading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : dash.loadFailed || historyAsync.hasError
                          ? _ReportLoadFailed(s: s)
                          : _body(
                              history: history,
                              earliestData: earliestData,
                              habits: habits,
                              days: days,
                              window: window,
                              dash: dash,
                              today: today,
                              locale: locale,
                              isRtl: isRtl,
                              lockedBefore: lockedBefore,
                              s: s,
                            ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _periodLabel(String locale) {
    final window = reportWindow(_scope, _anchor);
    switch (_scope) {
      case ReportScope.week:
        // "15 - 21 أغسطس": the month is named once, at the end, since both
        // ends almost always share it. When they do not, both get named.
        final sameMonth = window.start.month == window.end.month;
        final start = sameMonth
            ? westernDate(window.start, 'd', locale)
            : westernDate(window.start, 'd MMM', locale);
        return '$start - ${westernDate(window.end, 'd MMM', locale)}';
      case ReportScope.month:
        return westernDate(window.start, 'MMMM yyyy', locale);
      case ReportScope.year:
        return toWesternDigits('${window.start.year}');
    }
  }

  /// Opens the picker for whichever grain is showing.
  ///
  /// The week arm has no isUnlocked predicate because weeks are not gated
  /// (see [reportPeriodUnlocked]), and the year arm has none because the
  /// year tab mutes locked days rather than refusing the year.
  Future<void> _pickPeriod({
    required Set<String> allDoneKeys,
    required Map<String, int> counts,
    required DateTime? accountCreatedAt,
    required DateTime? earliestData,
    required DateTime today,
    required bool isPremium,
  }) async {
    switch (_scope) {
      case ReportScope.month:
        await _pickMonth(
          counts: counts,
          accountCreatedAt: accountCreatedAt,
          today: today,
          isPremium: isPremium,
        );
      case ReportScope.week:
        final picked = await showWeekPicker(
          context,
          weeks: weeksBetween(earliestData ?? today, today),
          selected: startOfGridWeek(_anchor),
          hasData: (weekStart) {
            for (var i = 0; i < 7; i++) {
              final day = DateTime(
                weekStart.year,
                weekStart.month,
                weekStart.day + i,
              );
              if (allDoneKeys.contains(day.toDateKey())) return true;
            }
            return false;
          },
        );
        if (picked == null || !mounted) return;
        setState(() {
          _moveDirection = picked.isBefore(_anchor) ? -1 : 1;
          _anchor = picked;
        });
      case ReportScope.year:
        final earliestYear = earliestData?.year ?? today.year;
        final picked = await showYearPicker(
          context,
          years: [
            for (var y = today.year; y >= earliestYear; y--) y,
          ],
          selected: _anchor.year,
          isUnlocked: (_) => true,
          hasData: (year) =>
              allDoneKeys.any((key) => key.startsWith('$year-')),
        );
        if (picked == null || !mounted) return;
        setState(() {
          _moveDirection = picked < _anchor.year ? -1 : 1;
          _anchor = DateTime(picked);
        });
    }
  }

  Future<void> _pickMonth({
    required Map<String, int> counts,
    required DateTime? accountCreatedAt,
    required DateTime today,
    required bool isPremium,
  }) async {
    final currentMonth = DateTime(today.year, today.month);
    final earliest = earliestStoryMonth(
      dailyGreenCounts: counts,
      accountCreatedAt: accountCreatedAt,
      currentMonth: currentMonth,
    );
    final picked = await showMonthPicker(
      context,
      months: monthsBetween(earliest, currentMonth),
      selected: DateTime(_anchor.year, _anchor.month),
      isUnlocked: (month) => canBrowseHistoryMonth(
        monthStart: month,
        now: today,
        isPremium: isPremium,
      ),
      hasStory: (month) {
        final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
        for (var d = 1; d <= daysInMonth; d++) {
          if ((counts[DateTime(month.year, month.month, d).toDateKey()] ?? 0) >
              0) {
            return true;
          }
        }
        return false;
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _anchor = picked);
  }

  Widget _body({
    required Map<String, Map<String, SquareState>> history,
    required DateTime? earliestData,
    required List<IslamicHabitTemplate> habits,
    required List<DateTime> days,
    required ({DateTime start, DateTime end}) window,
    required DashboardState dash,
    required DateTime today,
    required String locale,
    required bool isRtl,
    required DateTime? lockedBefore,
    required S s,
  }) {
    // Two views of the same period, and the split is the whole point.
    //
    // [stats] covers the WHOLE window and feeds the per-habit strips and
    // grids below, which need every day so the walled ones can be drawn
    // muted and sell on tap. [visibleStats] covers only what the viewer may
    // actually see, and feeds every AGGREGATE above them.
    //
    // Without that split the year tab told two stories at once: each habit
    // strip muted its walled days and honestly reported "0 يوم", while the
    // header directly above printed the real full-year total, completion
    // rate, strongest and weakest weekday, and the year-over-year delta for
    // a year whose every strip was blank. The aggregate is named in this
    // file's own gating comment as "the thing actually being sold", so it
    // was the one number that most needed the floor.
    final stats = computeHabitPeriodStats(
      habits: habits,
      history: history,
      days: days,
    );
    final visibleDays = visibleDaysFrom(days: days, floor: lockedBefore);
    final visibleStats = identical(visibleDays, days)
        ? stats
        : computeHabitPeriodStats(
            habits: habits,
            history: history,
            days: visibleDays,
          );
    // Every count in the header and the rhythm card comes from this one map,
    // derived from the same per-habit truth the grids are painted from. See
    // [dayCountsFrom].
    final dayCounts = dayCountsFrom(visibleStats);
    // A period whose predecessor predates the account shows no delta rather
    // than one identical to its own total, and a predecessor sitting behind
    // the paywall shows none either.
    final delta = periodDelta(
      scope: _scope,
      anchor: _anchor,
      history: history,
      habits: habits,
      today: today,
      earliestData: earliestData,
      floor: lockedBefore,
    );
    final summary = computePeriodSummary(
      dayCounts: dayCounts,
      days: visibleDays,
      habitStats: visibleStats,
    );

    if (!summary.hasAnything && stats.every((st) => st.doneCount == 0)) {
      return _ReportEmpty(
        text: switch (_scope) {
          ReportScope.week => s.reportsEmptyWeek,
          ReportScope.month => s.reportsEmptyMonth,
          ReportScope.year => s.reportsEmptyYear,
        },
      );
    }

void tapDay(DateTime day) => _showDay(
      day: day,
      stats: stats,
      // Counts exactly the rows the sheet is about to list. Reading this
      // from a different source is how the sheet came to be headed
      // "تم إنجاز 4" over six ticked habits.
      doneCount: dayCounts[day.toDateKey()] ?? 0,
    );

    return switch (_scope) {
      ReportScope.week => _weekBody(
          stats: stats,
          summary: summary,
          delta: delta,
          window: window,
          dash: dash,
          today: today,
          locale: locale,
          onTapDay: tapDay,
        ),
      ReportScope.month => _monthBody(
          stats: stats,
          summary: summary,
          dayCounts: dayCounts,
          days: visibleDays,
          delta: delta,
          dash: dash,
          today: today,
          locale: locale,
          lockedBefore: lockedBefore,
          onTapDay: tapDay,
          s: s,
        ),
      ReportScope.year => _yearBody(
          stats: stats,
          summary: summary,
          dayCounts: dayCounts,
          days: visibleDays,
          delta: delta,
          dash: dash,
          today: today,
          locale: locale,
          isRtl: isRtl,
          lockedBefore: lockedBefore,
          s: s,
        ),
    };
  }

  Widget _weekBody({
    required List<HabitPeriodStat> stats,
    required PeriodSummary summary,
    required int? delta,
    required ({DateTime start, DateTime end}) window,
    required DashboardState dash,
    required DateTime today,
    required String locale,
    required void Function(DateTime) onTapDay,
  }) {
    // The full seven columns, including days still to come: a week grid
    // that grew a column a day would move every cell under the reader.
    final weekDays = [
      for (var i = 0; i < 7; i++)
        DateTime(window.start.year, window.start.month, window.start.day + i),
    ];
    final split = splitArchived(stats);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportHeaderCard(summary: summary, locale: locale, delta: delta),
        const SizedBox(height: 10),
        WeeklyMatrixCard(
          stats: split.active,
          weekDays: weekDays,
          today: today,
          locale: locale,
          onTapDay: onTapDay,
          onTapHabit: (stat) => _openHabit(stat.habit),
        ),
        if (split.archived.isNotEmpty) ...[
          const SizedBox(height: 6),
          _ArchivedFold(
            count: split.archived.length,
            children: [
              const SizedBox(height: 4),
              WeeklyMatrixCard(
                stats: split.archived,
                weekDays: weekDays,
                today: today,
                locale: locale,
                onTapDay: onTapDay,
                muted: true,
                onTapHabit: (stat) => _openHabit(stat.habit),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _monthBody({
    required List<HabitPeriodStat> stats,
    required PeriodSummary summary,
    required int? delta,
    required Map<String, int> dayCounts,

    /// The days the viewer may actually SEE, already floored. Handed down
    /// rather than recomputed from the period so the weekday rhythm card
    /// cannot describe days the grids below it are muting.
    required List<DateTime> days,
    required DashboardState dash,
    required DateTime today,
    required String locale,
    required DateTime? lockedBefore,
    required void Function(DateTime) onTapDay,
    required S s,
  }) {
    final month = DateTime(_anchor.year, _anchor.month);
    final milestones =
        ref.watch(milestonesForMonthProvider(month)).valueOrNull ??
            const <MilestoneEvent>[];
    final story = computeMonthlyStory(
      dailyGreenCounts: dash.dailyGreenCounts,
      month: month,
      allMilestones: milestones,
      today: today,
      earliestMonth: earliestStoryMonth(
        dailyGreenCounts: dash.dailyGreenCounts,
        accountCreatedAt: dash.accountCreatedAt,
        currentMonth: DateTime(today.year, today.month),
      ),
    );
    final split = splitArchived(stats);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportHeaderCard(
          summary: summary,
          locale: locale,
          delta: delta,
          chips: milestoneChips(context, story),
        ),
        const SizedBox(height: 10),
        ..._rhythm(dayCounts: dayCounts, days: days, locale: locale),
        _SectionLabel(s.reportsHabitsSection),
        const SizedBox(height: 8),
        _monthCards(
          stats: split.active,
          month: month,
          today: today,
          lockedBefore: lockedBefore,
          onTapDay: onTapDay,
          muted: false,
        ),
        // Archived habits are folded away rather than mixed in. An archived
        // card looked identical to a live one, so a habit someone had
        // deliberately put away sat in the middle of their month reading as
        // a current commitment.
        if (split.archived.isNotEmpty) ...[
          const SizedBox(height: 6),
          _ArchivedFold(
            count: split.archived.length,
            children: [
              const SizedBox(height: 4),
              _monthCards(
                stats: split.archived,
                month: month,
                today: today,
                lockedBefore: lockedBefore,
                onTapDay: onTapDay,
                muted: true,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _monthCards({
    required List<HabitPeriodStat> stats,
    required DateTime month,
    required DateTime today,
    required DateTime? lockedBefore,
    required void Function(DateTime) onTapDay,
    required bool muted,
  }) =>
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.82,
        children: [
          for (final stat in stats)
            HabitMonthCard(
              stat: stat,
              month: month,
              today: today,
              lockedBefore: lockedBefore,
              onTapDay: onTapDay,
              muted: muted,
              onTapHabit: () => _openHabit(stat.habit),
            ),
        ],
      );

  Widget _yearBody({
    required List<HabitPeriodStat> stats,
    required PeriodSummary summary,
    required int? delta,
    required Map<String, int> dayCounts,

    /// See [_monthBody]'s identical parameter: the floored days, so the
    /// rhythm card never speaks for a walled part of the year.
    required List<DateTime> days,
    required DashboardState dash,
    required DateTime today,
    required String locale,
    required bool isRtl,
    required DateTime? lockedBefore,
    required S s,
  }) {
    final year = _anchor.year;
    // Archived habits keep their history but move under a fold: archiving
    // means "not part of my present", so the past shows up when asked for.
    // Shared with the other two tabs via [splitArchived] so all three agree
    // on what counts as archived.
    final split = splitArchived(stats);
    final active = split.active;
    final archived = split.archived;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportHeaderCard(summary: summary, locale: locale, delta: delta),
        const SizedBox(height: 10),
        ..._rhythm(dayCounts: dayCounts, days: days, locale: locale),
        _SectionLabel(s.reportsHabitsSection),
        const SizedBox(height: 8),
        for (final st in active) ...[
          _HabitYearRow(
            stat: st,
            year: year,
            today: today,
            isRtl: isRtl,
            lockedBefore: lockedBefore,
            muted: false,
            onTapHabit: () => _openHabit(st.habit),
          ),
          const SizedBox(height: 10),
        ],
        if (archived.isNotEmpty) ...[
          _ArchivedFold(
            count: archived.length,
            children: [
              for (final st in archived) ...[
                _HabitYearRow(
                  stat: st,
                  year: year,
                  today: today,
                  isRtl: isRtl,
                  lockedBefore: lockedBefore,
                  muted: true,
                  onTapHabit: () => _openHabit(st.habit),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ],
      ],
    );
  }

  /// The rhythm card, or nothing at all.
  ///
  /// Returns an empty list unless the period actually has a strongest and a
  /// weakest weekday worth naming. A year's weekday averages are almost
  /// always even, so on the سنوي tab this block used to fill most of a
  /// screen in order to report that there was no pattern. Silence is the
  /// better answer: the card showing up now means there is something in it.
  List<Widget> _rhythm({
    required Map<String, int> dayCounts,
    required List<DateTime> days,
    required String locale,
  }) {
    final periodLabel = _periodLabel(locale);
    final insight = computeWeekdayInsight(dayCounts: dayCounts, days: days);
    if (insight == null || !insight.isMeaningful) return const [];
    final totals = <int, int>{};
    final counts = <int, int>{};
    for (final day in days) {
      totals[day.weekday] =
          (totals[day.weekday] ?? 0) + (dayCounts[day.toDateKey()] ?? 0);
      counts[day.weekday] = (counts[day.weekday] ?? 0) + 1;
    }
    final averages = {
      for (final entry in counts.entries)
        entry.key:
            entry.value == 0 ? 0.0 : (totals[entry.key] ?? 0) / entry.value,
    };
    return [
      WeekdayRhythmCard(
        insight: insight,
        averages: averages,
        locale: locale,
        periodLabel: periodLabel,
      ),
      const SizedBox(height: 14),
    ];
  }
}

/// Cross-fades the report body, sliding it the way you just travelled.
///
/// Two different motions, because two different things can change:
///
///  - STEPPING A PERIOD slides horizontally, and the outgoing body leaves by
///    the opposite edge from the one the incoming body arrives at, so the
///    pair reads as one movement through time rather than a dissolve. The
///    direction is mirrored for Arabic, where the later period sits to the
///    LEFT (that is where the forward arrow is), so the same gesture means
///    the same thing in both locales.
///  - SWITCHING GRAIN does not move through time at all, it changes zoom, so
///    it fades and scales up very slightly instead of sliding. Giving it the
///    horizontal motion too would have said "you went back a period" every
///    time someone tapped سنوي.
///
/// The slide is 6% of the width. Enough to see, not enough to make anyone
/// wait for it: the whole thing is 260ms, and a report is something people
/// step through repeatedly.
class _ReportTransition extends StatelessWidget {
  final Key bodyKey;

  /// 1 forward in time, -1 back, 0 for a grain switch.
  final int direction;
  final bool isRtl;
  final Widget child;

  const _ReportTransition({
    required this.bodyKey,
    required this.direction,
    required this.isRtl,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      // Top-aligned, not centred: the two bodies are different heights, and
      // a centred stack would slide the incoming report vertically as well,
      // which reads as a glitch rather than a transition.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (child, animation) {
        if (direction == 0) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(animation),
              child: child,
            ),
          );
        }
        // Visual direction: forward in time is whichever side the forward
        // arrow sits on, which flips with the reading direction.
        final forwardIsRight = !isRtl;
        final movingForward = direction > 0;
        final entersFromRight = movingForward == forwardIsRight;
        // The outgoing child runs its own animation in reverse, so giving
        // it the opposite offset is what makes the two slide the same way
        // instead of both retreating to the same edge.
        final isIncoming = child.key == bodyKey;
        final dx = (entersFromRight ? 0.06 : -0.06) * (isIncoming ? 1 : -1);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero)
                .animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: bodyKey, child: child),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: gp.textSec,
        letterSpacing: 1.5,
      ),
    );
  }
}

/// The month's milestones as chips for [ReportHeaderCard].
///
/// A wrapping chip row rather than the old two-column card grid, which
/// reserved a whole card per milestone type and left a ragged half-empty
/// row whenever the count was odd. Chips wrap: one milestone takes one
/// line, six take two.
List<Widget> milestoneChips(BuildContext context, MonthlyStoryData story) {
  final s = S.of(context);
  final entries = <(IconData, Color, int, String)>[
    if (story.levelUps > 0)
      (
        Icons.bolt_rounded,
        GameColors.gold,
        story.levelUps,
        MilestoneType.levelUp.localizedName(s.isAr)
      ),
    if (story.streakMilestones > 0)
      (
        Icons.local_fire_department_rounded,
        GameColors.iconStreak,
        story.streakMilestones,
        MilestoneType.streakMilestone.localizedName(s.isAr)
      ),
    if (story.perfectDays > 0)
      (
        Icons.star_rounded,
        GameColors.success,
        story.perfectDays,
        MilestoneType.perfectDay.localizedName(s.isAr)
      ),
    if (story.perfectWeeks > 0)
      (
        Icons.auto_awesome_rounded,
        GameColors.iconXp,
        story.perfectWeeks,
        MilestoneType.perfectWeek.localizedName(s.isAr)
      ),
    if (story.achievementsUnlocked > 0)
      (
        Icons.emoji_events_rounded,
        GameColors.gold,
        story.achievementsUnlocked,
        MilestoneType.achievementUnlocked.localizedName(s.isAr)
      ),
  ];
  return [
    for (final e in entries)
      MilestoneTallyChip(icon: e.$1, color: e.$2, count: e.$3, label: e.$4),
  ];
}

/// One habit's year strip, the سنوي tab's row.
///
/// Uses the public [YearStripPainter] the old Year Record screen already
/// exposed rather than a second painter, so the two surfaces can never
/// disagree about where a day sits.
class _HabitYearRow extends StatelessWidget {
  final HabitPeriodStat stat;
  final int year;
  final DateTime today;
  final bool isRtl;
  final DateTime? lockedBefore;
  final bool muted;
  final VoidCallback onTapHabit;

  const _HabitYearRow({
    required this.stat,
    required this.year,
    required this.today,
    required this.isRtl,
    required this.lockedBefore,
    required this.muted,
    required this.onTapHabit,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final color = stat.habit.customColor ?? GameColors.emerald;
    final isQuit = stat.habit.goalType == GoalType.quit;
    // The label counts what the strip SHOWS: a full-history count beside a
    // mostly-muted strip read as a bug on the free tier.
    final floorKey = lockedBefore?.toDateKey();
    final visible = floorKey == null
        ? stat.doneCount
        : stat.doneDays.where((k) => k.compareTo(floorKey) >= 0).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: muted ? color.withOpacity(0.55) : color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              if (isQuit) ...[
                Icon(
                  Icons.front_hand_rounded,
                  size: 12,
                  color: muted ? gp.textTert : color,
                ),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: GestureDetector(
                  onTap: onTapHabit,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    stat.habit.localName(s.isAr),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: muted ? gp.textSec : gp.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isQuit
                    ? s.yearRecordCleanDaysCount(visible)
                    : s.yearRecordDaysCount(visible),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (lockedBefore != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.lock_rounded, size: 12, color: gp.textTert),
              ],
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxWidth / 7.6;
              return GestureDetector(
                onTapUp: lockedBefore == null
                    ? null
                    : (details) {
                        final dx =
                            (details.localPosition.dx / constraints.maxWidth)
                                .clamp(0.0, 1.0);
                        final row = (details.localPosition.dy / (height / 7))
                            .floor()
                            .clamp(0, 6);
                        final day = yearStripDayAt(
                          year: year,
                          dxFraction: dx,
                          row: row,
                          isRtl: isRtl,
                        );
                        if (day.year == year && day.isBefore(lockedBefore!)) {
                          showHistoryDemoGate(context);
                        }
                      },
                child: CustomPaint(
                  size: Size(constraints.maxWidth, height),
                  painter: YearStripPainter(
                    year: year,
                    doneDays: stat.doneDays,
                    color: color,
                    today: today,
                    isRtl: isRtl,
                    lockedBefore: lockedBefore,
                    emptyColor: gp.dark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.06),
                    lockedColor: gp.dark
                        ? Colors.white.withOpacity(0.03)
                        : Colors.black.withOpacity(0.03),
                    // Quieter than locked: see YearStripPainter.futureColor.
                    futureColor: gp.dark
                        ? Colors.white.withOpacity(0.015)
                        : Colors.black.withOpacity(0.015),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ArchivedFold extends StatefulWidget {
  final int count;
  final List<Widget> children;

  const _ArchivedFold({required this.count, required this.children});

  @override
  State<_ArchivedFold> createState() => _ArchivedFoldState();
}

class _ArchivedFoldState extends State<_ArchivedFold> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _open = !_open);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined, size: 14, color: gp.textTert),
                const SizedBox(width: 8),
                Text(
                  '${s.yearRecordArchivedSection} · ${toWesternDigits('${widget.count}')}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: gp.textTert,
                  ),
                ),
                const Spacer(),
                Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                  color: gp.textTert,
                ),
              ],
            ),
          ),
        ),
        if (_open) ...widget.children,
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  final HabitPeriodStat stat;
  final SquareState mark;

  const _DayRow({required this.stat, required this.mark});

  bool get _archived => stat.habit.archivedAt != null;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final habitColor = stat.habit.customColor ?? GameColors.emerald;
    final (IconData icon, Color color) = switch (mark) {
      SquareState.complete => (Icons.check_circle_rounded, habitColor),
      SquareState.bonus => (Icons.auto_awesome_rounded, GameColors.gold),
      SquareState.partial => (
          Icons.contrast_rounded,
          habitColor.withOpacity(0.8),
        ),
      SquareState.failed => (Icons.cancel_rounded, GameColors.warning),
      SquareState.skipped => (Icons.bedtime_rounded, GameColors.gold),
      SquareState.none => (
          Icons.radio_button_unchecked,
          gp.textTert.withOpacity(0.6),
        ),
    };
    final isDone = markIsDone(mark);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Row(
              children: [
                if (_archived) ...[
                  Icon(Icons.inventory_2_outlined,
                      size: 11, color: gp.textTert),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    stat.habit.localName(s.isAr),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isDone && !_archived
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: _archived
                          ? gp.textTert
                          : isDone
                              ? gp.textPrimary
                              : gp.textSec,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            // The state in words. Reuses the label the Grid already reads to
            // VoiceOver rather than inventing a second vocabulary for the
            // same six squares.
            mark == SquareState.none
                ? s.reportsDayScheduled
                : mark.localLabel(s.isAr),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: mark == SquareState.none ? gp.textTert : color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportEmpty extends StatelessWidget {
  final String text;
  const _ReportEmpty({required this.text});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Icon(Icons.auto_stories_rounded, size: 38, color: gp.textTert),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ReportLoadFailed extends StatelessWidget {
  final S s;
  const _ReportLoadFailed({required this.s});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 38, color: gp.textTert),
          const SizedBox(height: 12),
          Text(
            s.monthlyStoryLoadFailed,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.4),
          ),
        ],
      ),
    );
  }
}
