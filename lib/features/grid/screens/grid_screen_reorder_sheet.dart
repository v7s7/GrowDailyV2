part of 'grid_screen.dart';

/// Drag-to-reorder for the Grid's habit rows — the missing UI half of
/// HabitOrderNotifier, whose fractional-rank storage and the
/// habitListProvider sort that reads it both shipped long ago with no way
/// for anyone to actually produce an order. One drag rewrites only the
/// dragged habit's rank (midpoint of its new neighbours, see reorder()),
/// and the board re-sorts live behind the sheet.
Future<void> showHabitReorderSheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _HabitReorderSheet(),
  );
}

class _HabitReorderSheet extends ConsumerStatefulWidget {
  const _HabitReorderSheet();

  @override
  ConsumerState<_HabitReorderSheet> createState() =>
      _HabitReorderSheetState();
}

class _HabitReorderSheetState extends ConsumerState<_HabitReorderSheet> {
  /// Working copy of the display order. Seeded once from the same sorted
  /// list the board renders, then owned locally: ReorderableListView needs
  /// the row to move the instant the drop lands, and waiting for the
  /// provider round-trip (rank write -> re-sort) draws a one-frame snap
  /// back to the old position before settling.
  late List<IslamicHabitTemplate> _habits;

  @override
  void initState() {
    super.initState();
    _habits = [...ref.read(habitListProvider)];
  }

  void _onReorder(int oldIndex, int newIndex) {
    // Standard ReorderableListView index fix-up: indices are given against
    // the list WITH the dragged row still in place.
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;
    HapticFeedback.mediumImpact();

    final orderedIds = [for (final h in _habits) h.id];
    final moved = _habits.removeAt(oldIndex);
    _habits.insert(newIndex, moved);
    setState(() {});

    // The habit now sitting AFTER the dropped one is the anchor reorder()
    // wants; dropped last means no anchor (append).
    final beforeId =
        newIndex + 1 < _habits.length ? _habits[newIndex + 1].id : null;
    ref
        .read(habitOrderProvider.notifier)
        .reorder(moved.id, orderedIds, beforeId: beforeId);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.7;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: gp.border,
                borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
              ),
            ),
            Text(
              s.reorderHabitsTitle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.reorderHabitsHint,
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 11.5, color: gp.textSec, height: 1.35),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _habits.length,
                onReorder: _onReorder,
                proxyDecorator: (child, index, animation) => Material(
                  color: Colors.transparent,
                  child: child,
                ),
                itemBuilder: (context, index) {
                  final habit = _habits[index];
                  final (_, categoryColor) = categoryVisual(habit.category);
                  final color = habit.customColor ?? categoryColor;
                  return Padding(
                    key: ValueKey(habit.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    // The whole row is the drag handle: with one finger on
                    // a phone there is nothing else a row in a reorder
                    // sheet could mean, so no press-and-hold delay and no
                    // hunting for the grip icon (kept as the visual cue).
                    child: ReorderableDragStartListener(
                      index: index,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          color: gp.surface,
                          borderRadius:
                              BorderRadius.circular(GameSpacing.buttonRadius),
                          border: Border.all(color: gp.border, width: 0.5),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: CategoryIcon(
                                category: habit.category,
                                size: 15,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                habit.localName(s.isAr),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: gp.textPrimary,
                                ),
                              ),
                            ),
                            Icon(Icons.drag_handle_rounded,
                                size: 20, color: gp.textTert),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
