import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../features/achievements/models/achievement_model.dart';
import '../../../features/achievements/widgets/achievement_medal.dart';
import '../../../features/auth/notifiers/auth_notifier.dart';
import '../../../features/dashboard/notifiers/dashboard_notifier.dart';
import '../../../features/grid/notifiers/grid_journal_notifier.dart';
import '../../../features/grid/screens/grid_journal_screen.dart';
import '../../../features/habits/catalog/islamic_habit_catalog.dart';
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

  const ProgressPoint({required this.date, required this.completions});
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
      for (var i = 0; i < days.length; i++)
        ProgressPoint(
          date: days[i],
          completions: _completionCount(logs[i]),
        ),
    ];
  }

  final col = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('daily');
  final docs = await Future.wait(days.map((d) => col.doc(_dateKey(d)).get()));

  return [
    for (var i = 0; i < days.length; i++)
      ProgressPoint(
        date: days[i],
        completions: _completionCount(docs[i].data()),
      ),
  ];
});

String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

int _completionCount(Map<String, dynamic>? data) {
  final raw = data?['habitCompletions'] as Map<String, dynamic>? ?? {};
  return raw.values.fold<int>(0, (sum, value) => sum + (value as num).toInt());
}

// ─── The screen ─────────────────────────────────────────────────────────────

/// Pushed from Profile's single "Dashboard" row — replaces what used to be
/// three separate rows (Achievements, Habit Insights, Progress & Streak)
/// and three separate screens with one destination, three sections:
///
///  - Progress: the 14-day chart + streak-freeze shop, unchanged and still
///    fully free — it was never gated and isn't heavy, so it stays inline
///    exactly as it always was.
///  - Achievements: a compact horizontal preview (closest-to-unlock first)
///    instead of the full dozen-plus grid, with "View all" opening the
///    existing [AchievementsScreen] unchanged.
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
        title: Text(s.dashboardTitle,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary)),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SectionHeader(s.progressStreakTitle),
          const SizedBox(height: 12),
          // Only shown once there's an actual streak worth protecting.
          // Every account starts with a free freeze already in the bank
          // (see DashboardNotifier's `?? 1` default), so surfacing the shop
          // card from day one was pitching insurance before there was
          // anything to insure — the single most prominent thing on this
          // screen for a brand-new user, despite being neither urgent nor,
          // per usage, popular. Gating on a real 3-day streak instead of
          // account age since there's no signup-date field anywhere in this
          // codebase, and streak length is the more meaningful signal for
          // this specific card anyway.
          if (state.streak >= 3) ...[
            _StreakFreezeCard(state: state),
            const SizedBox(height: 14),
          ],
          _ProgressReportCard(state: state),
          const SizedBox(height: 28),
          _AchievementsPreviewSection(state: state),
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
    final total = points.fold<int>(0, (sum, p) => sum + p.completions);
    final best = points.fold<int>(
        0, (best, p) => p.completions > best ? p.completions : best);
    final activeDays = points.where((p) => p.completions > 0).length;
    final trendUp = points.length > 7 &&
        points.skip(7).fold<int>(0, (sum, p) => sum + p.completions) >=
            points.take(7).fold<int>(0, (sum, p) => sum + p.completions);

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
                  borderRadius: BorderRadius.circular(12),
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
                      isLoading
                          ? s.loadingReport
                          : trendUp
                              ? s.holdingStrong
                              : s.startAgain,
                      style: TextStyle(fontSize: 12, color: gp.textSec),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 142,
            width: double.infinity,
            child: CustomPaint(
              painter: _ProgressLinePainter(
                points: points.map((p) => p.completions).toList(),
                lineColor: GameColors.success,
                fillColor: GameColors.success.withOpacity(0.12),
                gridColor: gp.border,
                dotColor: GameColors.gold,
              ),
            ),
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
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
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: gp.textTert,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressLinePainter extends CustomPainter {
  final List<int> points;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color dotColor;

  const _ProgressLinePainter({
    required this.points,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.dotColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final maxValue = points.fold<int>(
      1,
      (highest, value) => value > highest ? value : highest,
    );
    final stepX = points.length == 1 ? 0.0 : size.width / (points.length - 1);
    final chartBottom = size.height - 18;
    final chartTop = 10.0;
    final chartHeight = chartBottom - chartTop;

    final gridPaint = Paint()
      ..color = gridColor.withOpacity(0.5)
      ..strokeWidth = 0.7;
    for (final ratio in [0.0, 0.5, 1.0]) {
      final y = chartTop + chartHeight * ratio;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final offsets = <Offset>[
      for (var i = 0; i < points.length; i++)
        Offset(
          stepX * i,
          chartBottom - (points[i] / maxValue) * chartHeight,
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

    final dotPaint = Paint()..color = dotColor;
    final haloPaint = Paint()..color = dotColor.withOpacity(0.16);
    for (final point in offsets) {
      if (point.dy < chartBottom) {
        canvas.drawCircle(point, 5, haloPaint);
        canvas.drawCircle(point, 2.6, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_ProgressLinePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.gridColor != gridColor;
}

class _StreakFreezeCard extends ConsumerWidget {
  final DashboardState state;
  const _StreakFreezeCard({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final canBuy = state.gold >= DashboardNotifier.streakFreezeCost &&
        state.streakFreezes < DashboardNotifier.maxStreakFreezes;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: GameColors.iconXp.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: GameColors.iconXp.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.ac_unit_rounded, color: GameColors.iconXp),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.streakFreeze,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  s.streakFreezeStatus(state.streakFreezes, DashboardNotifier.maxStreakFreezes),
                  style: TextStyle(fontSize: 12, color: gp.textSec),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: FilledButton.tonalIcon(
              onPressed: canBuy
                  ? () async {
                      HapticFeedback.mediumImpact();
                      final ok = await ref
                          .read(dashboardProvider.notifier)
                          .buyStreakFreeze();
                      if (context.mounted) {
                        final s2 = S.of(context);
                        // `canBuy` already gated this button on having enough
                        // gold and free slots, so a `false` result here means
                        // the purchase failed to save (e.g. no network) —
                        // not that funds were insufficient.
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok
                                ? s2.streakFreeze
                                : s2.errGeneric),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.toll_rounded, size: 16),
              label: Text('${DashboardNotifier.streakFreezeCost}'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Achievements preview section ──────────────────────────────────────────

class _AchievementsPreviewSection extends StatelessWidget {
  final DashboardState state;
  const _AchievementsPreviewSection({required this.state});

  double _progressFor(AchievementModel a) => switch (a.trigger) {
        AchievementTrigger.streak =>
          (state.streak / a.threshold).clamp(0.0, 1.0),
        AchievementTrigger.level =>
          (state.level / a.threshold).clamp(0.0, 1.0),
        AchievementTrigger.totalCompletions =>
          (state.totalCompletions / a.threshold).clamp(0.0, 1.0),
        AchievementTrigger.greenSquares =>
          (state.totalGreenSquares / a.threshold).clamp(0.0, 1.0),
        AchievementTrigger.habitMastery =>
          ((state.categoryCompletions[a.targetCategory] ?? 0) / a.threshold)
              .clamp(0.0, 1.0),
        _ => 0.0,
      };

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final unlockedIds = state.unlockedAchievements;
    final total = AchievementCatalog.all.length;

    // Unlocked first (recent wins feel good to see), then locked ones
    // closest-to-done first — the same aspirational pull a single
    // achievement's own progress bar already gives, just applied to which
    // six show up here. Capped at 6 so this stays a preview, not a second
    // copy of the full grid — see AchievementsScreen for the rest.
    final unlocked =
        AchievementCatalog.all.where((a) => unlockedIds.contains(a.id));
    final locked = AchievementCatalog.all
        .where((a) => !unlockedIds.contains(a.id))
        .toList()
      ..sort((a, b) => _progressFor(b).compareTo(_progressFor(a)));
    final preview = [...unlocked, ...locked].take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _SectionHeader(s.achievements),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: GameColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '${unlockedIds.length} / $total',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: GameColors.gold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 128,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: preview.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _MiniAchievementCard(
              achievement: preview[i],
              isUnlocked: unlockedIds.contains(preview[i].id),
              state: state,
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
  final DashboardState state;
  const _MiniAchievementCard({
    required this.achievement,
    required this.isUnlocked,
    required this.state,
  });

  double get _progress => switch (achievement.trigger) {
        AchievementTrigger.streak =>
          (state.streak / achievement.threshold).clamp(0.0, 1.0),
        AchievementTrigger.level =>
          (state.level / achievement.threshold).clamp(0.0, 1.0),
        AchievementTrigger.totalCompletions =>
          (state.totalCompletions / achievement.threshold).clamp(0.0, 1.0),
        AchievementTrigger.greenSquares =>
          (state.totalGreenSquares / achievement.threshold).clamp(0.0, 1.0),
        AchievementTrigger.habitMastery =>
          ((state.categoryCompletions[achievement.targetCategory] ?? 0) /
                  achievement.threshold)
              .clamp(0.0, 1.0),
        AchievementTrigger.special => 0.0,
      };

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final isAr = S.of(context).isAr;
    return Container(
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
            state: isUnlocked ? MedalState.unlocked : MedalState.inProgress,
            progress: _progress,
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
                  borderRadius: BorderRadius.circular(100),
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (headlines.isNotEmpty)
                  InsightHeadlineCard(
                    icon: headlines.first.$1,
                    color: headlines.first.$2,
                    text: headlines.first.$3,
                  ),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const InsightsScreen()),
                    );
                  },
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
          Container(
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
                ),
              ],
            ],
          ),
        const SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GridJournalScreen()),
            );
          },
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

  const _MiniJournalRow({
    required this.entry,
    required this.habitName,
    required this.isAr,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final accent = entry.state.accent;

    return Container(
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        habitName ?? s.gridJournalDeletedHabit,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: habitName == null
                              ? gp.textTert
                              : gp.textPrimary,
                          fontStyle: habitName == null
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('MMM d', locale).format(entry.day),
                      style: TextStyle(fontSize: 10.5, color: gp.textTert),
                    ),
                  ],
                ),
                if (entry.note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    entry.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: gp.textSec),
                  ),
                ] else ...[
                  const SizedBox(height: 3),
                  Text(
                    isAr ? entry.state.labelAr : entry.state.label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accent),
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
