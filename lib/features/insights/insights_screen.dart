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

/// The headline sentences (strongest day, most consistent habit, needs a
/// push, per-habit weekday misses) built from a computed [InsightsResult].
/// A top-level function (not buried in [_InsightsBody]) so ProgressHubScreen
/// can show the same first headline, in the same priority order, without
/// duplicating the copy logic.
List<(IconData, Color, String)> buildInsightHeadlines({
  required InsightsResult result,
  required List<IslamicHabitTemplate> habits,
  required S s,
  required String locale,
}) {
  String habitName(String id) {
    for (final h in habits) {
      if (h.id == id) return h.localName(s.isAr);
    }
    return s.gridJournalDeletedHabit;
  }

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
      ),
    if (result.mostConsistentHabitId != null)
      (
        Icons.verified_rounded,
        GameColors.emerald,
        s.insightMostConsistent(habitName(result.mostConsistentHabitId!)),
      ),
    if (result.needsPushHabitId != null)
      (
        Icons.favorite_border_rounded,
        GameColors.warning,
        s.insightNeedsPush(habitName(result.needsPushHabitId!)),
      ),
    for (final p in result.patterns.values)
      if (p.worstWeekday() != null)
        (
          Icons.trending_down_rounded,
          GameColors.error,
          s.insightWeekdayMiss(
            habitName(p.habitId),
            weekdayName(p.worstWeekday()!),
          ),
        ),
  ];
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
    final habits = ref.watch(habitListProvider);
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
/// same first headline in the exact same shape.
class InsightHeadlineCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const InsightHeadlineCard({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
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
        ],
      ),
    );
  }
}

/// One habit's completion rate as a labeled progress bar — the sortable
/// "receipts" behind the headline sentences above.
class _HabitRateRow extends StatelessWidget {
  final String name;
  final int completed;
  final int scheduled;
  final double rate;
  const _HabitRateRow({
    required this.name,
    required this.completed,
    required this.scheduled,
    required this.rate,
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
                '$completed/$scheduled',
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
