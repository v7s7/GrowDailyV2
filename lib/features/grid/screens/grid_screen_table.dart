part of 'grid_screen.dart';

// ─── The grid table itself ────────────────────────────────────────────────────

class _GridTable extends ConsumerStatefulWidget {
  final List<IslamicHabitTemplate> habits;
  final WeeklyGridState state;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(String id) onSelectionToggle;
  /// Long-press on a habit's name. Opens the per-habit actions menu
  /// (edit / pause / delete) — it used to start multi-select, which put
  /// the rare bulk case on the common gesture and left pausing with no
  /// route at all. Bulk selection is now an explicit header control.
  final void Function(String id) onHabitLongPress;
  // Only set by GridScreen when this is the first-displayed table (see
  // grid_screen.dart's build method), and only actually attached to
  // *today's* square in row 0 — see _habitRow's use of it. App Guide's
  // "Track a day" lesson can then circle the one exact square its own copy
  // ("Tap a square to color it in") is talking about, instead of the whole
  // row.
  final GlobalKey? todayCellKey;

  const _GridTable({
    required this.habits,
    required this.state,
    required this.selectionMode,
    required this.selectedIds,
    required this.onSelectionToggle,
    required this.onHabitLongPress,
    this.todayCellKey,
  });

  @override
  ConsumerState<_GridTable> createState() => _GridTableState();
}

class _GridTableState extends ConsumerState<_GridTable> {
  static const double _habitCol = 96;
  static const double _gap = 5;

  // Marks whichever header cell is "today", purely so the grid can scroll
  // straight to it right after it first appears — see initState. This
  // widget is rebuilt fresh (new State) every time the visible week
  // changes, because the parent wraps it in
  // KeyedSubtree(key: ValueKey(grid.weekStart)), so this naturally re-runs
  // exactly when it should and never fights the user's own scrolling
  // within a week they're already looking at.
  final GlobalKey _todayKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _todayKey.currentContext;
      // Scroll ONLY this table's own sideways scroller, and only when it
      // has one (the week is wider than the screen, see build).
      //
      // This used to be Scrollable.ensureVisible(ctx, alignment: 1), on the
      // belief that it was a no-op when the week fits. It is not: it walks
      // EVERY scrolling ancestor, so with no sideways scroller it scrolled
      // the page itself, putting today's header on the bottom edge. With a
      // Build, Quit and Paused table each doing it in mount order, the last
      // one won and the app opened at the very bottom of the Habits page
      // (Aziz, 2026-09-17). ScrollPosition.ensureVisible moves one position
      // and never walks up. The nearest Scrollable is the page's vertical
      // list when the week fits, which the axis check skips; asking
      // Scrollable.maybeOf for a horizontal axis instead would skip the page
      // and find HomeShell's PageView.
      final table = ctx == null ? null : Scrollable.maybeOf(ctx);
      final target = ctx?.findRenderObject();
      if (mounted &&
          table != null &&
          target != null &&
          table.position.axis == Axis.horizontal) {
        table.position.ensureVisible(target, alignment: 1);
      }
      // An older week's step squares carry the counts the log last saw, which
      // can be short of Health's (a day stops being read once its square is
      // marked). One fresh read the first time the week is shown this
      // session; the current week is runStepAutoComplete's. Same once-per-week
      // timing as the scroll above, for the same reason.
      if (mounted) {
        unawaited(refreshStepsForOlderWeek(ref, widget.state.days));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final avail = constraints.maxWidth;
          // The habit-name column is what decides whether a week fits.
          //
          // It was a flat 96. On a 402pt iPhone that left
          // (343 - 96 - 35) / 7 ≈ 30.3pt per square, under the old hard floor
          // of 34, which tripped the scrolling branch below — so the app's
          // main screen silently rendered only six and a half days, with the
          // seventh clipped at the edge and no fade, scrollbar or any other
          // hint that it was there. A week view that hides a day of the week
          // is wrong in a way no amount of square size makes up for.
          //
          // Letting the label column give ground first fixes it without
          // shrinking the squares in any way a finger would notice: 21% of
          // the available width, floored at 68 so two-line names still read,
          // capped at the old 96 so nothing changes on wide screens (iPad,
          // landscape) where it already fit. On a 402pt phone that yields
          // ~72pt of label and ~33.7pt squares — a third of a point smaller
          // than before, in exchange for Friday existing.
          // Floor stays 68. Raising it to 88 (to reserve room for the boost
          // badge — see its Positioned in _habitRow) keeps the names but
          // makes this row overflow by exactly 1.00px, which Flutter paints as
          // a stripe across the last habit. The arithmetic here is meant to
          // land on `avail` exactly, so any change to habitCol has to be
          // reconciled with the cell floor and rounding below, not just added.
          final habitCol = (avail * 0.21).clamp(68.0, _habitCol);
          double cell = (avail - habitCol - 7 * _gap) / 7;
          bool scroll = false;
          // Floor lowered 34 -> 30 for the same reason: it is the difference
          // between fitting and not fitting on a 375pt iPhone SE, and 30pt
          // squares still read clearly at this density. Below 30 the board
          // genuinely stops being usable, so that is where scrolling starts.
          if (cell < 30) {
            cell = 30;
            scroll = true;
          } else {
            cell = cell.clamp(30, 60).toDouble();
          }
          // Floor to a whole pixel. The row lays out as
          // habitCol + 7*_gap + 7*cell, which is `avail` exactly in real
          // arithmetic — but cell is a fraction (33.714… on a 402pt phone)
          // and seven of them plus the column rounds a hair over during
          // layout, overflowing the Row by 1.0px and painting Flutter's
          // yellow-and-black stripe down the corner of the main screen.
          // Flooring leaves a few spare pixels instead of a few spare
          // thousandths, and whole-pixel squares render crisper besides.
          cell = cell.floorToDouble();
          final table = _buildTable(context, ref, cell, habitCol);
          if (!scroll) return table;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table,
          );
        },
      ),
    );
  }

  Widget _buildTable(
      BuildContext context, WidgetRef ref, double cell, double habitCol) {
    final days = widget.state.days;
    // Fixed per-row height, shared by every row regardless of square size —
    // a 2-line habit name (long names wrap) used to make just that row
    // taller than its neighbors, so its squares sat lower than the squares
    // above/below it even though each square is individually the same
    // size. Locking every row to one height keeps every square aligned
    // into a clean grid no matter how the habit name wraps.
    final rowHeight = (cell > 46 ? cell : 46.0) + 10;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerRow(context, days, cell, habitCol),
        const SizedBox(height: 12),
        // Rows fade in on entrance — fade ONLY, no slideX: the staggered
        // horizontal slide meant every row sat at a slightly different
        // x-offset while entering, which read as "the columns don't line
        // up" in any glance (or screenshot) taken during those first
        // moments. Opacity can't move layout, so alignment is now
        // guaranteed from the very first frame.
        for (var i = 0; i < widget.habits.length; i++) ...[
          _habitRow(context, ref, widget.habits[i], days, cell, rowHeight,
                  habitCol,
                  todayCellKey: i == 0 ? widget.todayCellKey : null)
              .animate(delay: (i * 45).ms)
              .fadeIn(duration: 320.ms),
          if (i != widget.habits.length - 1) const SizedBox(height: _gap),
        ],
      ],
    );
  }

  Widget _headerRow(BuildContext context, List<DateTime> days, double cell,
      double habitCol) {
    final gp = context.gp;
    final isAr = S.of(context).isAr;

    // Whichever language the app isn't currently in renders as a smaller
    // second line underneath — so a date always reads in both, but the
    // language you're actually using still leads.
    Widget dayNameLine(String text, bool isToday, bool primary) {
      return SizedBox(
        height: primary ? 12 : 10,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            style: TextStyle(
              fontSize: primary ? 10 : 8,
              fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
              // No alpha on the accent branch any more. The ink sits
              // exactly on 4.5:1, so ANY alpha drops it back under - the
              // secondary line measured 2.03:1 on device. The size and
              // weight above already carry the hierarchy the alpha did.
              color: isToday
                  ? context.gp.goldInk
                  : gp.textTert.withOpacity(primary ? 1 : 0.75),
              letterSpacing: 0.2,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        SizedBox(width: habitCol),
        for (final day in days)
          Padding(
            padding: const EdgeInsets.only(left: _gap),
            child: SizedBox(
              // isRealToday, not isToday: this circle is purely the "which
              // date is today on the calendar" marker, so it follows the
              // real clock and moves at midnight even during the flex
              // window where the *editable* square (below) is still
              // yesterday's — see DateTimeGameExt.isRealToday.
              key: day.isRealToday ? _todayKey : null,
              width: cell,
              child: Column(
                children: [
                  dayNameLine(
                    DateFormat('EEE', isAr ? 'ar' : 'en').format(day),
                    day.isRealToday,
                    true,
                  ),
                  const SizedBox(height: 1),
                  dayNameLine(
                    DateFormat('EEE', isAr ? 'en' : 'ar').format(day),
                    day.isRealToday,
                    false,
                  ),
                  const SizedBox(height: 3),
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: day.isRealToday
                        ? BoxDecoration(
                            color: GameColors.gold.withOpacity(0.16),
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: day.isRealToday
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: day.isRealToday ? context.gp.goldInk : gp.textSec,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _habitRow(BuildContext context, WidgetRef ref,
      IslamicHabitTemplate habit, List<DateTime> days, double cell,
      double rowHeight, double habitCol,
      {GlobalKey? todayCellKey}) {
    final selected = widget.selectedIds.contains(habit.id);

    // For a flexible weekly quota ("N times a week, any days") an empty square
    // is ambiguous on its own: it is either a day the person genuinely owed
    // and skipped, or a rest day the quota entitled them to. Only the week as
    // a whole can tell those apart, so it is resolved once per row here rather
    // than per cell, and only for this one cadence — a daily or named-weekday
    // habit gets null and renders exactly as it always has.
    //
    // Deliberately NOT frequencyType == weekly alone: "Specific Days" is also
    // stored as weekly, distinguished only by scheduledWeekdays being set.
    //
    // Day by day, by the schedule the habit had ON that day (see
    // quotaDemandForRow): a week it changed in is part quota, part not, and
    // a past week keeps the target it was set against.
    final demand = quotaDemandForRow(
      habit: habit,
      days: days,
      isGreenAt: (i) => widget.state.squareFor(habit.id, days[i]).isGreen,
      isUnmarkedAt: (i) =>
          widget.state.squareFor(habit.id, days[i]) == SquareState.none,
    );

    // The row that was JUST created announces itself — see
    // newlyAddedHabitIdProvider for why. Wrapping only the matching row
    // keeps every other row's build byte-identical.
    if (ref.watch(newlyAddedHabitIdProvider) == habit.id) {
      return _NewHabitHighlight(
        child: _habitRowBody(
            context, ref, habit, days, cell, rowHeight, habitCol,
            todayCellKey: todayCellKey, demand: demand, selected: selected),
      );
    }

    return _habitRowBody(context, ref, habit, days, cell, rowHeight, habitCol,
        todayCellKey: todayCellKey, demand: demand, selected: selected);
  }

  Widget _habitRowBody(BuildContext context, WidgetRef ref,
      IslamicHabitTemplate habit, List<DateTime> days, double cell,
      double rowHeight, double habitCol,
      {GlobalKey? todayCellKey,
      List<DayDemand?>? demand,
      required bool selected}) {
    final gp = context.gp;
    final isAr = S.of(context).isAr;
    final today = DateTime.now().effectiveDay;
    // Today's count is dropped entirely while the link is stalled. A failed
    // read deliberately leaves the last good count in place rather than
    // zeroing it, which is right for a number the actions sheet can caption
    // ("the link is stalled") and wrong for the board, where a square
    // painted 60% full is an unqualified claim about today that nothing
    // currently supports.
    final stepsStalled = ref.watch(stepsFailureProvider) != null;
    // Every day's count, today's included, looked up by its date. Today used
    // to come from stepsTodayProvider, which carries no date: at midnight it
    // still held yesterday's walk, and the new day's square drew yesterday's
    // "12k" (seen 2026-09-17, 00:06). The day log is keyed by date, so a day
    // can only ever show a read OF that day. Watched unconditionally: it
    // stays empty on accounts that never linked a habit, so an unlinked board
    // pays nothing for it.
    final stepsByDay = ref.watch(stepsByDayProvider);

    return SizedBox(
      height: rowHeight,
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            // A habit paused earlier today keeps its row for the rest of
            // the day, but it must not be selectable: multi-select's only
            // actions are Remove and Edit, and both are wrong for a habit
            // that is already off the board. Remove runs the same
            // toggle() that would RE-ACTIVATE a paused preset (while the
            // confirmation says it was removed, and without passing the
            // habit cap), and Edit saves into a state list that no longer
            // holds it, so every change is silently dropped. Long-press
            // still works on these rows — that menu offers Resume.
            //
            // Outside selection mode a plain tap opens the same actions
            // sheet as the long-press. Long-press was the ONLY way to
            // reach Edit/Pause/Delete and nothing on the row hinted it
            // existed; a tap on the name used to do nothing at all, so
            // this claims a dead gesture rather than displacing one. (The
            // name's own tap-to-reveal is retired below in exchange — the
            // sheet's header shows the full name anyway.)
            onTap: widget.selectionMode
                ? (habit.archivedAt == null
                    ? () => widget.onSelectionToggle(habit.id)
                    : null)
                : () {
                    HapticFeedback.selectionClick();
                    widget.onHabitLongPress(habit.id);
                  },
            onLongPress: () {
              // In selection mode a long-press must not open a per-habit
              // menu on top of an active multi-select; it just toggles.
              if (widget.selectionMode && habit.archivedAt == null) {
                HapticFeedback.mediumImpact();
                widget.onSelectionToggle(habit.id);
                return;
              }
              widget.onHabitLongPress(habit.id);
            },
            child: SizedBox(
              width: habitCol,
              child: Padding(
                // Directional, not physical: this gap exists to keep the
                // habit name off the first square, and the first square is on
                // the left in Arabic. As a physical `right` it sat on the far
                // side of the name in RTL — so the name ran flush into the
                // board while 8pt went spare against the card edge. Harmless-
                // looking until the column narrowed, at which point the wasted
                // 8pt became a 1px RenderFlex overflow and Flutter drew its
                // yellow-and-black stripe across the corner of the main screen.
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: Row(
                  children: [
                    Builder(builder: (_) {
                      // Paused rows keep their pause tile even in
                      // selection mode: showing them an empty selection
                      // circle would invite a tap that does nothing (see
                      // the GestureDetector above).
                      if (widget.selectionMode && habit.archivedAt == null) {
                        return AnimatedContainer(
                          duration: GameMotion.quick,
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected
                                ? GameColors.gold
                                : Colors.transparent,
                            border: Border.all(
                              color: selected ? GameColors.gold : gp.border,
                              width: 1.5,
                            ),
                          ),
                          child: selected
                              ? const Icon(Icons.check_rounded,
                                  size: 13, color: Colors.black)
                              : null,
                        );
                      }
                      final (_, categoryColor) = categoryVisual(context, habit.category);
                      final color = habit.customColor ?? categoryColor;
                      // Only ever true for a habit paused *today*: the row
                      // is kept for the rest of the day so pausing at 9pm
                      // doesn't blank out squares already earned that day
                      // (see habitsArchivedTodayProvider). Without a visible
                      // mark it looks exactly like an active habit, so the
                      // pause reads as "nothing happened" — the category
                      // tile becomes a plain pause glyph and the name goes
                      // tertiary, which is also the one row treatment that
                      // costs zero layout width (see the boost-badge note
                      // below for why that matters here).
                      if (habit.archivedAt != null) {
                        return Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: gp.textTert.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Icon(Icons.pause_rounded,
                              size: 13, color: gp.textTert),
                        );
                      }
                      // A gold ring + small trophy badge marks a habit
                      // that's part of a Room's plan (see
                      // myLinkedRoomHabitsProvider) - an inline highlight
                      // rather than a separate "event habits" screen, so
                      // Grid stays the one place every habit lives.
                      final inRoom =
                          ref.watch(myLinkedRoomHabitsProvider).containsKey(habit.id);
                      // 2x while a linked room is LIVE — the visible promise
                      // behind roomBoostedReward's doubled XP/gold. This is
                      // a Positioned overlay on the icon, not a Row sibling
                      // next to the name, on purpose: a Row sibling only
                      // shows up on boosted rows, which quietly narrows the
                      // Expanded name's width *just for those rows* — the
                      // exact same habit name can then wrap to a different
                      // number of lines purely because a room went live,
                      // with nothing about the text itself changing. Every
                      // row's icon box and name column are now identically
                      // sized whether or not this badge is showing.
                      final boosted = ref
                          .watch(roomBoostedHabitsProvider)
                          .contains(habit.id);
                      // The boost badge hovers over this icon via a Positioned
                      // in the Clip.none Stack below. Its whole contract is:
                      // PAINT wherever it likes, but contribute nothing to
                      // layout — any width it adds to the row shows up as
                      // squares shifted only on boosted rows, i.e. weekday
                      // columns that bend at exactly the rows carrying a
                      // badge. Reserving the badge's width here instead (a
                      // 38pt box) was tried and is worse: it either collapses
                      // «سورة الملك» to «س…» or overflows the row by 1px —
                      // see grid_square_alignment_test.dart's boosted-row
                      // case, which locks the paint-only contract in.
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(7),
                              border: inRoom
                                  ? Border.all(color: GameColors.gold, width: 1.4)
                                  : null,
                            ),
                            child: CategoryIcon(
                              category: habit.category,
                              size: 13,
                              color: color,
                            ),
                          ),
                          if (inRoom)
                            Positioned(
                              right: -3,
                              bottom: -3,
                              child: Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                  color: GameColors.gold,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: gp.surface, width: 1.2),
                                ),
                                child: const Icon(Icons.emoji_events_rounded,
                                    size: 7, color: Colors.black),
                              ),
                            ),
                          // Linked to the step count (stepGoal != null): the
                          // "make it visible in the app" half of the steps
                          // link. Same paint-only Positioned contract as the
                          // trophy dot above — see the layout warning before
                          // this Stack — on the opposite corner so a habit
                          // that is both in a room and linked shows both.
                          if (habit.stepGoal != null)
                            Positioned(
                              left: -3,
                              bottom: -3,
                              child: Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                  color: GameColors.success,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: gp.surface, width: 1.2),
                                ),
                                child: const Icon(Icons.directions_walk_rounded,
                                    size: 7, color: Colors.white),
                              ),
                            ),
                          if (boosted)
                            // Anchored by `left` ONLY, at the icon's midpoint
                            // (11 = half its 22pt width), then pulled back by
                            // half the badge's own width with a paint-time
                            // FractionalTranslation. Two earlier shapes of
                            // this line were each a different bug:
                            //
                            //  - left/right: -8 let the badge's width reach
                            //    the row's layout, so a boosted habit's
                            //    squares sat ~10pt off and every weekday
                            //    column bent at exactly the boosted rows.
                            //  - left/right: 0 + Center kept layout straight
                            //    but forced the ~28pt badge INTO a tight 22pt
                            //    box — its inner Row then overflowed by 16px
                            //    and Flutter striped every boosted row.
                            //
                            // With one anchor the badge sizes to its natural
                            // width, the translation centres it purely at
                            // paint time, and a Positioned child never
                            // affects the Stack's own size — so it cannot
                            // touch column geometry, which the boosted-row
                            // case in grid_square_alignment_test.dart now
                            // asserts. `left` not `start`: the anchor is the
                            // icon's physical midpoint, same in RTL.
                            Positioned(
                              top: -9,
                              left: 11,
                              child: FractionalTranslation(
                                translation: const Offset(-0.5, 0),
                                child: const _BoostBadge(),
                              ),
                            ),
                        ],
                      );
                    }),
                    const SizedBox(width: 6),
                    Expanded(
                      // No tap-to-reveal here anymore: the row's own tap
                      // now opens the actions sheet (see the
                      // GestureDetector above), whose header shows the
                      // full untruncated name — the reveal's whole job —
                      // and a second recognizer on the text would steal
                      // exactly those taps from the sheet.
                      // The pause tile that replaced this row's category
                      // icon is the visible signal; this is the same thing
                      // said out loud, since a screen reader gets neither
                      // the glyph nor the dimmed color.
                      child: Semantics(
                        // Spoken counterparts of the row's visual-only
                        // states: the pause tile, and the steps-link dot.
                        label: habit.archivedAt != null ||
                                habit.stepGoal != null
                            ? [
                                habit.localName(isAr),
                                if (habit.archivedAt != null)
                                  S.of(context).habitPausedSection,
                                if (habit.stepGoal != null)
                                  S.of(context).stepLinkedBadge,
                              ].join(isAr ? '، ' : ', ')
                            : null,
                        child: SafeWrapText(
                          habit.localName(isAr),
                          maxLines: 2,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            // Paused today: dimmed, but only to secondary.
                            // Tertiary on this size of text lands around
                            // 2.3:1 in the light theme, under the 4.5:1 a
                            // label this small needs to stay readable.
                            color: habit.archivedAt != null
                                ? gp.textSec
                                : gp.textPrimary,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          for (final day in days)
            // Read once per cell and shared by the square's state, its fill
            // and its screen-reader label: three independent reads of the
            // same count is how they end up disagreeing mid-frame.
            Builder(builder: (context) {
              // The count this square shows and a tap adds one to: today's,
              // or yesterday's while it is still open (see _dayCount). Null
              // on every other square and for a habit done once a day, and
              // watched only on the two squares it can move.
              final liveCount = habit.effectiveDailyTarget > 1 &&
                      (day.isToday ||
                          day.isSameDayAs(
                            DateTime(today.year, today.month, today.day - 1),
                          ))
                  ? _dayCount(ref.watch(dashboardProvider), habit, day)
                  : null;
              // Still named for today; it is this square's own count now.
              final doneToday = liveCount ?? 0;
              // How far through the day's step goal a linked walking habit
              // got. Any day the session has a count for, not only today:
              // below half the goal nothing is ever written (see
              // kStepPartialShare), so a day that showed a real walk all day
              // used to go blank the moment it stopped being today.
              //
              // Non-null only while the walk is genuinely part done AND the
              // square is otherwise empty: at zero steps there is nothing to
              // draw, at the goal runStepAutoComplete has already turned the
              // square green, and an explicit mark (skipped, failed, bonus)
              // is a deliberate statement about the day that outranks a
              // measured count — the same precedence _effectiveSquare gives
              // those marks over a times-per-day tally.
              final steps =
                  day.isToday && stepsStalled
                      ? null
                      : stepsByDay[day.toDateKey()];
              final stepGoal = habit.stepGoal;
              final stepFraction = stepFillFraction(
                steps: steps,
                goal: stepGoal,
                // A day this habit does not run on is not part done, it is
                // not owed at all. Its square is drawn dimmed and inert, and
                // runStepAutoComplete skips it for the same reason, so
                // filling it in would be the one surface claiming a day the
                // rest of the app says is off.
                scheduled: habit.isScheduledFor(day),
                square: _effectiveSquare(habit, day, doneToday),
              );
              // "8.4k" inside the square, so a week of walking reads at a
              // glance instead of only through a held square (Aziz,
              // 2026-09-16, design option A). Same count, same schedule gate
              // as the fill above; see stepSquareCount for which marks keep
              // their glyph instead.
              final stepCount = stepSquareCount(
                steps: steps,
                goal: stepGoal,
                scheduled: habit.isScheduledFor(day),
                square: _effectiveSquare(habit, day, doneToday),
              );
              // Hoisted so the marker and the spoken label cannot disagree.
              // trim() because clearing a note used to store '' rather than
              // deleting the key, so old days carry tombstones.
              final hasNote =
                  widget.state.noteFor(habit.id, day).trim().isNotEmpty;
              // A day the habit asked nothing of: an off-day of a
              // specific-days schedule, or a quota day that was never
              // load-bearing. Painted soft green so a kept week reads as
              // whole instead of half empty (see isCoveredDay), and asked
              // about before a tap records anything on it (see _tapRestDay).
              final covered = isCoveredDay(
                habit: habit,
                day: day,
                today: today,
                square: _effectiveSquare(habit, day, doneToday),
                demand: demand == null || !days.contains(day)
                    ? null
                    : demand[days.indexOf(day)],
              );
              return Padding(
                padding: const EdgeInsets.only(left: _gap),
                child: _SquareCell(
                  // "Duha prayer, Wednesday 12 August, done" — built here
                  // because this is the only place that has both the habit's
                  // name and the active language. A locked day says so, since
                  // otherwise a screen-reader user would keep trying a square
                  // that can never respond.
                  semanticLabel: [
                    habit.localName(isAr),
                    westernDate(day, 'EEEE d MMMM', isAr ? 'ar' : 'en'),
                    _effectiveSquare(habit, day, doneToday).localLabel(isAr),
                    // "2 / 4" for a counted habit's square today, and
                    // yesterday's while it is still open. The number
                    // is drawn inside the square, where a screen reader cannot
                    // reach it, and "partly done" alone does not answer the
                    // only question this habit raises — how many are left.
                    // Costs no layout width, unlike a badge beside the name.
                    if (liveCount != null)
                      S.of(context).timesPerDayProgress(
                          liveCount, habit.effectiveDailyTarget),
                    // "5320 / 8000 steps today" for a linked walking habit.
                    // Same reason as the count above: the fill is a picture,
                    // and a picture is nothing to a screen reader. Gated on
                    // the schedule for the same reason the fill is: a day
                    // this habit does not run on is not part done.
                    if (stepGoal != null &&
                        habit.isScheduledFor(day) &&
                        (day.isToday || steps != null))
                      day.isToday
                          ? S.of(context).stepsProgressLine(steps, stepGoal)
                          : S.of(context).stepsWalkedLine(steps!, stepGoal),
                    if (day.isAfter(today))
                      isAr ? 'يوم قادم' : 'future day'
                    else if (!habit.isScheduledFor(day))
                      isAr ? 'غير مجدول' : 'not scheduled',
                    // container: true on the cell stops the corner mark
                    // announcing itself, so this is the only way a screen
                    // reader learns the day carries writing.
                    if (hasNote) S.of(context).gridNoteSemantics,
                  ].join(isAr ? '، ' : ', '),
                  // Only ever non-null for one cell in the whole table: row
                  // 0's real-today square (see _GridTableState._buildTable
                  // and _GridTable.todayCellKey's doc comment) — everywhere
                  // else this stays null, since a GlobalKey can only ever be
                  // attached to one live widget at a time.
                  key: day.isRealToday ? todayCellKey : null,
                  size: cell,
                  day: day,
                  // isRealToday, not isToday: purely which square gets the
                  // gold "today" ring — see DateTimeGameExt.isRealToday. The
                  // square that's actually *editable*/reward-eligible is
                  // decided independently inside _handleSquareTap/
                  // _handlePaletteTap (still day.isToday, unchanged) and by
                  // isFuture below, so this is cosmetic only.
                  isToday: day.isRealToday,
                  // A day after the reward day (`today` = effectiveDay) is
                  // future and stays locked — *except* the real calendar day
                  // itself during the flex window right after midnight
                  // (day.isRealToday true, today/effectiveDay still
                  // yesterday): that one is allowed to open and be colored in
                  // like any other non-reward day (flat XP only, same as
                  // backfilling any past square — see WeeklyGridNotifier.
                  // setSquare's anti-backdating doc comment), instead of
                  // sitting dimmed and untappable for 6 hours for no reason.
                  // A day beyond that (tomorrow-of-tomorrow, etc.) still
                  // isn't isRealToday either, so it stays correctly locked.
                  isFuture: day.startOfDay.isAfter(today) && !day.isRealToday,
                  isScheduled: habit.isScheduledFor(day),
                  isAlive: habit.isAliveOn(day),
                  isCovered: covered,
                  square: _effectiveSquare(habit, day, doneToday),
                  // Only today, and only for a habit that is actually counted:
                  // `completions` holds today's count and nothing else, so
                  // handing it to any other day's square would draw today's
                  // progress onto Tuesday. Yesterday while it is still open
                  // is the one other day with a count of its own (_dayCount).
                  dayCount: liveCount == null
                      ? null
                      : (done: liveCount, target: habit.effectiveDailyTarget),
                  stepFraction: stepFraction,
                  stepCount: stepCount,
                  hasNote: hasNote,
                  onTap: widget.selectionMode
                      ? null
                      : covered
                          ? () => _tapRestDay(ref, habit, day, days)
                          : () => _handleSquareTap(ref, habit, day),
                  onLongPress: widget.selectionMode
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          _openEditor(context, ref, habit, day);
                        },
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Today's square state for [habit], derived from its per-day count when
  /// it has one.
  ///
  /// A counted habit's square is a picture of `completions`, and it has to be
  /// that no matter which screen did the counting. Today and the notification
  /// actions only ever mirror a completion onto the Grid for a single-tap
  /// habit (completeHabit returns isGridSyncable, `frequencyTarget == 1`) —
  /// which was right when a square could not express "2 of 4" and is wrong
  /// now that it can. Without this, finishing a 4x habit from Today left its
  /// square sitting empty on the Grid with the day fully done.
  ///
  /// Deriving it here rather than widening that mirror keeps the change out
  /// of the reward system entirely: nothing about what a completion PAYS
  /// moves, only what the board draws.
  ///
  /// Yesterday's square too while it is still open: [done] is the square's
  /// own count from [_dayCount], today's or yesterday's, and zero on a day
  /// that has none, which leaves that day's stored square as it is.
  SquareState _effectiveSquare(
    IslamicHabitTemplate habit,
    DateTime day,
    int done,
  ) {
    final stored = widget.state.squareFor(habit.id, day);
    if (habit.effectiveDailyTarget <= 1 || done <= 0) {
      return stored;
    }
    // An explicit advanced mark (failed/bonus/skipped) is a deliberate
    // statement about the day and outranks the count, exactly as it does for
    // every other habit.
    if (stored == SquareState.failed ||
        stored == SquareState.bonus ||
        stored == SquareState.skipped) {
      return stored;
    }
    return done >= habit.effectiveDailyTarget
        ? SquareState.complete
        : SquareState.partial;
  }

  /// [habit]'s count on [day] as the board holds it: today's from
  /// `completions`, or yesterday's while it is still open from
  /// DashboardState.graceCompletions. Null for every other day, and for
  /// yesterday when its counts have not been read yet, so "not known" is
  /// never taken for "nothing done".
  ///
  /// Yesterday counts like today because Aziz asked for it (2026-09-24): a
  /// tap on yesterday's square of a habit done several times a day adds one,
  /// "if 5 times it will be 6 times, unless it's 6/6". The open check asks
  /// dayClockSourceProvider, as [_handleSquareTap] does, so a test can stand
  /// inside yesterday's open tail at any hour.
  int? _dayCount(
    DashboardState dash,
    IslamicHabitTemplate habit,
    DateTime day,
  ) {
    if (day.isToday) return dash.completions[habit.id] ?? 0;
    if (dash.graceDayKey != day.toDateKey() ||
        !day.isOpenDayAt(ref.read(dayClockSourceProvider)())) {
      return null;
    }
    return dash.graceCompletions[habit.id] ?? 0;
  }

  /// Handles a plain tap on a habit's square.
  ///
  /// Today's square reaching "complete" is special-cased to route through
  /// the exact same canonical reward path Today's own "Done" button uses
  /// (`DashboardNotifier.completeHabit`), instead of Grid's own flat
  /// per-square XP — one reward, ever, for a given habit-day, regardless of
  /// which screen it's completed from. This covers every habit, not just
  /// single-tap ones: it used to be gated to `frequencyTarget == 1`
  /// (mirroring `completeHabit`'s own Today→Grid mirror restriction), but
  /// that gate was copied into the wrong direction here. Today→Grid really
  /// does need it (a single square can't show "2 of 3 this week" yet — see
  /// `completeHabit`'s doc comment), but Grid→completions never had that
  /// problem: tapping today's square green is always a one-day fact ("I
  /// did this today"), exactly like one tap of Today's own button, so it
  /// should always register — the old gate just meant a multi-target
  /// habit's square could go fully green and pay out XP/gold on the Grid
  /// while `completions` (and therefore Night Review's "done today" count,
  /// Today's own checkbox, and everything else reading `isCompleted`)
  /// never heard about it. Everything else (other days, other colors)
  /// falls through to the original flat-rate tap-cycle, unchanged.
  Future<void> _handleSquareTap(
      WidgetRef ref, IslamicHabitTemplate habit, DateTime day) async {
    final perDay = habit.effectiveDailyTarget;
    // The state the person is actually looking at — see _effectiveSquare. A
    // counted habit finished from Today has a green square on screen, and a
    // tap on it has to mean "clear this", not "start counting".
    var current = _effectiveSquare(
      habit,
      day,
      _dayCount(ref.read(dashboardProvider), habit, day) ?? 0,
    );
    var next = current.next;
    // isOpenDay, not isToday: yesterday stays payable until the day cutoff
    // (see DateTimeGameExt.isOpenDay), so its square must reach the same
    // canonical reward path today's does. While this said isToday, a square
    // the app itself had labelled TODAY between midnight and the cutoff fell
    // into the anti-backdating branch instead — it turned green, paid
    // nothing, and Rooms counted it anyway.
    //
    // Asked of dayClockSourceProvider, which is DateTime.now in the app, so a
    // test can stand inside yesterday's open tail at any hour (see
    // grace_day_counted_square_test.dart). Against the real clock that branch
    // is only reachable by a suite run between midnight and kDayCutoffHour.
    final isSyncable = day.isOpenDayAt(ref.read(dayClockSourceProvider)());

    // ── A habit counted more than once a day ─────────────────────
    //
    // Today's square stops being a three-colour cycle and becomes a counter:
    // each tap adds one and fills the square that much further, and the
    // check only appears once the whole count is done
    // (design/Grid.dc.html). The colour cycle still owns every other square
    // — past days, and every habit that is once a day — so nothing that
    // existed before this feature changes behaviour here.
    //
    // Deliberately ahead of the two branches below: for a counted habit the
    // question "is the next colour green" is the wrong question, and letting
    // it be asked first is what would pay a full day's reward for one tap.
    //
    // Yesterday's square counts the same way while it is still open (Aziz,
    // 2026-09-24: "if 5 times it will be 6 times, unless it's 6/6"). It
    // counts from its own number (see _dayCount), never today's: a board
    // that has not read it yet reads it first, so no tap adds one to a
    // count nobody read.
    if (isSyncable && perDay > 1) {
      var done = _dayCount(ref.read(dashboardProvider), habit, day);
      if (done == null) {
        await ref.read(dashboardProvider.notifier).readGraceDay(day);
        if (!mounted) return;
        done = _dayCount(ref.read(dashboardProvider), habit, day) ?? 0;
        current = _effectiveSquare(habit, day, done);
        next = current.next;
      }
      if (done < perDay) {
        await _addOneToday(ref, habit, day, done: done, target: perDay);
        return;
      }
      // Already at the full count — falls through to the clear-confirm
      // branch below, which is the same "tap a finished square to empty it"
      // this habit had when it was once a day.
    }

    if (isSyncable && next == SquareState.complete) {
      await _completeSquareToday(ref, habit, day);
      return;
    }

    // isGreen, not `== complete`, and no test on the completions map.
    //
    // Both narrowings leaked. `== complete` let today's BLUE bonus square
    // through — isGreen is complete||bonus, and bonus.next is none, so a
    // single tap emptied a bonus square with no dialog at all, while the
    // identical square one day earlier got one. And ANDing on
    // `completions > 0` meant a green square whose completion is not in
    // memory (a swallowed daily-doc read, a failed load, a legacy pre-sync
    // square) also cleared silently. Reading the SQUARE is the right test:
    // it is what the person can see, and it is what they are acting on.
    // uncompleteHabit's own `current <= 0` early return already handles the
    // case where there is no completion to reverse.
    if (isSyncable && current.isGreen) {
      // The tapped day's own count, today's or yesterday's (_dayCount).
      // Today's map alone made yesterday's dialog promise no refund while
      // the clear below took yesterday's reward back.
      final backedByCompletion =
          (_dayCount(ref.read(dashboardProvider), habit, day) ?? 0) > 0;
      // Today's completed, synced squares should still behave like every
      // other editable square: tapping green cycles it back to empty, and
      // long-press still opens the explicit palette. Because this green
      // state was normally rewarded through DashboardNotifier.completeHabit,
      // undo that canonical completion first so Today un-checks the task and
      // XP/gold/green counters are refunded before the visual square is
      // cleared. [backedByCompletion] is what says whether there IS such a
      // completion: a bonus square never has one, and a green square can
      // outlive its record. It decides only what the dialog PROMISES —
      // naming an XP refund that is not coming would be a lie — and the
      // clear itself runs either way.
      //
      // The one confirmation on this whole board, and it is on the one tap
      // that takes something away: every other square tap only ever adds.
      // What a clear costs is recoverable now (the undo leaves a receipt and
      // marking the day again redeems it, on any day — see UndoneCompletion),
      // but recoverable is not free. A mis-tap on the busiest control in the
      // app should not quietly move someone's XP, gold and streak and then
      // depend on them noticing.
      //
      // Mirrors the completion's boost — see roomBoostedReward. Read once and
      // passed to both the dialog and the undo, so the number a person is
      // shown is the exact number that moves.
      final xpReward = roomBoostedReward(ref, habit.id, habit.xpReward);
      final goldReward = roomBoostedReward(ref, habit.id, habit.goldReward);
      final confirmed = await _confirmClearMark(
        context,
        habitName: habit.localName(S.of(context).isAr),
        xp: xpReward,
        gold: goldReward,
        noReward: !backedByCompletion,
      );
      if (!confirmed || !context.mounted) return;
      HapticFeedback.selectionClick();
      // Read BEFORE the clear, because the clear is what erases it. A counted
      // habit's day is N taps, and clearWholeDay below refunds all of them at
      // once, so Undo has to put all of them back — see _restoreClearedDay.
      // Without this the Undo called completeHabit exactly once and silently
      // left a 4/4 day sitting at 1/4.
      final clearedCount =
          _dayCount(ref.read(dashboardProvider), habit, day) ?? 0;
      await ref.read(dashboardProvider.notifier).uncompleteHabit(
            day: day,
            habitId: habit.id,
            xpReward: xpReward,
            goldReward: goldReward,
            // Same per-day count the completion was priced against, so
            // the refund matches the debit — see uncompleteHabit.
            frequencyTarget: habit.effectiveDailyTarget,
            // Tapping a full square empties it, which for a counted habit
            // means the whole day and not just its last tap.
            clearWholeDay: true,
            category: habit.category.name,
          );
      ref
          .read(weeklyGridProvider.notifier)
          .setSquareStateOnly(habit.id, day, next, source: kSquareSourceTap);
      syncRoomToday(ref, habit.id, day);
      if (!context.mounted) return;
      // Second net behind the dialog, and the cheaper one to reach for: the
      // same canonical completion the square's own tap would run, which also
      // redeems the receipt the undo just wrote, so nothing is left behind.
      final s = S.of(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(s.gridMarkCleared),
          // Never pin the bar open. See AppSnackBar.
          persist: false,
          action: SnackBarAction(
            label: s.undo,
            onPressed: () =>
                _restoreClearedDay(ref, habit, day, clearedCount),
          ),
        ));
      return;
    }

    // ── Clearing a finished day asks first, on every day ─────────
    //
    // Today's clear already asked, in the branch above, and named the XP and
    // gold it was about to take back. A past day never asked at all: one
    // stray tap on a green square erased a completed day outright, and
    // because past days sit outside the reward system there was no refund, no
    // snackbar and nothing on screen to notice it had happened.
    //
    // That gap was survivable while a tap had to travel white → yellow →
    // green → white to reach a clear. Now that one tap means done, green is
    // one tap from empty, and the single most destructive thing a square can
    // do is also the easiest to do by accident.
    //
    // Only for marks that say the day was DONE. A red or grey square is a
    // note about the day rather than a record of finishing it, and asking
    // before clearing one would be a confirmation on an ordinary edit.
    if (!isSyncable && current.isGreen) {
      final confirmed = await _confirmClearMark(
        context,
        habitName: habit.localName(S.of(context).isAr),
        xp: 0,
        gold: 0,
        // westernDate: the raw pattern drew «الجمعة ١٨ سبتمبر» in this
        // dialog, Arabic-Indic digits in an app that prints Latin ones.
        pastDayLabel: westernDate(
          day,
          'EEEE d MMMM',
          S.of(context).isAr ? 'ar' : 'en',
        ),
      );
      if (!confirmed || !context.mounted) return;
    }

    // A square turning green is the app's core reward moment — it gets a
    // heavier thump than the intermediate colors.
    if (next.isGreen) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    // Read BEFORE the tap, because the tap is what spends it: a green square
    // landing on a past day this habit really was completed on redeems the
    // receipt that undo left behind (see WeeklyGridNotifier.setSquare's
    // past-day branch), and that is worth saying out loud. Silently paying
    // for one past square and not another would read as a bug.
    final restoring = !isSyncable &&
        next.isGreen &&
        ref.read(dashboardProvider).undoneFor(habit.id, day.toDateKey()) !=
            null;
    ref.read(weeklyGridProvider.notifier).cycleSquare(habit.id, day);
    syncRoomToday(ref, habit.id, day);
    if (next.isGreen) _maybeCelebrateFullRow(ref, habit);
    if (restoring && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(S.of(context).gridMarkRestored),
        ));
    }
  }

  /// Today's square reaching green, through the one canonical reward path.
  /// Yesterday's too while it is still open (see DateTimeGameExt.isOpenDay).
  ///
  /// Lifted out of [_handleSquareTap] verbatim so the Undo on the
  /// mark-cleared snackbar can put the square back exactly the way tapping it
  /// would, instead of being a second, slightly different copy of the same
  /// twenty lines.
  Future<void> _completeSquareToday(
      WidgetRef ref, IslamicHabitTemplate habit, DateTime day) async {
    // Only meaningful for today: `completions` is today's map, so on a grace
    // day this shortcut would answer about the wrong day. completeHabit's own
    // `current >= frequencyTarget` guard covers that case safely instead.
    final alreadyDoneToday = day.isToday &&
        ref
            .read(dashboardProvider)
            .isCompleted(habit.id, habit.effectiveDailyTarget);
    HapticFeedback.mediumImpact();
    // A habit counted more than once a day, on yesterday's open tail. Its
    // square's own tap counts it one at a time now, like today's
    // (_addOneToday), so nothing sends such a day here; this stays so that
    // nothing can. Green here would mean the whole day, the palette's مكتمل
    // loop. The single call below cannot do it: it records ONE slot and
    // answers isGridSyncable, `frequencyTarget == 1`, false for every call
    // of a counted habit, and that was read as a refusal: one slot paid,
    // S.squareNotReadyYet, the square left empty and the room never told
    // (2026-09-24, see grace_day_counted_square_test.dart).
    if (!day.isToday && habit.effectiveDailyTarget > 1) {
      final landed = await _completeOpenDay(
        ref,
        context,
        habit: habit,
        day: day,
        source: kSquareSourceTap,
      );
      if (landed && mounted) _maybeCelebrateFullRow(ref, habit);
      return;
    }
    if (alreadyDoneToday) {
      // Already rewarded (e.g. completed from Today and the mirror
      // hasn't caught up) — just repair the visual state, no reward call.
      ref.read(weeklyGridProvider.notifier).markCompleteFromHabit(habit.id, day, source: kSquareSourceTap);
      syncRoomToday(ref, habit.id, day);
    } else {
      // Canonical reward first, then mirror the square. No need to
      // branch on completeHabit's return value here — the
      // alreadyDoneToday check above already guarantees completions is
      // under target, so this call can't be a same-day no-op.
      // completeHabit's return value only ever signals
      // `frequencyTarget == 1`, a flag its *other* callers (Today,
      // notification actions) use to decide whether *their* completion
      // should paint the Grid square — not relevant here, since the
      // user just painted this square themselves.
      final dashState = ref.read(dashboardProvider);
      final todayHabits = _streakRosterFor(ref, habit, day);
      // BRANCHED, and the branch is the point.
      //
      // completeHabit returns false when the account's own numbers have not
      // loaded yet, or when that load failed (see its two guards). It
      // refuses rather than computing a streak and an XP total from zeros
      // and writing them back as absolute values, which is right. What was
      // wrong is that this caller painted the square anyway: open the app
      // offline on a new day, or tap in the first second after a cold
      // start, and the square went green, the room strip updated, the
      // celebration fired, and nothing was recorded. The green square then
      // persisted, so it never looked wrong afterwards.
      //
      // This is the primary interaction on the home screen, so the one
      // outcome it must never have is silently doing nothing.
      final streakRunsOn = await _streakRunsOnFor(ref, habit, day);
      final rewarded =
          await ref.read(dashboardProvider.notifier).completeHabit(
                day: day,
                habitId: habit.id,
                scheduledWeekdays: habit.scheduledWeekdays.toSet(),
                runsOn: streakRunsOn,
                // 2x while a linked room is live — see roomBoostedReward.
                xpReward: roomBoostedReward(ref, habit.id, habit.xpReward),
                goldReward:
                    roomBoostedReward(ref, habit.id, habit.goldReward),
                frequencyTarget: habit.effectiveDailyTarget,
                // Today's answer comes from `completions`; a grace day's has
                // to come from that day's own squares, because `completions`
                // only ever holds today's counts. See
                // willCompleteAllSquaresOn.
                allHabitsDoneAfter: day.isToday
                    ? willCompleteAllHabitsToday(
                        state: dashState,
                        todayHabits: todayHabits,
                        habitId: habit.id,
                        frequencyTarget: habit.effectiveDailyTarget,
                        // A جزئي square counts half toward the threshold, so
                        // a day that is nearly full still keeps its streak.
                        halfDoneHabitIds:
                            ref.read(weeklyGridProvider).halfDoneTodayIds(),
                        skippedHabitIds:
                            ref.read(weeklyGridProvider).skippedTodayIds(),
                      )
                    : willCompleteAllSquaresOn(ref, habit, day),
                // Scales the daily earn ceiling with the roster, see
                // dailyXpCapFor. Same list the predicate above uses.
                scheduledHabitCount: todayHabits.length,
                category: habit.category.name,
                habitName: habit.localName(S.of(context).isAr),
              );
      if (!context.mounted) return;
      if (!rewarded) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(S.of(context).squareNotReadyYet),
          ));
        return;
      }
      ref
          .read(weeklyGridProvider.notifier)
          .markCompleteFromHabit(habit.id, day, source: kSquareSourceTap);
      syncRoomToday(ref, habit.id, day);
      _maybeCelebrateFullRow(ref, habit);
    }
  }

  /// Puts back a day that the clear-confirm just emptied, exactly as it stood.
  ///
  /// Undo has to be the inverse of what it is undoing, and what it undoes is
  /// `uncompleteHabit(clearWholeDay: true)` — which refunds ALL of a counted
  /// habit's taps in one call. Replaying a single completion therefore left a
  /// 4/4 day at 1/4: three quarters of the day quietly gone, after the person
  /// had just been told the clear was reversible. [count] is read before the
  /// clear, because the clear is what destroys it.
  ///
  /// The first re-tap redeems the UndoneCompletion receipt the clear wrote (see
  /// completeHabit); the rest are ordinary taps of the same day, so the day is
  /// paid exactly what it was paid before, no more.
  Future<void> _restoreClearedDay(
    WidgetRef ref,
    IslamicHabitTemplate habit,
    DateTime day,
    int count,
  ) async {
    // [count] is the cleared day's own count, yesterday's too while it is
    // open (see _dayCount), so yesterday replays tap by tap like today.
    if (count <= 1) {
      // The ordinary once-a-day case, and the one this always handled: a
      // single completion, restored through the same path a square tap uses.
      await _completeSquareToday(ref, habit, day);
      return;
    }
    final target = habit.effectiveDailyTarget;
    final xpReward = roomBoostedReward(ref, habit.id, habit.xpReward);
    final goldReward = roomBoostedReward(ref, habit.id, habit.goldReward);
    final todayHabits = _streakRosterFor(ref, habit, day);
    final streakRunsOn = await _streakRunsOnFor(ref, habit, day);
    HapticFeedback.mediumImpact();
    for (var i = 0; i < count; i++) {
      final before = _dayCount(ref.read(dashboardProvider), habit, day) ?? 0;
      if (before >= target) break;
      // Read each round, not once before the loop: the predicate adds ONE to
      // this habit's count, so a snapshot judged every replayed tap as the
      // first and a restored 4-of-4 day could never cross the threshold.
      final dashState = ref.read(dashboardProvider);
      await ref.read(dashboardProvider.notifier).completeHabit(
            day: day,
            habitId: habit.id,
            scheduledWeekdays: habit.scheduledWeekdays.toSet(),
            runsOn: streakRunsOn,
            xpReward: xpReward,
            goldReward: goldReward,
            frequencyTarget: target,
            // See willCompleteAllSquaresOn: `completions` is today's map,
            // so any other open day has to be answered from its squares,
            // with this habit as the square the replayed tap leaves.
            allHabitsDoneAfter: day.isToday
                ? willCompleteAllHabitsToday(
                    state: dashState,
                    todayHabits: todayHabits,
                    habitId: habit.id,
                    frequencyTarget: target,
                    halfDoneHabitIds:
                        ref.read(weeklyGridProvider).halfDoneTodayIds(),
                    skippedHabitIds:
                        ref.read(weeklyGridProvider).skippedTodayIds(),
                  )
                : before + 1 >= target
                    ? willCompleteAllSquaresOn(ref, habit, day)
                    : willCrossStreakThresholdOnPartial(ref, habit, day),
            // Scales the daily earn ceiling with the roster, see
            // dailyXpCapFor. Same list the predicate above uses.
            scheduledHabitCount: todayHabits.length,
            category: habit.category.name,
            habitName: habit.localName(S.of(context).isAr),
          );
      // Measured, not assumed: completeHabit refuses while the account's own
      // numbers are still loading or after a failed load, and its return value
      // cannot say so (it reports isGridSyncable). A refusal must stop the
      // replay rather than spin the loop to its count.
      final after = _dayCount(ref.read(dashboardProvider), habit, day) ?? 0;
      if (after <= before) break;
    }
    if (!context.mounted) return;
    final restored = _dayCount(ref.read(dashboardProvider), habit, day) ?? 0;
    if (restored <= 0) return;
    ref.read(weeklyGridProvider.notifier).markResultFromHabit(
          habit.id,
          day,
          restored >= target ? SquareState.complete : SquareState.partial,
          source: kSquareSourceTapUndo,
        );
    syncRoomToday(ref, habit.id, day);
    if (restored >= target) _maybeCelebrateFullRow(ref, habit);
  }

  /// One tap on the square of a habit counted more than once a day.
  ///
  /// Adds exactly one to the day's count, today's or yesterday's while it is
  /// still open (see _dayCount), through the same canonical reward
  /// path every other completion uses, so the day's XP, gold, streak and
  /// room sync all stay in one place. [DashboardNotifier.completeHabit]
  /// prices this tap as its share of the day rather than a whole day (see
  /// XpCalculator.rewardSliceForTap), which is what stops "4 times a day"
  /// from being four days' reward for the same habit.
  ///
  /// The square then mirrors the new count: partial while there is still
  /// something owed, complete on the tap that finishes it. Only that last
  /// tap celebrates, because only that one finished anything.
  Future<void> _addOneToday(
    WidgetRef ref,
    IslamicHabitTemplate habit,
    DateTime day, {
    required int done,
    required int target,
  }) async {
    final finishes = done + 1 >= target;
    // The finishing tap is the reward moment and gets the heavier thump;
    // the ones before it are progress, and should not feel like arrival.
    if (finishes) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }

    final dashState = ref.read(dashboardProvider);
    final todayHabits = _streakRosterFor(ref, habit, day);
    // Read the count BEFORE, because that is the only honest way to tell
    // whether this tap landed. completeHabit's return value cannot answer it
    // for a counted habit: it returns isGridSyncable, `frequencyTarget == 1`,
    // which is false for EVERY tap of a counted habit including the ones that
    // work perfectly. Treating that false as a refusal is exactly what this
    // method used to do, and it cost more than a wrong snackbar — it returned
    // before painting the square, so a counted habit's stored SquareState
    // stayed `none` all day. The count and the fill still rendered (both read
    // `completions` directly), which is why it looked fine while the room
    // sync, the day percentage and the heatmap — all of which read the STORED
    // square — never heard that anything had happened.
    final before = _dayCount(ref.read(dashboardProvider), habit, day) ?? 0;
    final streakRunsOn = await _streakRunsOnFor(ref, habit, day);
    await ref.read(dashboardProvider.notifier).completeHabit(
          day: day,
          habitId: habit.id,
          scheduledWeekdays: habit.scheduledWeekdays.toSet(),
          runsOn: streakRunsOn,
          xpReward: roomBoostedReward(ref, habit.id, habit.xpReward),
          goldReward: roomBoostedReward(ref, habit.id, habit.goldReward),
          frequencyTarget: target,
          // See willCompleteAllSquaresOn. On yesterday the square this tap
          // leaves is green only if it finishes the count, and جزئي before
          // that, so the day is judged with that square, not a green one.
          allHabitsDoneAfter: day.isToday
              ? willCompleteAllHabitsToday(
                  state: dashState,
                  todayHabits: todayHabits,
                  habitId: habit.id,
                  frequencyTarget: target,
                  halfDoneHabitIds:
                      ref.read(weeklyGridProvider).halfDoneTodayIds(),
                  skippedHabitIds:
                      ref.read(weeklyGridProvider).skippedTodayIds(),
                )
              : finishes
                  ? willCompleteAllSquaresOn(ref, habit, day)
                  : willCrossStreakThresholdOnPartial(ref, habit, day),
          // Scales the daily earn ceiling with the roster, see
          // dailyXpCapFor. Same list the predicate above uses.
          scheduledHabitCount: todayHabits.length,
          category: habit.category.name,
          habitName: habit.localName(S.of(context).isAr),
        );
    if (!context.mounted) return;
    // Same rule as _completeSquareToday, and the same reason: a refused
    // completion must not leave a square claiming something was recorded.
    // Measured off the count itself rather than a return flag, so it detects
    // the real refusals (a load still in flight, a failed load) and nothing
    // else.
    final after = _dayCount(ref.read(dashboardProvider), habit, day) ?? 0;
    if (after <= before) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(S.of(context).squareNotReadyYet),
        ));
      return;
    }
    // Painted from the count that landed, not the one the tap started from:
    // yesterday's may have moved on another device since this board read it,
    // and completeHabit counted from the stored day.
    ref.read(weeklyGridProvider.notifier).markResultFromHabit(
          habit.id,
          day,
          after >= target ? SquareState.complete : SquareState.partial,
          source: kSquareSourceTap,
        );
    syncRoomToday(ref, habit.id, day);
    if (finishes) _maybeCelebrateFullRow(ref, habit);
  }

  /// A tap on a covered square (the «–» of a day the habit asks nothing
  /// of). Aziz, 2026-09-24: "just make any – days clickable, but with a pop
  /// up that it's rest and how it will be handled". The pop-up says why the
  /// day is a rest day and what recording it would do (see restDayTapFor);
  /// only «سويتها» records, and then through the square's own tap, so an
  /// open day pays and a closed one records without points exactly as any
  /// other square does.
  Future<void> _tapRestDay(
    WidgetRef ref,
    IslamicHabitTemplate habit,
    DateTime day,
    List<DateTime> days,
  ) async {
    final index = days.indexOf(day);
    if (index < 0) return _handleSquareTap(ref, habit, day);
    final state = widget.state;
    final tap = restDayTapFor(
      habit: habit,
      days: days,
      index: index,
      isGreenAt: (i) => state.squareFor(habit.id, days[i]).isGreen,
      isUnmarkedAt: (i) =>
          state.squareFor(habit.id, days[i]) == SquareState.none,
    );
    final confirmed = await _confirmRestDay(
      context,
      habitName: habit.localName(S.of(context).isAr),
      day: day,
      tap: tap,
    );
    if (!confirmed || !mounted) return;
    await _handleSquareTap(ref, habit, day);
  }

  /// The pop-up [_tapRestDay] shows: why the day asks nothing, what recording
  /// it would do, and whether it earns. Answers whether «سويتها» was tapped.
  Future<bool> _confirmRestDay(
    BuildContext context, {
    required String habitName,
    required DateTime day,
    required RestDayTap tap,
  }) async {
    final gp = context.gp;
    final s = S.of(context);
    // «اليوم» and «أمس» where they apply, the weekday otherwise; lower case
    // when English puts one mid-sentence.
    String dayName(DateTime d, {bool midSentence = false}) {
      final relative = d.isToday || d.isYesterday;
      final word = d.isToday
          ? s.progressToday
          : d.isYesterday
              ? s.progressYesterday
              : westernDate(d, 'EEEE', s.isAr ? 'ar' : 'en');
      return midSentence && relative && !s.isAr ? word.toLowerCase() : word;
    }

    final why = switch (tap.reason) {
      RestDayReason.offPlan => s.restDayOffPlan(dayName(day), habitName),
      RestDayReason.coveredBySession =>
        s.restDayCoveredBySession(dayName(day)),
      RestDayReason.quotaMet =>
        s.restDayQuotaMet(tap.weekAfter! - 1, tap.weekTarget!),
      RestDayReason.notNeeded => s.restDayNotNeeded,
    };
    final after = tap.weekAfter;
    final target = tap.weekTarget;
    final what = after != null && target != null
        ? after > target
            ? s.restDayExtra
            : s.restDayQuotaCounts(after, target)
        : tap.covers != null
            ? s.restDayCovers(dayName(tap.covers!, midSentence: true))
            : s.restDayExtra;
    HapticFeedback.selectionClick();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: gp.surfaceHigh,
        title: Text(
          s.restDayTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              why,
              style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.45),
            ),
            const SizedBox(height: 8),
            Text(
              what,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: gp.textPrimary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tap.pays ? s.restDayWithPoints : s.restDayNoPoints,
              style: TextStyle(fontSize: 12.5, color: gp.textSec, height: 1.45),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              s.habitActionsCancel,
              style: TextStyle(fontSize: 13, color: gp.textSec),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              s.restDayConfirm,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: gp.goldInk,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Asks before clearing a mark that carries a real completion.
  ///
  /// Names the habit and says the two numbers out loud, because "are you
  /// sure" on its own tells nobody anything. Says the mark can be put back
  /// too: that is true on any day now (see [UndoneCompletion]), and someone
  /// who knows it is reversible answers this dialog faster, not slower.
  ///
  /// Shaped after confirmDeleteForever in habit_actions_sheet.dart, so the
  /// app has one look for "this one takes something away".
  /// [pastDayLabel] switches this to the past-day wording. A past day is
  /// outside the reward system, so naming an XP refund there would be a lie;
  /// what it promises instead is the thing that IS true, that re-marking the
  /// same day restores it at its original time.
  Future<bool> _confirmClearMark(
    BuildContext context, {
    required String habitName,
    required int xp,
    required int gold,
    String? pastDayLabel,
    bool noReward = false,
  }) async {
    final gp = context.gp;
    final s = S.of(context);
    HapticFeedback.mediumImpact();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: gp.surfaceHigh,
        title: Text(
          pastDayLabel == null
              ? s.gridClearMarkTitle
              : s.gridClearPastMarkTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
        content: Text(
          pastDayLabel != null
              ? s.gridClearPastMarkBody(habitName, pastDayLabel)
              : noReward
                  ? s.gridClearMarkBodyNoReward(habitName)
                  : s.gridClearMarkBody(habitName, xp, gold),
          style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              s.habitActionsCancel,
              style: TextStyle(fontSize: 13, color: gp.textSec),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              s.gridClearMarkConfirm,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.gp.errorInk,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Fires the "full row" moment: the green that just landed completed
  /// every scheduled day of this habit's visible week. Visual + haptic
  /// celebration ONLY, deliberately no XP/gold — a full row can also be
  /// assembled by backfilling past squares, and the anti-backdating rule
  /// (see WeeklyGridNotifier.setSquare) means past days must never reach
  /// the reward system; a rewarded row would reopen exactly that farm.
  /// Toggling a square off and back on can replay it — that's a deliberate
  /// pair of taps, not a loop, and it still grants nothing.
  void _maybeCelebrateFullRow(WidgetRef ref, IslamicHabitTemplate habit) {
    if (!mounted) return;
    final grid = ref.read(weeklyGridProvider);
    // A week kept with a session on another day of it is kept: the day that
    // session stands in for asks for nothing, and the session counts on its
    // own day (see moved_day_plan.dart).
    final moved = movedDemandForRow(
      habit: habit,
      days: grid.days,
      isGreenAt: (i) => grid.squareFor(habit.id, grid.days[i]).isGreen,
      isUnmarkedAt: (i) =>
          grid.squareFor(habit.id, grid.days[i]) == SquareState.none,
    );
    if (!isHabitRowComplete(
      days: grid.days,
      isScheduled: moved == null
          ? habit.isScheduledFor
          : (d) => !(moved[grid.days.indexOf(d)]?.isRest ?? true),
      squareFor: (d) => grid.squareFor(habit.id, d),
    )) {
      return;
    }
    HapticFeedback.heavyImpact();
    final s = S.of(context);
    ScaffoldMessenger.of(context).showOne(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.grid_view_rounded,
                color: context.gp.emeraldInk, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                s.gridFullRow(habit.localName(s.isAr)),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: context.gp.emeraldInk,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: context.gp.surface,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          side: BorderSide(color: GameColors.emerald, width: 1),
        ),
      ),
    );
  }

  void _openEditor(BuildContext context, WidgetRef ref,
      IslamicHabitTemplate habit, DateTime day) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Keeps the sheet's top clear of the status bar and notch, the same
      // setting _editSelected above uses. The bottom inset is the sheet's
      // own job: the card's outer margin adds MediaQuery padding.bottom, so
      // nothing near the bottom edge sits under the home-indicator bar.
      useSafeArea: true,
      builder: (_) => _CellEditorSheet(habit: habit, day: day),
    );
  }

}

/// [gridStreakRoster] read off this screen's providers: what a mark on [day]
/// judges today's streak point against, the same board the summary card
/// counts from.
Iterable<({String id, int frequencyTarget})> _streakRosterFor(
  WidgetRef ref,
  IslamicHabitTemplate habit,
  DateTime day,
) =>
    gridStreakRoster(
      habits: ref.read(habitListProvider),
      grid: ref.read(weeklyGridProvider),
      markingId: habit.id,
      day: day,
    );

// ─── Boost badge ────────────────────────────────────────────────────────────

/// The "2x" flag that hovers above a habit's icon while a linked room is
/// live — a small piece of fire, literally: the flame repeats a gentle
/// scale pulse for as long as the boost lasts, the same motion
/// _StreakAtRiskBanner's own flame uses, so "flame = something's hot right
/// now" reads the same everywhere it shows up in the app. Fixed content
/// (a flame glyph + the literal string "2x") means this badge is always the
/// exact same size, so it never nudges the row layout around it — see the
/// doc comment where it's placed in _GridTableState.
class _BoostBadge extends StatelessWidget {
  const _BoostBadge();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: GameColors.gold,
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        border: Border.all(color: gp.surface, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: GameColors.gold.withOpacity(0.45),
            blurRadius: 5,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded,
                  size: 9, color: Colors.black)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(
                begin: 0.8,
                end: 1.2,
                duration: 650.ms,
                curve: Curves.easeInOut,
              ),
          const SizedBox(width: 1.5),
          const Text(
            '2x',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// The square's own corner radius minus its border width — the radius of the
/// space INSIDE the border, which is what a fill has to be clipped to if its
/// top edge is to look flat rather than nibbled at both ends. Clipping at the
/// full 9 let the risen block's corners ride 0.8pt into the border.
const double _squareInnerRadius = 9 - 0.8;

/// The risen portion of a square that is only part done: a block anchored to
/// the bottom, clipped to [radius] so its top edge is a genuinely flat line,
/// with an optional 1pt rule drawn along that edge.
///
/// One helper for both cases on purpose. A counted habit at 2 of 4 and a
/// square somebody marked جزئي by hand are the same statement at two
/// precisions, and they should be the same picture — before this, one was a
/// self-rounded lozenge and the other was a centred clock face.
///
/// The rule is a `Border(top:)` on a decoration with NO borderRadius of its
/// own (the ClipRRect owns the rounding). That is deliberate: a non-uniform
/// border under a borderRadius asserts inside Border.paint.
Widget _levelFill({
  required double factor,
  required Color fill,
  required double radius,
  Color? line,
}) =>
    Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Align(
          // bottomCenter, never AlignmentDirectional — gravity has no locale,
          // and this has to sit at the bottom in Arabic too.
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: factor.clamp(0.0, 1.0),
            widthFactor: 1,
            child: AnimatedContainer(
              duration: GameMotion.standard,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: fill,
                border: line == null
                    ? null
                    : Border(top: BorderSide(color: line, width: 1)),
              ),
            ),
          ),
        ),
      ),
    );

/// The green square's one-shot celebration, which stops existing once it
/// has run.
///
/// The shimmer itself is unchanged; what changed is that it used to be
/// permanent. flutter_animate leaves its ShaderMask in the tree after the
/// animation ends, and a ShaderMask is a saveLayer plus a gradient shader
/// every time the square paints — so a well-filled board carried up to 84
/// of them, forever, for a 450ms effect that had long since finished. They
/// cost real raster time on a phone, which is what made a full board feel
/// heavier to scroll than an empty one. Dropping the wrapper on completion
/// leaves exactly the same pixels behind: the effect ends at full opacity,
/// so the last shimmer frame and the bare square are identical.
class _CelebrationShimmer extends StatefulWidget {
  const _CelebrationShimmer({required this.square, required this.child});

  final SquareState square;
  final Widget child;

  @override
  State<_CelebrationShimmer> createState() => _CelebrationShimmerState();
}

class _CelebrationShimmerState extends State<_CelebrationShimmer> {
  /// The square value the current celebration belongs to. Held rather than a
  /// bare bool so a cell whose state lands on a NEW green (tapped, or the
  /// week scrolled onto different data under the same element) celebrates
  /// again, while one merely rebuilt for an unrelated reason does not.
  SquareState? _celebratingFor;

  @override
  void initState() {
    super.initState();
    _celebratingFor = widget.square;
  }

  @override
  void didUpdateWidget(covariant _CelebrationShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.square != oldWidget.square) _celebratingFor = widget.square;
  }

  @override
  Widget build(BuildContext context) {
    if (_celebratingFor != widget.square) return widget.child;
    return widget.child
        .animate(
          key: ValueKey(widget.square),
          onComplete: (_) {
            // Post-frame: onComplete fires during the animation's own build,
            // and setState is not allowed to reenter that.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _celebratingFor = null);
            });
          },
        )
        .shimmer(
          delay: 80.ms,
          duration: 450.ms,
          color: Colors.white.withOpacity(0.55),
          // ShimmerEffect is NOT layout-neutral by default: it wraps the
          // square in Padding(EdgeInsets.all(0.5)) — a full extra logical
          // pixel of width/height per green square, for as long as the
          // effect widget is in the tree. Measured live: every green
          // square rendered 1pt wider than its empty neighbours, so a row
          // accumulated +1pt of drift per green square and weekday columns
          // visibly bent at exactly the well-filled rows — the more of the
          // week done, the more broken the board looked. `padding: 0`
          // opts out (the 0.5 default only softens a ShaderMask
          // antialiasing artifact at the very edge, invisible on these
          // rounded squares). Locked by the marked-squares case in
          // grid_square_alignment_test.dart.
          padding: 0,
        );
  }
}

/// [streakRunsOn] with the Grid's own storage and the dashboard's record of
/// the habit's last completion; see there.
Future<bool Function(DateTime day)> _streakRunsOnFor(
  WidgetRef ref,
  IslamicHabitTemplate habit,
  DateTime day,
) =>
    streakRunsOn(
      habit: habit,
      day: day,
      lastCompletedKey:
          ref.read(dashboardProvider).habitLastCompletedDate[habit.id],
      squaresOn: ref.read(weeklyGridProvider.notifier).storedSquaresFor,
    );

class _SquareCell extends StatelessWidget {
  final double size;
  final DateTime day;
  final bool isToday;
  final bool isFuture;
  // False when this habit's scheduledWeekdays is non-empty and doesn't
  // include this cell's weekday (see HabitModel/IslamicHabitTemplate — empty
  // means every day). Decides the gold ring only: whether the square can be
  // marked is [isAlive]'s job.
  final bool isScheduled;

  /// Whether the habit existed on this day. Until 2026-09-24 a day off a
  /// specific-days schedule was as inert as a future one, so a shower taken
  /// on Wednesday for a Monday, Thursday and Saturday habit could not be
  /// recorded at all, and the week then charged Thursday for it. Now any day
  /// the habit existed on can hold a session: it counts for the week and
  /// stands in for one of the habit's own days (see moved_day_plan.dart).
  /// Only a day before the habit was made or after it was archived stays
  /// inert, alongside the future.
  final bool isAlive;

  // An empty day a flexible weekly quota owed used to be painted here in the
  // `failed` red, computed from weeklyQuotaDemand and never stored. It is
  // gone (Aziz, 2026-09-09), and the argument for removing it is the one that
  // should have stopped it being added.
  //
  // It made the same day mean two different things depending on the cadence.
  // A daily habit nobody logged is empty, and the app says nothing about it;
  // the identical empty square on a 3x-a-week habit was called a failure.
  // Same person, same missing session, two verdicts. It also arrived at
  // midnight, before the flex window that still lets somebody mark yesterday
  // (see setSquare's grace), so a person who trains at 23:00 for the day just
  // gone met a red square that was already wrong when it was drawn.
  //
  // The week stays just as legible without it, because the distinction that
  // carries the meaning is still drawn: a day the habit asked nothing of is
  // soft emerald (isCovered), and a day it asked for and did not get is a
  // plain empty square — exactly what a daily habit's missed day looks like.
  // Only the person marks a day فشل now, on every cadence.

  /// An empty square on a day the habit asked nothing of (see
  /// [isCoveredDay]). Painted soft green, at full opacity even when the day
  /// is unscheduled and therefore inert: the dimming that used to apply to
  /// every off-day is what made a Monday-Wednesday-Friday habit look like
  /// four misses a week. A covered square stays tappable, off-day or quota
  /// day alike: a fifth session on a four-a-week habit is not an error, and a
  /// session on a specific-days habit's off-day keeps the week's promise
  /// (see [isAlive]).
  final bool isCovered;

  final SquareState square;

  /// Today's progress for a habit counted more than once a day, or null for
  /// every other square — which is every square this app had before counting
  /// existed, so they all keep rendering exactly as they did.
  ///
  /// When set, the square stops being one flat colour and fills in
  /// proportion to [done] over [target] (design/Grid.dc.html), with the
  /// running number in the middle so "how many left" is readable without
  /// counting pixels. The check still belongs to the finished state alone.
  final ({int done, int target})? dayCount;

  /// Today's steps as a fraction of a linked walking habit's goal, or null
  /// for every other square — which is every square that existed before the
  /// steps link, so they all keep rendering exactly as they did.
  ///
  /// Drawn as the same rising portion a counted habit draws, and for the same
  /// reason: the walk really is part done, and a flat empty square said it
  /// was not. No number inside it, unlike [dayCount] — "5,320" does not fit a
  /// grid cell at any legible size, and the proportion is the whole answer
  /// anyway. The exact figure is in the square's screen-reader label and in
  /// the habit's actions sheet.
  final double? stepFraction;

  /// A linked walking habit's step count for this day, or null for every
  /// other square. Written out by StepCountLabel ("2730", "12k").
  ///
  /// Drawn in the middle in place of the square's glyph: the colour still
  /// says what the walk earned, the number says how much it was. The fill
  /// under it keeps its colour and loses its 1pt waterline, which would
  /// otherwise run straight through the digits whenever the walk sat near
  /// half. The exact figure is in the held square's card (StepsDayCard).
  final int? stepCount;

  /// Whether the tap about to happen is the one that finishes this day, which
  /// is the only moment worth firing the completion burst for.
  ///
  /// `square.next.isGreen` answers this correctly for every square the colour
  /// cycle owns, and exactly backwards for a counted habit: at 0 done the
  /// effective square is `none`, whose `next` is `complete`, so the FIRST of
  /// four taps got the full completion burst while the day was 1/4 done, and
  /// the tap that actually finished it saw `partial` (whose next is `none`)
  /// and fired nothing. [dayCount] is non-null only for today's square of a
  /// habit counted more than once a day (and yesterday's while it is still
  /// open), which is precisely the case the colour cycle cannot answer, so
  /// its presence is the branch.
  ///
  /// The `done < target` half matters: a tap on an already-full counted square
  /// means CLEAR (see _handleSquareTap's fall-through), and celebrating
  /// someone emptying their day would be the worst possible time to.
  bool get _tapFinishesDay {
    final count = dayCount;
    if (count != null) {
      return count.done < count.target && count.done + 1 >= count.target;
    }
    return square.next.isGreen;
  }

  final bool hasNote;
  // Nullable: null while Grid's multi-select mode is active, so squares
  // stop responding to taps/long-presses and can't accidentally change a
  // habit-day's completion while the user is managing the habit list.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// What a screen reader announces for this square: habit, date, state.
  ///
  /// Built by the caller, which is the only place that knows the habit's name
  /// and the active language. Without it the Grid — the whole app — was a
  /// wall of unlabelled buttons to VoiceOver.
  final String semanticLabel;

  const _SquareCell({
    super.key,
    required this.size,
    required this.day,
    required this.semanticLabel,
    required this.isToday,
    required this.isFuture,
    required this.isScheduled,
    required this.isAlive,
    this.isCovered = false,
    required this.square,
    this.dayCount,
    this.stepFraction,
    this.stepCount,
    required this.hasNote,
    required this.onTap,
    required this.onLongPress,
  });

  /// True while this square is drawing a part-done count rather than a flat
  /// colour. At 0 there is nothing to draw and at the target the square is
  /// simply complete, so both ends fall back to ordinary square rendering.
  bool get _isCounting =>
      dayCount != null &&
      dayCount!.done > 0 &&
      dayCount!.done < dayCount!.target;

  /// True while this square is a hand-marked جزئي — drawn as a square filled
  /// to its own halfway line rather than as a centred glyph.
  ///
  /// Excludes the counting case for the same reason the glyph did: a counted
  /// square already draws its real proportion and its real number, and "half"
  /// would be a worse answer than "2 of 4" on top of being a wrong one.
  bool get _isHalfFill => square == SquareState.partial && !_isCounting;

  /// Whether [stepCount] is drawn. A times-per-day tally outranks it, as it
  /// outranks every other glyph: "2 of 4" is the question that square raises.
  bool get _showsStepCount => stepCount != null && !_isCounting;

  /// The ink for [stepCount], on whichever fill it lands on.
  ///
  /// The green and blue squares take their own state ink, the same colour
  /// the check and the sparkle were, so a finished day still reads as
  /// finished. Anything amber (a جزئي, or a part-done fill) takes the
  /// primary text colour instead of amber: the number straddles two washes
  /// of amber there, and amber on the deeper one measures about 3.2:1 in
  /// dark mode, while the primary ink clears 4.5:1 on both halves.
  Color _stepCountInk(BuildContext context) => switch (square) {
        SquareState.complete || SquareState.bonus =>
          square.accent(context.gp.dark),
        _ => context.gp.textPrimary,
      };

  /// The ink for the note corner, one branch per fill it can land on.
  ///
  /// The rule this replaces had three branches and no case for a computed
  /// quota miss or for [isCovered], so a note on either was drawn in
  /// `textTert`, the lowest ink in the palette, on red and on covered
  /// emerald. It also fell to `textTert` on the ordinary empty square, which
  /// is where most notes actually land: 3.17:1 in dark and 1.98:1 in light,
  /// against 7.24:1 and 3.88:1 for `textSec`. That is a step up a ladder that
  /// already exists, not a new colour.
  Color _noteInk(BuildContext context) {
    // Anything drawing a risen band: the band can reach the top corner, and
    // levelLine is the one ink measured to read on it (in light mode the
    // band's own accent on that band is 1.13:1, i.e. gone).
    if (_isHalfFill || _isCounting || stepFraction != null) {
      return SquareState.partial.levelLine(context.gp.dark);
    }
    // NOT complete.accent. A covered day is emerald-on-emerald: the fill is
    // emerald at 0.12 and the accent is the same hue at full strength, which
    // measures 1.63:1 in light mode, BELOW the 1.98:1 this method exists to
    // escape. It is also the worst square to lose the mark on, because a
    // covered day is empty by definition: the corner is the only thing drawn
    // in it, with no glyph beside it to say the day is special. textSec on
    // that fill is 4.13:1.
    if (isCovered) return context.gp.textSec;
    if (square.isMarked) return square.accent(context.gp.dark);
    return context.gp.textSec;
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.gp.dark;
    final disabled = isFuture || !isAlive;
    // The gold ring is an ASK, not a date stamp.
    //
    // Aziz, 2026-09-09: "the habits that I don't need to do today, the square
    // should not be outlined... I want to make it clear that no need for
    // today, and at the same time it does not feel like the user is missing
    // days, because he doesn't have to do it."
    //
    // Every habit used to get the ring on today's column, including the ones
    // today asks nothing of: a Mon/Wed/Fri habit wore it on a Tuesday, and a
    // four-a-week habit kept wearing it after the fourth session. A ring on
    // an empty square reads as an outstanding task, so a person who had done
    // everything they owed still saw a column of things apparently left to
    // do. The day header's own circle is what says which column is today
    // (see the isRealToday note there); this says what is still owed.
    //
    // So it is drawn only where today genuinely asks. See showsTodayRing,
    // where the rule lives so it can be asserted directly.
    final showTodayRing = showsTodayRing(
      isToday: isToday,
      isScheduled: isScheduled,
      isCovered: isCovered,
    );
    // Keying the pulse on the square state replays it on every color change:
    // marked cells get a satisfying pop, clearing back to white stays quiet.
    Widget cell = AnimatedContainer(
      duration: GameMotion.standard,
      curve: Curves.easeOut,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isCovered
            ? coveredDayFill(dark)
            // A counting square is drawn as empty-plus-a-rising-portion. Left
            // as square.fill it painted the partial colour edge to edge, and
            // the proportional overlay — the same colour — was invisible: the
            // square went straight from empty to fully yellow on tap one of
            // four, which is precisely the thing the count exists to avoid.
            : _isCounting
                ? SquareState.none.fill(dark)
                : square.fill(dark),
        borderRadius: BorderRadius.circular(9),
        // Same width for every square regardless of `isToday` — Flutter
        // centers a box border on the shape's edge, so a thicker border
        // bleeds outward and makes that one cell look bigger/misaligned
        // against the rest of the row. Today stays distinguished by color
        // alone so the whole grid lines up cleanly.
        //
        // `goldDim` (not the lighter `gold`) on purpose: the empty-square
        // fill is now a warm tan close in hue to `gold` itself, so a
        // `gold`-on-tan ring had too little contrast to read as a single
        // crisp line — it looked like a soft, doubled/"extra" outline
        // instead. `goldDim` is dark and saturated enough to stay crisp
        // against every fill color, not just the green "complete" state.
        border: Border.all(
          color: showTodayRing ? GameColors.goldDim : square.border(dark),
          width: 0.8,
        ),
      ),
      child: Stack(
        children: [
          // The proportional fill, under everything else so the note glyph
          // and the count still read on top of it. Drawn from the bottom
          // because a square filling upward is the one metaphor nobody has
          // to be taught.
          if (_isCounting)
            _levelFill(
              factor: dayCount!.done / dayCount!.target,
              fill: SquareState.partial.fill(dark),
              radius: _squareInnerRadius,
            ),
          // The same picture, frozen at a half, for a square somebody marked
          // جزئي from the long-press palette. No glyph: the mark IS the
          // square being half full, which is what the state has always meant
          // (see squareStateEffect — "counts as half a day") and what the
          // clock face it replaces never said. The flat top edge lands at the
          // identical height in every partial square down a column, and
          // aligned edges across a wall read far faster than aligned glyphs.
          if (_isHalfFill)
            _levelFill(
              factor: SquareState.partial.levelFactor!,
              fill: SquareState.partial.levelFill(dark),
              line: _showsStepCount
                  ? null
                  : SquareState.partial.levelLine(dark),
              radius: _squareInnerRadius,
            ),
          // The same picture again for a walking habit part-way to its step
          // goal. Borrows the جزئي colours rather than inventing a "steps"
          // colour: the board already teaches that a square filled part-way
          // in that tone means part done, and this is that, measured instead
          // of tapped. AnimatedContainer inside _levelFill means the level
          // rises rather than jumps when a fresh read comes back.
          if (stepFraction != null)
            _levelFill(
              factor: stepFraction!,
              fill: SquareState.partial.levelFill(dark),
              line: _showsStepCount
                  ? null
                  : SquareState.partial.levelLine(dark),
              radius: _squareInnerRadius,
            ),
          if (_showsStepCount)
            Center(
              child: StepCountLabel(
                steps: stepCount!,
                squareSize: size,
                color: _stepCountInk(context),
              ),
            ),
          // The count itself, standing in for the partial state's own glyph.
          // Both cannot be shown — the glyph is centred and would sit on top
          // of the number — and between "something is part done" and "2 of 4
          // are done", the number is the one that answers the question.
          if (_isCounting)
            Center(
              child: Text(
                '${dayCount!.done}',
                style: TextStyle(
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w800,
                  color: SquareState.partial.accent(dark),
                ),
              ),
            ),
          if (square.icon != null &&
              !_isCounting &&
              !_isHalfFill &&
              !_showsStepCount)
            Center(
              child: Icon(
                square.icon,
                size: size * 0.5,
                color: square.accent(dark),
              ),
            ),
          // A covered day says so, instead of only being tinted.
          //
          // It is empty by definition — nothing was owed, so no state was
          // ever written — and it used to carry no mark at all, which left a
          // 4x habit's rest days looking like days nothing happened on.
          // Nothing IS what happened; the point is that nothing was ASKED.
          // The dash is the app's existing "this day wanted nothing of you"
          // mark (see SquareState.skipped), and emerald says the day is
          // settled rather than missed. emeraldInkFor, not the emerald
          // token: emerald-on-emerald measures 1.63:1 in light mode, which
          // is why this square carried no glyph in the first place.
          if (isCovered &&
              square == SquareState.none &&
              !_isCounting &&
              !_showsStepCount)
            Center(
              child: Icon(
                Icons.remove_rounded,
                size: size * 0.5,
                // Full strength in light, softened only in dark. The ink
                // token is DERIVED by darkening until it clears 4.5:1
                // against the light floor, so thinning it in light mode
                // throws away the one guarantee it carries and puts this
                // mark back where the missing glyph started. Dark has the
                // headroom, and there the softening is what keeps a rest
                // day from shouting as loudly as a finished one.
                color: GameColors.emeraldInkFor(dark)
                    .withOpacity(dark ? 0.55 : 1),
              ),
            ),
          // The folded corner that says "you wrote here". It replaced a 9pt
          // sticky-note glyph in the BOTTOM-right whose paper-and-lines
          // interior was illegible at the 30pt cell floor and whose box
          // overlapped the centred state glyph. A solid triangle survives the
          // shrink, and the top-right corner is the one region of a square no
          // fill, count, waterline or glyph ever occupies.
          //
          // Clipped to the square's own inner radius, the way _levelFill is:
          // there is no ambient clip here (the AnimatedContainer sets a
          // decoration, and a BoxDecoration's borderRadius does not clip
          // children), so without this the triangle paints a hard nub outside
          // the 9pt silhouette and over the inner edge of the border,
          // including the gold today ring.
          if (hasNote)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_squareInnerRadius),
                child: Align(
                  alignment: Alignment.topRight,
                  child: NoteCorner(
                    size: (size * 0.30).clamp(9.0, 16.0),
                    ink: _noteInk(context),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    // Deliberately NO scale/elastic effects on squares, ever: every
    // geometric pop (0.7→1 elasticOut overshoots past 100%, 0.82→1 eases)
    // made a square transiently a different size than its neighbors — and
    // because each cell replays independently the moment its state lands
    // (ValueKey(square)), the whole board read as misaligned/mis-sized on
    // every week load and every tap. Squares are now always exactly
    // `size`×`size`, no exceptions; celebration stays as light-only
    // effects (shimmer/fade) that never move a pixel of layout.
    if (square.isGreen) {
      cell = _CelebrationShimmer(square: square, child: cell);
    } else if (square.isMarked) {
      cell = cell
          .animate(key: ValueKey(square))
          .fadeIn(duration: 180.ms, begin: 0.6);
    }
    final tap = onTap;
    final interactive = !disabled && tap != null;
    // Semantics adds no layout of its own - it annotates the subtree, so
    // nothing here moves a pixel. `container: true` stops the icon and note
    // glyph inside from being announced as separate unlabelled nodes.
    return Semantics(
      container: true,
      button: interactive,
      enabled: interactive,
      label: semanticLabel,
      child: GestureDetector(
        onTap: (disabled || tap == null)
            ? null
            : () {
              // Confetti fires from the cell itself the instant the tap
              // will turn it green — the market-standard completion moment.
              if (_tapFinishesDay) {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null && box.attached) {
                  showVictoryBurst(
                    context,
                    box.localToGlobal(box.size.center(Offset.zero)),
                  );
                }
              }
              tap();
            },
        // A past day carrying a note stays openable even once the habit
        // stopped asking for it. Change a habit's weekdays or archive it and
        // every note on a now-unscheduled day used to become permanently
        // unreachable from the Grid while its marker kept painting, with no
        // surface in the app able to open it except the journal.
        onLongPress: (!isFuture && (isAlive || hasNote)) ? onLongPress : null,
        child: Opacity(
          // A covered off-day keeps its full opacity: the soft green IS the
          // information, and dimming it back to the card is exactly the
          // "dark grey, like a missing day" this state exists to end. A day
          // someone wrote on is information for the same reason.
          opacity: disabled && !isCovered && !hasNote ? 0.35 : 1,
          child: cell,
        ),
      ),
    );
  }
}

/// Announces the row of a habit that was just created: scrolls it into
/// view, then a one-shot gold shimmer, then clears
/// [newlyAddedHabitIdProvider] so the highlight can never replay.
///
/// ensureVisible instead of a ScrollController on the CustomScrollView:
/// the table builds eagerly inside a SliverToBoxAdapter, so the new row
/// has a context the moment the sheet closes, and asking the scrollable
/// from the inside means this works identically wherever the row lands —
/// bottom of a single board, or mid-screen above the quit section — with
/// no coordinate math to drift out of date.
class _NewHabitHighlight extends ConsumerStatefulWidget {
  final Widget child;
  const _NewHabitHighlight({required this.child});

  @override
  ConsumerState<_NewHabitHighlight> createState() =>
      _NewHabitHighlightState();
}

class _NewHabitHighlightState extends ConsumerState<_NewHabitHighlight> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // The delay covers the scroll, so the shimmer runs where the eye
    // already is rather than off-screen. Clearing the provider on
    // completion unmounts this wrapper and returns the row to the exact
    // build every other row gets.
    return widget.child
        .animate(
          onComplete: (_) {
            if (!mounted) return;
            ref.read(newlyAddedHabitIdProvider.notifier).state = null;
          },
        )
        .shimmer(
          delay: 500.ms,
          duration: 1100.ms,
          color: GameColors.gold.withOpacity(0.35),
        );
  }
}
