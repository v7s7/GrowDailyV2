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

  /// The two list-wide actions, in the app's own sheet language rather
  /// than a Material popup: reorder the rows, or arm multi-select.
  void _showListActionsMenu(BuildContext context) {
    final s = S.of(context);
    final gp = context.gp;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          decoration: BoxDecoration(
            color: gp.surfaceHigh,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ListActionRow(
                icon: Icons.swap_vert_rounded,
                label: s.reorderHabitsTitle,
                subtitle: s.reorderHabitsMenuHint,
                onTap: () {
                  Navigator.pop(sheetContext);
                  showHabitReorderSheet(context);
                },
              ),
              Divider(color: gp.divider, height: 1),
              _ListActionRow(
                icon: Icons.checklist_rounded,
                label: s.gridSelectMultiple,
                subtitle: s.gridSelectMultipleHint,
                onTap: () {
                  Navigator.pop(sheetContext);
                  onStartSelection?.call();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final notifier = ref.read(weeklyGridProvider.notifier);
    final start = state.weekStart;
    // !canGoForward, not isCurrentWeek. Those two disagree for the flex window
    // once a week: isCurrentWeek asks whether the visible week holds the
    // REWARD day (effectiveDay), while the board deliberately seeds itself
    // from the real calendar so that 1am Saturday opens on the new week
    // (see WeeklyGridState's own seed comment). During Saturday's flex window
    // the app therefore puts you on the newest week and isCurrentWeek then
    // called it a past week: the header showed a date range plus a gold
    // "this week" prompt, and tapping that prompt ran goToCurrentWeek() ->
    // _goToWeek(the week you are already on) -> early return. A control
    // that argued you were lost and then did nothing about it.
    //
    // canGoForward is the honest question for a HEADER: is there a newer
    // week to move to. Deliberately not changing isCurrentWeek itself,
    // which reward-eligibility reads (rewardEligiblePoints /
    // todayCompletionRatio, both of which additionally check that the
    // effective today is one of the visible days, so they stay correct).
    final isNewestWeek = !state.canGoForward;
    // weekSpanLabel, not DateFormat('MMM d'): the raw pattern renders
    // Arabic-Indic digits and puts the month before the day, so the header
    // read «يوليو ١١ – يوليو ١٧» while the picker that sets it read
    // «11 – 17 يوليو». Same week, two different-looking dates, one tap
    // apart. See westernDate's doc comment for why day-before-month is the
    // correct Arabic order.
    final range = isNewestWeek ? s.gridThisWeek : weekSpanLabel(start, locale);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // No title anymore, on Aziz's call: «شبكة الانتصارات» was the
              // one line of the header that did nothing, and every icon that
              // earned a slot squeezed it further (it was already scaling
              // down to fit). The board below IS the identity; the header is
              // now purely the action strip, with the labelled add chip
              // holding the reading edge the title used to anchor and the
              // shortcuts clustered at the far end.
              //
              // The chip stays labelled, not a bare "+": it sits beside four
              // unlabelled glyphs, and the app's single most important
              // action must not look like a peer of the journal shortcut.
              // Still in the header rather than a FAB, for the reason the
              // original move records: a floating button over a grid covers
              // a real, tappable square.
              //
              // (History: the Progress Heatmap once sat here as a sparkline
              // glyph and now lives behind a worded row in _SummaryCard —
              // that reasoning is unchanged by the title's removal.)
              // The chip owns ALL the row's slack, and is the only thing in
              // it that can give way.
              //
              // The removed title used to be the Expanded that absorbed
              // that slack; without it the row was entirely inflexible (a
              // fixed chip beside four tight 44pt frames) and overflowed by
              // 20px at a 320pt viewport — an iPhone on Zoomed display, or
              // a small Android — and by 6px at 360pt once the system font
              // scale reached 1.4. Caught by an adversarial review probe,
              // not by any device I looked at, because a 402pt iPhone has
              // room to spare.
              //
              // Expanded + Align rather than Flexible + a Spacer, and the
              // difference is not cosmetic: a Spacer is an Expanded with
              // flex 1, so it and a Flexible chip SPLIT the free space
              // evenly. At 320pt that handed the chip ~44pt, crushing its
              // own inner Row until the "+" glyph overflowed — the same
              // stripe one layer down. Align gives the chip its natural
              // width at the reading edge and leaves every spare pixel
              // beside it, so the label only ellipsizes once the row
              // genuinely runs out of room.
              if (showAddAction)
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: Material(
                      color:
                          GameColors.gold.withOpacity(gp.dark ? 0.16 : 0.12),
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
                          //
                          // Grown on his call: this is the app's single most
                          // important action and it was sized like the glyphs
                          // beside it. The room came from dropping the fourth
                          // icon rather than from squeezing the row, so the
                          // narrow-phone fit test still has the slack it was
                          // written to protect.
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              14, 10, 17, 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_rounded,
                                  size: 21, color: GameColors.gold),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  s.addHabit,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: GameColors.gold,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  ),
                ),
              // Only when the chip is absent (an empty habit list, where
              // _GridEmptyState owns the add action instead). With the chip
              // present its Expanded already pushes the cluster to the far
              // end; a Spacer here as well would compete with it for the
              // free space — see the chip's own note.
              if (!showAddAction) const Spacer(),
              // The Progress Map's header glyph was removed on his call
              // (2026-09-03), and it is the one icon here that could go
              // without stranding anything: the worded row inside
              // _SummaryCard, a couple of hundred pixels below on this very
              // screen, opens exactly the same place. Two doors into one
              // room on one screen, and the one that came out was the
              // unlabelled glyph rather than the row that says what it is.
              //
              // The other three stay, and each for its own reason. Night
              // Review's only other door is a card on the Profile tab, and
              // it is an every-evening action; the tasbih's header slot is
              // its ONLY door in the whole app; and the overflow menu is the
              // only way to reach multi-select or reorder at all.
              //
              // All the action icons share one 44pt _HeaderAction frame, one
              // shared number so the cluster cannot drift uneven.
              //
              // Not a moon: Sleep already uses a crescent
              // (Icons.bedtime_rounded, see HabitCategory.icon) and a
              // second moon here read as "toggle dark mode" more than
              // "review my day". An open book reads as the daily
              // journal/reflection this actually opens.
              _HeaderAction(
                icon: Icons.auto_stories_rounded,
                tooltip: s.nightReviewTitle,
                route: '/night-review',
              ),
              // The tasbih counter, shown only to people who are actually
              // doing dhikr. A ring of dots is the closest Material gets to a
              // misbaha; every bead-free alternative read as something else
              // (workspaces as "groups", timelapse as a timer).
              //
              // Conditional on his call (2026-09-03): not everyone wants a
              // misbaha in their header, and it was costing every one of them
              // a permanent slot. An athkar-category habit on the board is
              // the honest test for "this person would use one" — أذكار
              // الصباح, أذكار المساء, تهجّد, or any custom habit they filed
              // under أذكار themselves.
              //
              // Deliberately NOT a setting. A toggle would have to default to
              // something, and both answers are worse than this: default on
              // and nothing changes for the people it was meant to spare;
              // default off and the feature is invisible to everyone who
              // would have wanted it, including the people who already use
              // it. Keying it to the board means it appears for exactly the
              // people it is for, and disappears when it stops being for
              // them, with nothing to discover or configure.
              if (ref
                  .watch(habitListProvider)
                  .any((h) => h.category == HabitCategory.athkar))
                _HeaderAction(
                  icon: Icons.blur_circular,
                  tooltip: s.tasbihTitle,
                  route: '/tasbih',
                ),
              // List-wide actions: multi-select and reorder. Multi-select
              // used to have its own header slot; when the Progress Map
              // took it, onStartSelection kept being passed here and
              // silently never rendered — the selection bar, bulk delete
              // and all, had NO entry point left in the app. Both actions
              // are rare-but-real, which is exactly what an overflow menu
              // is for.
              if (onStartSelection != null)
                IconButton(
                  icon: Icon(Icons.more_vert_rounded,
                      color: gp.textSec, size: 23),
                  tooltip: s.gridMoreActions,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 44, height: 44),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _showListActionsMenu(context);
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
                  // Tap the title to pick a week outright. The arrows move
                  // seven days per tap, which is fine for last week and
                  // useless for last spring - and they never say how far
                  // back the board goes, so a week you know you filled in
                  // is unaimable. Long-press keeps the old one-tap jump
                  // home for anyone already used to it.
                  onTap: () => _pickWeek(context, ref, state),
                  onLongPress: isNewestWeek
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          notifier.goToCurrentWeek();
                        },
                  child: Column(
                    children: [
                      // Chevron so the title reads as a control. Without
                      // it the week label looked like a caption between two
                      // arrows, and nobody tries tapping a caption.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: AnimatedSwitcher(
                              duration: GameMotion.standard,
                              child: Text(
                                range,
                                key: ValueKey(range),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: gp.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.expand_more_rounded,
                              size: 16, color: gp.textSec),
                        ],
                      ),
                      if (!isNewestWeek)
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

/// Opens the week picker and moves the board to whatever comes back.
///
/// The list runs from the account's earliest recorded square up to the
/// newest week, so it doubles as an answer to "how far back does this go" -
/// the question the arrows could never answer. No premium floor here on
/// purpose: the Grid has never gated past weeks (WeeklyGridNotifier.
/// previousWeek steps back without a canBrowseHistoryMonth check anywhere),
/// and a picker is not the place to introduce a paywall that did not exist
/// a moment ago.
Future<void> _pickWeek(
  BuildContext context,
  WidgetRef ref,
  WeeklyGridState state,
) async {
  final notifier = ref.read(weeklyGridProvider.notifier);
  // Every day that has ever been written, in date-key form. Cheap: this is
  // the dashboard rollup the Heatmap already reads, not a fresh query.
  final counts = ref.read(dashboardProvider).dailyGreenCounts;
  final newest = DateTime.now().startOfDisplayWeek;
  DateTime earliest = newest;
  for (final key in counts.keys) {
    final day = DateTime.tryParse(key);
    if (day == null) continue;
    final weekStart = day.startOfDisplayWeek;
    if (weekStart.isBefore(earliest)) earliest = weekStart;
  }
  // Always offer at least a few weeks back, so a brand-new account gets a
  // picker that demonstrates what it is for instead of a single chip.
  final floor = newest.subtract(const Duration(days: 7 * 7));
  if (earliest.isAfter(floor)) earliest = floor;
  // And never fewer weeks than the person has already arrowed to.
  if (state.weekStart.isBefore(earliest)) earliest = state.weekStart;

  final picked = await showWeekPicker(
    context,
    weeks: weeksBetween(earliest, newest),
    selected: state.weekStart,
    hasData: (weekStart) {
      for (var i = 0; i < 7; i++) {
        final key = weekStart.add(Duration(days: i)).toDateKey();
        if ((counts[key] ?? 0) > 0) return true;
      }
      return false;
    },
  );
  if (picked == null) return;
  notifier.goToWeek(picked);
}

/// One of the header's shortcut icons, in one shared 44pt frame — a single
/// number for the whole cluster so the icons cannot drift uneven, sized
/// between IconButton's default 48pt and the cramped 40pt these used while
/// they still shared the row with the (since removed) title.
class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final String route;
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return IconButton(
      icon: Icon(icon, color: gp.textSec, size: 23),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      onPressed: () {
        HapticFeedback.selectionClick();
        Navigator.pushNamed(context, route);
      },
    );
  }
}

/// One row of the header's list-actions menu — icon, label, quiet hint.
/// Mirrors habit_actions_sheet's _ActionRow shape so the two sheets read
/// as one family.
class _ListActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _ListActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: gp.textPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: gp.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: gp.textSec,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

  /// XP actually paid out today, handed in by the caller from
  /// DashboardState.earnedXpOn — see the construction site in
  /// grid_screen.dart for why this replaced the flat per-state sum.
  final int xpToday;

  /// Today's step count as runStepAutoComplete last read it, or null on an
  /// account with no linked walking habit (and before the first read of the
  /// session). Feeds [_stepPartials] so a walk in progress moves the
  /// percentage instead of counting for nothing until the goal lands.
  final int? stepsToday;
  const _SummaryCard({
    required this.habits,
    required this.state,
    required this.xpToday,
    required this.stepsToday,
  });

  /// Part-done credit for walking habits linked to the step count: the real
  /// fraction of today's goal walked so far.
  ///
  /// Only habits still short of their goal appear. One at or past it has been
  /// auto-completed, so it is already worth a whole unit through its own
  /// green square, and listing it here would be double counting (the ratio
  /// only consults this map for squares that are still empty, but a map that
  /// is wrong is a trap for the next reader of it).
  Map<String, double> _stepPartials() {
    final steps = stepsToday;
    if (steps == null || steps <= 0) return const {};
    return {
      for (final habit in habits)
        if (habit.stepGoal != null && steps < habit.stepGoal!)
          habit.id: steps / habit.stepGoal!,
    };
  }

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
    final ratio = state.todayCompletionRatio(
      scheduledTodayIds,
      partialUnits: _stepPartials(),
    );

    // What today actually paid out (see xpToday's doc comment). Past-day
    // marks still contribute nothing: setSquare's anti-backdating guard
    // means they never pay, so they never reach this counter either.
    final points = xpToday;

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

    // The Progress Map link used to sit right here, directly above the
    // board. It now lives once, as the icon in this screen's header: two
    // doors to the same screen a few hundred pixels apart made the map
    // look like two different things.
    return card;
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
