import 'dart:ui' as ui show TextDirection;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/western_digits.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../milestones/notifiers/habit_history_notifier.dart';
import '../../milestones/reports/habit_day_marks.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../../../shared/widgets/month_picker_sheet.dart';
import '../models/square_state.dart';
import '../notifiers/weekly_grid_notifier.dart'
    show startOfGridWeek, weeklyGridProvider, WeeklyGridState;

/// A month-by-month heatmap of green squares — one real calendar section per
/// month (correct 28/29/30/31-day grids, Sat-first weeks matching the
/// Victory Grid), newest month on top, instead of the old GitHub-style
/// week-columns strip that gave the eye no month boundaries to hold on to.
/// Day counts are DERIVED from the habit-history mirror, the same source
/// the reports and this screen's own detail sheet read. See
/// [derivedDayCounts] for why they are no longer taken from
/// [DashboardState.dailyGreenCounts].
///
/// Free accounts see the current month plus the two before it, in full.
/// Premium unlocks *lifetime*: every month from the first day that ever had
/// a colored square to now. The underlying data is already loaded either
/// way, so this is purely a display cap, not a data-access restriction.
class MonthlyHeatmapScreen extends ConsumerStatefulWidget {
  const MonthlyHeatmapScreen({super.key});

  static const int _freeMonthsToShow = 3;

  // Lifetime, but bounded: dailyGreenCounts is user-doc data, so a single
  // corrupt/hand-edited key with a bogus ancient date must never make this
  // screen try to render thousands of empty month sections. 20 years of
  // real usage stays comfortably inside this.
  static const int _maxLifetimeMonths = 240;

  @override
  ConsumerState<MonthlyHeatmapScreen> createState() =>
      _MonthlyHeatmapScreenState();
}

class _MonthlyHeatmapScreenState extends ConsumerState<MonthlyHeatmapScreen> {
  /// One key per rendered month, so picking a month can scroll to it.
  /// Keyed by 'yyyy-MM' rather than by DateTime, which does not compare
  /// equal across separately-constructed instances of the same month.
  final Map<String, GlobalKey> _monthKeys = {};

  /// The list runs OLDEST FIRST, so the current month is the last thing in
  /// it and the screen has to open at the bottom. Same shape as the iOS
  /// Calendar: today is where you land, and history is up.
  final ScrollController _scroll = ScrollController();
  bool _landed = false;

  void _landOnCurrentMonth() {
    if (_landed || !_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return; // not laid out yet; try again next frame
    _landed = true;
    _scroll.jumpTo(max);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(DateTime month) => _monthKeys.putIfAbsent(
        '${month.year}-${month.month}',
        () => GlobalKey(),
      );

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final dark = gp.dark;
    final isPremium = ref.watch(premiumProvider);
    // The mirror is the truth; the rollup is only a stand-in for the one
    // frame before it resolves, so the grid does not flash empty.
    final dash = ref.watch(dashboardProvider);
    // A day's green count only means something next to how many habits the
    // user actually tracks — 2 greens is a perfect day at 2 habits but a
    // quiet one at 8. Color by percentage of that day's scheduled habit
    // list, not the raw count, so a 100% day is always the deepest green
    // regardless of how many habits someone keeps.
    //
    // allHabitsEverProvider, not habitListProvider: this screen renders
    // months of past days, and habitListProvider only ever holds what's
    // active *today*. Reading that here would mean deleting a habit
    // silently rewrites every past month's percentages the instant it's
    // removed — the denominator would shrink to today's habit count while
    // dailyGreenCounts (the numerator) stays a frozen historical rollup,
    // so the two would stop agreeing. allHabitsEverProvider keeps an
    // archived habit counted for exactly the days it was really active.
    // Archived habits are excluded from this screen entirely, on BOTH
    // sides of the ratio.
    //
    // The screen used to keep them, on the reasoning that a habit you had
    // on the 18th and did not do IS a miss on the 18th, and that letting
    // people prune their way to a perfect history makes the map worthless
    // as a record. That argument is real; this deliberately overrules it.
    //
    // What wins: `archivedAt` records the day you got round to tidying up,
    // not the day you stopped. On a real account habit 07eb2b82 carried
    // archivedAt 2026-08-19 and so dragged 18 August down to 5 of 6 for a
    // habit already on its way out. The stamp systematically lags the real
    // end date, so the trailing days it penalises are exactly the days the
    // habit was already dead.
    //
    // Excluding it from BOTH sides is the load-bearing part: counting an
    // archived habit's completions while dropping it from the denominator
    // would let a day exceed 100%.
    final habits = ref
        .watch(allHabitsEverProvider)
        .where((h) => h.archivedAt == null)
        .toList();

    // Today is resolved from LIVE state, never from a rollup. See
    // [_todayDoneCount] — dailyGreenCounts does not reliably hold today.
    final todayDone =
        _todayDoneCount(habits, dash.completions, ref.watch(weeklyGridProvider));
    final todayKey = DateTime.now().effectiveDay.toDateKey();
    // The mirror is the truth for settled days; the rollup is only a
    // stand-in for the one frame before it resolves.
    // WHAT WAS DONE is counted from every habit the mirror holds, even
    // ones since archived or deleted. WHAT WAS OWED counts only habits
    // that still exist (see `habits` above).
    //
    // So the ratio can exceed 1, and that is the point: it clamps to a
    // full day, which is the honest reading of "you did at least as much
    // as you currently track". The alternative, filtering the numerator to
    // match, blanked out most of July while the month badge above it still
    // said 133 squares — the same screen telling two different stories.
    //
    // This does mean archiving a habit can turn a past day green. That is
    // a deliberate trade: `archivedAt` records the day you tidied up, not
    // the day you stopped, so leaving old obligations in the denominator
    // punishes people for pruning. One line to reverse if it ever gets
    // abused: put the filter back on the numerator.
    final liveIds = {for (final h in habits) h.id};
    final counts = ref.watch(habitYearHistoryProvider).maybeWhen(
          data: (mirror) => {
            ...derivedDayCounts(mirror, liveIds),
            todayKey: todayDone,
          },
          orElse: () => {...dash.dailyGreenCounts, todayKey: todayDone},
        );

    final today = DateTime.now().effectiveDay;
    final currentMonth = DateTime(today.year, today.month, 1);
    final months = _visibleMonths(
      currentMonth: currentMonth,
      counts: counts,
      isPremium: isPremium,
    );

    // Summary stats across exactly the months on screen, so the numbers
    // always agree with what the eye can verify below them.
    var total = 0;
    var activeDays = 0;
    var best = 0;
    for (final month in months) {
      final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
      for (var d = 1; d <= daysInMonth; d++) {
        final count =
            counts[DateTime(month.year, month.month, d).toDateKey()] ?? 0;
        if (count <= 0) continue;
        total += count;
        activeDays++;
        if (count > best) best = count;
      }
    }

    // Oldest at the top, current month last. The screen then opens at the
    // bottom so today is what you see, and scrolling UP walks back through
    // history, which is how every calendar app people already use behaves.
    final ordered = months.reversed.toList();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _landOnCurrentMonth());

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        title: Text(s.heatmapTitle),
      ),
      // Pinch-to-zoom over the whole map: two fingers zoom (smoothly,
      // centered on the pinch), one finger still scrolls the list normally.
      // panEnabled stays false on purpose — a one-finger pan would fight
      // the ListView's own scroll gesture for every drag; with it off the
      // two gestures never collide, and vertical travel while zoomed still
      // works through the list itself.
      body: SafeArea(
        child: Column(
          children: [
            // PINNED. These three numbers describe the whole record, so
            // they should not slide away the moment you look at a month.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.heatmapSubtitle,
                    style: TextStyle(
                        fontSize: 13, color: gp.textSec, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _StatTile(label: s.heatmapTotalGreen, value: '$total'),
                      const SizedBox(width: 10),
                      _StatTile(
                          label: s.heatmapActiveDays, value: '$activeDays'),
                      const SizedBox(width: 10),
                      _StatTile(
                        label: s.heatmapBestDay,
                        value: best == 0 ? '—' : '$best',
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 350.ms),
            Expanded(
              child: InteractiveViewer(
                panEnabled: false,
                maxScale: 2.5,
                child: ListView(
                  controller: _scroll,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    // The wall is at the TOP now: scrolling up is what runs
                    // you out of history, so that is where the offer goes.
                    if (!isPremium) ...[
                      _UpgradeForFullHistoryCard(
                        freeMonths: MonthlyHeatmapScreen._freeMonthsToShow,
                      ),
                      const SizedBox(height: 6),
                    ],
                    for (var i = 0; i < ordered.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: _MonthSection(
                          key: _keyFor(ordered[i]),
                          month: ordered[i],
                          counts: counts,
                          habits: habits,
                          today: today,
                          dark: dark,
                          onTapDay: (day, count) =>
                              _showDayInfo(context, day, count),
                          onTapMonth: () => _pickMonth(ordered, counts),
                        ),
                      ),
                    const SizedBox(height: 14),
                    // Sits directly under the current month, so it is on
                    // screen the moment the list lands.
                    _HeatLegend(dark: dark),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Newest first. Free: the current month and the two before it, always.
  /// Premium: every month from the earliest colored day on record to now —
  /// but never fewer than the free tier's three, so a brand-new Premium
  /// account still sees a full-looking screen instead of one lonely month.
  /// Tapping any month header opens the month list and scrolls to the
  /// month chosen.
  ///
  /// This screen is one long scroll of month sections, which for a Premium
  /// account can be years deep: reaching a month two winters back meant an
  /// unaided flick with no index and no way to aim. The header was the
  /// obvious thing to tap and did nothing at all.
  ///
  /// The picker deliberately lists MORE months than the screen renders. A
  /// free account only ever draws three sections, so without the locked
  /// months in the list there is nothing to tap to find out what is behind
  /// the gate — the same reason Monthly Story shows them. A locked month
  /// answers with the shared history gate and leaves the sheet open (see
  /// showMonthPicker), so the next tap can land on a month they do own.
  Future<void> _pickMonth(
    List<DateTime> rendered,
    Map<String, int> counts,
  ) async {
    final today = DateTime.now().effectiveDay;
    final currentMonth = DateTime(today.year, today.month, 1);

    // Every month from the earliest recorded day to now, so the list
    // doubles as the answer to "how far back does this go".
    DateTime earliest = currentMonth;
    for (final entry in counts.entries) {
      if (entry.value <= 0) continue;
      final parsed = DateTime.tryParse(entry.key);
      if (parsed == null) continue;
      final month = DateTime(parsed.year, parsed.month, 1);
      if (month.isBefore(earliest)) earliest = month;
    }
    final span = (currentMonth.year - earliest.year) * 12 +
        (currentMonth.month - earliest.month) +
        1;
    final months = [
      for (var i = 0; i < span.clamp(1, MonthlyHeatmapScreen._maxLifetimeMonths); i++)
        DateTime(currentMonth.year, currentMonth.month - i, 1),
    ];

    bool hasGreens(DateTime month) {
      final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
      for (var d = 1; d <= daysInMonth; d++) {
        if ((counts[DateTime(month.year, month.month, d).toDateKey()] ?? 0) > 0) {
          return true;
        }
      }
      return false;
    }

    final picked = await showMonthPicker(
      context,
      months: months,
      selected: currentMonth,
      isUnlocked: (month) => canBrowseHistoryMonth(
        monthStart: month,
        now: currentMonth,
        isPremium: ref.read(premiumProvider),
      ),
      hasStory: hasGreens,
    );
    if (picked == null || !mounted) return;

    final key = _monthKeys['${picked.year}-${picked.month}'];
    final target = key?.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: GameMotion.standard,
      curve: Curves.easeOutCubic,
      // Just under the top edge rather than flush against it, so the
      // month's own header is not the very first pixel on screen.
      alignment: 0.05,
    );
  }

  static List<DateTime> _visibleMonths({
    required DateTime currentMonth,
    required Map<String, int> counts,
    required bool isPremium,
  }) {
    var monthsBack = MonthlyHeatmapScreen._freeMonthsToShow;
    if (isPremium) {
      DateTime? earliest;
      for (final entry in counts.entries) {
        if (entry.value <= 0) continue;
        final parsed = DateTime.tryParse(entry.key);
        if (parsed == null) continue;
        if (earliest == null || parsed.isBefore(earliest)) earliest = parsed;
      }
      if (earliest != null) {
        final span = (currentMonth.year - earliest.year) * 12 +
            (currentMonth.month - earliest.month) +
            1;
        monthsBack = span.clamp(MonthlyHeatmapScreen._freeMonthsToShow, MonthlyHeatmapScreen._maxLifetimeMonths);
      }
    }
    return [
      for (var i = 0; i < monthsBack; i++)
        DateTime(currentMonth.year, currentMonth.month - i, 1),
    ];
  }

  /// Opens the full day breakdown — every habit's outcome that day (done,
  /// partial, slipped, skipped, missed) plus any note written from the
  /// Grid's long-press palette. Replaces the old one-line snackbar, which
  /// could only say "N squares" with no answer to "which ones, and why?".
  void _showDayInfo(BuildContext context, DateTime day, int count) {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _HeatDayDetailSheet(day: day),
    );
  }
}

/// Buckets a day's green count by what fraction of the user's current habit
/// list it represents — 100% is always the deepest green, 80%+ the next
/// shade down, and so on — rather than an absolute count that would never
/// reach full green for someone tracking only 2-3 habits.
/// How many habits are finished TODAY, counted from live state.
///
/// Today cannot come from either stored source. The habit-history mirror
/// is a cache of the daily documents and lags while the day is still being
/// written. And `DashboardState.dailyGreenCounts`, the rollup, does not
/// hold today either: probed on a real account at 16:41 with two habits
/// visibly completed and showing as مكتمل in this screen's own detail
/// sheet, the rollup reported ZERO for today's key. Its incremental
/// writers are not the only path by which a habit gets completed, so it
/// misses work as it happens, which is the same drift that left the
/// lifetime total 77 squares short.
///
/// `completions` is the live per-habit tally for today that the Dashboard
/// itself works from, so a habit counts once it has reached its own
/// frequencyTarget. That matches what the detail sheet calls مكتمل.
int _todayDoneCount(
  List<IslamicHabitTemplate> habits,
  Map<String, int> completions,
  WeeklyGridState grid,
) {
  final today = DateTime.now().effectiveDay;
  // The Grid must be showing the week that contains today, or squareFor
  // answers `none` for every habit and we would erase the day rather than
  // read it. Same guard the reports' withLiveToday uses, and for the same
  // reason.
  final gridKnowsToday = grid.weekStart == startOfGridWeek(today);
  var done = 0;
  for (final h in habits) {
    if (!h.isScheduledFor(today)) continue;
    final target = h.frequencyTarget < 1 ? 1 : h.frequencyTarget;
    final byCount = (completions[h.id] ?? 0) >= target;
    final bySquare = gridKnowsToday && grid.squareFor(h.id, today).isGreen;
    if (byCount || bySquare) done++;
  }
  return done;
}

/// How many habits were finished on each day, counting ONLY habits that
/// still exist and are not archived.
///
/// One set of habits decides the numerator, the denominator, the month
/// badges and the lifetime totals. That single rule is what keeps this
/// screen honest, and getting there took three wrong turns worth
/// recording, because each one is tempting on its own:
///
///  1. Counting every completion the mirror held against a denominator of
///     only current habits. 8 July had eleven DELETED habits completed and
///     two current ones missed, so the ratio passed 1, clamped, and
///     painted a glowing perfect day. A map that flatters is worse than no
///     map.
///  2. Adding those deleted habits to the denominator instead. Honest
///     arithmetic, but it filled the day sheet with eleven rows reading
///     «عادة محذوفة» and graded the user against habits they had already
///     thrown away.
///  3. Filtering the numerator but not the totals, which left July's badge
///     claiming 133 squares above a month of empty cells.
///
/// This account carried 24 orphaned ids, every one of them inside 13 June
/// to 29 July 2026, most with one or two days: a habit list that was being
/// rebuilt, not a record worth grading. Deleting a habit is a decision,
/// the same as archiving one, and neither should keep marking your past.
///
/// The cost is real and worth stating: a month spent on habits you have
/// since deleted now reads as quiet. That is the honest reading of "how
/// did I do at the habits I keep", and it can never overstate a day.
Map<String, int> derivedDayCounts(
  Map<String, Map<String, SquareState>> mirror,
  Set<String> countedHabitIds,
) {
  final out = <String, int>{};
  for (final habit in mirror.entries) {
    if (!countedHabitIds.contains(habit.key)) continue;
    for (final day in habit.value.entries) {
      if (markIsDone(day.value)) {
        out[day.key] = (out[day.key] ?? 0) + 1;
      }
    }
  }
  return out;
}

int heatLevel(int count, int totalHabits) {
  if (count <= 0) return 0;
  if (totalHabits <= 0) {
    // No habits currently tracked (e.g. all archived) — fall back to a
    // plain count scale so old green history still renders something.
    if (count <= 2) return 1;
    if (count <= 4) return 2;
    if (count <= 7) return 3;
    return 4;
  }
  final pct = count / totalHabits;
  if (pct >= 1.0) return 4;
  if (pct >= 0.8) return 3;
  if (pct >= 0.5) return 2;
  return 1;
}

Color heatColor(int level, bool dark) {
  if (level <= 0) return SquareState.none.fill(dark);
  const opacities = [0.0, 0.30, 0.50, 0.70, 0.92];
  return GameColors.emerald.withOpacity(opacities[level.clamp(1, 4)]);
}

// ─── One month's section: header + weekday row + true calendar grid ─────────

class _MonthSection extends StatelessWidget {
  final DateTime month;
  final Map<String, int> counts;
  final List<IslamicHabitTemplate> habits;
  final DateTime today;
  final bool dark;
  final void Function(DateTime day, int count) onTapDay;

  /// Opens the month picker. Every section's header calls the same one.
  final VoidCallback onTapMonth;

  const _MonthSection({
    super.key,
    required this.month,
    required this.counts,
    required this.habits,
    required this.today,
    required this.dark,
    required this.onTapDay,
    required this.onTapMonth,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final locale = Localizations.localeOf(context).languageCode;
    // toWesternDigits: the raw pattern renders «أغسطس ٢٠٢٦» while the
    // picker one tap away renders «أغسطس 2026», so the same month wore two
    // different years. ASCII digits everywhere is the app's rule — see
    // westernDate's doc comment.
    final monthLabel =
        toWesternDigits(DateFormat.yMMMM(locale).format(month));
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    // This month's own little total — lets the eye compare months at a
    // glance without reading individual cells.
    var monthGreens = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      monthGreens +=
          counts[DateTime(month.year, month.month, d).toDateKey()] ?? 0;
    }

    // Leading blanks so day 1 lands under its true weekday column —
    // startOfGridWeek keeps this in lockstep with the Victory Grid's own
    // Sat-first convention (same trick NightReviewHistoryScreen uses).
    final leading = month.difference(startOfGridWeek(month)).inDays;

    // Plain day-1-to-N order: the 1st sits in the top row, the last day in
    // the bottom row, exactly like every calendar anyone already uses.
    //
    // These weeks USED to be reversed. That was correct while the month
    // sections stacked newest-on-top, because otherwise the two directions
    // fought: day 1 at the top of a card read forward in time while the
    // card above it read backward. The section order has since flipped to
    // oldest-first, opening scrolled to the bottom, so the reversal now
    // creates exactly the contradiction it was added to prevent. Removing
    // it makes every direction on this screen agree again, in the other
    // direction: oldest up, newest down, within a month and across them.
    final cells = <int?>[
      for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= daysInMonth; d++) d,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final weeks = <List<int?>>[
      for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
    ];
    final orderedDays = weeks.expand((week) => week).toList();

    return Container(
      padding: const EdgeInsets.all(14),
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
              Expanded(
                // The header is the thing people instinctively tap to
                // change month, and it used to be inert text. Chevron so
                // it reads as a control rather than a caption.
                child: GestureDetector(
                  onTap: onTapMonth,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          monthLabel,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: gp.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.expand_more_rounded,
                          size: 16, color: gp.textSec),
                    ],
                  ),
                ),
              ),
              if (monthGreens > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: GameColors.emerald.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.grid_view_rounded,
                          size: 11, color: GameColors.emerald),
                      const SizedBox(width: 4),
                      Text(
                        '$monthGreens',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: GameColors.emerald,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // THE GRID IS LTR even though the app is RTL, and only the grid:
          // the month title and its badge above stay RTL with the rest of
          // the screen.
          //
          // A calendar month is a number line, and the numbers themselves
          // are western digits that read left to right. Mirroring the
          // weeks put the 1st on the right and ran the week leftward, so
          // each row's digits marched against the direction the digits
          // themselves are read. Left to right makes the whole grid scan
          // the same way its contents do, and matches the calendar app
          // people already have on the same phone.
          //
          // Saturday stays the first column, so it is now the LEFTMOST
          // one, and startOfGridWeek keeps the leading-blank maths correct
          // without any change: direction is presentation only here.
          Directionality(
            // ui.TextDirection: package:intl exports a TextDirection of
            // its own that shadows dart:ui's in this file.
            textDirection: ui.TextDirection.ltr,
            child: Column(
              children: [
                const _WeekdayHeaderRow(),
                const SizedBox(height: 4),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  children: [
                    for (final d in orderedDays)
                      if (d == null)
                        const SizedBox.shrink()
                      else
                        _dayCell(DateTime(month.year, month.month, d)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day) {
    final count = counts[day.toDateKey()] ?? 0;
    final scheduled = habits.where((h) => h.isScheduledFor(day)).length;
    return _HeatCell(
      day: day,
      count: count,
      totalHabits: scheduled,
      dark: dark,
      // Same exemption as the Grid's own cells: the real calendar day
      // during the window right after midnight isn't "future" just because
      // effectiveDay hasn't caught up yet — see DateTimeGameExt.isRealToday.
      isFuture: day.isAfter(today) && !day.isRealToday,
      onTap: onTapDay,
    );
  }
}

/// Sat → Fri, matching the Victory Grid's own week convention so this
/// calendar's rhythm never disagrees with the rest of the app.
class _WeekdayHeaderRow extends StatelessWidget {
  const _WeekdayHeaderRow();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final locale = Localizations.localeOf(context).languageCode;
    // Any real Saturday works as a labeling anchor — today's own grid week
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
                // seven distinct letters (ح ن ث ر خ ج س), and is unchanged for
                // English (S M T W T F S). Same choice as insights_screen.
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

/// What a day's cell is, categorically. Three PAINTED states, not five
/// shades of one.
///
/// The old scale bucketed a percentage into four opacities of emerald
/// (0.30 / 0.50 / 0.70 / 0.92). Two things broke it:
///
///   1. On a #07100D background those opacities are not far enough apart
///      to rank by eye. Most of a month collapsed into two visible greens.
///   2. Buckets discard the difference inside them. With eleven habits the
///      steps are 9.1%, so 7/11 (63.6%) and 8/11 (72.7%) are DIFFERENT
///      DAYS that land in the same bucket and paint identically. The user
///      who reported this was looking at exactly that.
///
/// So the level no longer carries the amount. [_DayFill] says which of
/// three pictures to draw, and inside `partial` the amount is carried by
/// the HEIGHT the colour climbs, which is a non-colour channel: it ranks
/// by eye at a glance, survives greyscale, and survives colourblindness.
enum _DayFill { rest, empty, partial, full }

_DayFill dayFill(int done, int planned) {
  if (planned <= 0) {
    // Nothing was owed. Work done anyway still reads as a full day; a day
    // with nothing owed and nothing done is a REST day, not a failure —
    // the same position the streak already takes (see commit bce64ff).
    return done > 0 ? _DayFill.full : _DayFill.rest;
  }
  if (done <= 0) return _DayFill.empty;
  return done >= planned ? _DayFill.full : _DayFill.partial;
}

class _HeatCell extends StatelessWidget {
  final DateTime day;
  final int count;
  final int totalHabits;
  final bool dark;
  final bool isFuture;
  final void Function(DateTime day, int count) onTap;

  const _HeatCell({
    required this.day,
    required this.count,
    required this.totalHabits,
    required this.dark,
    required this.isFuture,
    required this.onTap,
  });

  /// The bar is solid, never translucent. Opacity on a near-black card is
  /// what made the old scale unreadable in the first place.
  Color get _bar => GameColors.emerald;

  /// Ink that reads on a solid [_bar] fill. Same 0.1791 luminance
  /// crossover [GameColors.onEmerald] already uses, so it stays correct on
  /// the darker, moodier presets where white would win instead of black.
  Color get _onBar => GameColors.onEmerald;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final fill = dayFill(count, totalHabits);

    // A future date is a date and nothing else: no plate, no border. The
    // old blanket Opacity(0.25) rendered the rest of the month at roughly
    // 1.3:1 against the card, which is not dimmed, it is illegible.
    if (isFuture) {
      return AspectRatio(
        aspectRatio: 1,
        child: Center(
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: gp.textTert,
            ),
          ),
        ),
      );
    }

    final isFull = fill == _DayFill.full;
    final isRest = fill == _DayFill.rest;

    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTap: () => onTap(day, count),
        child: LayoutBuilder(
          builder: (context, box) {
            final side = box.maxHeight;
            // The number lives in the top strip and the bar is capped
            // below it, so a 10.5pt glyph is never half on emerald and
            // half on the track. It also means a full day is the ONLY
            // cell whose colour reaches the top edge, which is what makes
            // "is this day complete" a yes/no question rather than a
            // ranking one.
            const numberStrip = 12.0;
            final zone = (side - numberStrip).clamp(0.0, double.infinity);
            final ratio = totalHabits <= 0
                ? 0.0
                : (count / totalHabits).clamp(0.0, 1.0);
            // The 4pt base is not a floor that distorts the scale: every
            // step stays equal, it just stops 1-of-11 rendering as a
            // hairline nobody can see.
            final barHeight = fill == _DayFill.partial
                ? 4.0 + (zone - 4.0) * ratio
                : 0.0;

            return Container(
              decoration: BoxDecoration(
                color: isFull
                    ? _bar
                    : (isRest ? Colors.transparent : gp.surfaceHL),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: day.isToday
                      ? GameColors.gold
                      : (isFull ? _onBar.withOpacity(0.28) : gp.border),
                  // isToday (effectiveDay), NOT isRealToday — see the
                  // note in _dayCell.
                  width: day.isToday ? 1.4 : (isFull ? 1.2 : 0.5),
                ),
                // The glow the perfect day earns. Blur exceeds the gutter
                // between cells on purpose, so a run of complete days
                // merges into one band of light and a perfect week looks
                // like a streak rather than seven separate stickers.
                boxShadow: isFull
                    ? [
                        BoxShadow(
                          color: _bar.withOpacity(dark ? 0.42 : 0.28),
                          blurRadius: dark ? 9 : 6,
                          spreadRadius: dark ? 0 : 0.5,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(
                  children: [
                    if (barHeight > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: barHeight,
                        child: ColoredBox(color: _bar),
                      ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: isFull ? 11 : 10.5,
                            fontWeight: day.isToday
                                ? FontWeight.w800
                                : (isFull ? FontWeight.w800 : FontWeight.w700),
                            color: day.isToday
                                ? GameColors.gold
                                : (isFull
                                    ? _onBar
                                    : (isRest
                                        ? gp.textTert
                                        : gp.textPrimary)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Day detail sheet ────────────────────────────────────────────────────────

/// One habit's resolved outcome for the tapped day, ready to render.
class _DayHabitOutcome {
  final String name;
  final bool isDeleted;
  final SquareState state;
  final String note;
  const _DayHabitOutcome({
    required this.name,
    required this.isDeleted,
    required this.state,
    required this.note,
  });
}

/// The tapped day's full story, loaded straight from its daily doc — the
/// same `squareStates`/`squareNotes` fields the Grid's long-press palette
/// writes, so every action chosen there (skip, slip, bonus, partial) and
/// every note shows up here exactly as recorded. Habits scheduled that day
/// with no mark at all render as "not done", so misses are visible too, not
/// just wins. One caveat inherited from the data model: the schedule check
/// uses the *current* habit list (past days don't store what was scheduled
/// back then), so a habit added today also shows "not done" on older days.
class _HeatDayDetailSheet extends ConsumerWidget {
  final DateTime day;
  const _HeatDayDetailSheet({required this.day});

  Future<Map<String, dynamic>> _loadDayDoc(String? uid) async {
    try {
      if (uid != null) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('daily')
            .doc(day.toDateKey())
            .get();
        return snap.data() ?? const {};
      }
      return await LocalStoreService.getDailyMap(day.toDateKey());
    } catch (_) {
      return const {};
    }
  }

  List<_DayHabitOutcome> _outcomes(
    Map<String, dynamic> doc,
    List<IslamicHabitTemplate> habits,
    bool isAr,
    String deletedLabel,
  ) {
    final rawStates = (doc['squareStates'] as Map?) ?? const {};
    final rawNotes = (doc['squareNotes'] as Map?) ?? const {};
    // Multi-tap habits (weekly 3x etc.) completed through Today never get
    // a Grid square mirrored (completeHabit's single-tap-only sync rule) —
    // their record lives in habitCompletions instead. Read both, or every
    // such habit would show "Not done" on days it was genuinely finished.
    final rawCompletions = (doc['habitCompletions'] as Map?) ?? const {};

    // Union of "scheduled that day per the current list" and "has any mark
    // or completion on record" — the record half is what keeps a
    // since-deleted habit's history honest instead of silently vanishing
    // from past days.
    // Only habits that still exist, matching the cell above exactly. Marks
    // left behind by deleted habits are ignored rather than listed as
    // «عادة محذوفة»: this account held 24 such ids from a habit list that
    // was being rebuilt, and eleven of them landed on a single day. They
    // are not history the user recognises, and the cell no longer counts
    // them, so the sheet must not either.
    final known = {for (final h in habits) h.id};
    final ids = <String>{
      for (final h in habits)
        if (h.isScheduledFor(day)) h.id,
      ...rawStates.keys.map((k) => k.toString()).where(known.contains),
      for (final e in rawCompletions.entries)
        if (e.value is num &&
            (e.value as num) > 0 &&
            known.contains(e.key.toString()))
          e.key.toString(),
    };

    final byId = {for (final h in habits) h.id: h};
    SquareState stateFor(String id) {
      final marked = SquareState.fromJson(rawStates[id]?.toString());
      if (marked != SquareState.none) return marked;
      final done = rawCompletions[id];
      return done is num && done > 0 ? SquareState.complete : SquareState.none;
    }

    final outcomes = <_DayHabitOutcome>[
      for (final id in ids)
        _DayHabitOutcome(
          name: byId[id]?.localName(isAr) ?? deletedLabel,
          isDeleted: byId[id] == null,
          state: stateFor(id),
          note: (rawNotes[id] as String?)?.trim() ?? '',
        ),
    ];

    // Marked outcomes first (the day's actual story), misses last — and a
    // stable order inside each group so the sheet doesn't reshuffle
    // between opens.
    outcomes.sort((a, b) {
      final ga = a.state == SquareState.none ? 1 : 0;
      final gb = b.state == SquareState.none ? 1 : 0;
      if (ga != gb) return ga - gb;
      return a.name.compareTo(b.name);
    });
    return outcomes;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final dateLabel = DateFormat('EEEE, MMM d', locale).format(day);
    final uid = ref.watch(authStateProvider).asData?.value?.uid;
    // allHabitsEverProvider so an archived (not hard-deleted) habit still
    // resolves to its real name here instead of falling all the way back
    // to [deletedLabel] — see [_outcomesFor]'s isDeleted union above.
    // Archived habits are dropped here too, so the sheet and the cell can
    // never disagree about what a day owed.
    final habits = ref
        .watch(allHabitsEverProvider)
        .where((h) => h.archivedAt == null)
        .toList();

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              dateLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: gp.textTert,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _loadDayDoc(uid),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: CircularProgressIndicator(
                            color: GameColors.gold, strokeWidth: 2),
                      ),
                    );
                  }
                  final outcomes = _outcomes(
                    snap.data!,
                    habits,
                    s.isAr,
                    s.gridJournalDeletedHabit,
                  );
                  if (outcomes.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          s.heatmapDayEmpty,
                          style:
                              TextStyle(fontSize: 13, color: gp.textTert),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: outcomes.length,
                    separatorBuilder: (_, __) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Container(height: 0.5, color: gp.border),
                    ),
                    itemBuilder: (context, i) =>
                        _OutcomeRow(outcome: outcomes[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutcomeRow extends StatelessWidget {
  final _DayHabitOutcome outcome;
  const _OutcomeRow({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final state = outcome.state;
    final accent = state.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                state.icon ?? Icons.circle_outlined,
                size: 15,
                color: accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                outcome.name,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  fontStyle:
                      outcome.isDeleted ? FontStyle.italic : FontStyle.normal,
                  color:
                      outcome.isDeleted ? gp.textTert : gp.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
              ),
              child: Text(
                s.isAr ? state.labelAr : state.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
        if (outcome.note.isNotEmpty)
          Padding(
            // Indented under the name, aligned past the icon tile.
            padding: const EdgeInsetsDirectional.only(start: 40, top: 4),
            child: Text(
              outcome.note,
              style: TextStyle(
                fontSize: 12.5,
                color: gp.textSec,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Legend ───────────────────────────────────────────────────────────────

class _HeatLegend extends StatelessWidget {
  final bool dark;
  const _HeatLegend({required this.dark});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(s.heatmapLess,
            style: TextStyle(fontSize: 11, color: gp.textTert)),
        const SizedBox(width: 6),
        for (var level = 0; level <= 4; level++)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: heatColor(level, dark),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        const SizedBox(width: 2),
        Text(s.heatmapMore,
            style: TextStyle(fontSize: 11, color: gp.textTert)),
      ],
    );
  }
}

// ─── Stat tile ─────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
                height: 1,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: gp.textTert,
                letterSpacing: 0.6,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Upgrade card (free tier only) ─────────────────────────────────────────

class _UpgradeForFullHistoryCard extends StatelessWidget {
  final int freeMonths;
  const _UpgradeForFullHistoryCard({required this.freeMonths});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.pushNamed(context, '/premium');
      },
      borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: GameColors.gold.withOpacity(gp.dark ? 0.10 : 0.08),
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: GameColors.gold.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: GameColors.gold.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_clock_rounded,
                  size: 20, color: GameColors.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.heatmapUpgradeTitle,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.heatmapUpgradeBody(freeMonths),
                    style: TextStyle(
                        fontSize: 12, color: gp.textSec, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: gp.textTert),
          ],
        ),
      ),
    );
  }
}
