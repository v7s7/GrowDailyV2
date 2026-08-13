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

  @override
  void initState() {
    super.initState();
    final note = ref
        .read(weeklyGridProvider)
        .noteFor(widget.habit.id, widget.day);
    _noteCtrl = TextEditingController(text: note);
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

    return AnimatedPadding(
      duration: GameMotion.standard,
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gp.border, width: 0.5),
        ),
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
                      widget.day.isRealToday
                          ? s.gridNotYetActiveHint
                          : s.gridPastDayHint,
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
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < palette.length; i++)
                  _PaletteSwatch(
                    state: palette[i],
                    selected: palette[i] == current,
                    label: isAr ? palette[i].labelAr : palette[i].label,
                    onTap: () => _handlePaletteTap(isLocked, palette[i]),
                  )
                      .animate(delay: (i * 35).ms)
                      .fadeIn(duration: 220.ms)
                      .scale(
                        begin: const Offset(0.8, 0.8),
                        curve: Curves.easeOutBack,
                      ),
              ],
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
      ref.read(dashboardProvider.notifier).uncompleteHabit(
            habitId: habit.id,
            // Mirrors the completion's boost — see roomBoostedReward.
            xpReward: roomBoostedReward(ref, habit.id, habit.xpReward),
            goldReward: roomBoostedReward(ref, habit.id, habit.goldReward),
            category: habit.category.name,
          );
      ref
          .read(weeklyGridProvider.notifier)
          .setSquareStateOnly(habit.id, day, picked);
      syncRoomToday(ref, habit.id, day);
      return;
    }

    final isSyncable = day.isToday;
    final alreadyDoneToday = ref
        .read(dashboardProvider)
        .isCompleted(habit.id, habit.frequencyTarget);
    if (isSyncable && picked == SquareState.complete && !alreadyDoneToday) {
      final dashState = ref.read(dashboardProvider);
      final todayHabits = ref
          .read(habitListProvider)
          .where((h) => h.isScheduledFor(day))
          .map((h) => (id: h.id, frequencyTarget: h.frequencyTarget));
      // No branch on the return value — see _handleSquareTap's doc
      // comment; alreadyDoneToday above already guarantees this lands.
      await ref.read(dashboardProvider.notifier).completeHabit(
            habitId: habit.id,
            // 2x while a linked room is live — see roomBoostedReward.
            xpReward: roomBoostedReward(ref, habit.id, habit.xpReward),
            goldReward: roomBoostedReward(ref, habit.id, habit.goldReward),
            frequencyTarget: habit.frequencyTarget,
            allHabitsDoneAfter: willCompleteAllHabitsToday(
              state: dashState,
              todayHabits: todayHabits,
              habitId: habit.id,
              frequencyTarget: habit.frequencyTarget,
            ),
            category: habit.category.name,
            habitName: habit.localName(S.of(context).isAr),
          );
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
          AnimatedContainer(
            duration: GameMotion.quick,
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: state.fill(dark),
              borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
              border: Border.all(
                color: selected ? state.accent : state.border(dark),
                width: selected ? 2 : 0.8,
              ),
            ),
            child: Icon(
              state.icon ?? Icons.circle_outlined,
              size: 20,
              color: state == SquareState.none ? gp.textTert : state.accent,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              color: selected ? state.accent : gp.textSec,
            ),
          ),
        ],
      ),
    );
  }
}
