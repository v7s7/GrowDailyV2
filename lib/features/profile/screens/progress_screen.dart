import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/theme/game_theme.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';

class ProgressPoint {
  final DateTime date;
  final int completions;

  const ProgressPoint({required this.date, required this.completions});
}

// autoDispose: this screen is only ever reached via Navigator.push from
// Profile, so it fully unmounts on pop. Without autoDispose this plain
// FutureProvider would compute once, cache forever, and never refetch —
// complete a habit on Dashboard, come back to Progress & Streak, and the
// chart (including "today") would still show whatever was true the first
// time this was ever opened this session, since the only thing that would
// invalidate it is authStateProvider changing (sign in/out), not new
// completions. autoDispose means it's torn down the moment this screen is
// popped, so reopening it always re-fetches fresh instead.
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

/// Pushed from Profile's "Progress & Streak" row — the 14-day chart and the
/// streak-freeze shop card used to sit inline on Profile; both are about
/// ongoing performance rather than identity, so they're grouped here
/// instead of competing with the profile header for space.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

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
        title: Text(s.progressStreakTitle,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary)),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _StreakFreezeCard(state: state),
          const SizedBox(height: 14),
          _ProgressReportCard(state: state),
        ],
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
