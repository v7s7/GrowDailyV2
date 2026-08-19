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
import '../../premium/notifiers/premium_notifier.dart';
import '../../../shared/widgets/month_picker_sheet.dart';
import '../models/square_state.dart';
import '../notifiers/weekly_grid_notifier.dart' show startOfGridWeek;

/// A month-by-month heatmap of green squares — one real calendar section per
/// month (correct 28/29/30/31-day grids, Sat-first weeks matching the
/// Victory Grid), newest month on top, instead of the old GitHub-style
/// week-columns strip that gave the eye no month boundaries to hold on to.
/// Reads straight from [DashboardState.dailyGreenCounts] — a rollup already
/// loaded with the rest of the dashboard — so even the Premium lifetime view
/// opens instantly with no extra reads; the whole history is already in that
/// one map.
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
    final counts = ref.watch(dashboardProvider).dailyGreenCounts;
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
    final habits = ref.watch(allHabitsEverProvider);

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
        child: InteractiveViewer(
          panEnabled: false,
          maxScale: 2.5,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
            Text(
              s.heatmapSubtitle,
              style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.4),
            ).animate().fadeIn(duration: 350.ms),
            const SizedBox(height: 16),
            Row(
              children: [
                _StatTile(label: s.heatmapTotalGreen, value: '$total'),
                const SizedBox(width: 10),
                _StatTile(label: s.heatmapActiveDays, value: '$activeDays'),
                const SizedBox(width: 10),
                _StatTile(
                  label: s.heatmapBestDay,
                  value: best == 0 ? '—' : '$best',
                ),
              ],
            ).animate(delay: 60.ms).fadeIn(duration: 350.ms),
            const SizedBox(height: 8),
            for (var i = 0; i < months.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: _MonthSection(
                  key: _keyFor(months[i]),
                  month: months[i],
                  counts: counts,
                  habits: habits,
                  today: today,
                  dark: dark,
                  onTapDay: (day, count) => _showDayInfo(context, day, count),
                  onTapMonth: () => _pickMonth(months, counts),
                )
                    // Only stagger the first screenful — a lifetime list
                    // shouldn't make month #40 wait seconds to appear.
                    .animate(delay: (100 + (i < 4 ? i * 70 : 280)).ms)
                    .fadeIn(duration: 350.ms),
              ),
            const SizedBox(height: 16),
            _HeatLegend(dark: dark),
            if (!isPremium) ...[
              const SizedBox(height: 18),
              _UpgradeForFullHistoryCard(
                freeMonths: MonthlyHeatmapScreen._freeMonthsToShow,
              ).animate(delay: 200.ms).fadeIn(duration: 350.ms),
            ],
          ],
          ),
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

    // Sections stack newest-month-on-top (_visibleMonths), so left as plain
    // day-1-to-N order this block would fight that: day 1 at the *top* of
    // July's card reads forward in time, while July's card sitting above
    // June's reads backward — two directions stacked on each other. Flip
    // whole calendar *weeks* here (not individual days, which would shuffle
    // which weekday column a day sits in under _WeekdayHeaderRow) so the
    // most recent week of the month is the top row and the first week is
    // the bottom row. That makes every direction on this screen agree:
    // newest is always up, oldest is always down, top of the list to the
    // bottom — today included, which is why it never needs a scroll.
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
    final reversedDays = weeks.reversed.expand((week) => week).toList();

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
          const _WeekdayHeaderRow(),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (final d in reversedDays)
                if (d == null)
                  const SizedBox.shrink()
                else
                  _dayCell(DateTime(month.year, month.month, d)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day) {
    final count = counts[day.toDateKey()] ?? 0;
    final scheduled =
        habits.where((h) => h.isScheduledFor(day)).length;
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

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final level = heatLevel(count, totalHabits);
    // The day number stays visible on every cell (unlike the old strip's
    // anonymous squares) — that's what makes this read as a real calendar:
    // "the 14th was a strong day" needs no counting on fingers.
    final numberColor = level >= 3
        ? Colors.white
        : (level > 0 ? gp.textPrimary : gp.textTert);
    return AspectRatio(
      aspectRatio: 1,
      child: Opacity(
        opacity: isFuture ? 0.25 : 1,
        child: GestureDetector(
          onTap: isFuture ? null : () => onTap(day, count),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: heatColor(level, dark),
              borderRadius: BorderRadius.circular(7),
              // isToday (effectiveDay), NOT isRealToday. Every cell on
              // this grid IS an effective day: dailyGreenCounts is keyed
              // by DateTime.now().effectiveDay.toDateKey(), so a square
              // coloured at 2am lands on the previous cell. Ringing the
              // real calendar day therefore marked a cell that cannot
              // receive today's work — and on the 1st of a month before
              // 6am it marked a cell in a month this screen does not even
              // render (the newest section is effectiveDay's month), so
              // the ring vanished entirely.
              border: Border.all(
                color: day.isToday ? GameColors.gold : gp.border,
                width: day.isToday ? 1.4 : 0.5,
              ),
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    day.isToday ? FontWeight.w800 : FontWeight.w600,
                color: day.isToday ? GameColors.gold : numberColor,
              ),
            ),
          ),
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
    final ids = <String>{
      for (final h in habits)
        if (h.isScheduledFor(day)) h.id,
      ...rawStates.keys.map((k) => k.toString()),
      for (final e in rawCompletions.entries)
        if (e.value is num && (e.value as num) > 0) e.key.toString(),
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
    final habits = ref.watch(allHabitsEverProvider);

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
