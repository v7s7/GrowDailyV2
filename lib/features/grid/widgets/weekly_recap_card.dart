import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../features/premium/screens/premium_screen.dart';
import '../../../core/providers/day_clock_provider.dart';
import '../../../core/providers/weekly_recap_collapsed_provider.dart';
import '../../../core/providers/weekly_note_offer_provider.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../models/covered_day.dart';
import '../../habits/catalog/islamic_habit_catalog.dart';
import '../../habits/models/habit_day_demand.dart'
    show DayDemand, movedDemandForRow;
import '../../habits/notifiers/custom_habits_notifier.dart';
import '../../premium/notifiers/premium_notifier.dart';
import '../../settings/models/notification_settings.dart';
import '../../settings/notifiers/notification_settings_notifier.dart';
import '../../../shared/widgets/app_snackbar.dart';
import '../models/square_state.dart';
import '../notifiers/weekly_grid_notifier.dart';

/// The week's numbers, computed purely from [DashboardState.dailyGreenCounts]
/// so the card costs zero reads and is trivially unit-testable — see
/// test/features/grid/weekly_recap_test.dart.
class WeeklyRecapData {
  final int thisWeekTotal;
  final int lastWeekTotal;

  /// The strongest day of the current week, or null when nothing was
  /// colored at all. Ties resolve to the earliest such day, so the result
  /// is deterministic.
  final DateTime? bestDay;

  /// This week against last week, compared day by day: what the delta chip,
  /// its colour and the encouragement line all read.
  ///
  /// Not always [thisWeekTotal] minus [lastWeekTotal]. A day of this week
  /// still open (DateTimeGameExt.isSettledAt) takes its partner from last
  /// week at most at its own count, the rule periodDelta applies on the
  /// report's week tab (Aziz, 2026-09-11: a day still open is not a miss).
  /// Written when the card showed on Friday, with all of Friday still open
  /// and Thursday too until kDayCutoffHour: compared in full, a Friday
  /// morning read as «أسبوع أهدى» before the week had had its chance. The
  /// card now waits for the week to seal ([recapWeekStartAt]), where every
  /// day has closed and this changes nothing; it stays so the arithmetic is
  /// right at any clock it is handed. An open day can still raise the
  /// change, never lower it. The two totals stay plain totals: each is a
  /// fact about its own week.
  final int delta;

  const WeeklyRecapData({
    required this.thisWeekTotal,
    required this.lastWeekTotal,
    required this.bestDay,
    required this.delta,
  });
}

WeeklyRecapData computeWeeklyRecap({
  required Map<String, int> dailyGreenCounts,
  required DateTime weekStart,

  /// The wall clock, for [WeeklyRecapData.delta]'s still-open rule. Null
  /// compares every day in full. Required, though nullable, so the card
  /// cannot forget its clock and still compile.
  required DateTime? now,
}) {
  var thisTotal = 0;
  var lastTotal = 0;
  var delta = 0;
  DateTime? bestDay;
  var best = 0;
  for (var i = 0; i < 7; i++) {
    final day = weekStart.add(Duration(days: i));
    final count = dailyGreenCounts[day.toDateKey()] ?? 0;
    thisTotal += count;
    if (count > best) {
      best = count;
      bestDay = day;
    }
    final prev = weekStart.subtract(Duration(days: 7 - i));
    final prevCount = dailyGreenCounts[prev.toDateKey()] ?? 0;
    lastTotal += prevCount;
    final stillOpen = now != null && !day.isSettledAt(now);
    delta += count - (stillOpen && prevCount > count ? count : prevCount);
  }
  return WeeklyRecapData(
    thisWeekTotal: thisTotal,
    lastWeekTotal: lastTotal,
    bestDay: bestDay,
    delta: delta,
  );
}

/// Totals for the last [weeks] grid weeks, oldest first, ending with the
/// week that starts at [currentWeekStart] — the Premium trend bars' data.
/// Pure; see test/features/grid/weekly_recap_test.dart.
List<int> weeklyTotals({
  required Map<String, int> dailyGreenCounts,
  required DateTime currentWeekStart,
  int weeks = 4,
}) {
  return [
    for (var w = weeks - 1; w >= 0; w--)
      () {
        final start = currentWeekStart.subtract(Duration(days: 7 * w));
        var total = 0;
        for (var i = 0; i < 7; i++) {
          total += dailyGreenCounts[
                  start.add(Duration(days: i)).toDateKey()] ??
              0;
        }
        return total;
      }(),
  ];
}

/// The habit missed most this week, or null when none was missed at least
/// twice: one miss is life.
///
/// Counted day by day, for every habit shape, as the card always counted:
/// a scheduled day that is neither green nor skipped is a miss, and a future
/// day never counts. The one change is that a day counts only once it is
/// SETTLED at [now] (DateTimeGameExt.isSettledAt): an explicit فشل at once,
/// a blank or جزئي day once it closes. When the card showed on Friday, a
/// Friday morning counted both Thursday (open until kDayCutoffHour) and
/// Friday itself as misses before anyone could have finished them (Aziz,
/// 2026-09-11). A day that has closed counts exactly as before, and the
/// sealed week the card now recaps holds nothing else.
///
/// Pure, over [squareFor], so it can be asserted without a Grid; see
/// test/features/grid/weekly_recap_test.dart.
IslamicHabitTemplate? mostMissedHabitThisWeek({
  required Iterable<IslamicHabitTemplate> habits,
  required List<DateTime> days,
  required SquareState Function(String habitId, DateTime day) squareFor,
  required DateTime now,
}) {
  final today = now.effectiveDay;
  IslamicHabitTemplate? most;
  var worst = 1; // require >= 2, so start the bar above 1
  for (final h in habits) {
    var misses = 0;
    // A day stood in for by a session on another day of the week owes
    // nothing (see moved_day_plan.dart), so it cannot be a miss.
    final moved = movedDemandForRow(
      habit: h,
      days: days,
      isGreenAt: (i) => squareFor(h.id, days[i]).isGreen,
      isUnmarkedAt: (i) => squareFor(h.id, days[i]) == SquareState.none,
      now: now,
    );
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      if (!h.isScheduledFor(day)) continue;
      if (moved?[i] == DayDemand.earned) continue;
      if (day.startOfDay.isAfter(today)) continue;
      final sq = squareFor(h.id, day);
      if (sq.isGreen || sq == SquareState.skipped) continue;
      if (!day.isSettledAt(now, answered: sq.answersDay)) continue;
      misses++;
    }
    if (misses > worst) {
      worst = misses;
      most = h;
    }
  }
  return most;
}

/// One dot of a habit's week in the Premium recap, before it is coloured.
enum RecapDot {
  /// A day the habit asked nothing of (see isCoveredDay): soft green.
  covered,

  /// Not scheduled, still to come, or still open with nothing on it: dim,
  /// neutral.
  quiet,
  done,
  failed,
  skipped,
  partial,

  /// Scheduled, closed, and nothing recorded: the hollow ring.
  missed,
}

/// One habit's week in the Premium recap at [now]: its seven dots and its
/// done/scheduled count.
///
/// The arithmetic the card always used, for every habit shape: each
/// scheduled day that is not in the future counts, a تخطّي included, each
/// green one is done, and a flexible quota habit counts every day it was
/// alive. The one change is that a day enters the count only once it is
/// settled, the rule every report percentage follows (Aziz, 2026-09-11). On
/// Friday morning a blank Friday, and a blank Thursday still inside its
/// grace, are quiet dots outside the count rather than hollow misses inside
/// it. A day that has closed reads exactly as it did before that rule.
///
/// Pure, over [squareOn]; see test/features/grid/weekly_recap_test.dart.
({int done, int scheduled, List<RecapDot> dots}) habitWeekRow({
  required IslamicHabitTemplate habit,
  required List<DateTime> days,
  required SquareState Function(DateTime day) squareOn,
  required DateTime now,
}) {
  final today = now.effectiveDay;
  var done = 0;
  var scheduled = 0;
  final dots = <RecapDot>[];
  // A specific-days week holding a session off its plan: the session counts
  // on its own day, and the planned day it stands in for is covered (see
  // moved_day_plan.dart). Null for every other week, which reads as before.
  final moved = movedDemandForRow(
    habit: habit,
    days: days,
    isGreenAt: (i) => squareOn(days[i]).isGreen,
    isUnmarkedAt: (i) => squareOn(days[i]) == SquareState.none,
    now: now,
  );
  for (var i = 0; i < days.length; i++) {
    final day = days[i];
    final sq = squareOn(day);
    final isFuture = day.startOfDay.isAfter(today);
    final demand = moved?[i];
    final isScheduled =
        demand == null ? habit.isScheduledFor(day) : !demand.isRest;
    final settled = day.isSettledAt(now, answered: sq.answersDay);
    if (isScheduled && !isFuture && settled) {
      scheduled++;
      if (sq.isGreen) done++;
    }
    // An off-day the schedule never asked for is a soft green dot, not a
    // dim one: the same covered state the Grid's squares paint, so the
    // recap and the board agree about which days were owed.
    final covered = !isFuture &&
        isCoveredDay(
          habit: habit,
          day: day,
          today: today,
          square: sq,
          demand: demand,
        );
    dots.add(
      covered
          ? RecapDot.covered
          : !isScheduled || isFuture
              ? RecapDot.quiet
              : sq.isGreen
                  ? RecapDot.done
                  : sq == SquareState.failed
                      ? RecapDot.failed
                      : sq == SquareState.skipped
                          ? RecapDot.skipped
                          : sq == SquareState.partial
                              ? RecapDot.partial
                              : settled
                                  ? RecapDot.missed
                                  : RecapDot.quiet,
    );
  }
  return (done: done, scheduled: scheduled, dots: dots);
}

/// The count at the end of a recap row, from [habitWeekRow]'s numbers.
///
/// A placeholder while the row counts nothing yet, never «0/0»: a habit
/// created on Thursday, or one whose only day this week is a Friday still
/// open, has nothing to count, and the report's own cards print the same '–'
/// for it (HabitMonthCard, the habit detail sheet).
String recapRowCount({required int done, required int scheduled}) =>
    scheduled <= 0 ? '–' : '$done/$scheduled';

/// The first day of the week the recap card shows at [now], or null while
/// it is not showing.
///
/// The card recaps a week once it has SEALED: from the instant its last day
/// closes (DateTimeGameExt.closesAt, [kDayCutoffHour] on the first day of
/// the next grid week) to the end of that day. With the grid week running
/// Saturday to Friday, that is Saturday from 10:00 until midnight, the same
/// instant the week's notification goes out at
/// (NotificationService.kWeeklyNoteHour), so the banner and the card name
/// one number and it can no longer move under either.
///
/// It used to show all of Friday, on a week still being lived. Aziz,
/// 2026-09-18: "it appears in friday, and user can still change it by doing
/// friday tasks". Saturday midnight would not have fixed that: Friday stays
/// payable until the cutoff.
DateTime? recapWeekStartAt(DateTime now) {
  final today = now.effectiveDay;
  if (!startOfGridWeek(today).isSameDayAs(today)) return null;
  final lastDay = DateTime(today.year, today.month, today.day - 1);
  if (now.isBefore(lastDay.closesAt)) return null;
  return DateTime(today.year, today.month, today.day - 7);
}

/// The week the recap card shows at [now], or null when it renders nothing:
/// outside its window ([recapWeekStartAt]), with no habits, or when that
/// week and the one before it are both empty. Two silent weeks in a row =
/// nothing to say; a recap of zeros would only rub it in, and the regular
/// empty-state/nudge surfaces handle that.
///
/// The card asks this before it builds, and Profile's section asks it
/// before putting its header over the card, so the header never sits over
/// a card that renders nothing. It used to be two copies of one gate kept
/// in step by a comment.
DateTime? recapWeekToShow({
  required DateTime now,
  required bool hasHabits,
  required Map<String, int> dailyGreenCounts,
}) {
  final weekStart = recapWeekStartAt(now);
  if (weekStart == null || !hasHabits) return null;
  final recap = computeWeeklyRecap(
    dailyGreenCounts: dailyGreenCounts,
    weekStart: weekStart,
    // Only the two totals are read here, and neither takes a clock.
    now: null,
  );
  if (recap.thisWeekTotal == 0 && recap.lastWeekTotal == 0) return null;
  return weekStart;
}

/// Where a tap on the week's numbered note lands at [now]
/// (NotificationService.openWeeklyRecapPayload): Profile while the card for
/// the week it counts is showing, which starts the instant the note goes
/// out, and the Grid once that card has gone, rather than a Profile with
/// nothing on it about the week the note was about.
String weeklyNoteTapRoute(DateTime now) =>
    recapWeekStartAt(now) == null ? '/grid' : '/profile';

/// The squares of the week a recap is showing: its seven days, first day
/// first, and every habit's square on each. What the per-habit rows and the
/// needs-attention line read; see [recapWeekProvider].
class RecapWeek {
  final List<DateTime> days;

  /// dateKey to (habitId to square), the shape WeeklyGridState.states holds.
  final Map<String, Map<String, SquareState>> states;

  const RecapWeek({required this.days, required this.states});

  SquareState squareFor(String habitId, DateTime day) =>
      states[day.toDateKey()]?[habitId] ?? SquareState.none;
}

/// The sealed week starting [weekStart], for [recapWeekProvider].
///
/// [live] is the Grid's own squares when it is showing this very week
/// (scrolled back to it): current to the last tap, a square painted on a
/// closed day included, and free. Otherwise each day is read from the store
/// through [readDay] (WeeklyGridNotifier.storedSquaresFor), the way the
/// Grid reads its own week: seven documents, each on its own.
///
/// Null when any day could not be read. An unreadable day is not an empty
/// one (see storedSquaresFor), and the rows and the needs-attention line
/// would draw it as missed, so both wait rather than guess.
Future<RecapWeek?> readRecapWeek({
  required DateTime weekStart,
  required Map<String, Map<String, SquareState>>? live,
  required Future<Map<String, SquareState>?> Function(DateTime day) readDay,
}) async {
  final days = [
    for (var i = 0; i < 7; i++)
      DateTime(weekStart.year, weekStart.month, weekStart.day + i),
  ];
  if (live != null) return RecapWeek(days: days, states: live);
  final read = await Future.wait(days.map(readDay));
  if (read.contains(null)) return null;
  return RecapWeek(
    days: days,
    states: {
      for (var i = 0; i < days.length; i++) days[i].toDateKey(): read[i]!,
    },
  );
}

/// The sealed week that starts on [weekStart], as [readRecapWeek] reads it.
///
/// The card shows once its week has sealed, and by then the Grid has rolled
/// on to the new week, so the sealed one is no longer in memory. Watched
/// only while the card is showing, so its reads happen on a Saturday with
/// Profile open; autoDispose, so the next visit reads again rather than
/// keep a week someone has since painted a square on.
final recapWeekProvider =
    FutureProvider.autoDispose.family<RecapWeek?, DateTime>((ref, weekStart) {
  // Selected, so a tap on the week the Grid is showing (the new one, as a
  // rule) re-runs nothing here.
  final live = ref.watch(weeklyGridProvider.select((grid) =>
      grid.weekStart.isSameDayAs(weekStart) && !grid.isLoading
          ? grid.states
          : null));
  return readRecapWeek(
    weekStart: weekStart,
    live: live,
    readDay: ref.watch(weeklyGridProvider.notifier).storedSquaresFor,
  );
});

/// The "حصاد الأسبوع" card on Profile, for the week that has just sealed
/// (see [recapWeekStartAt]: Saturday from kDayCutoffHour to midnight).
/// Renders nothing at all outside that window, or when there's nothing to
/// recap, so it costs the layout nothing the rest of the week.
///
/// Total greens against the week before with a delta chip, the week's best
/// day, the habit that got missed the most (only when it actually needs the
/// attention), and one calm line of encouragement picked by how the week
/// compares. The totals, the best day and the trend come from
/// dailyGreenCounts, already in memory; the per-habit rows and the
/// needs-attention line read the sealed week's squares ([recapWeekProvider]).
class WeeklyRecapCard extends ConsumerWidget {
  const WeeklyRecapCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-read at midnight and at kDayCutoffHour, the two instants the card
    // can go or appear at. See dayClockProvider.
    final now = ref.watch(dayClockProvider);
    // Nothing else is watched outside the window.
    if (recapWeekStartAt(now) == null) return const SizedBox.shrink();

    // allHabitsEverProvider: the "most missed" scan below walks the whole
    // sealed week day by day, so a habit archived partway through it
    // should still count for the days before it was archived, not vanish
    // from the tally the instant it's gone from the active list.
    final habits = ref.watch(allHabitsEverProvider);
    final counts = ref.watch(dashboardProvider).dailyGreenCounts;
    final weekStart = recapWeekToShow(
      now: now,
      hasHabits: habits.isNotEmpty,
      dailyGreenCounts: counts,
    );
    if (weekStart == null) return const SizedBox.shrink();
    final recap = computeWeeklyRecap(
      dailyGreenCounts: counts,
      weekStart: weekStart,
      now: now,
    );

    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final collapsed = ref.watch(weeklyRecapCollapsedProvider);

    // The habit most missed in the sealed week, from that week's own
    // squares, so absent until they have been read. Skipped squares don't
    // count as misses: a deliberate skip is a decision, not a slip. Shown
    // only at 2+ misses, one miss is life.
    final week = ref.watch(recapWeekProvider(weekStart)).valueOrNull;
    String? mostMissedName;
    if (week != null) {
      mostMissedName = mostMissedHabitThisWeek(
        habits: habits,
        days: week.days,
        squareFor: week.squareFor,
        now: now,
      )?.localName(s.isAr);
    }

    final delta = recap.delta;
    final encouragement = recap.lastWeekTotal == 0
        ? s.weeklyRecapFirst
        : delta > 0
            ? s.weeklyRecapUp
            : delta < 0
                ? s.weeklyRecapDown
                : s.weeklyRecapSame;
    final deltaColor = delta > 0
        ? GameColors.emerald
        : delta < 0
            ? GameColors.warning
            : gp.textTert;

    // The Saturday note goes only to someone who chose it; this is where the
    // app asks (see weekly_note_offer_provider.dart). Not while it is on,
    // once answered, or with every notification switched off.
    final offerNote = weeklyNoteOfferShown(
      settings: ref.watch(notificationSettingsProvider),
      answered: ref.watch(weeklyNoteOfferAnsweredProvider),
    );

    final card = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          border: Border.all(color: GameColors.gold.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The header doubles as the fold control. Tapping anywhere along
            // it collapses the card to just this row — and the row keeps the
            // week's headline number, so a folded card still answers "how did
            // my week go" without being unfolded. That is what makes folding
            // cheap enough to offer: you lose the detail, never the point.
            Semantics(
              button: true,
              expanded: !collapsed,
              label: s.weeklyRecapTitle,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setWeeklyRecapCollapsed(ref, !collapsed);
                },
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: GameColors.gold.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(Icons.insights_rounded,
                          size: 16, color: context.gp.goldInk),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      s.weeklyRecapTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    // Folded: the number rides up here so the row still says
                    // something. Expanded: it would only repeat the big stat
                    // directly underneath, so it goes away.
                    if (collapsed) ...[
                      Text(
                        '${recap.thisWeekTotal}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: context.gp.goldInk,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    AnimatedRotation(
                      turns: collapsed ? 0 : 0.5,
                      duration: GameMotion.quick,
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          size: 22, color: gp.textTert),
                    ),
                  ],
                ),
              ),
            ),
            // AnimatedSize rather than an if/else swap: folding a card that
            // just snaps out of existence reads as a glitch, and the whole
            // point of collapse-over-dismiss is that the card is still there.
            AnimatedSize(
              duration: GameMotion.relaxed,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: collapsed
                  ? const SizedBox(width: double.infinity)
                  : _RecapBody(
                      recap: recap,
                      delta: delta,
                      deltaColor: deltaColor,
                      encouragement: encouragement,
                      mostMissedName: mostMissedName,
                      habits: habits,
                      week: week,
                      counts: counts,
                      weekStart: weekStart,
                      now: now,
                      locale: locale,
                    ),
            ),
          ],
        ),
      ),
    );
    if (!offerNote) return card;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [card, const WeeklyNoteOffer()],
    );
  }
}

/// Whether the recap card carries [WeeklyNoteOffer] under it: only while the
/// Saturday note is off and the question unanswered, and never with every
/// notification switched off, where a yes could deliver nothing.
bool weeklyNoteOfferShown({
  required NotificationSettings settings,
  required bool answered,
}) =>
    settings.masterEnabled && !settings.weeklyNoteOn && !answered;

/// «نذكّرك بحصاد أسبوعك كل سبت الصبح؟» under the recap card: the one place
/// the app asks about the Saturday note (see weekly_note_offer_provider.dart).
///
/// «إيه» turns the note on and asks the phone for notification permission
/// (it only prompts the first time); refused, it says notifications are off
/// in the phone's settings, the words the Settings screen's own banner uses.
/// «لا، شكرًا» leaves it off. Either answer, and the line is gone for good.
class WeeklyNoteOffer extends ConsumerWidget {
  const WeeklyNoteOffer({super.key});

  Future<void> _yes(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final s = S.of(context);
    await markWeeklyNoteOfferAnswered(ref);
    await ref
        .read(notificationSettingsProvider.notifier)
        .update((c) => c.copyWith(weeklyNoteOn: true));
    final granted = await NotificationService.instance.requestPermissions();
    if (!granted) {
      messenger?.showOne(SnackBar(content: Text(s.notifSystemPermissionOff)));
    }
  }

  Future<void> _no(WidgetRef ref) async {
    HapticFeedback.selectionClick();
    await markWeeklyNoteOfferAnswered(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final buttonStyle = TextButton.styleFrom(
      minimumSize: const Size(44, 36),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 4, 6),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: gp.border),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_none_rounded,
                size: 18, color: gp.goldInk),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.weeklyNoteOfferAsk,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: gp.textSec,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _yes(context, ref),
              style: buttonStyle.copyWith(
                foregroundColor: WidgetStatePropertyAll(gp.goldInk),
              ),
              child: Text(
                s.weeklyNoteOfferYes,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () => _no(ref),
              style: buttonStyle.copyWith(
                foregroundColor: WidgetStatePropertyAll(gp.textTert),
              ),
              child: Text(
                s.weeklyNoteOfferNo,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything below the recap card's header — split out so [AnimatedSize] has
/// a single child to grow and shrink, and so the fold state lives in exactly
/// one place rather than being threaded through twenty `if (!collapsed)`
/// checks inside one very long build method.
class _RecapBody extends ConsumerWidget {
  final WeeklyRecapData recap;
  final int delta;
  final Color deltaColor;
  final String encouragement;
  final String? mostMissedName;
  final List<IslamicHabitTemplate> habits;

  /// The sealed week's squares, null until read (see [recapWeekProvider]).
  final RecapWeek? week;
  final Map<String, int> counts;
  final DateTime weekStart;
  final DateTime now;
  final String locale;

  const _RecapBody({
    required this.recap,
    required this.delta,
    required this.deltaColor,
    required this.encouragement,
    required this.mostMissedName,
    required this.habits,
    required this.week,
    required this.counts,
    required this.weekStart,
    required this.now,
    required this.locale,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    // Local copy so Dart can promote it to non-null inside the guard below —
    // a nullable *field* never promotes, only a local does.
    final missed = mostMissedName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            const SizedBox(height: 12),
            Row(
              children: [
                _RecapStat(
                  value: '${recap.thisWeekTotal}',
                  label: s.weeklyRecapThisWeek,
                  trailing: delta == 0
                      ? null
                      : Text(
                          delta > 0 ? '+$delta' : '$delta',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: deltaColor,
                          ),
                        ),
                ),
                _RecapDivider(),
                _RecapStat(
                  value: '${recap.lastWeekTotal}',
                  label: s.weeklyRecapLastWeek,
                ),
                _RecapDivider(),
                _RecapStat(
                  value: recap.bestDay == null
                      ? '–'
                      : DateFormat('EEEE', locale).format(recap.bestDay!),
                  label: s.heatmapBestDay,
                  small: true,
                ),
              ],
            ),
            if (missed != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.favorite_border_rounded,
                      size: 13, color: gp.textTert),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.weeklyRecapNeedsLove(missed),
                      style: TextStyle(fontSize: 12, color: gp.textSec),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(
              encouragement,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: gp.textTert,
                height: 1.35,
              ),
            ),
            // ── Premium depth: per-habit week rows + 4-week trend ─────
            // The free card above stays complete on its own (it drives
            // retention, so it's deliberately not crippled); Premium adds
            // the receipts underneath. Free users see one quiet teaser
            // line instead — an offer, not a hole.
            // Premium depth: per-habit week rows + the 4-week trend.
            //
            // A free user now sees the SAME section, blurred, with an unlock
            // chip over it — rather than the single line of teaser text that
            // used to stand in for it. The blurred version is the person's
            // own real week, so the offer is concrete ("this is your data,
            // slightly out of focus") instead of abstract ("there is more,
            // somewhere"). IgnorePointer under the blur so nothing behind the
            // glass is tappable, and the whole stack routes to /premium.
            _RecapDepth(
              habits: habits,
              week: week,
              counts: counts,
              weekStart: weekStart,
              now: now,
            ),
      ],
    );
  }
}

/// The recap's paid half — a week row per habit, then the 4-week trend.
///
/// Free users get exactly the same widgets behind a blur with an unlock chip
/// on top, instead of the one line of teaser text this used to render. The
/// difference matters: the blurred version is the person's own real week, so
/// the pitch is "this is yours, out of focus" rather than "something exists
/// that you cannot see". Nothing under the glass is tappable, and a tap
/// anywhere on it goes to the paywall.
class _RecapDepth extends ConsumerWidget {
  final List<IslamicHabitTemplate> habits;
  final RecapWeek? week;
  final Map<String, int> counts;
  final DateTime weekStart;
  final DateTime now;

  const _RecapDepth({
    required this.habits,
    required this.week,
    required this.counts,
    required this.weekStart,
    required this.now,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isPremium = ref.watch(premiumAccessProvider);
    // A local, so it promotes inside the guard below.
    final week = this.week;

    final depth = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (week != null) ...[
          const SizedBox(height: 12),
          Container(height: 0.5, color: gp.border),
          const SizedBox(height: 10),
          Text(
            s.weeklyRecapPerHabit,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: gp.textSec,
            ),
          ),
          const SizedBox(height: 8),
          // Skip a habit that's both gone (archived) AND had nothing real to
          // show this week — the shape a mistake/test habit leaves behind. A
          // currently-active habit always shows, even at 0/7: that's a real
          // miss worth seeing. See _weekDoneCount's own doc comment. And
          // skip one added after the week ended (see _addedAfter).
          for (final h in habits)
            if (!_addedAfter(h, week) &&
                (h.archivedAt == null || _weekDoneCount(h, week, now) > 0))
              _HabitWeekRow(
                habit: h,
                week: week,
                now: now,
                isAr: s.isAr,
              ),
        ],
        const SizedBox(height: 10),
        Text(
          s.weeklyRecapTrend,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: gp.textSec,
          ),
        ),
        const SizedBox(height: 6),
        _TrendBars(
          totals: weeklyTotals(
            dailyGreenCounts: counts,
            currentWeekStart: weekStart,
          ),
          currentWeekStart: weekStart,
          thisWeekLabel: s.weeklyRecapThisWeek,
        ),
      ],
    );

    if (isPremium) return depth;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PremiumScreen(source: 'weekly_recap', reason: PremiumReason.history),
          ),
        );
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ExcludeSemantics as well as IgnorePointer: blurred content is
          // decoration for a free user, and a screen reader announcing every
          // habit's week behind the glass would hand over exactly what the
          // blur is withholding.
          ExcludeSemantics(
            child: IgnorePointer(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Opacity(opacity: 0.55, child: depth),
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: gp.surface,
                  borderRadius:
                      BorderRadius.circular(GameSpacing.pillRadius),
                  border: Border.all(
                      color: GameColors.gold.withOpacity(0.45), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 13, color: context.gp.goldInk),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        s.weeklyRecapPremiumTeaser,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: context.gp.goldInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// How many of [habit]'s scheduled, non-future days in [week] are actually
/// green: its real completions that week. Used to decide whether an
/// archived habit is worth a row at all (see the filter above), and read
/// off the same [habitWeekRow] the row itself draws, so the filter and the
/// row's own count cannot disagree.
int _weekDoneCount(
  IslamicHabitTemplate habit,
  RecapWeek week,
  DateTime now,
) =>
    habitWeekRow(
      habit: habit,
      days: week.days,
      squareOn: (day) => week.squareFor(habit.id, day),
      now: now,
    ).done;

/// Whether [habit] was added after [week]'s last day. The card shows on the
/// Saturday after the week, and a habit made that morning belongs to the
/// new week: a row of seven quiet dots and '–' for it would say nothing
/// about this one.
bool _addedAfter(IslamicHabitTemplate habit, RecapWeek week) {
  final born = habit.createdAt;
  return born != null &&
      DateTime(born.year, born.month, born.day).isAfter(week.days.last);
}

/// One habit's week at a glance inside the Premium recap: name, seven day
/// dots in grid-week order (green done, red slipped, gray skipped, hollow
/// missed, dim future, unscheduled or still open), and its n/scheduled
/// count. The arithmetic is [habitWeekRow]; this only paints it.
class _HabitWeekRow extends StatelessWidget {
  final IslamicHabitTemplate habit;
  final RecapWeek week;
  final DateTime now;
  final bool isAr;
  const _HabitWeekRow({
    required this.habit,
    required this.week,
    required this.now,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final row = habitWeekRow(
      habit: habit,
      days: week.days,
      squareOn: (day) => week.squareFor(habit.id, day),
      now: now,
    );
    final dots = <Widget>[];
    for (final dot in row.dots) {
      final Color color = switch (dot) {
        RecapDot.covered => GameColors.emerald.withOpacity(0.45),
        RecapDot.quiet => gp.border.withOpacity(0.45),
        RecapDot.done => GameColors.emerald,
        RecapDot.failed => GameColors.error,
        // The same neutral every other surface gives a تخطّي, rather than
        // this card's own textTert. It was the one place that never moved.
        RecapDot.skipped => SquareState.skipped.accent(gp.dark),
        RecapDot.partial => GameColors.warning,
        RecapDot.missed => Colors.transparent,
      };
      dots.add(Container(
        width: 7,
        height: 7,
        margin: const EdgeInsetsDirectional.only(end: 3),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: color == Colors.transparent
              ? Border.all(color: gp.border, width: 1)
              : null,
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              habit.localName(isAr),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: gp.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ...dots,
          const SizedBox(width: 6),
          Text(
            recapRowCount(done: row.done, scheduled: row.scheduled),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: gp.textTert,
            ),
          ),
        ],
      ),
    );
  }
}

/// Four bars, oldest to newest, the recapped week in gold — enough to see
/// direction without pretending to be a chart screen. Each bar sits on a
/// dim full-height track so a quiet week still reads as "a bar with
/// little in it" rather than a stray sliver floating with nothing to
/// anchor it against, and every column is [Expanded] so the whole row
/// fills exactly the width it's given instead of drifting to one side
/// with fixed-width bars. The recapped week gets both its usual gold color
/// and an explicit «أسبوعك» tag underneath — the color alone was easy
/// to miss.
class _TrendBars extends StatelessWidget {
  final List<int> totals;
  final DateTime currentWeekStart;
  final String thisWeekLabel;
  const _TrendBars({
    required this.totals,
    required this.currentWeekStart,
    required this.thisWeekLabel,
  });

  static const _trackHeight = 52.0;
  static const _barWidth = 28.0;
  static const _minBarHeight = 6.0;

  @override
  Widget build(BuildContext context) {
    final max = totals.fold<int>(0, (m, v) => v > m ? v : m);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < totals.length; i++)
          Expanded(
            child: _TrendBar(
              value: totals[i],
              max: max,
              isCurrent: i == totals.length - 1,
              // weeks-old count from the end: last bar (current) is 0
              // weeks back, the one before it is 1 week back, etc.
              weekStart: currentWeekStart
                  .subtract(Duration(days: 7 * (totals.length - 1 - i))),
              thisWeekLabel: thisWeekLabel,
              trackHeight: _trackHeight,
              barWidth: _barWidth,
              minBarHeight: _minBarHeight,
            ),
          ),
      ],
    );
  }
}

class _TrendBar extends StatelessWidget {
  final int value;
  final int max;
  final bool isCurrent;
  final DateTime weekStart;
  final String thisWeekLabel;
  final double trackHeight;
  final double barWidth;
  final double minBarHeight;
  const _TrendBar({
    required this.value,
    required this.max,
    required this.isCurrent,
    required this.weekStart,
    required this.thisWeekLabel,
    required this.trackHeight,
    required this.barWidth,
    required this.minBarHeight,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final barColor = isCurrent ? GameColors.gold : GameColors.emerald;
    final barHeight = max == 0
        ? minBarHeight
        : minBarHeight + (trackHeight - minBarHeight) * (value / max);
    final weekEnd = weekStart.add(const Duration(days: 6));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: trackHeight,
          child: Center(
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  width: barWidth,
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: gp.border.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                Container(
                  width: barWidth,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: isCurrent ? barColor : barColor.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: GameColors.gold.withOpacity(0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 12,
            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w700,
            color: isCurrent ? context.gp.goldInk : gp.textPrimary,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          isCurrent ? thisWeekLabel : '${weekStart.day}-${weekEnd.day}',
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            color: isCurrent ? context.gp.goldInk : gp.textTert,
          ),
        ),
      ],
    );
  }
}

class _RecapStat extends StatelessWidget {
  final String value;
  final String label;
  final Widget? trailing;
  final bool small;
  const _RecapStat({
    required this.value,
    required this.label,
    this.trailing,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: small ? 13 : 18,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9.5, color: gp.textTert),
          ),
        ],
      ),
    );
  }
}

class _RecapDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      height: 30,
      color: context.gp.border,
      margin: const EdgeInsets.symmetric(horizontal: 6),
    );
  }
}
