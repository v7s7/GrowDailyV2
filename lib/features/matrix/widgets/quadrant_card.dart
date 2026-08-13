import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/voice_note_service.dart';
import '../../../core/theme/game_theme.dart';
import '../models/matrix_task.dart';
import '../notifiers/matrix_notifier.dart';
import 'edit_quadrant_sheet.dart';
import 'move_task_sheet.dart';

part 'quadrant_card_animated_stack.dart';
part 'quadrant_card_task_tile.dart';
part 'quadrant_card_tile_helpers.dart';
part 'quadrant_card_expanded_screen.dart';

class QuadrantCard extends StatelessWidget {
  final MatrixQuadrant quadrant;
  final List<MatrixTask> tasks;
  final void Function(String id) onToggle;
  final void Function(String id) onDelete;
  final void Function(String id, MatrixQuadrant q) onMove;
  // Drag-and-drop landing spot: [beforeId] is the task to land in front of,
  // or null for "dropped on empty space" (append to the end instead).
  final void Function(String id, MatrixQuadrant q, String? beforeId)
      onReorder;
  final void Function(String id) onToggleFav;
  final VoidCallback onAddTapped;
  // Pencil icon on a row — opens TaskDetailSheet for that task (title,
  // description, voice note, Delete/Move). Takes the whole MatrixTask
  // rather than just an id since the sheet needs more than the id to seed
  // its fields, and every other row-level callback here already narrows
  // down to a single task by the time it reaches this widget.
  final void Function(MatrixTask task) onOpenDetails;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(String id) onSelectionToggle;
  final void Function(String id) onSelectionStart;
  // Opens QuadrantExpandedScreen — a near-fullscreen view of just this
  // quadrant, for when the 2x2 grid's half-width cell is too cramped to
  // read comfortably. Wired from the header (see build() below), not
  // triggered from anywhere inside the task list itself, so it never
  // competes with a row's own tap-to-complete/drag/swipe handling.
  final VoidCallback onExpand;
  // Resolved by the caller via MatrixState.titleFor/colorFor (the user's
  // own override if they've set one, else the built-in default) — this
  // widget stays a plain presentational StatelessWidget rather than
  // reaching into matrixProvider itself, same as tasks/onToggle/etc. above
  // already do.
  final String title;
  final Color color;
  // Long-press on the header — opens the Edit Quadrant sheet (rename +
  // recolor). Its own callback rather than folded into onExpand's tap, so
  // a long-press never also fires the tap gesture underneath it.
  final VoidCallback onEditQuadrant;

  const QuadrantCard({
    super.key,
    required this.quadrant,
    required this.tasks,
    required this.onToggle,
    required this.onDelete,
    required this.onMove,
    required this.onReorder,
    required this.onToggleFav,
    required this.onAddTapped,
    required this.onOpenDetails,
    this.selectionMode = false,
    this.selectedIds = const {},
    required this.onSelectionToggle,
    required this.onSelectionStart,
    required this.onExpand,
    required this.title,
    required this.color,
    required this.onEditQuadrant,
  });

  // `tasks` now holds pending tasks plus anything finished today — a done
  // task stays right here, struck through, for the rest of the day it was
  // finished on (see doneToday/visible in MatrixScreen) instead of
  // vanishing the instant it's checked off. It only drops out of this list
  // for good once the day rolls over, at which point it's still reachable
  // in Completed history via the screen header. This badge counts only the
  // still-pending ones, not the already-done-today ones sitting below them.
  int get _pending => tasks.where((t) => !t.isDone).length;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    // Still-pending tasks are sorted by their manual `order` rank (see
    // MatrixNotifier.reorder) so a drag actually changes what's on screen;
    // anything finished today sinks to the bottom instead of staying mixed
    // in with what's left to do — and animates there (see
    // _AnimatedTaskStack below), sliding back up to its old spot in that
    // same order the moment it's unchecked.
    final active = tasks.where((t) => !t.isDone).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final done = tasks.where((t) => t.isDone).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final ordered = [...active, ...done];
    // A dedicated drag-handle icon on each tile (see _TaskTile) is the only
    // thing that starts a drag, so this target never fights the card's own
    // tap/long-press/swipe handling.
    return DragTarget<String>(
      // Only steps in when this quadrant is empty — once it has rows of
      // its own, each row (and the "add another" row) is its own drop
      // target below, and letting both accept the same drop would fire
      // onReorder twice for a single gesture.
      onWillAcceptWithDetails: (details) => tasks.isEmpty,
      onAcceptWithDetails: (details) =>
          onReorder(details.data, quadrant, null),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isHovering ? color : gp.border,
            width: isHovering ? 2 : 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              border: Border(
                  bottom: BorderSide(
                      color: color.withOpacity(0.15), width: 0.5)),
            ),
            child: Row(
              children: [
                // The label/dot/badge area is its own tap target for
                // "expand" — deliberately most of the header's width, so
                // this reads as the generous "tap this quadrant to see it
                // clearly" spot the whole header used to be for "add,"
                // rather than something you have to aim for. The two icon
                // buttons to its right get first pick of any touch that
                // actually lands on them.
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
                      onTap: onExpand,
                      onLongPress: onEditQuadrant,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: color, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                title,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                    // Letter-spacing disconnects Arabic
                                    // glyphs (the script is cursive/joined)
                                    // — only the Latin small-caps label
                                    // wants that look.
                                    letterSpacing: isAr ? 0 : 0.8),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_pending > 0) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
                                ),
                                child: Text('$_pending',
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: color)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                _HeaderIconButton(
                  icon: Icons.open_in_full_rounded,
                  color: color,
                  tooltip: s.matrixExpandQuadrant,
                  onTap: onExpand,
                ),
                const SizedBox(width: 4),
                _HeaderIconButton(
                  icon: Icons.add_rounded,
                  color: color,
                  onTap: onAddTapped,
                ),
              ],
            ),
          ),
          Expanded(
            // Longer than the tile's own 380ms completion pop (see
            // _TaskTileState._spring) so a just-finished task's checkmark
            // animation gets to actually play before this crossfades the
            // whole list down to one fewer row.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              // AnimatedSwitcher's default layoutBuilder stacks children
              // with Alignment.center — fine when a child fills the space,
              // but a short task list (or the list content inside the
              // scroll view) doesn't, so it was floating dead-centered in
              // the quadrant instead of starting at the top. Pin it to the
              // top instead; the empty state still centers itself
              // internally, so it's unaffected.
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.topCenter,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              child: tasks.isEmpty
                ? _EmptyQuadrantBody(
                    key: const ValueKey('empty'),
                    color: color,
                    onTap: onAddTapped,
                  )
                // Keyed on a stable constant, not on the task ids — this key
                // only needs to change when AnimatedSwitcher should actually
                // crossfade (switching between the empty state above and this
                // list). Keying it on the joined ids meant every single
                // toggle/add/delete re-faded the *entire* list instead of
                // just the row that changed.
                : _AnimatedTaskStack(
                    key: const ValueKey('list'),
                    quadrant: quadrant,
                    tasks: ordered,
                    accentColor: color,
                    onToggle: onToggle,
                    onDelete: onDelete,
                    selectionMode: selectionMode,
                    selectedIds: selectedIds,
                    onSelectionToggle: onSelectionToggle,
                    onSelectionStart: onSelectionStart,
                    onMove: onMove,
                    onReorder: onReorder,
                    onToggleFav: onToggleFav,
                    onAddTapped: onAddTapped,
                    onOpenDetails: onOpenDetails,
                  ),
            ),
          ),
        ],
      ),
    );
      },
    );
  }
}
