import 'dart:math' show pi;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../../features/achievements/models/achievement_model.dart';
import '../../../features/auth/notifiers/auth_notifier.dart';
import '../../../features/dashboard/notifiers/dashboard_notifier.dart';
import '../../../shared/widgets/game_nav_bar.dart';


class ProgressPoint {
  final DateTime date;
  final int completions;

  const ProgressPoint({required this.date, required this.completions});
}

final progressReportProvider = FutureProvider<List<ProgressPoint>>((ref) async {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;

  final today = DateTime.now();
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

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final state = ref.watch(dashboardProvider);
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.email?.split('@').first ?? 'Warrior';
    final unlockedIds = state.unlockedAchievements;
    final sorted = [
      ...AchievementCatalog.all.where((a) => unlockedIds.contains(a.id)),
      ...AchievementCatalog.all.where((a) => !unlockedIds.contains(a.id)),
    ];

    return Scaffold(
      backgroundColor: gp.bg,
      bottomNavigationBar: const GameNavBar(currentIndex: 4),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: gp.bg,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            title: Text(s.profile,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: gp.textPrimary,
                    letterSpacing: -0.3)),
            actions: [
              IconButton(
                icon: Icon(
                  Theme.of(context).brightness == Brightness.dark
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  size: 22,
                  color: gp.textSec,
                ),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  ref.read(themeModeProvider.notifier).toggle();
                },
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _HeroHeader(state: state, displayName: displayName),
            )
                .animate()
                .fadeIn(duration: 500.ms)
                .slideY(begin: -0.04, curve: Curves.easeOut),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _StatsRow(state: state),
            ).animate(delay: 100.ms).fadeIn(duration: 400.ms),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _StreakFreezeCard(state: state),
            ).animate(delay: 150.ms).fadeIn(duration: 400.ms),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _ProgressReportCard(state: state),
            ).animate(delay: 190.ms).fadeIn(duration: 400.ms),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
              child: Row(
                children: [
                  Text(s.achievements,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: gp.textSec,
                          letterSpacing: 1.5)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: GameColors.gold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '${unlockedIds.length} / ${AchievementCatalog.all.length}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: GameColors.gold),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.78,
              children: sorted
                  .asMap()
                  .entries
                  .map((e) => _AchievementCard(
                        achievement: e.value,
                        isUnlocked: unlockedIds.contains(e.value.id),
                        state: state,
                      )
                          .animate(delay: (e.key * 45).ms)
                          .fadeIn(duration: 350.ms)
                          .slideY(begin: 0.1))
                  .toList(),
            ),
          ),
          const SliverToBoxAdapter(child: _SettingsSection()),
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ),
    );
  }
}

// ─── Hero Header ─────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final DashboardState state;
  final String displayName;
  const _HeroHeader({required this.state, required this.displayName});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 108,
            height: 108,
            child: CustomPaint(
              painter: _RingPainter(
                progress: state.levelProgress,
                trackColor: gp.border,
                arcColor: GameColors.gold,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${state.level}',
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: GameColors.gold,
                        height: 1,
                        letterSpacing: -1.5,
                      ),
                    ),
                    Text(
                      S.of(context).level,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: gp.textTert,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            displayName,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: gp.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            S.of(context).xpProgress(state.currentLevelXp, state.xpToNext, state.level + 1),
            style: TextStyle(
                fontSize: 12,
                color: gp.textTert,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: state.levelProgress,
              backgroundColor: gp.border,
              valueColor:
                  const AlwaysStoppedAnimation(GameColors.gold),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${state.cumulativeXp} ${S.of(context).cumulativeXp}',
            style: TextStyle(
                fontSize: 11,
                color: gp.textTert,
                fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }
}

// ─── Ring Painter ─────────────────────────────────────────────────────────────

class _RingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color arcColor;
  const _RingPainter(
      {required this.progress,
      required this.trackColor,
      required this.arcColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 7;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final arc = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        progress * 2 * pi,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.arcColor != arcColor;
}

// ─── Stats Row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final DashboardState state;
  const _StatsRow({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Row(
      children: [
        _StatCell(
            icon: Icons.local_fire_department_rounded,
            color: GameColors.streakOrange,
            value: '${state.streak}',
            label: s.streak),
        const SizedBox(width: 8),
        _StatCell(
            icon: Icons.emoji_events_rounded,
            color: GameColors.gold,
            value: '${state.longestStreak}',
            label: s.best),
        const SizedBox(width: 8),
        _StatCell(
            icon: Icons.check_circle_rounded,
            color: GameColors.xpBlue,
            value: '${state.totalCompletions}',
            label: s.total),
        const SizedBox(width: 8),
        _StatCell(
            icon: Icons.toll_rounded,
            color: GameColors.gold,
            value: '${state.gold}',
            label: s.gold),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _StatCell(
      {required this.icon,
      required this.color,
      required this.value,
      required this.label});

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
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: gp.textPrimary,
                  height: 1,
                  letterSpacing: -0.5),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: gp.textTert,
                  letterSpacing: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Progress Report ─────────────────────────────────────────────────────────

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
    final today = DateTime.now();
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
                child: const Icon(Icons.show_chart_rounded,
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

// ─── Streak Freeze Card ───────────────────────────────────────────────────────

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
        border: Border.all(color: GameColors.xpBlue.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: GameColors.xpBlue.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.ac_unit_rounded, color: GameColors.xpBlue),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok
                                ? s2.streakFreeze
                                : 'Need ${DashboardNotifier.streakFreezeCost} ${s2.gold}'),
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

// ─── Achievement Card ─────────────────────────────────────────────────────────

class _AchievementCard extends StatelessWidget {
  final AchievementModel achievement;
  final bool isUnlocked;
  final DashboardState state;
  const _AchievementCard(
      {required this.achievement,
      required this.isUnlocked,
      required this.state});

  Color get _color => switch (achievement.rarity) {
        AchievementRarity.common => GameColors.rarityCommon,
        AchievementRarity.uncommon => GameColors.rarityUncommon,
        AchievementRarity.rare => GameColors.rarityRare,
        AchievementRarity.epic => GameColors.rarityEpic,
        AchievementRarity.legendary => GameColors.rarityLegendary,
      };

  IconData get _icon => switch (achievement.trigger) {
        AchievementTrigger.streak =>
          Icons.local_fire_department_rounded,
        AchievementTrigger.level => Icons.bolt_rounded,
        AchievementTrigger.totalCompletions =>
          Icons.check_circle_rounded,
        AchievementTrigger.habitMastery => Icons.menu_book_rounded,
        AchievementTrigger.greenSquares => Icons.grid_view_rounded,
        _ => Icons.stars_rounded,
      };

  double get _progress => switch (achievement.trigger) {
        AchievementTrigger.streak =>
          (state.streak / achievement.threshold).clamp(0.0, 1.0),
        AchievementTrigger.level =>
          (state.level / achievement.threshold).clamp(0.0, 1.0),
        AchievementTrigger.totalCompletions =>
          (state.totalCompletions / achievement.threshold)
              .clamp(0.0, 1.0),
        AchievementTrigger.greenSquares =>
          (state.totalGreenSquares / achievement.threshold).clamp(0.0, 1.0),
        _ => 0.0,
      };

  int get _current => switch (achievement.trigger) {
        AchievementTrigger.streak => state.streak,
        AchievementTrigger.level => state.level,
        AchievementTrigger.totalCompletions => state.totalCompletions,
        AchievementTrigger.greenSquares => state.totalGreenSquares,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final c = _color;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color: isUnlocked ? c.withOpacity(0.5) : gp.border,
          width: isUnlocked ? 1 : 0.5,
        ),
      ),
      child: Opacity(
        opacity: isUnlocked ? 1.0 : 0.55,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: (isUnlocked ? c : gp.textTert)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_icon,
                      size: 18,
                      color: isUnlocked ? c : gp.textTert),
                ),
                const Spacer(),
                if (isUnlocked)
                  Icon(Icons.verified_rounded, size: 16, color: c),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              achievement.name,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: gp.textPrimary,
                  height: 1.25),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              achievement.rarity.displayName.toUpperCase(),
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: c,
                  letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),
            if (isUnlocked)
              Row(children: [
                if (achievement.xpReward > 0) ...[
                  const Icon(Icons.bolt_rounded,
                      size: 11, color: GameColors.xpBlue),
                  const SizedBox(width: 2),
                  Text('+${achievement.xpReward}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: GameColors.xpBlue)),
                  const SizedBox(width: 8),
                ],
                if (achievement.goldReward > 0) ...[
                  const Icon(Icons.toll_rounded,
                      size: 11, color: GameColors.gold),
                  const SizedBox(width: 2),
                  Text('+${achievement.goldReward}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: GameColors.gold)),
                ],
              ])
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: gp.border,
                  valueColor:
                      AlwaysStoppedAnimation(c.withOpacity(0.5)),
                  minHeight: 3,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$_current / ${achievement.threshold}',
                style: TextStyle(
                    fontSize: 10,
                    color: gp.textTert,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Settings ─────────────────────────────────────────────────────────────────

class _SettingsSection extends ConsumerWidget {
  const _SettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final locale = ref.watch(localeProvider);
    final isAr = locale.languageCode == 'ar';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.settings,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: gp.textSec,
                  letterSpacing: 1.5)),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: gp.surface,
              borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
              border: Border.all(color: gp.border, width: 0.5),
            ),
            child: Column(
              children: [
                // GrowDaily Premium
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pushNamed(context, '/premium');
                  },
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(GameSpacing.cardRadius),
                    topRight: Radius.circular(GameSpacing.cardRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.workspace_premium_rounded,
                            size: 20, color: GameColors.gold),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(s.premiumTitle,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: gp.textPrimary,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded,
                            size: 14, color: gp.textTert),
                      ],
                    ),
                  ),
                ),
                Container(height: 0.5, color: gp.divider),
                // Dark Mode toggle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                        size: 20,
                        color: gp.textSec,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(s.darkMode,
                            style: TextStyle(
                                fontSize: 15,
                                color: gp.textPrimary,
                                fontWeight: FontWeight.w500)),
                      ),
                      Switch(
                        value: isDark,
                        onChanged: (_) {
                          HapticFeedback.selectionClick();
                          ref.read(themeModeProvider.notifier).toggle();
                        },
                      ),
                    ],
                  ),
                ),
                Container(height: 0.5, color: gp.divider),
                // Language toggle
                InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ref.read(localeProvider.notifier).toggle();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(Icons.language_rounded, size: 20, color: gp.textSec),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(s.language,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: gp.textPrimary,
                                  fontWeight: FontWeight.w500)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: GameColors.gold.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                                color: GameColors.gold.withOpacity(0.3), width: 0.5),
                          ),
                          child: Text(
                            isAr ? 'العربية' : 'English',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: GameColors.gold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(height: 0.5, color: gp.divider),
                // Sign Out
                InkWell(
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    ref.read(guestModeProvider.notifier).state = false;
                    await ref.read(authNotifierProvider.notifier).signOut();
                    if (context.mounted) {
                      Navigator.pushNamedAndRemoveUntil(
                          context, '/', (_) => false);
                    }
                  },
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(GameSpacing.cardRadius),
                    bottomRight: Radius.circular(GameSpacing.cardRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.logout_rounded,
                            size: 20, color: GameColors.error),
                        const SizedBox(width: 12),
                        Text(s.signOut,
                            style: const TextStyle(
                                fontSize: 15,
                                color: GameColors.error,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Icon(Icons.arrow_forward_ios_rounded,
                            size: 14, color: gp.textTert),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
