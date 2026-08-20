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
      // Nothing to do if today isn't in this particular week (a past week
      // has no "today" cell at all) or the table isn't scrolled in the
      // first place (everything already fits) — ensureVisible is a safe
      // no-op either way, it only acts when there's an actual scrollable
      // ancestor and the target isn't already fully in view.
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(ctx, alignment: 1);
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
              color: isToday
                  ? GameColors.gold.withOpacity(primary ? 1 : 0.8)
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
              // real clock and moves at midnight even during the 6-hour
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
                        color: day.isRealToday ? GameColors.gold : gp.textSec,
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
    final gp = context.gp;
    final isAr = S.of(context).isAr;
    final today = DateTime.now().effectiveDay;
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
    final isFlexibleQuota = habit.frequencyType == HabitFrequencyType.weekly &&
        habit.scheduledWeekdays.isEmpty;
    final demand = isFlexibleQuota
        ? weeklyQuotaDemand(
            dayCount: days.length,
            doneDays: {
              for (var i = 0; i < days.length; i++)
                if (widget.state.squareFor(habit.id, days[i]).isGreen) i,
            },
            target: habit.frequencyTarget,
          )
        : null;

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
            onTap: widget.selectionMode && habit.archivedAt == null
                ? () => widget.onSelectionToggle(habit.id)
                : null,
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
                      final (_, categoryColor) = categoryVisual(habit.category);
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
                      // Tap-to-reveal only outside selection mode: the
                      // GestureDetector wrapping this whole label already
                      // claims onTap there (to toggle selection), and a
                      // second tap recognizer on the truncated name
                      // underneath it would otherwise fight that gesture
                      // for the same tap instead of cleanly falling through
                      // to it. A name that isn't actually truncated is
                      // unaffected either way - see SafeWrapText.
                      // tapToRevealWhenTruncated's own doc comment.
                      // The pause tile that replaced this row's category
                      // icon is the visible signal; this is the same thing
                      // said out loud, since a screen reader gets neither
                      // the glyph nor the dimmed color.
                      child: Semantics(
                        label: habit.archivedAt != null
                            ? [
                                habit.localName(isAr),
                                S.of(context).habitPausedSection,
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
                          tapToRevealWhenTruncated: !widget.selectionMode,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          for (final day in days)
            Padding(
              padding: const EdgeInsets.only(left: _gap),
              child: _SquareCell(
                // "Duha prayer, Wednesday 12 August, done" — built here
                // because this is the only place that has both the habit's
                // name and the active language. A locked day says so, since
                // otherwise a screen-reader user would keep trying a square
                // that can never respond.
                semanticLabel: [
                  habit.localName(isAr),
                  DateFormat('EEEE d MMMM', isAr ? 'ar' : 'en').format(day),
                  widget.state.squareFor(habit.id, day).localLabel(isAr),
                  if (day.isAfter(today))
                    isAr ? 'يوم قادم' : 'future day'
                  else if (!habit.isScheduledFor(day))
                    isAr ? 'غير مجدول' : 'not scheduled',
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
                // itself during the 6-hour window right after midnight
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
                // A day this flexible quota genuinely owed and that stayed
                // empty — the week's real miss, and the only empty square the
                // app is entitled to call one. Rest days stay plain. Never
                // applied to today or a future day: a day still in progress
                // has not been missed yet, and `owed` for those means "this is
                // your last chance", not "you failed".
                isMissedQuotaDay: demand != null &&
                    day.isBefore(today) &&
                    demand[days.indexOf(day)] == DayDemand.owed &&
                    widget.state.squareFor(habit.id, day) == SquareState.none,
                square: widget.state.squareFor(habit.id, day),
                hasNote: widget.state.noteFor(habit.id, day).isNotEmpty,
                onTap: widget.selectionMode
                    ? null
                    : () => _handleSquareTap(ref, habit, day),
                onLongPress: widget.selectionMode
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        _openEditor(context, ref, habit, day);
                      },
              ),
            ),
        ],
      ),
    );
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
    final current = widget.state.squareFor(habit.id, day);
    final next = current.next;
    final isSyncable = day.isToday;

    if (isSyncable && next == SquareState.complete) {
      final alreadyDoneToday = ref
          .read(dashboardProvider)
          .isCompleted(habit.id, habit.effectiveDailyTarget);
      HapticFeedback.mediumImpact();
      if (alreadyDoneToday) {
        // Already rewarded (e.g. completed from Today and the mirror
        // hasn't caught up) — just repair the visual state, no reward call.
        ref.read(weeklyGridProvider.notifier).markCompleteFromHabit(habit.id, day);
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
        final todayHabits = ref
            .read(habitListProvider)
            .where((h) => h.isScheduledFor(day))
            .map((h) => (id: h.id, frequencyTarget: h.effectiveDailyTarget));
        await ref.read(dashboardProvider.notifier).completeHabit(
              habitId: habit.id,
              // 2x while a linked room is live — see roomBoostedReward.
              xpReward: roomBoostedReward(ref, habit.id, habit.xpReward),
              goldReward:
                  roomBoostedReward(ref, habit.id, habit.goldReward),
              frequencyTarget: habit.effectiveDailyTarget,
              allHabitsDoneAfter: willCompleteAllHabitsToday(
                state: dashState,
                todayHabits: todayHabits,
                habitId: habit.id,
                frequencyTarget: habit.effectiveDailyTarget,
                // A جزئي square counts half toward the threshold, so a day
                // that is nearly full still keeps its streak.
                halfDoneHabitIds:
                    ref.read(weeklyGridProvider).halfDoneTodayIds(),
              ),
              category: habit.category.name,
              habitName: habit.localName(S.of(context).isAr),
            );
        ref
            .read(weeklyGridProvider.notifier)
            .markCompleteFromHabit(habit.id, day);
        syncRoomToday(ref, habit.id, day);
        _maybeCelebrateFullRow(ref, habit);
      }
      return;
    }

    if (isSyncable &&
        current == SquareState.complete &&
        (ref.read(dashboardProvider).completions[habit.id] ?? 0) > 0) {
      // Today's completed, synced squares should still behave like every
      // other editable square: tapping green cycles it back to empty, and
      // long-press still opens the explicit palette. Because this green
      // state was rewarded through DashboardNotifier.completeHabit, undo
      // that canonical completion first so Today un-checks the task and
      // XP/gold/green counters are refunded before the visual square is
      // cleared. Checks completions[habitId] > 0 directly rather than
      // isCompleted (completions >= frequencyTarget): for a multi-target
      // habit, one Grid-driven tap only ever registers one completion,
      // which alone can sit well under its weekly target — isCompleted
      // would stay false and this whole branch would be skipped, leaving
      // a phantom completions entry this square could never undo again.
      HapticFeedback.selectionClick();
      await ref.read(dashboardProvider.notifier).uncompleteHabit(
            habitId: habit.id,
            // Mirrors the completion's boost — see roomBoostedReward.
            xpReward: roomBoostedReward(ref, habit.id, habit.xpReward),
            goldReward: roomBoostedReward(ref, habit.id, habit.goldReward),
            category: habit.category.name,
          );
      ref
          .read(weeklyGridProvider.notifier)
          .setSquareStateOnly(habit.id, day, next);
      syncRoomToday(ref, habit.id, day);
      return;
    }

    // A square turning green is the app's core reward moment — it gets a
    // heavier thump than the intermediate colors.
    if (next.isGreen) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    ref.read(weeklyGridProvider.notifier).cycleSquare(habit.id, day);
    syncRoomToday(ref, habit.id, day);
    if (next.isGreen) _maybeCelebrateFullRow(ref, habit);
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
    if (!isHabitRowComplete(
      days: grid.days,
      isScheduled: habit.isScheduledFor,
      squareFor: (d) => grid.squareFor(habit.id, d),
    )) {
      return;
    }
    HapticFeedback.heavyImpact();
    final s = S.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.grid_view_rounded,
                color: GameColors.emerald, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                s.gridFullRow(habit.localName(s.isAr)),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: GameColors.emerald,
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
      // Without this, the sheet's bottom edge (and whatever sits near it)
      // renders flush with the literal bottom of the screen instead of
      // clearing the home-indicator bar — see _editSelected above for the
      // full explanation.
      useSafeArea: true,
      builder: (_) => _CellEditorSheet(habit: habit, day: day),
    );
  }

}

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

class _SquareCell extends StatelessWidget {
  final double size;
  final DateTime day;
  final bool isToday;
  final bool isFuture;
  // False when this habit's scheduledWeekdays is non-empty and doesn't
  // include this cell's weekday (see HabitModel/IslamicHabitTemplate — empty
  // means every day). Gets the exact same dimmed, inert treatment as a
  // future day: a habit set to "Sun/Mon only" can't be tapped, long-pressed,
  // or otherwise marked done on any other day. Doesn't hide history — a
  // square already completed before the habit's schedule was narrowed still
  // shows its real color, just dimmed and no longer editable.
  final bool isScheduled;

  /// A past, empty day that a flexible weekly quota genuinely owed — computed
  /// by [weeklyQuotaDemand], never stored and never marked by the user.
  ///
  /// Drawn in the same red the explicit `failed` state uses, because it means
  /// the same thing: a day that was asked for and did not happen. What it is
  /// NOT is every empty square — a 3x-a-week habit has four days it owes
  /// nothing on, and those stay plain. The count of these across a week is
  /// exactly the shortfall (proved in weekly_quota_plan_test.dart), so the app
  /// can never show more red than the person actually fell short by.
  final bool isMissedQuotaDay;

  final SquareState square;
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
    this.isMissedQuotaDay = false,
    required this.square,
    required this.hasNote,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final dark = context.gp.dark;
    final disabled = isFuture || !isScheduled;
    // Keying the pulse on the square state replays it on every color change:
    // marked cells get a satisfying pop, clearing back to white stays quiet.
    Widget cell = AnimatedContainer(
      duration: GameMotion.standard,
      curve: Curves.easeOut,
      width: size,
      height: size,
      decoration: BoxDecoration(
        // A computed quota miss borrows the explicit `failed` state's own fill
        // and border rather than inventing a red: it means exactly what a
        // hand-marked red square means — a day that was owed and did not
        // happen — so it should look like one. No new colour to learn, and it
        // stays correct automatically in every theme preset and in light mode.
        color: isMissedQuotaDay
            ? SquareState.failed.fill(dark)
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
          color: isToday
              ? GameColors.goldDim
              : isMissedQuotaDay
                  ? SquareState.failed.border(dark)
                  : square.border(dark),
          width: 0.8,
        ),
      ),
      child: Stack(
        children: [
          if (square.icon != null)
            Center(
              child: Icon(
                square.icon,
                size: size * 0.5,
                color: square.accent,
              ),
            ),
          // A tiny note glyph instead of a bare 4x4 dot - at the smallest
          // cell size (34px) the old plain dot was easy to miss entirely
          // and read as a stray pixel rather than "there's a note here".
          // Same color logic as before, just a shape that actually says
          // "note" instead of "something is different about this square".
          if (hasNote)
            Positioned(
              right: 2,
              bottom: 2,
              child: Icon(
                Icons.sticky_note_2_rounded,
                size: 9,
                color: square.isMarked
                    ? square.accent
                    : context.gp.textTert,
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
      cell = cell.animate(key: ValueKey(square)).shimmer(
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
              if (square.next.isGreen) {
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
        onLongPress: disabled ? null : onLongPress,
        child: Opacity(
          opacity: disabled ? 0.35 : 1,
          child: cell,
        ),
      ),
    );
  }
}
