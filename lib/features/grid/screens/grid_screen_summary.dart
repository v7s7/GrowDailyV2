part of 'grid_screen.dart';

// ─── Selection bar (multi-select habits for bulk delete) ──────────────────────

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  const _SelectionBar({
    required this.count,
    required this.onClear,
    required this.onDelete,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: GameColors.gold.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GameColors.gold.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: gp.textSec),
            onPressed: onClear,
          ),
          Expanded(
            child: Text(
              s.matrixSelectedCount(count),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
          ),
          if (onEdit != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.edit_outlined, size: 18, color: gp.textSec),
              onPressed: onEdit,
            ),
          TextButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 17),
            label: Text(s.matrixDeleteSelected),
            style: TextButton.styleFrom(foregroundColor: GameColors.error),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 180.ms).slideY(begin: -0.15);
  }
}

// ─── Header (title + week navigation) ─────────────────────────────────────────

class _GridHeader extends ConsumerWidget {
  final WeeklyGridState state;
  const _GridHeader({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final notifier = ref.read(weeklyGridProvider.notifier);
    final start = state.weekStart;
    final end = start.add(const Duration(days: 6));
    final range = state.isCurrentWeek
        ? s.gridThisWeek
        : '${DateFormat('MMM d', locale).format(start)} – '
            '${DateFormat('MMM d', locale).format(end)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.gridTitle,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: gp.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.insights_rounded, color: gp.textSec),
                tooltip: s.heatmapTitle,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.pushNamed(context, '/heatmap');
                },
              ),
              IconButton(
                // Not a moon: Sleep already uses a crescent
                // (Icons.bedtime_rounded, see HabitCategory.icon) and a
                // second moon here read as "toggle dark mode" more than
                // "review my day". An open book reads as the daily
                // journal/reflection this actually opens.
                icon: Icon(Icons.auto_stories_rounded, color: gp.textSec),
                tooltip: s.nightReviewTitle,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.pushNamed(context, '/night-review');
                },
              ),
              // A third icon used to live here for Habit Notes (per-habit
              // notes and Skipped/Failed/Bonus marks left from this
              // screen's own long-press editor) - moved to Dashboard's
              // Habit Notes preview section instead (see
              // ProgressHubScreen's _JournalPreviewSection), alongside
              // Achievements/Insights, since browsing *past* entries is a
              // "look back at my details" action like those, not something
              // that needed a third icon crowding the row above the grid
              // someone's actively coloring today. Still reachable at the
              // exact same '/grid-journal' route either way.
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _NavArrow(
                icon: Icons.chevron_left_rounded,
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.previousWeek();
                },
              ),
              Expanded(
                child: GestureDetector(
                  onTap: state.isCurrentWeek
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          notifier.goToCurrentWeek();
                        },
                  child: Column(
                    children: [
                      AnimatedSwitcher(
                        duration: GameMotion.standard,
                        child: Text(
                          range,
                          key: ValueKey(range),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: gp.textPrimary,
                          ),
                        ),
                      ),
                      if (!state.isCurrentWeek)
                        Text(
                          s.gridThisWeek,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: GameColors.gold,
                            letterSpacing: 0.5,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _NavArrow(
                icon: Icons.chevron_right_rounded,
                enabled: state.canGoForward,
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.nextWeek();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  const _NavArrow(
      {required this.icon, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: Material(
        color: gp.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          side: BorderSide(color: gp.border, width: 0.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: gp.textSec, size: 24),
          ),
        ),
      ),
    );
  }
}

// ─── Summary card (green squares, points, completion) ─────────────────────────

class _SummaryCard extends StatelessWidget {
  final List<IslamicHabitTemplate> habits;
  final WeeklyGridState state;
  const _SummaryCard({required this.habits, required this.state});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final today = DateTime.now().effectiveDay;
    final habitIds = habits.map((h) => h.id).toList();
    final scheduledTodayIds = habits
        .where((h) => h.isScheduledFor(today))
        .map((h) => h.id)
        .toList();
    final greens = state.greenSquares(habitIds);
    final ratio = state.todayCompletionRatio(scheduledTodayIds);

    // Only today's marks are reward-eligible. Past-day marks remain visual
    // history, but the summary must not present them as earned XP.
    final points = state.rewardEligiblePoints(scheduledTodayIds);

    final greensToday = () {
      if (!state.days.any((d) => d.isSameDayAs(today))) return 0;
      final row = state.states[today.toDateKey()];
      if (row == null) return 0;
      return scheduledTodayIds
          .where((id) => (row[id] ?? SquareState.none).isGreen)
          .length;
    }();
    final perfectDay = scheduledTodayIds.isNotEmpty &&
        greensToday >= scheduledTodayIds.length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            GameColors.emerald.withOpacity(gp.dark ? 0.14 : 0.10),
            gp.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(
          color: GameColors.emerald.withOpacity(perfectDay ? 0.6 : 0.28),
          width: perfectDay ? 1.2 : 0.8,
        ),
      ),
      child: Row(
        children: [
          _RingStat(ratio: ratio),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    // Count up to the current total so each new green square
                    // visibly ticks the score.
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: greens.toDouble()),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => Text(
                        '${v.round()}',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          color: GameColors.emerald,
                          height: 1,
                          letterSpacing: -1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        s.gridGreenSquares,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: gp.textSec,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: GameMotion.relaxed,
                  child: Text(
                    perfectDay
                        ? s.gridPerfectDay
                        : greensToday > 0
                            ? s.gridGreensToday(greensToday)
                            : s.gridTapHint,
                    key: ValueKey(
                      '$perfectDay-$greensToday-${(ratio * 100).round()}',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: perfectDay ? GameColors.emerald : gp.textTert,
                      fontWeight:
                          perfectDay ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _MiniStat(
                      icon: Icons.bolt_rounded,
                      value: '$points',
                      label: s.gridPoints,
                      color: GameColors.gold,
                    ),
                    const SizedBox(width: 20),
                    _MiniStat(
                      icon: Icons.percent_rounded,
                      value: '${(ratio * 100).round()}%',
                      label: s.gridComplete,
                      color: GameColors.iconXp,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    )
        // A single celebratory sweep the moment today goes fully green.
        .animate(target: perfectDay ? 1 : 0)
        .shimmer(
          duration: 900.ms,
          color: GameColors.emerald.withOpacity(0.30),
        );
  }
}

class _RingStat extends StatelessWidget {
  final double ratio;
  const _RingStat({required this.ratio});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => CircularProgressIndicator(
                value: v,
                strokeWidth: 6,
                backgroundColor: gp.surfaceHL,
                valueColor:
                    AlwaysStoppedAnimation(GameColors.emerald),
                strokeCap: StrokeCap.round,
              ),
            ),
          ),
          Icon(
            ratio >= 1.0
                ? Icons.emoji_events_rounded
                : Icons.grid_view_rounded,
            color: GameColors.emerald,
            size: 24,
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _MiniStat(
      {required this.icon,
      required this.value,
      required this.label,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: gp.textTert),
        ),
      ],
    );
  }
}
