part of 'grid_screen.dart';

// ─── Long-press cell editor (palette + reflection note) ───────────────────────

class _CellEditorSheet extends ConsumerStatefulWidget {
  final IslamicHabitTemplate habit;
  final DateTime day;
  const _CellEditorSheet({required this.habit, required this.day});

  @override
  ConsumerState<_CellEditorSheet> createState() => _CellEditorSheetState();
}

class _CellEditorSheetState extends ConsumerState<_CellEditorSheet> {
  late final TextEditingController _noteCtrl;

  /// Whether a note stored on this day sits outside the free-history window.
  ///
  /// The Grid keeps past WEEKS free on purpose (see _pickWeek's doc comment:
  /// "a picker is not the place to introduce a paywall that did not exist a
  /// moment ago"), so nothing here gates navigation, the board, or the
  /// palette. What did leak is the note TEXT: Grid Journal paywalls notes
  /// older than kFreeHistoryMonths, and long-pressing the same square on the
  /// board handed the same sentence over for free.
  ///
  /// Deliberately only ever true when a note ALREADY EXISTS. Writing a fresh
  /// note on an old day stays open, because this is about reading what is
  /// stored, not about renting the keyboard. That distinction is also what
  /// keeps it safe: an emptied field whose Save button still wrote through
  /// would erase the very note it was meant to withhold, so the editor drops
  /// the Save button entirely in this state rather than saving a blank.
  ///
  /// NOT `final`: it was, and that froze the paywall in place. The wall's own
  /// lock card is a purchase funnel (it opens the history demo gate, whose CTA
  /// pushes /premium), and PremiumScreen applies the entitlement immediately
  /// without popping — so a customer came back to this still-mounted sheet and
  /// found no text field and no Save button, having just paid for exactly
  /// that. See the ref.listen in build.
  late bool _noteWalled;

  @override
  void initState() {
    super.initState();
    final note = ref
        .read(weeklyGridProvider)
        .noteFor(widget.habit.id, widget.day);
    _noteWalled = WeeklyGridState.noteIsWalled(
      note: note,
      day: widget.day,
      now: DateTime.now().effectiveDay,
      isPremium: ref.read(premiumProvider),
    );
    _noteCtrl = TextEditingController(text: _noteWalled ? '' : note);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Recompute the wall if entitlement changes while this sheet is open.
    // The controller has to be re-seeded in the same setState: initState put
    // an EMPTY string in it when walled, so a rebuild alone would unlock a
    // text field onto a blank note and Save would write that blank through
    // over the note the user just bought access to.
    ref.listen<bool>(premiumProvider, (_, isPremium) {
      final stored =
          ref.read(weeklyGridProvider).noteFor(widget.habit.id, widget.day);
      final walled = WeeklyGridState.noteIsWalled(
        note: stored,
        day: widget.day,
        now: DateTime.now().effectiveDay,
        isPremium: isPremium,
      );
      if (walled == _noteWalled) return;
      setState(() {
        _noteWalled = walled;
        _noteCtrl.text = walled ? '' : stored;
      });
    });

    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final locale = Localizations.localeOf(context).languageCode;
    final current =
        ref.watch(weeklyGridProvider).squareFor(widget.habit.id, widget.day);
    // Whether this square is a synced completion (rewarded via the
    // canonical completeHabit path) — shown with a note above the palette
    // instead of hiding it, since picking a different color here is a
    // deliberate "I completed this by mistake" correction (see
    // _handlePaletteTap), not an accidental undo. Pre-existing green
    // squares from before this sync existed aren't caught by this check
    // (never recorded in `completions`) and behave via the plain
    // flat-rate palette path below, unaffected. Checks completions
    // directly rather than isCompleted/frequencyTarget == 1 — covers
    // multi-target habits too now that _handleSquareTap/_handlePaletteTap
    // sync those as well; see _handleSquareTap's doc comment.
    final isLocked = widget.day.isToday &&
        current == SquareState.complete &&
        (ref.watch(dashboardProvider).completions[widget.habit.id] ?? 0) > 0;
    final palette = [
      SquareState.complete,
      SquareState.partial,
      SquareState.bonus,
      SquareState.failed,
      SquareState.skipped,
      SquareState.none,
    ];

    // The keyboard eats the height this sheet was sized for, and a Column
    // has no way to give ground: it just paints its overflow outside the
    // Container, which is how the Save button ended up sitting BELOW the
    // card on its own. Bounding the height and scrolling the contents is
    // what keeps every child inside the rounded rect at any keyboard state.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final maxSheetHeight = MediaQuery.sizeOf(context).height - viewInsets - 96;

    return AnimatedPadding(
      duration: GameMotion.standard,
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + viewInsets,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Builder(builder: (_) {
                  final (_, categoryColor) =
                      categoryVisual(widget.habit.category);
                  final color = widget.habit.customColor ?? categoryColor;
                  return Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: CategoryIcon(
                      category: widget.habit.category,
                      size: 18,
                      color: color,
                    ),
                  );
                }),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.habit.localName(isAr),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: gp.textPrimary,
                        ),
                      ),
                      Text(
                        DateFormat('EEEE, MMM d', locale).format(widget.day),
                        style: TextStyle(fontSize: 12, color: gp.textSec),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (isLocked) ...[
              Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: gp.textTert, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.gridSquareDoneFromToday,
                      style: TextStyle(fontSize: 12, color: gp.textSec),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            if (!widget.day.isToday) ...[
              Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: gp.textTert, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      // The real calendar day during the 6-hour window
                      // right after midnight isn't a "past" day (it just
                      // hasn't become the official reward day yet) —
                      // saying so here would be actively wrong, not just
                      // imprecise, so it gets its own copy instead of
                      // reusing gridPastDayHint. See DateTimeGameExt.
                      // isRealToday/isToday's doc comments.
                      //
                      // A day holding an outstanding receipt is the other
                      // day gridPastDayHint is wrong about: "no rewards"
                      // is the rule for backfilling, and this square is
                      // not a backfill, it is a completion this app itself
                      // undid and can hand straight back (see
                      // UndoneCompletion). Telling someone their own
                      // correction pays nothing, while it silently pays,
                      // is the worst of both.
                      widget.day.isRealToday
                          ? s.gridNotYetActiveHint
                          : (ref.watch(dashboardProvider).undoneFor(
                                      widget.habit.id,
                                      widget.day.toDateKey()) !=
                                  null
                              ? s.gridRestorableDayHint
                              : s.gridPastDayHint),
                      style: TextStyle(fontSize: 12, color: gp.textSec),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            Text(
              s.gridEditSquare.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: gp.textTert,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            // Equal shares in a Row, not a Wrap. Six choices that are one set
            // of options should look like one set: the Wrap broke after five
            // and stranded "لم يكتمل" alone on a second line, which made the
            // sixth choice read as a different KIND of thing.
            //
            // Past roughly 1.35x text scale the labels genuinely cannot fit a
            // sixth of the width (مكتمل breaks to "مكت/مل"), so it drops to a
            // deliberate 3 + 3 instead. Two even rows still read as one set;
            // 5 + 1 never did. Nothing is clamped, so accessibility sizes get
            // the full type they asked for.
            _PaletteGrid(
              palette: palette,
              current: current,
              isAr: isAr,
              onPick: (state) => _handlePaletteTap(isLocked, state),
            ),
            const SizedBox(height: 12),
            // What the current choice DOES, in one line, changing as the
            // choice changes. This is the only place in the app that
            // explains how تخطّي, فشل and an empty square differ, and it is
            // deliberately placed at the moment somebody is choosing between
            // them rather than in a help screen nobody opens.
            AnimatedSwitcher(
              duration: GameMotion.relaxed,
              child: Row(
                key: ValueKey(current),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    current == SquareState.skipped
                        ? Icons.bedtime_rounded
                        : Icons.info_outline_rounded,
                    size: 13,
                    color: current == SquareState.skipped
                        ? GameColors.gold
                        : gp.textTert,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      s.squareStateEffect(current),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: gp.textSec,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              s.gridNoteLabel,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (_noteWalled)
              // No text field and no Save button: there is nothing to type
              // over, and nothing that could write a blank through.
              InkWell(
                onTap: () => showHistoryDemoGate(context),
                borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: GameColors.gold.withOpacity(gp.dark ? 0.10 : 0.08),
                    borderRadius:
                        BorderRadius.circular(GameSpacing.cardRadius),
                    border:
                        Border.all(color: GameColors.gold.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_rounded,
                          size: 16, color: GameColors.gold),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.gridNoteLocked,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: gp.textSec,
                              height: 1.35),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 16,
                          color: GameColors.gold.withOpacity(0.7)),
                    ],
                  ),
                ),
              )
            else ...[
              TextField(
                controller: _noteCtrl,
                maxLines: 3,
                minLines: 2,
                textInputAction: TextInputAction.newline,
                style: TextStyle(fontSize: 14, color: gp.textPrimary),
                decoration: InputDecoration(hintText: s.gridNoteHint),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ref.read(weeklyGridProvider.notifier).setNote(
                          widget.habit.id,
                          widget.day,
                          _noteCtrl.text,
                        );
                    Navigator.pop(context);
                  },
                  child: Text(s.gridSave),
                ),
              ),
            ],
          ],
        ),
        ),
      ),
      ),
    );
  }

  /// Handles tapping a palette swatch for [picked].
  ///
  /// - If the square is currently a synced, reward-locked completion
  ///   (`isLocked`) and [picked] isn't `complete`, this is a correction:
  ///   reverse the canonical reward first (`uncompleteHabit`), then
  ///   update the visual state only.
  /// - If the square isn't done yet and [picked] is `complete` for
  ///   today's habit, this is the same canonical completion tapping the
  ///   square or Today's button would do — reward first, then mirror the
  ///   visual state (see _handleSquareTap's doc comment for why every
  ///   habit syncs here now, not just single-tap ones).
  /// - Everything else falls through to the original flat-rate
  ///   `setSquare` path, unchanged.
  Future<void> _handlePaletteTap(bool isLocked, SquareState picked) async {
    HapticFeedback.selectionClick();
    final habit = widget.habit;
    final day = widget.day;

    if (isLocked && picked != SquareState.complete) {
      // AWAITED, and the await is the whole fix.
      //
      // The doc comment above has always said "reverse the canonical reward
      // FIRST, then update the visual state only", but without this await
      // "first" was only true of the call order, not of the writes. Both
      // paths land in the same stored daily map: uncompleteHabit clears
      // habitCompletions[id], setSquareStateOnly writes squareStates[id], and
      // each is a read, modify, write of the whole map. Unawaited, the square
      // write read the map BEFORE the uncomplete had written it back, so it
      // saved its own square change on top of a stale copy and put the
      // completion count back to 1.
      //
      // What that looked like to a person: correct a green square to red, the
      // square turns red and stays red, and the habit still counts as done
      // for XP, the streak and every report. Reproduced in
      // test/features/grid/palette_correction_race_test.dart.
      //
      // Awaiting costs nothing visually: setSquareStateOnly sets its state
      // synchronously and only persists in the background, so the square
      // still turns red on the same frame as the tap.
      await ref.read(dashboardProvider.notifier).uncompleteHabit(
            habitId: habit.id,
            // Mirrors the completion's boost, see roomBoostedReward.
            xpReward: roomBoostedReward(ref, habit.id, habit.xpReward),
            goldReward: roomBoostedReward(ref, habit.id, habit.goldReward),
            category: habit.category.name,
          );
      if (!mounted) return;
      ref
          .read(weeklyGridProvider.notifier)
          .setSquareStateOnly(habit.id, day, picked);
      syncRoomToday(ref, habit.id, day);
      return;
    }

    final isSyncable = day.isToday;
    final alreadyDoneToday = ref
        .read(dashboardProvider)
        .isCompleted(habit.id, habit.effectiveDailyTarget);
    if (isSyncable && picked == SquareState.complete && !alreadyDoneToday) {
      final dashState = ref.read(dashboardProvider);
      final todayHabits = ref
          .read(habitListProvider)
          .where((h) => h.isScheduledFor(day))
          .map((h) => (id: h.id, frequencyTarget: h.effectiveDailyTarget));
      // BRANCHED. The comment that used to sit here said alreadyDoneToday
      // above already guaranteed this landed, and that stopped being true
      // when completeHabit gained its two load guards: it also refuses while
      // the account's numbers are still loading, and after that load failed.
      // Unbranched, a tap in either of those windows painted the square green
      // and recorded nothing, which is the one failure a person can never
      // see, because the square looks identical to one that worked.
      final rewarded = await ref.read(dashboardProvider.notifier).completeHabit(
            habitId: habit.id,
            // 2x while a linked room is live — see roomBoostedReward.
            xpReward: roomBoostedReward(ref, habit.id, habit.xpReward),
            goldReward: roomBoostedReward(ref, habit.id, habit.goldReward),
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
      if (!mounted) return;
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
          .setSquareStateOnly(habit.id, day, SquareState.complete);
      syncRoomToday(ref, habit.id, day);
      return;
    }

    ref.read(weeklyGridProvider.notifier).setSquare(habit.id, day, picked);
    syncRoomToday(ref, habit.id, day);
  }
}

/// Lays the six square states out as ONE row of six, falling back to two
/// rows of three once the text scale makes six labels unreadable.
class _PaletteGrid extends StatelessWidget {
  final List<SquareState> palette;
  final SquareState current;
  final bool isAr;
  final ValueChanged<SquareState> onPick;

  const _PaletteGrid({
    required this.palette,
    required this.current,
    required this.isAr,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    // Measured off a real label rather than assumed: scale(10)/10 is the
    // effective multiplier whatever the platform's curve happens to be.
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final perRow = scale <= 1.35 ? 6 : 3;

    Widget swatch(int i) => _PaletteSwatch(
          state: palette[i],
          selected: palette[i] == current,
          label: isAr ? palette[i].labelAr : palette[i].label,
          onTap: () => onPick(palette[i]),
        )
            .animate(delay: (i * 35).ms)
            .fadeIn(duration: 220.ms)
            .scale(
              begin: const Offset(0.8, 0.8),
              curve: Curves.easeOutBack,
            );

    Widget row(int start, int end) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = start; i < end; i++) ...[
              if (i > start) const SizedBox(width: 6),
              Expanded(child: swatch(i)),
            ],
          ],
        );

    if (perRow >= palette.length) return row(0, palette.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var start = 0; start < palette.length; start += perRow) ...[
          if (start > 0) const SizedBox(height: 12),
          row(start, (start + perRow).clamp(0, palette.length)),
        ],
      ],
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  final SquareState state;
  final bool selected;
  final String label;
  final VoidCallback onTap;
  const _PaletteSwatch({
    required this.state,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final dark = gp.dark;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Square, filling whatever share the Row hands it, up to the 46 it
          // used to be fixed at. AspectRatio rather than a fixed size so six
          // of these still fit across a 375pt phone.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 46),
            child: AspectRatio(
              aspectRatio: 1,
              child: AnimatedContainer(
                duration: GameMotion.quick,
                decoration: BoxDecoration(
                  color: state.fill(dark),
                  borderRadius:
                      BorderRadius.circular(GameSpacing.buttonRadius),
                  border: Border.all(
                    color: selected ? state.accent : state.border(dark),
                    width: selected ? 2 : 0.8,
                  ),
                ),
                child: Icon(
                  state.icon ?? Icons.circle_outlined,
                  size: 20,
                  color:
                      state == SquareState.none ? gp.textTert : state.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Two lines allowed: "إنجاز إضافي" does not fit one share on one
          // line, and shrinking every label to suit the longest one would
          // cost legibility on all six.
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              height: 1.2,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: selected ? state.accent : gp.textSec,
            ),
          ),
        ],
      ),
    );
  }
}
