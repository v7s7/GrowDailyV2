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
              // Selection can now be switched on from the header with
              // nothing picked yet, which used to render "0 selected"
              // beside a live red Delete — an accurate label that still
              // reads as a broken screen. At zero this says what to do,
              // and the Delete button below isn't there to be pressed.
              count == 0 ? s.gridSelectPrompt : s.matrixSelectedCount(count),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: count == 0 ? gp.textSec : gp.textPrimary,
              ),
            ),
          ),
          if (onEdit != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.edit_outlined, size: 18, color: gp.textSec),
              onPressed: onEdit,
            ),
          if (count > 0)
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

  /// Whether to show the "+" add-habit action. False while the habit list is
  /// empty, because the empty state below renders its own, larger pair of
  /// buttons and owns [addHabitKey] in that case — two live widgets can never
  /// share one GlobalKey.
  final bool showAddAction;

  /// App Guide's coach-mark anchor for the "Add a habit" lesson. Moves with
  /// the button: it used to sit on the floating action button.
  final GlobalKey? addHabitKey;

  /// Turns on multi-select. Long-press used to do this, but long-press is
  /// now the per-habit actions menu (edit / pause / delete) — the common
  /// case. Selecting several habits at once is the rare one, so it gets
  /// an explicit control instead of the gesture. Null while there are no
  /// habits to select.
  final VoidCallback? onStartSelection;

  const _GridHeader({
    required this.state,
    required this.showAddAction,
    this.addHabitKey,
    this.onStartSelection,
  });

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
              // This row holds ACTIONS only. The Progress Heatmap used to sit
              // here as a third unlabelled glyph (Icons.insights_rounded),
              // and it was the weakest thing on the screen: a *report*, drawn
              // as a sparkline, whose headline stat ("Squares filled" /
              // "مربّعات ملوّنة") is the same string in both languages as the
              // big number 200px below it. It now lives behind a worded row
              // at the bottom of the summary card that already previews it —
              // see _SummaryCard — which is both more discoverable and
              // honest about what it is.
              //
              // What replaced it is the add-habit button, moved up from a
              // floating action button. On a tall habit list that FAB
              // overlapped the board and covered a real, tappable square:
              // fine over a list, wrong over a grid where every cell is a
              // target. Up here it can never cover the thing the app is for,
              // and "+" needs no tooltip to be understood.
              // Labelled, not a bare glyph. The comment above used to argue
              // that "+" needs no tooltip — true of a "+" standing alone, but
              // it does not stand alone: it sits immediately beside a second
              // unlabelled glyph, and two mystery icons in a row make the
              // app's single most important action look like a peer of the
              // journal shortcut rather than the thing the screen is for.
              // Naming it costs about 60pt of a header that has empty space to
              // spare, and it is the one control a first-run user must find.
              //
              // Still in the header rather than a FAB, for the reason the
              // original move records: a floating button over a grid covers a
              // real, tappable square.
              if (showAddAction)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Material(
                    color: GameColors.gold.withOpacity(gp.dark ? 0.16 : 0.12),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      key: addHabitKey,
                      borderRadius: BorderRadius.circular(999),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        showAddHabitHub(context, ref);
                      },
                      child: Padding(
                        // Asymmetric on purpose: the icon carries its own
                        // optical padding, the text does not.
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            10, 7, 12, 7),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded,
                                size: 18, color: GameColors.gold),
                            const SizedBox(width: 5),
                            Text(
                              s.addHabit,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: GameColors.gold,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (onStartSelection != null)
                IconButton(
                  icon: Icon(Icons.checklist_rounded, color: gp.textSec),
                  tooltip: s.habitSelectMultiple,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    onStartSelection!();
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

    final card = Container(
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
                        // Agrees with the number it sits beside — Arabic
                        // takes the singular at 1, the dual at 2, the plural
                        // at 3–10 and the accusative singular at 11+, so a
                        // fixed plural read "1 مربّعات ملوّنة" on the app's
                        // main screen. English is unaffected.
                        s.gridGreenSquaresCount(greens),
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
                // Flexible, not bare children: these two stats sit beside the
                // summary card's big number, so the width left for them is
                // already narrow, and both carry a translated label whose
                // length isn't ours to control. On a 402pt iPhone this Row
                // overflowed by 24px — the yellow-and-black stripe on the
                // app's main screen in debug, and silently clipped text in
                // release. The gap shrinks before the content does, and each
                // stat gets to ellipsize its own label rather than push its
                // neighbour off the card. Reproduced by
                // grid_square_alignment_test's phone-width group, which is
                // the only place the narrow branch is exercised at all.
                Row(
                  children: [
                    Flexible(
                      child: _MiniStat(
                        icon: Icons.bolt_rounded,
                        value: '$points',
                        label: s.gridPoints,
                        color: GameColors.gold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: _MiniStat(
                        icon: Icons.percent_rounded,
                        value: '${(ratio * 100).round()}%',
                        label: s.gridComplete,
                        color: GameColors.iconXp,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    )
        // The Heatmap's new front door, replacing the unlabelled sparkline
        // that used to sit in the app bar (see _GridHeader). A worded row at
        // the foot of this card is the better home for it precisely because
        // this card is already the week-scoped preview of what that screen
        // shows across months — the link now sits under the thing it expands,
        // rather than being a mystery glyph two hundred pixels away.
        //
        // Deliberately NOT "make the whole card tappable": the card already
        // prints "Tap to color · long-press for more colors" (s.gridTapHint)
        // inside itself, so a card-wide tap target would directly contradict
        // its own instructions.
        //
        // A single celebratory sweep the moment today goes fully green. Stays
        // on the card alone, not on the Column below — a shimmer sweeping
        // across the heatmap link too would read as that row celebrating
        // something, which it has no part in.
        .animate(target: perfectDay ? 1 : 0)
        .shimmer(
          duration: 900.ms,
          color: GameColors.emerald.withOpacity(0.30),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        const SizedBox(height: 8),
        const _HeatmapLinkRow(),
      ],
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

/// The worded door to the Progress Heatmap, sitting directly under the
/// summary card it expands.
///
/// Shape copied from LifeTimelineScreen's own footer link and from every
/// "View all" row on ProgressHub — leading icon, label, trailing chevron —
/// so it behaves identically in Arabic without any directional work of its
/// own: `Icons.chevron_right_rounded` is auto-mirrored by Flutter under an
/// RTL Directionality, exactly as the Profile rows already are.
class _HeatmapLinkRow extends StatelessWidget {
  const _HeatmapLinkRow();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.pushNamed(context, '/heatmap');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.calendar_view_month_rounded,
                  size: 18, color: gp.textSec),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.heatmapTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: gp.textSec,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: gp.textTert),
            ],
          ),
        ),
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
    // mainAxisSize.min so a Flexible parent can hand this exactly the width it
    // needs and no more; the icon and the value are never allowed to shrink
    // (a clipped number is worse than a clipped word), so only the label is
    // Flexible and only the label ellipsizes.
    return Row(
      mainAxisSize: MainAxisSize.min,
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
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: gp.textTert),
          ),
        ),
      ],
    );
  }
}
