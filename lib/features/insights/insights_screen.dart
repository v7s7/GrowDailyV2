import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/extensions/datetime_ext.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/providers/day_clock_provider.dart';
import '../../features/premium/screens/premium_screen.dart';
import '../../core/services/local_store_service.dart';
import '../../core/theme/game_theme.dart';
import '../../core/utils/western_digits.dart';
import '../auth/notifiers/auth_notifier.dart';
import '../grid/models/square_state.dart';
import '../habits/catalog/islamic_habit_catalog.dart';
import '../habits/notifiers/custom_habits_notifier.dart';
import '../premium/notifiers/premium_notifier.dart';
import 'insight_engine.dart';

const int _insightsDaysWindow = 56; // 8 full grid weeks

/// Loads the last [daysWindow] days of daily docs for [uid] (or local Hive
/// storage for a guest) — the same raw shape [computeInsights] consumes.
/// A top-level function (not a screen method) so ProgressHubScreen's own
/// Insights preview section can run the exact same fetch without
/// duplicating it or depending on InsightsScreen's internals.
///
/// [today] is the caller's dayClockProvider day, the same clock
/// computeInsights judges the window with, so the days read and the days
/// judged come from one clock, and a test can pin both.
Future<List<(DateTime, Map<String, dynamic>)>> loadInsightsWindow(
  String? uid, {
  required DateTime today,
  int daysWindow = _insightsDaysWindow,
}) async {
  final days = [
    for (var i = 0; i < daysWindow; i++) today.subtract(Duration(days: i)),
  ];
  try {
    if (uid != null) {
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('daily');
      final snaps = await Future.wait(
        days.map((d) => col.doc(d.toDateKey()).get()),
      );
      return [
        for (var i = 0; i < days.length; i++)
          (days[i], snaps[i].data() ?? const <String, dynamic>{}),
      ];
    }
    return [
      for (final d in days)
        (d, await LocalStoreService.getDailyMap(d.toDateKey())),
    ];
  } catch (_) {
    return const [];
  }
}

/// One headline sentence plus everything its detail sheet needs to open
/// without recomputing anything: icon, color, the sentence itself, which
/// habit it's about (null for the account-wide "strongest day" headline),
/// and — for the weekday-miss kind specifically — the weekday it names, so
/// the detail sheet can point at the same day the sentence already called
/// out instead of silently re-deriving it.
typedef InsightHeadline = (IconData, Color, String, String?, int?);

/// Which question a headline card answers, so its sheet can show the
/// evidence that question needs.
///
/// Carried beside [InsightHeadline] rather than inside it, because the
/// record's shape is shared with the Progress hub and with tests. Four of
/// the five kinds can still be read off the record alone (see
/// [_InsightDetailSheet]'s fallback); [quotaWeeks] cannot, since it names a
/// habit and no weekday exactly as "most consistent" and "needs a push" do,
/// and the same quota habit can hold one of those titles too.
enum InsightKind {
  strongestDay,
  mostConsistent,
  needsPush,
  weekdayMiss,
  quotaWeeks,
}

/// Every headline card with the question it answers, in priority order:
/// strongest day, most consistent habit, needs a push, per-habit weekday
/// misses, then weekly quotas that fell short. A top-level function (not
/// buried in [_InsightsBody]) so ProgressHubScreen can show the same first
/// headline, in the same order, without duplicating the copy logic.
List<(InsightHeadline, InsightKind)> buildInsightCards({
  required InsightsResult result,
  required List<IslamicHabitTemplate> habits,
  required S s,
  required String locale,
}) {
  String weekdayName(int weekday) {
    // Any date with the right weekday works as a formatting anchor.
    final anchor = DateTime(2026, 7, 13); // a Monday
    return DateFormat('EEEE', locale)
        .format(anchor.add(Duration(days: weekday - DateTime.monday)));
  }

  return [
    if (result.strongestWeekday != null)
      (
        (
          Icons.emoji_events_rounded,
          GameColors.gold,
          s.insightStrongestDay(weekdayName(result.strongestWeekday!)),
          null,
          result.strongestWeekday,
        ),
        InsightKind.strongestDay,
      ),
    if (result.mostConsistentHabitId != null)
      (
        (
          Icons.verified_rounded,
          GameColors.emerald,
          s.insightMostConsistent(
              habitDisplayName(result.mostConsistentHabitId!, habits, s)),
          result.mostConsistentHabitId,
          null,
        ),
        InsightKind.mostConsistent,
      ),
    if (result.needsPushHabitId != null)
      (
        (
          Icons.favorite_border_rounded,
          GameColors.warning,
          s.insightNeedsPush(
              habitDisplayName(result.needsPushHabitId!, habits, s)),
          result.needsPushHabitId,
          null,
        ),
        InsightKind.needsPush,
      ),
    for (final p in result.patterns.values)
      if (p.worstWeekday() != null)
        (
          (
            Icons.trending_down_rounded,
            GameColors.error,
            s.insightWeekdayMiss(
              habitDisplayName(p.habitId, habits, s),
              weekdayName(p.worstWeekday()!),
            ),
            p.habitId,
            p.worstWeekday(),
          ),
          InsightKind.weekdayMiss,
        ),
    // A weekly quota never gets the card above (its blank days land on the
    // end of a short week by arithmetic, see InsightCadence.weeklyQuota), so
    // its own slip, a week that fell short, gets this one instead.
    for (final p in result.patterns.values)
      if (p.quotaShortfall() case final short?)
        (
          (
            Icons.trending_down_rounded,
            GameColors.error,
            s.insightQuotaWeeks(
              habitDisplayName(p.habitId, habits, s),
              short.met,
              short.weeks,
            ),
            p.habitId,
            null,
          ),
          InsightKind.quotaWeeks,
        ),
  ];
}

/// [buildInsightCards] without the kinds, for a caller that only draws the
/// cards.
List<InsightHeadline> buildInsightHeadlines({
  required InsightsResult result,
  required List<IslamicHabitTemplate> habits,
  required S s,
  required String locale,
}) =>
    [
      for (final (headline, _) in buildInsightCards(
        result: result,
        habits: habits,
        s: s,
        locale: locale,
      ))
        headline,
    ];

/// Shared by [buildInsightHeadlines] and the detail sheet — a deleted habit
/// still has a [HabitPattern] for any day it was active, so this always
/// needs the same "fall back to a placeholder name" handling both places
/// used to duplicate.
String habitDisplayName(
    String id, List<IslamicHabitTemplate> habits, S s) {
  for (final h in habits) {
    if (h.id == id) return h.localName(s.isAr);
  }
  return s.gridJournalDeletedHabit;
}

/// Habit Insights — the "your own patterns" screen: which habit slips on
/// which weekday, your strongest day, your most consistent habit, and the
/// one that needs a push, all computed from the last 8 weeks of the same
/// daily docs every other history surface already reads (56 doc reads,
/// once per open, served from Firestore's offline cache after the first).
///
/// The headline sentences are free for everyone — real analysis of your own
/// data, not a locked hole. Premium adds the receipts underneath: every
/// habit's own completion-rate row, not just the single strongest one free
/// accounts see (see _InsightsBody's per-habit list). Same "complete free
/// tier + Premium receipts underneath" shape as WeeklyRecapCard, chosen
/// over the old all-or-nothing pitch screen this replaced because "we
/// computed your patterns but won't show you any of it" reads as hostile
/// where "here's a real taste, unlock the rest" reads as an offer.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(title: Text(s.insightsTitle)),
      body: SafeArea(
        child: _InsightsBody(loadWindow: loadInsightsWindow),
      ),
    );
  }
}

class _InsightsBody extends ConsumerWidget {
  final Future<List<(DateTime, Map<String, dynamic>)>> Function(
    String? uid, {
    required DateTime today,
  }) loadWindow;
  const _InsightsBody({required this.loadWindow});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final uid = ref.watch(authStateProvider).asData?.value?.uid;
    // allHabitsEverProvider, not habitListProvider: this screen analyzes
    // an 8-week window of past days (see loadInsightsWindow), and
    // computeInsights only ever sees a habit's history for days it's in
    // this list for. habitListProvider is "active right now" only, so an
    // archived habit's entire past — every day it was genuinely scheduled
    // and completed — would silently drop out of every pattern, weekday
    // rollup, and best/worst pick the instant it's archived. This also
    // means habitDisplayName below can resolve an archived habit's real
    // name instead of falling all the way back to "Deleted habit".
    final habits = ref.watch(allHabitsEverProvider);
    final isPremium = ref.watch(premiumAccessProvider);
    // Re-read at midnight and at kDayCutoffHour, so a screen left open
    // across 10:00 takes yesterday in when it closes. See dayClockProvider.
    final now = ref.watch(dayClockProvider);

    return FutureBuilder<List<(DateTime, Map<String, dynamic>)>>(
      future: loadWindow(uid, today: now.effectiveDay),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Center(
            child: CircularProgressIndicator(
                color: GameColors.gold, strokeWidth: 2),
          );
        }
        final result = computeInsights(
          habits: habits,
          days: snap.data!,
          now: now,
        );
        // ~2 weeks of a single daily habit — below that, patterns are
        // noise and the honest answer is "come back later". Same bar for
        // everyone — this is a data floor, not a Premium gate.
        if (result.totalSamples < 14) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                s.insightsEmpty,
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13.5, color: gp.textSec, height: 1.5),
              ),
            ),
          );
        }

        String habitName(String id) {
          for (final h in habits) {
            if (h.id == id) return h.localName(s.isAr);
          }
          return s.gridJournalDeletedHabit;
        }

        final cards = buildInsightCards(
          result: result,
          habits: habits,
          s: s,
          locale: locale,
        );

        // Sorted with a sample floor rather than by raw rate — see
        // rankHabitPatterns for why a 1-of-1 habit must not top this list.
        final ranked = rankHabitPatterns(result.patterns.values);
        // Free: just the single strongest habit's real row — a genuine
        // taste, not a stripped one (see this screen's own doc comment).
        // Premium: every habit. No teaser row at all when there's only one
        // habit to begin with — nothing's actually being held back then.
        final visibleRows = isPremium ? ranked : ranked.take(1).toList();
        final showTeaser = !isPremium && ranked.length > 1;

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              s.insightsWindow,
              style: TextStyle(fontSize: 12, color: gp.textTert),
            ).animate().fadeIn(duration: 300.ms),
            const SizedBox(height: 12),
            for (var i = 0; i < cards.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InsightHeadlineCard(
                  icon: cards[i].$1.$1,
                  color: cards[i].$1.$2,
                  text: cards[i].$1.$3,
                  onTap: () => showInsightDetailSheet(
                    context,
                    headline: cards[i].$1,
                    kind: cards[i].$2,
                    result: result,
                    habits: habits,
                    locale: locale,
                  ),
                ).animate(delay: (i * 60).ms).fadeIn(duration: 350.ms),
              ),
            // The per-habit rates arrived with no label and no container —
            // a run of bare bars starting straight after the last headline
            // card, so "18 / 28" had nothing on screen saying what it
            // counted. Given a header and the same card treatment every
            // other list in the app uses.
            const SizedBox(height: GameSpacing.lg),
            Text(
              s.insightsPerHabitTitle,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: gp.textSec,
                  letterSpacing: s.isAr ? 0 : 1.5),
            ),
            const SizedBox(height: GameSpacing.md),
            Container(
              padding: const EdgeInsets.fromLTRB(
                  GameSpacing.lg, GameSpacing.lg, GameSpacing.lg, GameSpacing.sm),
              decoration: BoxDecoration(
                color: gp.surface,
                borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                border: Border.all(color: gp.border, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in visibleRows)
                    _HabitRateRow(
                      name: habitName(p.habitId),
                      completed: p.completed,
                      scheduled: p.scheduled,
                      rate: p.rate,
                    ),
                ],
              ),
            ),
            if (showTeaser)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PremiumScreen(source: 'insights_teaser'),
          ),
        );
                  },
                  child: Row(
                    children: [
                      Icon(Icons.lock_rounded,
                          size: 13, color: context.gp.goldInk),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s.insightsBreakdownTeaser,
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
          ],
        );
      },
    );
  }
}

/// One headline sentence in its own small card (icon + colored border +
/// text) — public because ProgressHubScreen's Insights preview renders the
/// same first headline in the exact same shape. [onTap] is optional:
/// ProgressHubScreen's preview card leaves it null (that whole section
/// already has its own "View full Insights" tap target below it), while
/// InsightsScreen wires every card to open [showInsightDetailSheet]. A
/// trailing chevron only appears when [onTap] is set, so the two contexts
/// stay visually honest about what tapping does.
class InsightHeadlineCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback? onTap;
  const InsightHeadlineCard({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
            border: Border.all(color: color.withOpacity(0.35), width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: gp.textPrimary,
                    height: 1.35,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: gp.textTert.withOpacity(0.6)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One habit's completion rate as a labeled progress bar — the sortable
/// "receipts" behind the headline sentences above, and also reused (with
/// [showPercent] on) as the two comparison rows under a "most consistent" /
/// "needs a push" detail sheet. That second context needs the percent
/// visible: those sheets lead with a sentence quoting the two rates ("27% vs
/// 100%"), and showing only raw fractions (e.g. "1/56" and "6/56") invited
/// comparing the completion *counts* instead of the percentages the sentence
/// is about. Same bug shape as the old fixed-scale bar chart: the numbers on
/// screen didn't back up the claim next to them.
class _HabitRateRow extends StatelessWidget {
  final String name;
  final int completed;
  final int scheduled;
  final double rate;
  final bool showPercent;
  const _HabitRateRow({
    required this.name,
    required this.completed,
    required this.scheduled,
    required this.rate,
    this.showPercent = false,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final color = rate >= 0.8
        ? GameColors.emerald
        : rate >= 0.5
            ? GameColors.warning
            : GameColors.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: gp.textPrimary,
                  ),
                ),
              ),
              Text(
                showPercent
                    ? '${(rate * 100).round()}%  ·  $completed/$scheduled'
                    : '$completed/$scheduled',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: gp.textTert,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate,
              minHeight: 6,
              backgroundColor: gp.border.withOpacity(0.5),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Insight Detail Sheet (tap any headline card) ─────────────────────────

/// Opens the tap-through detail for one headline card: the same icon,
/// color, and sentence as the card itself, plus a day-by-day breakdown and
/// a short actionable tip. Every headline kind resolves to one of two
/// shapes here — a specific habit's pattern (most consistent / needs a
/// push / weekday miss, all of which carry a habitId) or the account-wide
/// weekday spread (the "strongest day" headline, which isn't about any one
/// habit) — see [_InsightDetailSheet.build] for how it picks between them.
///
/// [kind] is the question the tapped card answers (see [InsightKind]). Null
/// reads it off [headline], which works for every kind but a weekly quota's.
void showInsightDetailSheet(
  BuildContext context, {
  required InsightHeadline headline,
  required InsightsResult result,
  required List<IslamicHabitTemplate> habits,
  required String locale,
  InsightKind? kind,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _InsightDetailSheet(
      headline: headline,
      kind: kind,
      result: result,
      habits: habits,
      locale: locale,
    ),
  );
}

class _InsightDetailSheet extends StatelessWidget {
  final InsightHeadline headline;
  final InsightKind? kind;
  final InsightsResult result;
  final List<IslamicHabitTemplate> habits;
  final String locale;

  const _InsightDetailSheet({
    required this.headline,
    required this.kind,
    required this.result,
    required this.habits,
    required this.locale,
  });

  String _weekdayName(int weekday) {
    final anchor = DateTime(2026, 7, 13); // a Monday
    return DateFormat('EEEE', locale)
        .format(anchor.add(Duration(days: weekday - DateTime.monday)));
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final (icon, color, text, habitId, weekday) = headline;
    final pattern = habitId == null ? null : result.patterns[habitId];
    // The card's question: told by the caller, or read off the headline for
    // a caller that predates InsightKind, which every kind but a weekly
    // quota's allows.
    final kind = this.kind ??
        (weekday != null
            ? (habitId != null
                ? InsightKind.weekdayMiss
                : InsightKind.strongestDay)
            : habitId == result.mostConsistentHabitId
                ? InsightKind.mostConsistent
                : habitId == result.needsPushHabitId
                    ? InsightKind.needsPush
                    : null);
    // The habit's own colour for its record's squares, the one its Grid row
    // and its reports cells are drawn in. A deleted habit falls back to the
    // system emerald, as those do.
    IslamicHabitTemplate? habit;
    for (final h in habits) {
      if (h.id == habitId) habit = h;
    }
    final habitColor = habit?.customColor ?? GameColors.emerald;
    // The days the engine actually read, which the records are laid out
    // from. A result built without them (a test's hand-made one) falls back
    // to the same eight weeks back from today the window line prints.
    final recordEnd = result.windowEnd ?? DateTime.now().effectiveDay;
    final recordStart = result.windowStart ??
        DateTime(recordEnd.year, recordEnd.month,
            recordEnd.day - (_insightsDaysWindow - 1));
    final quotaAverage = pattern?.quotaAveragePerWeek;
    final sectionLabel = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: gp.textTert,
      letterSpacing: 0.8,
    );

    final scheduledByWeekday =
        pattern?.scheduledByWeekday ?? result.overallScheduledByWeekday;
    final completedByWeekday =
        pattern?.completedByWeekday ?? result.overallCompletedByWeekday;
    final totalScheduled = pattern?.scheduled ??
        result.overallScheduledByWeekday.values.fold<int>(0, (a, b) => a + b);
    final totalCompleted = pattern?.completed ??
        result.overallCompletedByWeekday.values.fold<int>(0, (a, b) => a + b);
    final rate = totalScheduled == 0 ? 0.0 : totalCompleted / totalScheduled;

    // The concrete window behind "last 8 weeks" — see
    // insightWindowWithDates's doc comment for why this is shown at all.
    // Through westernDate, day before month in Arabic: DateFormat('MMM d')
    // printed «يوليو ٢٥ – سبتمبر ١٨», month first and in Arabic-Indic digits
    // beside the 8 of «آخر 8 أسابيع» (see weekSpanLabel's doc comment).
    final today = DateTime.now().effectiveDay;
    final windowStart = today.subtract(const Duration(days: _insightsDaysWindow - 1));
    final dayMonth = s.isAr ? 'd MMMM' : 'MMM d';
    final dateRange = s.insightWindowWithDates(
      westernDate(windowStart, dayMonth, locale),
      westernDate(today, dayMonth, locale),
    );

    // Order matters: a habit can be both "most consistent" overall AND
    // have its own worst weekday, so those two would collide if the
    // habitId-only checks ran first. Whenever this exact card named a
    // weekday (weekday-miss or strongest-day), that's literally what its
    // sentence said, so it has to win over a same-habit coincidence below.
    // A weekly quota's card names no weekday, so only its kind tells it from
    // the "most consistent" / "needs a push" card of the same habit.
    final bool isWeekdayKind = weekday != null;
    final String tip;
    if (kind == InsightKind.quotaWeeks) {
      tip = s.insightTipQuotaWeeks;
    } else if (weekday != null && habitId != null) {
      tip = s.insightTipWeekdayMiss(_weekdayName(weekday));
    } else if (weekday != null) {
      tip = s.insightTipStrongestDay;
    } else if (habitId == result.mostConsistentHabitId) {
      tip = s.insightTipMostConsistent;
    } else if (habitId == result.needsPushHabitId) {
      tip = s.insightTipNeedsPush;
    } else {
      tip = '';
    }

    // Habit-vs-habit comparison data — only meaningful for the two
    // habit-based kinds (isWeekdayKind == false). "Most consistent"
    // compares down to the runner-up (how big its lead is); "needs a push"
    // compares up to the most consistent habit (how big the gap is) —
    // whichever way tells the more useful story for that card. A perfect
    // record (never missed) short-circuits the comparison entirely: "zero
    // misses" is a stronger, simpler statement than any pair of rates.
    final myName = pattern == null ? '' : habitDisplayName(pattern.habitId, habits, s);
    final isPerfectRecord = pattern != null &&
        pattern.scheduled > 0 &&
        pattern.completed == pattern.scheduled;
    HabitPattern? comparisonPattern;
    if (!isWeekdayKind && pattern != null && !isPerfectRecord) {
      final ranked = result.patterns.values.toList()
        ..sort((a, b) => b.rate.compareTo(a.rate));
      if (habitId == result.mostConsistentHabitId) {
        final myIndex = ranked.indexWhere((p) => p.habitId == habitId);
        if (myIndex >= 0 && myIndex + 1 < ranked.length) {
          comparisonPattern = ranked[myIndex + 1];
        }
      } else if (habitId == result.needsPushHabitId &&
          result.mostConsistentHabitId != null) {
        comparisonPattern = result.patterns[result.mostConsistentHabitId];
      }
    }
    final comparisonName = comparisonPattern == null
        ? ''
        : habitDisplayName(comparisonPattern.habitId, habits, s);
    // The two rates the sentence quotes, rounded the way the big number and
    // _HabitRateRow round, so it never quotes a figure the bars under it
    // don't print. Their difference is never shown: see
    // insightNeedsPushCompare for what that cost.
    final myPercent = (rate * 100).round();
    final comparisonPercent = ((comparisonPattern?.rate ?? 0) * 100).round();

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
                  ),
                  child: Icon(icon, size: 21, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              dateRange,
              style: TextStyle(fontSize: 11, color: gp.textTert),
            ),
            const SizedBox(height: 16),
            // A quota's big number is its sessions per week against the
            // target, not a percentage of days: which of its days were
            // "owed" is arithmetic (see InsightCadence.weeklyQuota), and the
            // card above already gives the weeks that reached the target.
            if (kind == InsightKind.quotaWeeks &&
                quotaAverage != null &&
                pattern != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    formatPerWeek(quotaAverage),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: gp.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    s.insightQuotaAverage(pattern.quotaTarget ?? 1),
                    style: TextStyle(fontSize: 12.5, color: gp.textSec),
                  ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${(rate * 100).round()}%',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: gp.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    s.insightDetailRate(totalCompleted, totalScheduled),
                    style: TextStyle(fontSize: 12.5, color: gp.textSec),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            // Weekday-based cards (strongest day / weekday miss) compare
            // days against each other, so the wave chart fits. Habit-based
            // cards (most consistent / needs a push) are inherently a
            // habit-vs-habit claim, not a day-vs-day one — a weekday chart
            // there doesn't actually explain "why this habit," so those get
            // a direct comparison against the next-nearest habit instead.
            //
            // Two habits the wave cannot describe get their own record (see
            // InsightCadence). A specific-days habit's weekday card shows its
            // own days only, each week of the window a dated square, where
            // the wave drew seven columns for a habit owing two. A weekly
            // quota's card shows its weeks against the target.
            if (kind == InsightKind.quotaWeeks && pattern != null) ...[
              Text(s.insightDetailByWeek, style: sectionLabel),
              const SizedBox(height: 12),
              _QuotaWeeksChart(
                weeks: pattern.quotaWeeks,
                color: habitColor,
                today: recordEnd,
                locale: locale,
              ),
            ] else if (isWeekdayKind &&
                pattern != null &&
                pattern.cadence == InsightCadence.specificDays) ...[
              Text(s.insightDetailOwnDays, style: sectionLabel),
              const SizedBox(height: 12),
              _OwnDaysRecord(
                pattern: pattern,
                windowStart: recordStart,
                windowEnd: recordEnd,
                highlightWeekday: weekday,
                highlightColor: color,
                color: habitColor,
                locale: locale,
              ),
            ] else if (isWeekdayKind) ...[
              Text(
                s.insightDetailByDay,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: gp.textTert,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              _WeekdayWaveChart(
                scheduledByWeekday: scheduledByWeekday,
                completedByWeekday: completedByWeekday,
                highlightWeekday: weekday,
                highlightColor: color,
                locale: locale,
              ),
            ] else ...[
              Text(
                s.insightDetailCompare,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: gp.textTert,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              if (isPerfectRecord)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded, size: 18, color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.insightPerfectRecord(totalScheduled),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: gp.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else if (comparisonPattern != null) ...[
                Text(
                  habitId == result.mostConsistentHabitId
                      ? s.insightMostConsistentCompare(
                          comparisonName, myPercent, comparisonPercent)
                      : s.insightNeedsPushCompare(
                          comparisonName, myPercent, comparisonPercent),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: gp.textPrimary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                _HabitRateRow(
                  name: myName,
                  completed: pattern!.completed,
                  scheduled: pattern.scheduled,
                  rate: pattern.rate,
                  showPercent: true,
                ),
                _HabitRateRow(
                  name: comparisonName,
                  completed: comparisonPattern.completed,
                  scheduled: comparisonPattern.scheduled,
                  rate: comparisonPattern.rate,
                  showPercent: true,
                ),
              ] else
                Text(
                  s.insightOnlyHabitTracked,
                  style: TextStyle(fontSize: 13, color: gp.textSec),
                ),
            ],
            if (tip.isNotEmpty) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_rounded, size: 15, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tip,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: gp.textPrimary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The weekday wave's seven rates, Monday to Sunday, null for a weekday with
/// no scheduled sample in the window.
///
/// Null, never 0.0. A weekday nobody owed anything on has no rate, and a 0%
/// over a point on the floor read as a weekday missed every time: a
/// Monday-and-Thursday habit showed five of them, and holding a day still
/// open back (computeInsights) can empty a weekday for a habit created this
/// week. The chart prints '–' for it and draws no point, the placeholder the
/// reports print where nothing is owed.
///
/// Pure; see test/features/insights/insights_open_day_test.dart.
List<double?> weekdayWaveRates({
  required Map<int, int> scheduledByWeekday,
  required Map<int, int> completedByWeekday,
}) =>
    [
      for (var day = DateTime.monday; day <= DateTime.sunday; day++)
        (scheduledByWeekday[day] ?? 0) == 0
            ? null
            : (completedByWeekday[day] ?? 0) / scheduledByWeekday[day]!,
    ];

/// Mon..Sun completion-rate wave — a smooth-line + gradient-fill chart for
/// 7 weekday points. ProgressHubScreen's 14-day chart used to share this
/// exact painter-based look; that one is now a bar chart with visible
/// per-day counts instead (better for "how many today," a small countable
/// number), while this wave stays a curve since a weekday *rate* pattern
/// is closer to a continuous, day-to-day trend than a raw daily count.
///
/// Scaled against this week's own highest rate, not a fixed 0-100%
/// ceiling: a "needs a push" or weekday-miss pattern is by definition made
/// of low numbers (a 13% day was the tallest point in the case that
/// prompted this), and against a fixed ceiling every point reads as
/// equally flat near the bottom regardless of whether the real spread was
/// 0-13% or 0-90% — exactly the "the low bar is 0, so that's not helpful"
/// problem the bar-chart version had. Used for both a single habit's
/// pattern and the account-wide spread behind "Your strongest day", so it
/// only ever takes raw weekday maps, never a [HabitPattern] directly.
class _WeekdayWaveChart extends StatelessWidget {
  final Map<int, int> scheduledByWeekday;
  final Map<int, int> completedByWeekday;
  final int? highlightWeekday;
  final Color highlightColor;
  final String locale;

  const _WeekdayWaveChart({
    required this.scheduledByWeekday,
    required this.completedByWeekday,
    required this.highlightColor,
    required this.locale,
    this.highlightWeekday,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    const days = [
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
      DateTime.saturday,
      DateTime.sunday,
    ];
    // Any date with the right weekday works as a formatting anchor — same
    // trick buildInsightHeadlines uses for the full weekday name, just with
    // the narrow ('EEEEE') form here since 7 full names won't fit a row.
    final anchor = DateTime(2026, 7, 13); // a Monday
    final rates = weekdayWaveRates(
      scheduledByWeekday: scheduledByWeekday,
      completedByWeekday: completedByWeekday,
    );
    final highlightIndex =
        highlightWeekday == null ? null : days.indexOf(highlightWeekday!);
    // The day-label Rows below are plain Flutter Rows, so Directionality
    // auto-mirrors them for Arabic (Monday ends up on the right, Sunday on
    // the left) with zero extra code — Flutter does that for every Row.
    // CustomPainter gets no such help: Canvas coordinates are always literal
    // left-to-right pixels regardless of locale, so without this the curve
    // stayed Monday-left/Sunday-right even in RTL, silently disagreeing
    // with its own labels (the "why is Monday's point on the low/left side"
    // bug). Passing this through so the painter can mirror its x-axis to
    // match.
    //
    // Deliberately locale-based (this app is only ever EN/AR — see every
    // other `isAr`-keyed string in app_strings.dart) rather than
    // `Directionality.of(context) == TextDirection.rtl`: this file already
    // imports both package:flutter/material.dart and package:intl/intl.dart,
    // and intl.dart exports its own bidi TextDirection that silently wins
    // the import collision over dart:ui's — `TextDirection.rtl` resolves to
    // intl's enum there, which has no `rtl` member, and fails to compile
    // (a known, commonly-reported Flutter/intl namespace conflict, not a
    // typo). Comparing the locale string sidesteps that entirely.
    final isRtl = locale == 'ar';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Exact values above the curve — the wave shape alone lost the
        // precise per-day numbers the old bar version had, and a shape
        // with no anchoring numbers is hard to actually read.
        Row(
          children: [
            for (var i = 0; i < days.length; i++)
              Expanded(
                child: Text(
                  rates[i] == null ? '–' : '${(rates[i]! * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: days[i] == highlightWeekday
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: days[i] == highlightWeekday
                        ? gp.textPrimary
                        : gp.textTert,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 80,
          width: double.infinity,
          child: CustomPaint(
            painter: _WeekdayWavePainter(
              rates: rates,
              highlightIndex: highlightIndex,
              lineColor: highlightColor,
              fillColor: highlightColor.withOpacity(0.14),
              gridColor: gp.border,
              isRtl: isRtl,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final day in days)
              Expanded(
                child: Text(
                  DateFormat('EEEEE', locale).format(
                      anchor.add(Duration(days: day - DateTime.monday))),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: day == highlightWeekday
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color:
                        day == highlightWeekday ? gp.textPrimary : gp.textSec,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _WeekdayWavePainter extends CustomPainter {
  // 7 values, 0.0-1.0, Monday..Sunday; null where the weekday owed nothing
  // (see weekdayWaveRates), which gets no point and breaks the line.
  final List<double?> rates;
  final int? highlightIndex;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  // Whether the ambient Directionality is RTL — see the doc comment on
  // _WeekdayWaveChart's isRtl for why the painter needs to know this at
  // all (Canvas coordinates don't auto-mirror the way Row children do).
  final bool isRtl;

  const _WeekdayWavePainter({
    required this.rates,
    required this.highlightIndex,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.isRtl,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (rates.isEmpty) return;
    // The scaling fix: divide by this week's own peak rate, not a fixed
    // 1.0 (100%) ceiling. Falls back to 1.0 only when every day is
    // genuinely 0%, so the line draws flat along the bottom instead of
    // dividing by zero.
    final maxRate =
        rates.fold<double>(0, (m, r) => r != null && r > m ? r : m);
    final effectiveMax = maxRate <= 0 ? 1.0 : maxRate;

    // Column width, not point-to-point step: each rate owns an equal
    // 1/7th slice and sits at that slice's center (x = stepX * (i + 0.5)),
    // the same layout the day-label Row above/below uses (7 Expanded
    // columns, each centering its own text). Using size.width / (n - 1)
    // here instead would put point 0 at the very left edge and point 6 at
    // the very right edge — plausible-looking, but silently misaligned
    // with the centered labels sitting above and below the curve.
    final stepX = size.width / rates.length;
    final chartBottom = size.height - 4;
    const chartTop = 6.0;
    final chartHeight = chartBottom - chartTop;

    final gridPaint = Paint()
      ..color = gridColor.withOpacity(0.5)
      ..strokeWidth = 0.7;
    canvas.drawLine(Offset(0, chartBottom), Offset(size.width, chartBottom), gridPaint);

    // rates[0] is always Monday (see _WeekdayWaveChart's `days` list). In
    // LTR that belongs at the left edge; in RTL — to match where the
    // Monday label actually lands once its Row auto-mirrors — it belongs
    // at the right edge instead. Mirroring each point's x around the
    // canvas center is what moves it there without touching the rest of
    // the drawing logic below (fill/line/dots all just consume `offsets`
    // in whatever order they come in).
    final offsets = <Offset?>[
      for (var i = 0; i < rates.length; i++)
        rates[i] == null
            ? null
            : Offset(
                isRtl ? size.width - stepX * (i + 0.5) : stepX * (i + 0.5),
                chartBottom - (rates[i]! / effectiveMax) * chartHeight,
              ),
    ];

    // One fill and one line per run of weekdays that have a rate, never
    // across a weekday that owed nothing (see weekdayWaveRates). A run of one
    // point draws only its dot.
    final runs = <List<Offset>>[];
    var run = <Offset>[];
    for (final point in offsets) {
      if (point == null) {
        if (run.isNotEmpty) runs.add(run);
        run = <Offset>[];
        continue;
      }
      run.add(point);
    }
    if (run.isNotEmpty) runs.add(run);

    for (final points in runs) {
      if (points.length < 2) continue;
      final fillPath = Path()..moveTo(points.first.dx, chartBottom);
      for (final point in points) {
        fillPath.lineTo(point.dx, point.dy);
      }
      fillPath.lineTo(points.last.dx, chartBottom);
      fillPath.close();
      canvas.drawPath(fillPath, Paint()..color = fillColor);

      final linePath = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final next = points[i];
        final midX = (prev.dx + next.dx) / 2;
        linePath.cubicTo(midX, prev.dy, midX, next.dy, next.dx, next.dy);
      }
      canvas.drawPath(
        linePath,
        Paint()
          ..color = lineColor
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var i = 0; i < offsets.length; i++) {
      final isHighlighted = i == highlightIndex;
      final point = offsets[i];
      if (point == null) continue;
      canvas.drawCircle(
          point, isHighlighted ? 7 : 4, Paint()..color = lineColor.withOpacity(0.18));
      canvas.drawCircle(
          point,
          isHighlighted ? 3.6 : 2.4,
          Paint()..color = isHighlighted ? lineColor : lineColor.withOpacity(0.7));
    }
  }

  @override
  bool shouldRepaint(_WeekdayWavePainter oldDelegate) =>
      oldDelegate.rates != rates ||
      oldDelegate.highlightIndex != highlightIndex ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.isRtl != isRtl;
}

// ─── A habit's own record: specific days and weekly quotas ─────────────────

/// A quota's sessions per week, for the big number on its sheet: one
/// decimal, dropped when it is whole, so «3» rather than «3.0» and «2.6»
/// rather than «2.571».
String formatPerWeek(double perWeek) {
  final fixed = perWeek.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

/// The dates in one row of a specific-days record: [weekday]'s date in each
/// 7-day block of the window, oldest first, the blocks counted back from
/// [windowEnd] so the last one always ends on the clock's day. Null where a
/// block reaches back past [windowStart], which only a window that is not a
/// whole number of weeks can do.
///
/// Blocks counted back from today, not Saturday weeks. The 56-day window
/// holds every weekday exactly eight times, so every row has exactly eight
/// squares, each column holds one day of every row, and a row's squares are
/// exactly the days its count was taken from. Saturday weeks would cut the
/// same window into nine columns on six days of every seven, with a
/// half-read week at the front whose unread half would look like a gap in
/// the record.
///
/// Pure; see test/features/insights/insight_cadence_test.dart.
List<DateTime?> recordRowDays({
  required int weekday,
  required DateTime windowStart,
  required DateTime windowEnd,
}) {
  final start = DateTime(windowStart.year, windowStart.month, windowStart.day);
  final end = DateTime(windowEnd.year, windowEnd.month, windowEnd.day);
  // Whole calendar days, counted in UTC so a daylight-saving change inside
  // the window cannot lose or add one.
  final span = DateTime.utc(end.year, end.month, end.day)
          .difference(DateTime.utc(start.year, start.month, start.day))
          .inDays +
      1;
  final blocks = (span + 6) ~/ 7;
  // How far back from the window's last day this weekday falls.
  final back = (end.weekday - weekday + 7) % 7;
  final days = <DateTime?>[];
  for (var k = blocks - 1; k >= 0; k--) {
    final day = DateTime(end.year, end.month, end.day - back - 7 * k);
    days.add(day.isBefore(start) ? null : day);
  }
  return days;
}

/// A specific-days habit's record on its weekday sheet: one row for each day
/// it runs on, one square per week, oldest first in the reading direction.
///
/// What the weekday wave drew for these habits (Aziz, 2026-09-18, on a
/// Monday and Thursday habit): seven columns for a habit that owes two days,
/// five of them «–», and the two real rates as lone dots scaled against each
/// other. This keeps what the wave was for, comparing the habit's own days,
/// and adds what it could never show: WHICH weeks slipped, so "Thursday is
/// the weaker day" can be checked by eye, and so can whether the slips are
/// old or recent.
///
/// Each square is a real day with its date on it, in the cell language of
/// the habit's own calendar (habit_detail_sheet.dart) and the reports
/// matrix: the habit's colour when done, its outline when owed and left
/// empty, the Grid's grey for a تخطّي, amber for a فشل, faint for a day still
/// open, a gold ring on today. A tap names the day and what it recorded in
/// one line underneath, the answer the habit's calendar gives, rather than a
/// sheet on top of a sheet.
///
/// The count at the end of each row is the engine's own per-weekday count,
/// the numbers the rate above is summed from, so the rows always add up to
/// it.
class _OwnDaysRecord extends StatefulWidget {
  final HabitPattern pattern;
  final DateTime windowStart;
  final DateTime windowEnd;

  /// The weekday the card named, whose row is drawn forward.
  final int? highlightWeekday;
  final Color highlightColor;

  /// The habit's own colour, for its done squares.
  final Color color;
  final String locale;

  const _OwnDaysRecord({
    required this.pattern,
    required this.windowStart,
    required this.windowEnd,
    required this.highlightWeekday,
    required this.highlightColor,
    required this.color,
    required this.locale,
  });

  @override
  State<_OwnDaysRecord> createState() => _OwnDaysRecordState();
}

class _OwnDaysRecordState extends State<_OwnDaysRecord> {
  /// The square the caption is describing, or null before any tap.
  DateTime? _picked;

  // 13 July 2026 is a Monday; any date with the right weekday names it.
  String _weekdayName(int weekday) => DateFormat('EEEE', widget.locale)
      .format(DateTime(2026, 7, 13 + weekday - DateTime.monday));

  /// The line for [day]: its full date and what it recorded. A day completed
  /// by a count, with no green square behind it, reads as complete, because
  /// that is what the row's count called it.
  String _dayLine(S s, DateTime day) {
    final record = widget.pattern.record[day.toDateKey()];
    final mark = record == null
        ? SquareState.none
        : record.done && !record.mark.isGreen
            ? SquareState.complete
            : record.mark;
    return s.habitStatsDayLine(
      westernDate(day, 'EEEE d MMMM', widget.locale),
      mark.localLabel(s.isAr),
    );
  }

  TableRow _row(BuildContext context, int weekday) {
    final gp = context.gp;
    final s = S.of(context);
    final p = widget.pattern;
    final end = widget.windowEnd;
    final today = DateTime(end.year, end.month, end.day);
    final picked = _picked;
    final highlighted = weekday == widget.highlightWeekday;
    final days = recordRowDays(
      weekday: weekday,
      windowStart: widget.windowStart,
      windowEnd: widget.windowEnd,
    );
    final counted = p.scheduledByWeekday[weekday] ?? 0;
    final done = p.completedByWeekday[weekday] ?? 0;
    final textColor = highlighted ? gp.textPrimary : gp.textSec;

    return TableRow(
      decoration: highlighted
          ? BoxDecoration(
              color: widget.highlightColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            )
          : null,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 10, 6),
          child: Text(
            _weekdayName(weekday),
            maxLines: 1,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: highlighted ? FontWeight.w800 : FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // As wide as the column allows, never wider than a square the
              // habit's calendar would draw.
              final size = days.isEmpty
                  ? 0.0
                  : (constraints.maxWidth / days.length).clamp(0.0, 34.0);
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final day in days)
                    SizedBox(
                      width: size,
                      height: size,
                      child: day == null
                          ? null
                          : _RecordCell(
                              day: day,
                              state: p.record[day.toDateKey()]?.state,
                              color: widget.color,
                              isToday: day.isSameDayAs(today),
                              isPicked:
                                  picked != null && day.isSameDayAs(picked),
                              // Before the habit existed there is nothing
                              // to report, so the date alone, never «فارغ».
                              semanticsLabel:
                                  p.record.containsKey(day.toDateKey())
                                      ? _dayLine(s, day)
                                      : westernDate(
                                          day, 'EEEE d MMMM', widget.locale),
                              onTap: p.record.containsKey(day.toDateKey())
                                  ? () {
                                      HapticFeedback.selectionClick();
                                      setState(() => _picked = day);
                                    }
                                  : null,
                            ),
                    ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 8, 6),
          child: Text(
            counted == 0 ? '–' : s.insightCountOf(done, counted),
            maxLines: 1,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              fontWeight: highlighted ? FontWeight.w800 : FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final picked = _picked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          columnWidths: const {
            0: IntrinsicColumnWidth(),
            1: FlexColumnWidth(),
            2: IntrinsicColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            for (final weekday in widget.pattern.weekdays)
              _row(context, weekday),
          ],
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: GameMotion.relaxed,
          child: Text(
            picked == null ? s.habitStatsDayHint : _dayLine(s, picked),
            key: ValueKey(picked),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: picked == null ? FontWeight.w400 : FontWeight.w600,
              color: picked == null ? gp.textTert : gp.textSec,
            ),
          ),
        ),
      ],
    );
  }
}

/// One square of [_OwnDaysRecord]: a date, painted with what it recorded.
class _RecordCell extends StatelessWidget {
  final DateTime day;

  /// What the day came to, or null when the habit did not exist yet (or had
  /// been archived) on it: still a real date, drawn fainter than a day that
  /// is open, and not tappable, since there is nothing to say about it.
  final InsightDayState? state;
  final Color color;
  final bool isToday;
  final bool isPicked;
  final String semanticsLabel;
  final VoidCallback? onTap;

  const _RecordCell({
    required this.day,
    required this.state,
    required this.color,
    required this.isToday,
    required this.isPicked,
    required this.semanticsLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    Color ink(double opacity) =>
        (gp.dark ? Colors.white : Colors.black).withOpacity(opacity);
    // The date on the habit's own colour: dark on a light colour and light
    // on a dark one, so a custom colour never swallows its own number.
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black.withOpacity(0.72);
    final (Color fill, Color? border, Color text, bool flag) = switch (state) {
      InsightDayState.done => (color, null, onColor, false),
      // The same fill and the reports' gold corner flag: this habit, extra.
      InsightDayState.bonus => (color, null, onColor, true),
      // Half the done colour, as everywhere a جزئي is drawn.
      InsightDayState.partial => (
          color.withOpacity(0.5),
          color,
          gp.textPrimary,
          false,
        ),
      InsightDayState.failed => (
          GameColors.warning.withOpacity(0.14),
          GameColors.warning.withOpacity(0.7),
          gp.warningInk,
          false,
        ),
      // The Grid's own تخطّي grey: chosen, and out of the count.
      InsightDayState.rest => (
          SquareState.skipped.fill(gp.dark),
          null,
          gp.textSec,
          false,
        ),
      // Owed and left empty: an outline in the habit's colour, never red.
      // Red is for فشل, a word somebody chose (see the reports' _MatrixCell).
      InsightDayState.missed => (
          Colors.transparent,
          color.withOpacity(0.35),
          gp.textTert,
          false,
        ),
      InsightDayState.covered => (
          color.withOpacity(0.18),
          null,
          gp.textTert,
          false,
        ),
      InsightDayState.open => (
          ink(0.04),
          null,
          gp.textTert.withOpacity(0.75),
          false,
        ),
      null => (ink(0.02), null, gp.textTert.withOpacity(0.4), false),
    };
    return Semantics(
      label: semanticsLabel,
      button: onTap != null,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: AnimatedContainer(
            duration: GameMotion.relaxed,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(7),
              border: isPicked
                  ? Border.all(color: GameColors.gold, width: 1.6)
                  : isToday
                      ? Border.all(color: GameColors.gold)
                      : border == null
                          ? null
                          : Border.all(color: border),
            ),
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        toWesternDigits('${day.day}'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: state == InsightDayState.done ||
                                  state == InsightDayState.bonus
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: text,
                        ),
                      ),
                    ),
                  ),
                ),
                if (flag)
                  PositionedDirectional(
                    top: 2,
                    end: 2,
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: GameColors.gold,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A weekly quota's weeks against its target, oldest first in the reading
/// direction: one bar per Saturday week, made of one segment for each
/// session the week asked for, filled for each session recorded.
///
/// Weeks, not weekdays: see InsightCadence.weeklyQuota. Segments rather than
/// one bar scaled to a percentage, because a quota is a count. «3 of 4» is
/// three filled squares out of four, countable at a glance, and a week that
/// did more than it asked shows a full bar with its real count under it.
///
/// A week that fell short draws its empty segments as the habit's outline,
/// the way a missed day is drawn everywhere else. The week still running,
/// and a week the habit only lived part of, keep theirs faint: nothing is
/// owed there yet, or the week never asked in full. This week's count is
/// gold, the way today is marked on every other grid.
class _QuotaWeeksChart extends StatelessWidget {
  final List<QuotaWeek> weeks;
  final Color color;
  final DateTime today;
  final String locale;

  const _QuotaWeeksChart({
    required this.weeks,
    required this.color,
    required this.today,
    required this.locale,
  });

  Widget _bar(
    BuildContext context,
    QuotaWeek week, {
    required double segment,
    required double gap,
    required double barHeight,
  }) {
    final gp = context.gp;
    final s = S.of(context);
    final day = DateTime(today.year, today.month, today.day);
    final weekEnd =
        DateTime(week.start.year, week.start.month, week.start.day + 7);
    final current = !day.isBefore(week.start) && day.isBefore(weekEnd);
    final filled = week.done < week.target ? week.done : week.target;
    final shortfall = week.scored && !week.met;
    final faint = (gp.dark ? Colors.white : Colors.black).withOpacity(0.05);
    return Semantics(
      label: '${westernDate(week.start, s.isAr ? 'd MMMM' : 'MMM d', locale)}'
          ' · ${s.insightCountOf(week.done, week.target)}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: barHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Top segment first, so sessions fill from the bottom up.
                for (var i = week.target - 1; i >= 0; i--)
                  Container(
                    width: 20,
                    height: segment,
                    margin:
                        EdgeInsets.only(top: i == week.target - 1 ? 0 : gap),
                    decoration: BoxDecoration(
                      color: i < filled
                          ? (week.whole ? color : color.withOpacity(0.55))
                          : shortfall
                              ? Colors.transparent
                              : faint,
                      borderRadius: BorderRadius.circular(4),
                      border: i >= filled && shortfall
                          ? Border.all(color: color.withOpacity(0.35))
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${week.done}',
            style: TextStyle(
              fontSize: 11,
              fontWeight:
                  current || week.met ? FontWeight.w800 : FontWeight.w600,
              color: current
                  ? gp.goldInk
                  : week.met
                      ? gp.textPrimary
                      : gp.textTert,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = 3.0;
    final tallest =
        weeks.fold<int>(1, (most, w) => w.target > most ? w.target : most);
    // A target of seven still fits the sheet; a target of one is a square,
    // not a tower.
    final segment = (66 / tallest).clamp(7.0, 16.0);
    final barHeight = tallest * segment + (tallest - 1) * gap;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final week in weeks)
          Expanded(
            child: _bar(
              context,
              week,
              segment: segment,
              gap: gap,
              barHeight: barHeight,
            ),
          ),
      ],
    );
  }
}
