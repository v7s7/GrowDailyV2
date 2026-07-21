import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/extensions/datetime_ext.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/services/local_store_service.dart';
import '../../core/theme/game_theme.dart';
import '../auth/notifiers/auth_notifier.dart';
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
Future<List<(DateTime, Map<String, dynamic>)>> loadInsightsWindow(
  String? uid, {
  int daysWindow = _insightsDaysWindow,
}) async {
  final today = DateTime.now().effectiveDay;
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

/// The headline sentences (strongest day, most consistent habit, needs a
/// push, per-habit weekday misses) built from a computed [InsightsResult].
/// A top-level function (not buried in [_InsightsBody]) so ProgressHubScreen
/// can show the same first headline, in the same priority order, without
/// duplicating the copy logic.
List<InsightHeadline> buildInsightHeadlines({
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
        Icons.emoji_events_rounded,
        GameColors.gold,
        s.insightStrongestDay(weekdayName(result.strongestWeekday!)),
        null,
        result.strongestWeekday,
      ),
    if (result.mostConsistentHabitId != null)
      (
        Icons.verified_rounded,
        GameColors.emerald,
        s.insightMostConsistent(
            habitDisplayName(result.mostConsistentHabitId!, habits, s)),
        result.mostConsistentHabitId,
        null,
      ),
    if (result.needsPushHabitId != null)
      (
        Icons.favorite_border_rounded,
        GameColors.warning,
        s.insightNeedsPush(
            habitDisplayName(result.needsPushHabitId!, habits, s)),
        result.needsPushHabitId,
        null,
      ),
    for (final p in result.patterns.values)
      if (p.worstWeekday() != null)
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
  ];
}

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
  final Future<List<(DateTime, Map<String, dynamic>)>> Function(String? uid)
      loadWindow;
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
    final isPremium = ref.watch(premiumProvider);

    return FutureBuilder<List<(DateTime, Map<String, dynamic>)>>(
      future: loadWindow(uid),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Center(
            child: CircularProgressIndicator(
                color: GameColors.gold, strokeWidth: 2),
          );
        }
        final result = computeInsights(habits: habits, days: snap.data!);
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

        final headlines = buildInsightHeadlines(
          result: result,
          habits: habits,
          s: s,
          locale: locale,
        );

        final ranked = result.patterns.values.toList()
          ..sort((a, b) => b.rate.compareTo(a.rate));
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
            for (var i = 0; i < headlines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InsightHeadlineCard(
                  icon: headlines[i].$1,
                  color: headlines[i].$2,
                  text: headlines[i].$3,
                  onTap: () => showInsightDetailSheet(
                    context,
                    headline: headlines[i],
                    result: result,
                    habits: habits,
                    locale: locale,
                  ),
                ).animate(delay: (i * 60).ms).fadeIn(duration: 350.ms),
              ),
            const SizedBox(height: 8),
            for (final p in visibleRows)
              _HabitRateRow(
                name: habitName(p.habitId),
                completed: p.completed,
                scheduled: p.scheduled,
                rate: p.rate,
              ),
            if (showTeaser)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pushNamed(context, '/premium');
                  },
                  child: Row(
                    children: [
                      Icon(Icons.lock_rounded,
                          size: 13, color: GameColors.gold),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s.insightsBreakdownTeaser,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: GameColors.gold,
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
/// visible: those sheets lead with a "$N points ahead/behind" sentence
/// computed from the two rates, and showing only raw fractions (e.g.
/// "1/56" and "6/56") invited comparing the completion *counts* instead
/// (6 - 1 = 5) instead of the percentages the headline actually used
/// (11% - 2% = 9) — same bug shape as the old fixed-scale bar chart:
/// the numbers on screen didn't back up the claim next to them.
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
void showInsightDetailSheet(
  BuildContext context, {
  required InsightHeadline headline,
  required InsightsResult result,
  required List<IslamicHabitTemplate> habits,
  required String locale,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _InsightDetailSheet(
      headline: headline,
      result: result,
      habits: habits,
      locale: locale,
    ),
  );
}

class _InsightDetailSheet extends StatelessWidget {
  final InsightHeadline headline;
  final InsightsResult result;
  final List<IslamicHabitTemplate> habits;
  final String locale;

  const _InsightDetailSheet({
    required this.headline,
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
    final today = DateTime.now().effectiveDay;
    final windowStart = today.subtract(const Duration(days: _insightsDaysWindow - 1));
    final dateRange = s.insightWindowWithDates(
      DateFormat('MMM d', locale).format(windowStart),
      DateFormat('MMM d', locale).format(today),
    );

    // Order matters: a habit can be both "most consistent" overall AND
    // have its own worst weekday, so those two would collide if the
    // habitId-only checks ran first. Whenever this exact card named a
    // weekday (weekday-miss or strongest-day), that's literally what its
    // sentence said, so it has to win over a same-habit coincidence below.
    final bool isWeekdayKind = weekday != null;
    final String tip;
    if (weekday != null && habitId != null) {
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
    // misses" is a stronger, simpler statement than any percentage-point
    // margin.
    final myName = pattern == null ? '' : habitDisplayName(pattern.habitId, habits, s);
    final isPerfectRecord = pattern != null &&
        pattern.scheduled > 0 &&
        pattern.completed == pattern.scheduled;
    HabitPattern? comparisonPattern;
    var comparisonPoints = 0;
    if (!isWeekdayKind && pattern != null && !isPerfectRecord) {
      final ranked = result.patterns.values.toList()
        ..sort((a, b) => b.rate.compareTo(a.rate));
      if (habitId == result.mostConsistentHabitId) {
        final myIndex = ranked.indexWhere((p) => p.habitId == habitId);
        if (myIndex >= 0 && myIndex + 1 < ranked.length) {
          comparisonPattern = ranked[myIndex + 1];
          comparisonPoints =
              ((pattern.rate - comparisonPattern.rate) * 100).round();
        }
      } else if (habitId == result.needsPushHabitId &&
          result.mostConsistentHabitId != null) {
        comparisonPattern = result.patterns[result.mostConsistentHabitId];
        if (comparisonPattern != null) {
          comparisonPoints =
              ((comparisonPattern.rate - pattern.rate) * 100).round();
        }
      }
    }
    final comparisonName = comparisonPattern == null
        ? ''
        : habitDisplayName(comparisonPattern.habitId, habits, s);

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
                    borderRadius: BorderRadius.circular(12),
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
            if (isWeekdayKind) ...[
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
                    borderRadius: BorderRadius.circular(12),
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
                          comparisonName, comparisonPoints)
                      : s.insightNeedsPushCompare(
                          comparisonName, comparisonPoints),
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
                  borderRadius: BorderRadius.circular(12),
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

/// Mon..Sun completion-rate wave — the same smooth-line + gradient-fill
/// language as ProgressHubScreen's 14-day chart ([_ProgressLinePainter]
/// there), re-purposed for 7 weekday points instead of 14 daily ones.
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
    final rates = [
      for (final day in days)
        (scheduledByWeekday[day] ?? 0) == 0
            ? 0.0
            : (completedByWeekday[day] ?? 0) / scheduledByWeekday[day]!,
    ];
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
                  '${(rates[i] * 100).round()}%',
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
  final List<double> rates; // 7 values, 0.0-1.0, Monday..Sunday
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
    final maxRate = rates.fold<double>(0, (m, r) => r > m ? r : m);
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
    final offsets = <Offset>[
      for (var i = 0; i < rates.length; i++)
        Offset(
          isRtl ? size.width - stepX * (i + 0.5) : stepX * (i + 0.5),
          chartBottom - (rates[i] / effectiveMax) * chartHeight,
        ),
    ];

    final fillPath = Path()..moveTo(offsets.first.dx, chartBottom);
    for (final point in offsets) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath.lineTo(offsets.last.dx, chartBottom);
    fillPath.close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);

    final linePath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (var i = 1; i < offsets.length; i++) {
      final prev = offsets[i - 1];
      final next = offsets[i];
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

    for (var i = 0; i < offsets.length; i++) {
      final isHighlighted = i == highlightIndex;
      final point = offsets[i];
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
