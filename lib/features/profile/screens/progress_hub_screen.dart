import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// hide TextDirection: intl's own TextDirection enum (LTR/RTL/UNKNOWN) would
// otherwise collide with dart:ui/material's TextDirection (ltr/rtl) the
// moment either is referenced unqualified anywhere in this library -
// _ProgressReportBody's chart Row below needs the material one. Same fix as
// profile_screen.dart/room_detail_screen.dart's identical import.

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/bidi_fraction.dart';
import '../../../core/utils/western_digits.dart';
import '../../../features/achievements/models/achievement_model.dart';
import '../../../features/achievements/widgets/achievement_medal.dart';
import '../../../features/achievements/widgets/tier_detail_sheet.dart';
import '../../../features/achievements/widgets/tier_palette.dart';
import '../../../features/auth/notifiers/auth_notifier.dart';
import '../../../features/dashboard/notifiers/dashboard_notifier.dart';
import '../../../features/grid/models/square_state.dart';
import '../../../features/grid/notifiers/grid_journal_notifier.dart';
import '../../../features/grid/screens/grid_journal_screen.dart';
import '../../../features/grid/screens/grid_screen.dart' show categoryVisual;
import '../../../features/habits/models/habit_model.dart' show HabitCategory;
import '../../../features/habits/notifiers/custom_habits_notifier.dart';
import '../../../features/insights/insight_engine.dart';
import '../../../features/insights/insights_screen.dart';
import '../../../features/premium/notifiers/premium_notifier.dart';
import 'achievements_screen.dart';

// ─── 14-day progress chart data (moved verbatim from the old standalone ───
// ProgressScreen, now retired — see ProgressHubScreen's own doc comment) ───

class ProgressPoint {
  final DateTime date;
  final int completions;

  /// habitId -> times completed that day, and habitId -> the note / advanced
  /// state left on that square from Grid's long-press editor. All three come
  /// out of the *same* per-day `daily` document the completion count is
  /// already read from (`habitCompletions`, `squareNotes`, `squareStates` —
  /// see WeeklyGridNotifier._persistSquare and grid_journal_notifier.dart),
  /// so carrying them costs no extra reads at all: the chart was already
  /// fetching these documents and throwing everything except one integer
  /// away.
  ///
  /// Habit *names* are deliberately not stored here — squareStates/
  /// habitCompletions only ever keyed by habitId, so there's nothing to
  /// denormalize. [_DayDetailSheet] resolves names live from
  /// habitListProvider at render time, the same "resolve live, explain if
  /// it's gone" approach GridJournalScreen already uses for the identical
  /// situation.
  final Map<String, int> habitCompletions;
  final Map<String, String> notes;
  final Map<String, SquareState> states;

  const ProgressPoint({
    required this.date,
    required this.completions,
    this.habitCompletions = const {},
    this.notes = const {},
    this.states = const {},
  });

  /// Every habitId worth a row in the day sheet: anything completed, plus
  /// anything carrying a note or a Skipped/Failed/Bonus mark even if it was
  /// never completed — a day someone skipped everything and wrote down why
  /// is exactly the day worth opening.
  Set<String> get detailedHabitIds => {
        ...habitCompletions.keys,
        ...notes.keys.where((k) => (notes[k] ?? '').trim().isNotEmpty),
        ...states.keys.where((k) =>
            states[k] != null && states[k] != SquareState.none),
      };

  bool get hasDetail => detailedHabitIds.isNotEmpty;
}

// autoDispose: this section is only ever visible while ProgressHubScreen is
// on screen, so it fully tears down on pop. Without autoDispose this plain
// FutureProvider would compute once, cache forever, and never refetch —
// complete a habit on Dashboard, come back here, and the chart (including
// "today") would still show whatever was true the first time this was ever
// opened this session, since the only thing that would invalidate it is
// authStateProvider changing (sign in/out), not new completions.
// autoDispose means it's torn down the moment this screen is popped, so
// reopening it always re-fetches fresh instead.
final progressReportProvider =
    FutureProvider.autoDispose<List<ProgressPoint>>((ref) async {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;

  final today = DateTime.now().effectiveDay;
  final days = List.generate(14, (i) {
    final d = today.subtract(Duration(days: 13 - i));
    return DateTime(d.year, d.month, d.day);
  });
  if (uid == null) {
    final logs = await Future.wait(
      days.map((d) => LocalStoreService.getDailyMap(_dateKey(d))),
    );
    return [
      for (var i = 0; i < days.length; i++) _pointFrom(days[i], logs[i]),
    ];
  }

  final col = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('daily');
  final docs = await Future.wait(days.map((d) => col.doc(_dateKey(d)).get()));

  return [
    for (var i = 0; i < days.length; i++) _pointFrom(days[i], docs[i].data()),
  ];
});

String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

int _completionCount(Map<String, dynamic>? data) {
  final raw = data?['habitCompletions'] as Map<String, dynamic>? ?? {};
  return raw.values.fold<int>(0, (sum, value) => sum + (value as num).toInt());
}

/// Builds one day's full [ProgressPoint] from its raw `daily` document.
///
/// One helper for both the guest (Hive) and signed-in (Firestore) paths
/// below, which read the same shape from different stores — previously each
/// built its own ProgressPoint inline, so the detail parsing would have had
/// to be written (and kept in sync) twice.
///
/// Defensive about every field independently: a malformed or missing map
/// degrades that one map to empty rather than losing the whole day, which
/// matters because these documents are written by several different
/// features (Grid, Dashboard, Night Review) across app versions.
ProgressPoint _pointFrom(DateTime day, Map<String, dynamic>? data) {
  final rawCompletions = data?['habitCompletions'];
  final rawNotes = data?['squareNotes'];
  final rawStates = data?['squareStates'];
  return ProgressPoint(
    date: day,
    completions: _completionCount(data),
    habitCompletions: rawCompletions is Map
        ? rawCompletions.map((k, v) =>
            MapEntry(k.toString(), (v as num?)?.toInt() ?? 0))
        : const {},
    notes: rawNotes is Map
        ? rawNotes.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
        : const {},
    states: rawStates is Map
        ? rawStates.map((k, v) =>
            MapEntry(k.toString(), SquareState.fromJson(v?.toString())))
        : const {},
  );
}

/// Rolls [DashboardState.categoryCompletions]' raw keys up to one count per
/// broad display category (HabitCategory's 9-value set: faith/health/
/// learning/focus/sleep/money/mind/social/custom). Raw keys are a mix of
/// two granularities depending on *when* each completion was recorded: the
/// fine-grained catalog categories (quran/athkar/fitness/fasting/sadaqah)
/// for anything completed after IslamicHabitTemplate.fromMap's category-
/// recovery fix (see that factory's doc comment), and the already-collapsed
/// broad ones for anything recorded before it. Without this rollup, "Quran"
/// and "Faith" would show as two separate rows for what a user experiences
/// as the same life area — this reuses HabitCategory.toJson's existing
/// collapse rule (round-tripping each key through fromJson().toJson().
/// fromJson()) rather than inventing a second one. Pure; no Firestore/
/// Riverpod involved, so this is trivially unit-testable.
Map<HabitCategory, int> aggregateCategoryCompletions(Map<String, int> raw) {
  final out = <HabitCategory, int>{};
  for (final entry in raw.entries) {
    if (entry.value <= 0) continue;
    final display =
        HabitCategory.fromJson(HabitCategory.fromJson(entry.key).toJson());
    out[display] = (out[display] ?? 0) + entry.value;
  }
  return out;
}

// ─── The screen ─────────────────────────────────────────────────────────────

/// Pushed from Profile's single "Dashboard" row — replaces what used to be
/// three separate rows (Achievements, Habit Insights, Progress & Streak)
/// and three separate screens with one destination, three sections:
///
///  - Progress: a 14-day bar chart with each day's real completion count
///    shown as a number, not just implied by a curve's height (see
///    _ProgressBarColumn) — free, ungated. The streak-freeze shop card that
///    used to sit at the top of this section has moved to
///    CharacterClosetScreen: it's a gold purchase, and this page is now
///    purely "look back at your progress," nothing to buy on it.
///  - Achievements: a compact horizontal preview (unlocked first, then the
///    closest-to-unlock rung of each family), with "View all" opening
///    [AchievementsScreen]. Each medal opens the same tier sheet its
///    counterpart on the full screen does — see [showTierDetailSheet].
///  - Category breakdown: lifetime completions per broad habit category,
///    as a share of the total.
///  - Habit Insights: a compact preview of the real headline insight plus
///    "View full Insights" opening [InsightsScreen] — which itself now
///    shows a complete free tier (every headline, your strongest habit's
///    real row) with Premium's per-habit breakdown as an add-on underneath,
///    not a locked door. See that screen's own doc comment for why.
///  - Habit Notes: a compact preview of the most recent notes/Skipped/
///    Failed/Bonus entries plus "View all" opening [GridJournalScreen] —
///    moved here from its own icon atop the Grid screen (see
///    _JournalPreviewSection's doc comment for why), the same "recent
///    preview + full screen underneath" shape as Achievements/Insights
///    above.
class ProgressHubScreen extends ConsumerWidget {
  const ProgressHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final state = ref.watch(dashboardProvider);

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(s.progressTitle,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary)),
      ),
      // Everything here is period-agnostic on purpose: a 14-day chart,
      // lifetime medals, a lifetime category share, the newest notes. The
      // أسبوعي / شهري / سنوي report is NOT here, it is its own destination
      // (see ReportsScreen). They shared this scroll for exactly one round
      // and the medals ended up reading as part of whichever month was
      // being viewed above them, which is the confusion that split them.
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SectionHeader(s.progressStreakTitle),
          const SizedBox(height: 12),
          // Streak Freeze purchase card used to live here (gated on a 3-day
          // streak) — relocated to CharacterClosetScreen since this page is
          // now purely "look back at your progress" and a gold-spending shop
          // card interrupted that. See closet screen's own section for the
          // exact same card, gating, and reasoning.
          _ProgressReportCard(state: state),
          const SizedBox(height: 28),
          _AchievementsPreviewSection(state: state),
          const SizedBox(height: 28),
          _CategoryBreakdownSection(state: state),
          const SizedBox(height: 28),
          const _InsightsPreviewSection(),
          const SizedBox(height: 28),
          const _JournalPreviewSection(),
        ],
      ),
    );
  }
}

/// The small caps label style already used throughout Profile/Settings
/// (PROFILE, SETTINGS, OVERVIEW) — `.toUpperCase()` here so section titles
/// that are normally mixed-case elsewhere (e.g. "Habit Insights" as an
/// AppBar title) read consistently with that convention in this one place.
/// A no-op for Arabic, which has no case distinction.
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Text(
      title.toUpperCase(),
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: gp.textSec,
          letterSpacing: 1.5),
    );
  }
}

// ─── Progress section (unchanged content, moved from ProgressScreen) ──────

class _ProgressReportCard extends ConsumerWidget {
  final DashboardState state;
  const _ProgressReportCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(progressReportProvider);
    return report.when(
      data: (points) {
        final chartPoints = points.isEmpty
            ? _guestPoints(state.completions.values.fold<int>(
                0,
                (sum, count) => sum + count,
              ))
            : points;
        return _ProgressReportBody(points: chartPoints, state: state);
      },
      loading: () => _ProgressReportBody(
        points: _guestPoints(0),
        state: state,
        isLoading: true,
      ),
      error: (_, __) => _ProgressReportBody(
        points: _guestPoints(state.completions.values.fold<int>(
          0,
          (sum, count) => sum + count,
        )),
        state: state,
      ),
    );
  }

  List<ProgressPoint> _guestPoints(int todayCompletions) {
    final today = DateTime.now().effectiveDay;
    return List.generate(14, (i) {
      final date = today.subtract(Duration(days: 13 - i));
      return ProgressPoint(
        date: DateTime(date.year, date.month, date.day),
        completions: i == 13 ? todayCompletions : 0,
      );
    });
  }
}

class _ProgressReportBody extends StatelessWidget {
  final List<ProgressPoint> points;
  final DashboardState state;
  final bool isLoading;

  const _ProgressReportBody({
    required this.points,
    required this.state,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final total = points.fold<int>(0, (sum, p) => sum + p.completions);
    final best = points.fold<int>(
        0, (best, p) => p.completions > best ? p.completions : best);
    final activeDays = points.where((p) => p.completions > 0).length;
    final trendUp = points.length > 7 &&
        points.skip(7).fold<int>(0, (sum, p) => sum + p.completions) >=
            points.take(7).fold<int>(0, (sum, p) => sum + p.completions);
    // Three states, not two. `trendUp` compares the last 7 days against the
    // previous 7 with `>=`, so a completely empty fortnight scores 0 >= 0
    // and came out as "holding strong" — the app congratulating someone on
    // a chart with nothing in it, which is the fastest way to make every
    // other encouraging line on the screen read as noise. An empty window
    // now says so plainly instead of guessing at a trend that doesn't exist.
    final subtitle = isLoading
        ? s.loadingReport
        : total == 0
            ? s.noProgressYet
            : trendUp
                ? s.holdingStrong
                : s.startAgain;

    return Container(
      padding: const EdgeInsets.all(18),
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
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: GameColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
                ),
                child: Icon(Icons.show_chart_rounded,
                    color: GameColors.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.fourteenDayProgress,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: gp.textSec),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // textDirection: TextDirection.ltr — pinned regardless of app
          // locale. points is oldest-first, today last (see
          // progressReportProvider), and reading left-to-right with today
          // on the right is the whole point of a chronological chart like
          // this - a plain Row would otherwise mirror it to right-to-left
          // under Arabic (Row always follows the ambient Directionality
          // unless told not to), putting today on the left and running the
          // calendar backwards. Each bar's own day-of-month label already
          // renders correctly either way, since that's text content, not
          // position - only the columns' left-right order needed pinning.
          Row(
            textDirection: TextDirection.ltr,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < points.length; i++)
                Expanded(
                  child: _ProgressBarColumn(
                    point: points[i],
                    maxValue: best <= 0 ? 1 : best,
                    isToday: i == points.length - 1,
                    locale: locale,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _MiniReportStat(label: s.total, value: '$total'),
              const SizedBox(width: 8),
              _MiniReportStat(label: s.activeDays, value: '$activeDays/14'),
              const SizedBox(width: 8),
              _MiniReportStat(label: s.bestDay, value: '$best'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniReportStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniReportStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final isAr = S.of(context).isAr;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: gp.textPrimary,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              // 8pt was below anything legible, and the 1.0 letter-spacing
              // made the Latin worse while doing nothing at all for Arabic,
              // which has no letter-spacing concept in this sense — the
              // shaping joins regardless. Both fixed here; the spacing is
              // now Latin-only, matching how every other small-caps label in
              // this app is written.
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: gp.textTert,
                letterSpacing: isAr ? 0 : 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One column of the 14-day bar chart — a numeric completion count sitting
/// directly on top of a bar sized relative to the busiest day in the
/// window, with a narrow weekday initial below. Replaces the old smooth
/// line/area chart: for a small, countable metric like "habits done today",
/// research into habit-tracker UX consistently favors bars with the actual
/// number visible over a curve the eye has to interpolate — see this
/// screen's redesign notes for the competitive patterns that drove this.
class _ProgressBarColumn extends StatelessWidget {
  final ProgressPoint point;
  final int maxValue;
  final bool isToday;
  final String locale;

  static const double _trackHeight = 72;

  const _ProgressBarColumn({
    required this.point,
    required this.maxValue,
    required this.isToday,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final hasData = point.completions > 0;
    final barColor = isToday
        ? GameColors.gold
        : hasData
            ? GameColors.success
            : gp.border;
    // A zero-completion day still gets a small visible sliver instead of an
    // empty gap — a blank column reads as "missing data" next to 13 others
    // that all have real bars, not "zero, on purpose".
    final barHeight = hasData
        ? (_trackHeight * (point.completions / maxValue))
            .clamp(6.0, _trackHeight)
            .toDouble()
        : 3.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showDayDetailSheet(context, point, locale),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${point.completions}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: hasData ? gp.textPrimary : gp.textTert,
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: _trackHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                width: double.infinity,
                height: barHeight,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // The day-of-month number, not a bare weekday initial — 'EEEEE'
          // (Tu/Th both read "T", Sa/Su both read "S") made it impossible
          // to tell which actual day a column was without counting from
          // today.
          //
          // Plain interpolation rather than DateFormat('d', locale). Routed
          // through DateFormat, this axis rendered ٣ ٤ ٥ directly beneath
          // the ASCII completion counts sitting on top of the very same
          // bars — two numeral systems in one column. Interpolating the day
          // fixes it (verified on device, Arabic locale).
          //
          // Worth knowing what it was *not*: `DateFormat('d', 'ar')` returns
          // the ASCII string "3" in a plain test process — only 'ar_EG' and
          // friends carry Arabic-Indic symbol data — so this is not intl
          // choosing digits for the locale, and "just pass 'en'" would have
          // been a fix for a cause that isn't there. The substitution
          // happens further down, at render; reminder_picker.dart's
          // reminderOffsetLabel documents the same class of surprise from
          // the opposite direction. Either way the reliable rule is the one
          // the rest of the app already follows by accident: Grid's week
          // header, the monthly heatmap and the weekly recap all build day
          // numbers with plain interpolation, and none of them has ever
          // shown this. This was the outlier, not the standard.
          Text(
            '${point.date.day}',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
              color: isToday ? GameColors.gold : gp.textTert,
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens a lightweight read-only detail sheet for one bar of the 14-day
/// chart — the chart itself only ever has room for a bare number per day,
/// this is where "which day, and what actually happened on it" lives.
void _showDayDetailSheet(BuildContext context, ProgressPoint point, String locale) {
  HapticFeedback.selectionClick();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (ctx) => _DayDetailSheet(point: point, locale: locale),
  );
}

/// One habit's row inside [_DayDetailSheet]: what it was, whether it was
/// done, and anything written about it that day.
///
/// The note is the whole point of this row existing — Grid's long-press
/// editor is where someone records *why* a day went the way it did, and
/// until now that text was only reachable by hunting for it in the Habit
/// Notes screen. Surfacing it against the day it belongs to is what turns
/// this chart from a row of numbers into something you can actually reread.
class _DayHabitRow extends StatelessWidget {
  final String name;
  final int completions;
  final String note;
  final SquareState state;

  const _DayHabitRow({
    required this.name,
    required this.completions,
    required this.note,
    required this.state,
  });

  /// Icon per state, with the color taken from [SquareState.accent] — the
  /// same hue the Grid square itself uses, so a Skipped day reads as the
  /// same thing in both places rather than picking new colors here.
  (IconData, Color) _visual(BuildContext context) {
    final gp = context.gp;
    return switch (state) {
      SquareState.skipped => (Icons.next_plan_outlined, state.accent),
      SquareState.failed => (Icons.cancel_outlined, state.accent),
      SquareState.bonus => (Icons.auto_awesome_rounded, state.accent),
      _ => completions > 0
          ? (Icons.check_circle_rounded, GameColors.success)
          : (Icons.radio_button_unchecked_rounded, gp.textTert),
    };
  }

  /// Only the three "worth explaining" states get a written label — a plain
  /// completed or not-done habit is already obvious from the icon, and
  /// labelling it would just add noise to every row.
  String? _stateLabel(bool isAr) => switch (state) {
        SquareState.skipped ||
        SquareState.failed ||
        SquareState.bonus =>
          isAr ? state.labelAr : state.label,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final (icon, color) = _visual(context);
    final stateLabel = _stateLabel(s.isAr);
    final hasNote = note.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: gp.textPrimary,
                        ),
                      ),
                    ),
                    // Only worth showing for a habit done more than once —
                    // a plain "1" next to a checkmark says nothing new.
                    if (completions > 1) ...[
                      const SizedBox(width: 8),
                      Text(
                        '×$completions',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: GameColors.success,
                        ),
                      ),
                    ],
                  ],
                ),
                if (stateLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    stateLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
                if (hasNote) ...[
                  const SizedBox(height: 5),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: gp.surfaceHigh,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: gp.border, width: 0.5),
                    ),
                    child: Text(
                      note.trim(),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: gp.textSec,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ConsumerWidget, not StatelessWidget: habit *names* aren't stored on the
/// day's document (only ids are — see ProgressPoint.habitCompletions), so
/// this resolves them live from habitListProvider at render time, falling
/// back to the "deleted habit" label for one that's since been removed.
class _DayDetailSheet extends ConsumerWidget {
  final ProgressPoint point;
  final String locale;

  const _DayDetailSheet({required this.point, required this.locale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final hasData = point.completions > 0;
    final isAr = s.isAr;

    final habitsById = {
      for (final h in ref.watch(allHabitsEverProvider)) h.id: h,
    };
    // Completed habits first, then anything only carrying a note or a
    // skip/fail mark; alphabetical within each group so the order is stable
    // between openings rather than following map insertion order.
    final rows = point.detailedHabitIds.map((id) {
      return (
        id: id,
        name: habitsById[id]?.localName(isAr) ?? s.gridJournalDeletedHabit,
        completions: point.habitCompletions[id] ?? 0,
        note: point.notes[id] ?? '',
        state: point.states[id] ?? SquareState.none,
      );
    }).toList()
      ..sort((a, b) {
        final byDone = (b.completions > 0 ? 1 : 0)
            .compareTo(a.completions > 0 ? 1 : 0);
        return byDone != 0 ? byDone : a.name.compareTo(b.name);
      });
    // Today/Yesterday reads faster at a glance, but the literal calendar
    // date is always shown too (see below) so this never becomes
    // ambiguous about which real day it's for.
    final headline = point.date.isToday
        ? s.progressToday
        : point.date.isYesterday
            ? s.progressYesterday
            : weekdayDateLabel(point.date, isAr: s.isAr, locale: locale);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            if (point.date.isToday || point.date.isYesterday) ...[
              const SizedBox(height: 2),
              Text(
                weekdayDateLabel(point.date, isAr: s.isAr, locale: locale),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: gp.textSec),
              ),
            ],
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: gp.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: gp.border, width: 0.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: (hasData ? GameColors.success : gp.border)
                          .withOpacity(hasData ? 0.12 : 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      hasData
                          ? Icons.check_circle_rounded
                          : Icons.remove_circle_outline_rounded,
                      size: 18,
                      color: hasData ? GameColors.success : gp.textTert,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.progressDayCompletions(point.completions),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: gp.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  s.progressDayBreakdown,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: gp.textTert,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // Capped height + scroll: a heavy day with a dozen habits and
              // long notes would otherwise push this sheet past the screen.
              // shrinkWrap keeps a light day compact instead of always
              // reserving the full height.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.42,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: rows.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: gp.border),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return _DayHabitRow(
                      name: r.name,
                      completions: r.completions,
                      note: r.note,
                      state: r.state,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Achievements preview section ──────────────────────────────────────────

class _AchievementsPreviewSection extends StatelessWidget {
  final DashboardState state;
  const _AchievementsPreviewSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final unlockedIds = state.unlockedAchievements;
    final total = AchievementCatalog.all.length;

    // Unlocked first (recent wins feel good to see), then one "next up"
    // achievement per family, closest-to-done family first. One per family
    // — not just the six closest by raw progress ratio — because several
    // families tie at exactly 0% for anyone who hasn't touched that
    // category yet; a pure ratio sort let whichever family sits first in
    // the catalog array (Streak, then Level) win every tie and crowd out
    // the rest, so a new user's very first look at this strip could show
    // four rungs of the same ladder and never even see the 1-tap "color
    // your first square" win sitting right there. Capped at 6 so this
    // stays a preview, not a second copy of the full grid — see
    // AchievementsScreen for the rest.
    final stats = state.achievementStats;
    final unlocked =
        AchievementCatalog.all.where((a) => unlockedIds.contains(a.id));
    final nextPerFamily = AchievementCatalog.families
        // null when the family is mastered. Was an inline
        // `tiers.indexWhere(...)` here and a `tiers[unlockedCount]` on the
        // full screen — the same question answered two different ways, one
        // of which broke on a ladder with a gap. Both now call this.
        .map((f) => AchievementCatalog.nextLockedIn(f.id, unlockedIds))
        .whereType<AchievementModel>()
        .toList()
      ..sort((a, b) =>
          stats.progressFor(b).compareTo(stats.progressFor(a)));
    final preview = [...unlocked, ...nextPerFamily].take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SectionHeader(s.achievements),
            const Spacer(),
            // Neutral, or platinum once the whole catalog is cleared — NOT
            // GameColors.gold. That's the preset's *accent* role, not a hue
            // promise: it resolves to teal, rose or violet depending on the
            // theme, so a medal counter painted with it was teal on most
            // presets. Medals have their own colour system now (see
            // TierPalette); this matches the per-family count pills on
            // AchievementsScreen exactly. The PRO badge and the spinners
            // elsewhere on this page still use GameColors.gold, correctly —
            // those genuinely are accent-role elements.
            _CountPill(
              label: progressFraction(unlockedIds.length, total),
              accent: unlockedIds.length == total
                  ? TierPalette.from(context, AchievementTier.platinum).ink
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        // A fade on the scrolling edge instead of a hard slice. The strip is
        // wider than the screen by design, but a card cut dead flat against
        // the container edge reads as a layout bug rather than "there's more
        // over here" — the fade is the only thing that says which.
        _EdgeFade(
          child: SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: preview.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _MiniAchievementCard(
                achievement: preview[i],
                isUnlocked: unlockedIds.contains(preview[i].id),
                stats: stats,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AchievementsScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  s.achievementsViewAll(total),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: gp.textSec),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    size: 16, color: gp.textTert),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniAchievementCard extends StatelessWidget {
  final AchievementModel achievement;
  final bool isUnlocked;
  final AchievementStats stats;
  const _MiniAchievementCard({
    required this.achievement,
    required this.isUnlocked,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final isAr = S.of(context).isAr;
    final medalState =
        isUnlocked ? MedalState.unlocked : MedalState.inProgress;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // The same sheet the full screen's medals open. These are literally
      // the same medals one tap apart, and only one of the two responded —
      // tapping a medal here did nothing at all, which reads as broken
      // rather than as "this one isn't interactive".
      onTap: () => showTierDetailSheet(context, achievement, stats,
          unlocked: isUnlocked),
      child: Container(
        width: 96,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AchievementMedal(
              tier: achievement.tier,
              icon: achievementIconFor(achievement.trigger),
              size: 40,
              state: medalState,
              progress: stats.progressFor(achievement),
              semanticLabel: medalSemanticLabel(
                achievement: achievement,
                state: medalState,
                current: stats.currentFor(achievement),
                isAr: isAr,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              achievement.localName(isAr),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: gp.textPrimary,
                  height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

/// The small "4 / 20" chip beside a section header.
///
/// [accent] null means neutral — the deliberate default, so a counter never
/// borrows a colour that implies something about the numbers it's showing.
class _CountPill extends StatelessWidget {
  final String label;
  final Color? accent;

  const _CountPill({required this.label, this.accent});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final c = accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (c ?? gp.textTert).withOpacity(0.15),
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: c ?? gp.textSec),
      ),
    );
  }
}

/// Fades the scrolling edge of a horizontal strip into the page background,
/// so a partially-visible card reads as "scroll for more" instead of as a
/// card that got sliced off.
///
/// Direction-aware: under RTL the strip scrolls the other way, so the fade
/// has to sit on the other side. A fixed `Alignment.centerRight` would have
/// put it on the wrong edge for the app's primary language.
class _EdgeFade extends StatelessWidget {
  final Widget child;
  const _EdgeFade({required this.child});

  @override
  Widget build(BuildContext context) {
    final bg = context.gp.bg;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ShaderMask(
      // dstIn: the gradient's alpha multiplies the child's, so opaque white
      // keeps the strip and transparent erases it.
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
        end: rtl ? Alignment.centerLeft : Alignment.centerRight,
        colors: [bg, bg, bg.withOpacity(0)],
        stops: const [0, 0.88, 1],
      ).createShader(rect),
      child: child,
    );
  }
}

// ─── Habit Insights preview section ────────────────────────────────────────

/// A compact preview: the single real headline sentence (same priority
/// order [InsightsScreen] itself uses) plus a "View full Insights" row.
/// The full free-vs-Premium split (every headline, one real per-habit row
/// free, the rest Premium) lives on InsightsScreen itself so it's defined
/// in exactly one place — this section is a taste, not a second copy of
/// that logic.
class _InsightsPreviewSection extends ConsumerWidget {
  const _InsightsPreviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final uid = ref.watch(authStateProvider).asData?.value?.uid;
    final habits = ref.watch(habitListProvider);
    final isPremium = ref.watch(premiumProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SectionHeader(s.insightsTitle),
            if (!isPremium) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: GameColors.gold.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
                child: Text(
                  'PRO',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: GameColors.gold,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<(DateTime, Map<String, dynamic>)>>(
          future: loadInsightsWindow(uid),
          builder: (context, snap) {
            if (!snap.hasData) {
              // Not const: GameColors.gold is a mutable static Color (the
              // theme-preset system can swap it at runtime), so it isn't a
              // compile-time constant - see BUILD_LESSONS.md #6.
              return SizedBox(
                height: 64,
                child: Center(
                  child: CircularProgressIndicator(
                      color: GameColors.gold, strokeWidth: 2),
                ),
              );
            }
            final result = computeInsights(habits: habits, days: snap.data!);
            if (result.totalSamples < 14) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: gp.surface,
                  borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                  border: Border.all(color: gp.border, width: 0.5),
                ),
                child: Text(
                  s.insightsEmpty,
                  style:
                      TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.4),
                ),
              );
            }
            final headlines = buildInsightHeadlines(
              result: result,
              habits: habits,
              s: s,
              locale: locale,
            );
            // Shared by the headline card below and the "View full
            // Insights" row under it, so tapping either one opens the same
            // screen the same way — the card used to just sit there
            // display-only (InsightHeadlineCard already supports an onTap,
            // it just wasn't being passed one here), leaving only the small
            // text+chevron row actually tappable.
            void openInsights() {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const InsightsScreen()),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (headlines.isNotEmpty)
                  InsightHeadlineCard(
                    icon: headlines.first.$1,
                    color: headlines.first.$2,
                    text: headlines.first.$3,
                    onTap: openInsights,
                  ),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: openInsights,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          s.dashboardViewFullInsights,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: gp.textSec),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded,
                            size: 16, color: gp.textTert),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Habit Notes (Grid Journal) preview section ────────────────────────────

/// A compact preview of the most recent Habit Notes entries — the notes and
/// Skipped/Failed/Bonus marks left from Grid's own long-press square editor
/// (see grid_journal_notifier.dart's doc comment for the full "why a
/// separate screen" reasoning). Used to sit as its own third icon atop the
/// Grid screen, next to Night Review and the progress heatmap — moved here
/// instead since "browse my past notes" is a look-back-at-my-details action
/// like everything else on this screen, not something that needed to sit
/// above the grid someone's actively coloring today. Shows whatever's
/// already loaded for the *current* month (same live [gridJournalProvider]
/// GridJournalScreen itself uses) rather than searching back further, since
/// this is a taste, not a second copy of that screen's own month browser.
class _JournalPreviewSection extends ConsumerWidget {
  const _JournalPreviewSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final locale = Localizations.localeOf(context).languageCode;
    final journal = ref.watch(gridJournalProvider);
    final habitById = {
      for (final h in ref.watch(habitListProvider)) h.id: h,
    };
    final preview = journal.entries.take(3).toList();

    // Shared by every tappable surface in this section (each preview row,
    // the empty state, and the "View all" row) so the whole section opens
    // the same screen the same way, not just the small text+chevron at the
    // bottom — previously only that last row was actually tappable.
    void openJournal() {
      HapticFeedback.selectionClick();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GridJournalScreen()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(s.gridJournalTitle),
        const SizedBox(height: 12),
        if (journal.isLoading)
          // Not const: GameColors.gold is a mutable static Color (theme
          // presets swap it at runtime) - see BUILD_LESSONS.md #6.
          SizedBox(
            height: 48,
            child: Center(
              child: CircularProgressIndicator(
                  color: GameColors.gold, strokeWidth: 2),
            ),
          )
        else if (preview.isEmpty)
          InkWell(
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            onTap: openJournal,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: gp.surface,
                borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                border: Border.all(color: gp.border, width: 0.5),
              ),
              child: Text(
                s.gridJournalEmpty,
                style:
                    TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.4),
              ),
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < preview.length; i++) ...[
                if (i != 0) const SizedBox(height: 8),
                _MiniJournalRow(
                  entry: preview[i],
                  habitName: habitById[preview[i].habitId]?.localName(isAr),
                  isAr: isAr,
                  locale: locale,
                  onTap: openJournal,
                ),
              ],
            ],
          ),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: openJournal,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  s.dashboardViewFullJournal,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: gp.textSec),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    size: 16, color: gp.textTert),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One compact row in [_JournalPreviewSection] — a smaller, single-line-note
/// version of GridJournalScreen's own _JournalEntryCard (that one affords a
/// full multi-line note and a state-label pill; this one only has room for
/// a taste of each).
class _MiniJournalRow extends StatelessWidget {
  final GridJournalEntry entry;
  final String? habitName;
  final bool isAr;
  final String locale;
  final VoidCallback onTap;

  const _MiniJournalRow({
    required this.entry,
    required this.habitName,
    required this.isAr,
    required this.locale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final accent = entry.state.accent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(entry.state.icon ?? Icons.circle_outlined,
                    size: 15, color: accent),
              ),
              const SizedBox(width: 10),
              // Title, date, and note/state now stack instead of sharing
              // one row with the date pinned to the far end — that layout
              // left a large dead gap between a short title and the date
              // (see the screenshot this was reported from), since
              // Expanded pushed the date all the way to the row's edge
              // regardless of how little space the title actually needed.
              // Stacking is immune to that: it never depends on how long
              // either piece of text happens to be.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habitName ?? s.gridJournalDeletedHabit,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color:
                            habitName == null ? gp.textTert : gp.textPrimary,
                        fontStyle: habitName == null
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      westernDate(entry.day, 'MMM d', locale),
                      style: TextStyle(fontSize: 10.5, color: gp.textTert),
                    ),
                    const SizedBox(height: 3),
                    if (entry.note.isNotEmpty)
                      Text(
                        entry.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: gp.textSec),
                      )
                    else
                      Text(
                        isAr ? entry.state.labelAr : entry.state.label,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: accent),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Category Breakdown section ────────────────────────────────────────────

/// "Where does my effort actually go" — a horizontal-bar breakdown of
/// lifetime completions across HabitCategory's broad set (Faith, Health,
/// Learning...), built entirely from DashboardState.categoryCompletions
/// (already loaded, same map achievement progress already reads) via
/// [aggregateCategoryCompletions]. Renders nothing for a brand-new account
/// with no completions yet, same "costs nothing on a quiet day" posture as
/// WeeklyRecapCard.
class _CategoryBreakdownSection extends StatelessWidget {
  final DashboardState state;
  const _CategoryBreakdownSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final aggregated = aggregateCategoryCompletions(state.categoryCompletions);
    if (aggregated.isEmpty) return const SizedBox.shrink();

    final entries = aggregated.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalCount = entries.fold<int>(0, (sum, e) => sum + e.value);
    final gp = context.gp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(s.categoryBreakdownTitle),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            border: Border.all(color: gp.border, width: 0.5),
          ),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i != 0) const SizedBox(height: 14),
                _CategoryBar(
                  category: entries[i].key,
                  count: entries[i].value,
                  totalCount: totalCount,
                  isAr: s.isAr,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// How much of the track one category's bar fills: its share of the total.
///
/// Pure and public so the rule can be tested, because it is the rule that
/// decides whether the picture agrees with the number printed beside it.
///
/// A category that really happened never renders as nothing: below 3% the
/// fill is floored, since at 1% of a ~340pt track the bar rounds to about
/// three pixels and reads as an empty row. "You did this once" is precisely
/// what a habit app must not draw as zero. The floor only ever affects
/// slivers, so it cannot make a small category look like a large one.
double categoryBarRatio({required int count, required int totalCount}) {
  if (totalCount <= 0 || count <= 0) return 0;
  final exact = (count / totalCount).clamp(0.0, 1.0);
  return exact < 0.03 ? 0.03 : exact;
}

class _CategoryBar extends StatelessWidget {
  final HabitCategory category;
  final int count;

  /// Sum across every category — the denominator behind the share figure.
  final int totalCount;
  final bool isAr;

  const _CategoryBar({
    required this.category,
    required this.count,
    required this.totalCount,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final (icon, color) = categoryVisual(category);
    // The bar and the number now measure the SAME thing: share of total.
    //
    // They used to disagree. The bar was drawn relative to the biggest
    // category, so the top row was always full width, while the number beside
    // it was a share of the total. On a real account that put "68%" against a
    // bar filling the whole track, and the row underneath at 26% drawn about
    // 40% wide. Both numbers were right and the picture was wrong: whichever
    // one you read, the other contradicted it. A chart whose length has to be
    // explained is not doing its job.
    //
    // Sharing the denominator costs the old version's one real advantage,
    // that the longest bar always reached the end. What it buys is a bar you
    // can read without a footnote: the track is the whole of your effort, and
    // each fill is that category's piece of it. The rows stay comparable to
    // each other because they are all on one scale, which is the same reason
    // the old version was comparable, just an honest scale.
    final share = totalCount <= 0 ? 0 : ((count / totalCount) * 100).round();
    final ratio = categoryBarRatio(count: count, totalCount: totalCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                category.localizedName(isAr),
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: gp.textPrimary),
              ),
            ),
            Text(
              '$share%',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: gp.textTert),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: gp.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            // textTert at low opacity, not gp.border — the border shade is
            // tuned to be a nearly invisible hairline between surfaces, so a
            // short bar sat in what looked like empty space. Matches
            // AchievementProgressBar.
            backgroundColor: gp.textTert.withOpacity(0.18),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
