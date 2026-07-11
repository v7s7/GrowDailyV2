import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/voice_note_service.dart';
import '../../../core/theme/game_theme.dart';
import '../models/matrix_task.dart';

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
  });

  Color get _color => switch (quadrant) {
        MatrixQuadrant.doFirst => GameColors.error,
        MatrixQuadrant.schedule => GameColors.xpBlue,
        MatrixQuadrant.delegate => GameColors.streakOrange,
        MatrixQuadrant.eliminate => GameColors.textTertiary,
      };

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
    final isAr = S.of(context).isAr;
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
            color: isHovering ? _color : gp.border,
            width: isHovering ? 2 : 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: _color.withOpacity(0.1),
            child: InkWell(
              onTap: onAddTapped,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: _color.withOpacity(0.15), width: 0.5)),
                ),
                child: Row(
                  children: [
                    Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            color: _color, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        quadrant.localLabel(isAr),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _color,
                            // Letter-spacing disconnects Arabic glyphs (the
                            // script is cursive/joined) — only the Latin
                            // small-caps label wants that look.
                            letterSpacing: isAr ? 0 : 0.8),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_pending > 0) ...[const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: _color.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text('$_pending',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: _color)),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Icon(Icons.add_rounded, size: 14, color: _color),
                  ],
                ),
              ),
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
                    color: _color,
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
                    accentColor: _color,
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

// ─── Animated task stack ───────────────────────────────────────────────────

/// Renders [tasks] (already ordered: still-pending first, anything finished
/// today sunk to the bottom) as a scrollable stack of fixed-height rows,
/// each positioned purely by its index in that order. A row's position is
/// just "whatever index this task currently has" — so checking a task off
/// (or undoing that) changes its index on the very next build, and
/// AnimatedPositioned smoothly slides it, plus everything that shifts to
/// fill the gap it left, to their new spots instead of the list silently
/// re-sorting itself with no visible motion.
class _AnimatedTaskStack extends StatefulWidget {
  final MatrixQuadrant quadrant;
  final List<MatrixTask> tasks;
  final Color accentColor;
  final void Function(String id) onToggle;
  final void Function(String id) onDelete;
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(String id) onSelectionToggle;
  final void Function(String id) onSelectionStart;
  final void Function(String id, MatrixQuadrant q) onMove;
  final void Function(String id, MatrixQuadrant q, String? beforeId)
      onReorder;
  final void Function(String id) onToggleFav;
  final VoidCallback onAddTapped;
  final void Function(MatrixTask task) onOpenDetails;

  const _AnimatedTaskStack({
    super.key,
    required this.quadrant,
    required this.tasks,
    required this.accentColor,
    required this.onToggle,
    required this.onDelete,
    required this.selectionMode,
    required this.selectedIds,
    required this.onSelectionToggle,
    required this.onSelectionStart,
    required this.onMove,
    required this.onReorder,
    required this.onToggleFav,
    required this.onAddTapped,
    required this.onOpenDetails,
  });

  @override
  State<_AnimatedTaskStack> createState() => _AnimatedTaskStackState();
}

/// Owns two purely-visual, ephemeral pieces of state that never touch real
/// task data: which row (if any) a drag is currently hovering over in
/// *this* quadrant, and whether one of *this* quadrant's own tasks is the
/// one currently being dragged. Both reset the moment a drag ends, however
/// it ends — nothing here is written anywhere until onReorder actually
/// fires on drop.
class _AnimatedTaskStackState extends State<_AnimatedTaskStack> {
  static const double _minRowHeight = 40;
  // A little generous on purpose: overestimating how much width the row's
  // checkbox/play-note/star/drag-handle/menu icons reserve (and so
  // overestimating row height) just costs a few harmless extra pixels of
  // padding; underestimating it risks measuring a title as "fits on one
  // line" when the real row actually wraps it to two, clipping text. Bumped
  // from 130 when the voice-note play icon was added — it's not always
  // present, but this budget has to cover the widest row, which now
  // sometimes includes it.
  static const double _rowChromeWidth = 155;
  static const double _insertionGap = 16;
  static const _titleStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  bool _isHovering = false;
  // Meaningful only while _isHovering is true: which task a drop would
  // land in front of, or null meaning "at the end."
  String? _insertionBeforeId;
  // Id of this quadrant's own task currently being dragged, if any —
  // collapses its row here while its floating preview follows the drag
  // elsewhere (possibly into another quadrant entirely).
  String? _draggingId;
  // Keys the Stack that lays out every row (see build()) — used to convert
  // a drag's raw global pointer position into a Y offset within that
  // Stack's own coordinate space, which is what nearestBeforeId compares
  // against tops[]/heights[]. One stable key for the widget's lifetime,
  // not recreated per build.
  final _stackKey = GlobalKey();

  double _rowHeightFor(BuildContext context, String title, double maxWidth) {
    final textWidth = maxWidth - _rowChromeWidth;
    final tp = TextPainter(
      text: TextSpan(text: title, style: _titleStyle),
      maxLines: 2,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: textWidth < 40 ? 40 : textWidth);
    final height = tp.size.height + 16; // 8px top + 8px bottom padding
    return height < _minRowHeight ? _minRowHeight : height;
  }

  void _beginDrag(String id) {
    if (!mounted) return;
    setState(() => _draggingId = id);
  }

  void _endDrag() {
    if (!mounted) return;
    setState(() {
      _draggingId = null;
      _isHovering = false;
      _insertionBeforeId = null;
    });
  }

  void _clearHover() {
    if (!mounted || !_isHovering) return;
    setState(() {
      _isHovering = false;
      _insertionBeforeId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final tasks = widget.tasks;
    return LayoutBuilder(
      builder: (context, constraints) {
        final heights = [
          for (final t in tasks)
            _rowHeightFor(context, t.title, constraints.maxWidth),
        ];

        int? insertionIndex;
        if (_isHovering) {
          insertionIndex = _insertionBeforeId == null
              ? tasks.length
              : tasks.indexWhere((t) => t.id == _insertionBeforeId);
          if (insertionIndex == -1) insertionIndex = tasks.length;
        }

        // A single forward pass computes every row's top offset *and* the
        // insertion line's position together: a row being dragged away
        // contributes zero height (it's collapsed), and the hovered gap
        // (if any) opens up exactly where it's about to land — so
        // everything else visibly slides to make room before you've even
        // let go.
        final tops = <double>[];
        var cursor = 0.0;
        double? lineTop;
        for (var i = 0; i < tasks.length; i++) {
          if (insertionIndex == i) {
            lineTop = cursor + _insertionGap / 2 - 1.5;
            cursor += _insertionGap;
          }
          tops.add(cursor);
          cursor += tasks[i].id == _draggingId ? 0 : heights[i];
        }
        if (insertionIndex == tasks.length) {
          lineTop = cursor + _insertionGap / 2 - 1.5;
          cursor += _insertionGap;
        }
        final totalHeight = cursor;

        // Nearest-row-midpoint lookup, shared by onMove (continuous hover
        // feedback below) and onAcceptWithDetails (the actual drop): given
        // a Y position within the Stack's own coordinate space, which task
        // should the drop land in front of. Skips the row currently being
        // dragged — it's collapsed to zero height, so its "midpoint" is a
        // single point rather than a meaningful landing zone.
        String? nearestBeforeId(double localY) {
          for (var i = 0; i < tasks.length; i++) {
            if (tasks[i].id == _draggingId) continue;
            if (localY < tops[i] + heights[i] / 2) return tasks[i].id;
          }
          return null;
        }

        void updateHover(Offset globalOffset) {
          final box = _stackKey.currentContext?.findRenderObject();
          if (box is! RenderBox || !box.attached) return;
          final beforeId =
              nearestBeforeId(box.globalToLocal(globalOffset).dy);
          if (_isHovering && _insertionBeforeId == beforeId) return;
          if (!mounted) return;
          HapticFeedback.selectionClick();
          setState(() {
            _isHovering = true;
            _insertionBeforeId = beforeId;
          });
        }

        // One drop target for the whole quadrant, instead of a separate
        // tiny DragTarget per row. The old per-row version meant a release
        // had to land inside one specific row's exact strip — and the gap
        // between rows, exactly where the insertion-line indicator tells
        // you to drop, wasn't part of *any* row's hit area, so the most
        // obvious spot to release was also the one most likely to silently
        // do nothing. Tracking the raw pointer position instead and
        // snapping to the nearest row midpoint (nearestBeforeId above)
        // means any release anywhere in the quadrant lands somewhere
        // sensible, and the insertion line always matches where a drop
        // will actually go.
        return DragTarget<String>(
          onWillAcceptWithDetails: (details) => true,
          onMove: (details) => updateHover(details.offset),
          onLeave: (data) => _clearHover(),
          onAcceptWithDetails: (details) {
            final box = _stackKey.currentContext?.findRenderObject();
            final beforeId = (box is RenderBox && box.attached)
                ? nearestBeforeId(box.globalToLocal(details.offset).dy)
                : _insertionBeforeId;
            _endDrag();
            widget.onReorder(details.data, widget.quadrant, beforeId);
          },
          builder: (context, candidateData, rejectedData) =>
              SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  key: _stackKey,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  height: totalHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Do NOT chain `.animate()` (flutter_animate) onto
                      // this AnimatedPositioned, even for a
                      // harmless-looking entrance fade.
                      // `Positioned`/`AnimatedPositioned` must be a DIRECT
                      // Stack child with nothing but Stateless/Stateful
                      // widgets between it and the Stack — `.animate()`
                      // wraps it in a widget that paints its own
                      // Opacity/Transform, which sits *between* this
                      // AnimatedPositioned and the Stack. That silently
                      // breaks positioning: every row falls back to being
                      // laid out unpositioned, on top of the others,
                      // instead of at tops[i] — which is exactly the
                      // "overlapping, garbled" row bug from July 2026. If a
                      // row needs an entrance effect, animate something
                      // *inside* this subtree (e.g. wrap the Container
                      // below), never this widget itself.
                      for (var i = 0; i < tasks.length; i++)
                        AnimatedPositioned(
                          key: ValueKey(tasks[i].id),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          top: tops[i],
                          left: 0,
                          right: 0,
                          height:
                              tasks[i].id == _draggingId ? 0 : heights[i],
                          // Clipped so a collapsing row's content shrinks
                          // cleanly rather than overflowing its shrinking
                          // box. No per-row DragTarget anymore — the whole
                          // quadrant is one drop target now (see above),
                          // so this is just a plain positioned tile.
                          child: ClipRect(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 160),
                              opacity: tasks[i].id == _draggingId ? 0 : 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                        color: gp.divider, width: 1),
                                  ),
                                ),
                                child: _TaskTile(
                                  task: tasks[i],
                                  accentColor: widget.accentColor,
                                  onToggle: () =>
                                      widget.onToggle(tasks[i].id),
                                  onDelete: () =>
                                      widget.onDelete(tasks[i].id),
                                  selectionMode: widget.selectionMode,
                                  selected: widget.selectedIds
                                      .contains(tasks[i].id),
                                  onSelectionToggle: () => widget
                                      .onSelectionToggle(tasks[i].id),
                                  onSelectionStart: () => widget
                                      .onSelectionStart(tasks[i].id),
                                  onMove: (q) =>
                                      widget.onMove(tasks[i].id, q),
                                  onToggleFav: () =>
                                      widget.onToggleFav(tasks[i].id),
                                  onDragStart: () =>
                                      _beginDrag(tasks[i].id),
                                  onDragEnd: _endDrag,
                                  onOpenDetails: () =>
                                      widget.onOpenDetails(tasks[i]),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Insertion line — marks exactly where a dropped task
                      // will land, instead of tinting a whole existing row.
                      // Explicitly keyed (unlike relying on list position)
                      // so it's never confused with one of the per-task
                      // AnimatedPositioned entries above as tasks.length
                      // changes and shifts everyone's position in this
                      // list.
                      AnimatedPositioned(
                        key: const ValueKey('insertion-line'),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        top: lineTop ?? 0,
                        left: 4,
                        right: 4,
                        height: 3,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: _isHovering ? 1 : 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: widget.accentColor,
                                borderRadius: BorderRadius.circular(2),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        widget.accentColor.withOpacity(0.5),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Dropping past the last row — including on this "add
                // another" row, or any blank space below it — means "put
                // it last": nearestBeforeId returns null once the pointer
                // is past every row's midpoint, same as it always meant.
                _AddAnotherRow(
                    color: widget.accentColor, onTap: widget.onAddTapped),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Empty quadrant body ──────────────────────────────────────────────────────

/// The whole square is the tap target — not just the tiny + icon in the
/// header — so a blank quadrant never means hunting for a small icon.
class _EmptyQuadrantBody extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _EmptyQuadrantBody({
    super.key,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add_rounded, size: 16, color: color),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(
                      begin: 0.9,
                      end: 1.06,
                      duration: 1100.ms,
                      curve: Curves.easeInOut),
              const SizedBox(height: 4),
              Text(s.matrixTapToAdd,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10,
                      color: gp.textTert,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Add-another row (populated quadrants) ────────────────────────────────────

/// A persistent, generously-sized "add" affordance at the end of a
/// populated quadrant's list, so adding a second or third goal never means
/// hunting for the small + icon back up in the header.
class _AddAnotherRow extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _AddAnotherRow({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Text(
            s.matrixAddAnother,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ),
    );
  }
}

// ─── Task Tile ───────────────────────────────────────────────────────────────

class _TaskTile extends StatefulWidget {
  final MatrixTask task;
  final Color accentColor;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelectionToggle;
  final VoidCallback onSelectionStart;
  final void Function(MatrixQuadrant) onMove;
  final VoidCallback onToggleFav;
  // Bubble a drag's start/end up to the enclosing list, which uses them to
  // collapse this row out of the way while it's the one being dragged
  // (see _AnimatedTaskStackState._draggingId).
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  // Pencil icon — opens TaskDetailSheet for this row's task.
  final VoidCallback onOpenDetails;

  const _TaskTile({
    super.key,
    required this.task,
    required this.accentColor,
    required this.onToggle,
    required this.onDelete,
    required this.selectionMode,
    required this.selected,
    required this.onSelectionToggle,
    required this.onSelectionStart,
    required this.onMove,
    required this.onToggleFav,
    this.onDragStart,
    this.onDragEnd,
    required this.onOpenDetails,
  });

  @override
  State<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<_TaskTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring;
  late final Animation<double> _scale;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.35)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 30),
      TweenSequenceItem(
          tween: Tween(begin: 1.35, end: 0.88)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 20),
      TweenSequenceItem(
          tween: Tween(begin: 0.88, end: 1.0)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 50),
    ]).animate(_spring);
  }

  @override
  void dispose() {
    _spring.dispose();
    // Only ever true for the one row that was actually playing — leaving
    // this row's tree (deleted, or the screen it's on going away entirely)
    // shouldn't leave its voice note still audibly playing from a tile
    // that no longer exists.
    if (VoiceNoteService.instance.currentlyPlayingTaskId.value ==
        widget.task.id) {
      VoiceNoteService.instance.stopPlayback().ignore();
    }
    super.dispose();
  }

  void _handleTap() {
    if (widget.selectionMode) {
      widget.onSelectionToggle();
      return;
    }
    _spring.forward(from: 0.0);
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Dismissible(
      key: ValueKey('dismiss-${widget.task.id}'),
      direction: widget.selectionMode ? DismissDirection.none : DismissDirection.endToStart,
      onDismissed: (_) => widget.onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          color: GameColors.error.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: GameColors.error, size: 16),
      ),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          _handleTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          widget.onSelectionStart();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          color: _pressed ? gp.surfaceHL.withOpacity(0.7) : Colors.transparent,
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _scale,
                builder: (_, __) => Transform.scale(
                  scale: _spring.isAnimating ? _scale.value : 1.0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.selectionMode
                          ? (widget.selected ? GameColors.gold : Colors.transparent)
                          : widget.task.isDone
                              ? widget.accentColor
                              : Colors.transparent,
                      border: Border.all(
                        color: widget.selectionMode
                            ? (widget.selected ? GameColors.gold : gp.border)
                            : widget.task.isDone
                                ? widget.accentColor
                                : gp.border,
                        width: 1.5,
                      ),
                      boxShadow: widget.selected || widget.task.isDone
                          ? [
                              BoxShadow(
                                color: (widget.selected
                                        ? GameColors.gold
                                        : widget.accentColor)
                                    .withOpacity(0.35),
                                blurRadius: 6,
                              )
                            ]
                          : null,
                    ),
                    child: widget.selectionMode
                        ? (widget.selected
                            ? const Icon(Icons.check_rounded,
                                size: 10, color: Colors.black)
                            : null)
                        : widget.task.isDone
                            ? const Icon(Icons.check_rounded,
                                size: 10, color: Colors.black)
                            : null,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    color: widget.task.isDone ? gp.textTert : gp.textPrimary,
                    decoration: widget.task.isDone
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    decorationColor: gp.textTert,
                  ),
                  child: Text(widget.task.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ),
              if (!widget.selectionMode && widget.task.voiceNotePath != null)
                VoiceNotePlayButton(
                  taskId: widget.task.id,
                  path: widget.task.voiceNotePath!,
                  color: widget.accentColor,
                ),
              // Flags this task as a favorite — a plain, sticky bool, not a
              // due date, so it's one tap and never opens a picker, and it
              // never expires on its own. Hidden in selection mode along
              // with drag/move, same as those.
              if (!widget.selectionMode)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onToggleFav();
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      widget.task.isFav
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 16,
                      color: widget.task.isFav
                          ? GameColors.gold
                          : gp.textTert.withOpacity(0.6),
                    ),
                  ),
                ),
              // Dragging is scoped to this small handle rather than the
              // whole tile so it never fights the row's own long-press
              // (which starts multi-select) or its swipe-to-delete.
              if (!widget.selectionMode)
                LongPressDraggable<String>(
                  data: widget.task.id,
                  // Default long-press-to-drag takes 500ms, which reads as
                  // sluggish for something you want to reorder quickly and
                  // often — a third of that is still deliberate enough to
                  // not fire on an ordinary tap.
                  delay: const Duration(milliseconds: 150),
                  onDragStarted: () {
                    HapticFeedback.mediumImpact();
                    widget.onDragStart?.call();
                  },
                  onDragEnd: (_) => widget.onDragEnd?.call(),
                  feedback: Material(
                    color: Colors.transparent,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: gp.surfaceHigh,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: widget.accentColor, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Text(widget.task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: gp.textPrimary)),
                      ),
                    ),
                  ),
                  childWhenDragging: Icon(Icons.drag_indicator_rounded,
                      size: 16, color: gp.textTert.withOpacity(0.25)),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.drag_indicator_rounded,
                        size: 16, color: gp.textTert.withOpacity(0.6)),
                  ),
                ),
              if (!widget.selectionMode)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onOpenDetails,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.edit_outlined,
                        size: 15, color: gp.textTert),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Delete/Move-to-quadrant used to live in a "..." menu opened from here
  // (_showTaskActions) — now part of TaskDetailSheet instead, opened via
  // the pencil icon above, so this row only ever carries one icon for
  // "more about this task" instead of two.
}

// ─── Voice note play button ────────────────────────────────────────────────

/// Compact play/stop toggle for a task's attached voice note. Reactive via
/// ValueListenableBuilder rather than Riverpod — this whole file is plain
/// callback-driven widgets with no `ref` anywhere, and VoiceNoteService is a
/// bare singleton in the same style as NotificationService, not a provider.
/// Every row with a voice note listens to the same
/// currentlyPlayingTaskId, so exactly one of them ever shows the "playing"
/// state, however many rows are on screen. Public (no leading underscore)
/// so TaskDetailSheet can reuse it too, for the same note's playback pill
/// there.
class VoiceNotePlayButton extends StatelessWidget {
  final String taskId;
  final String path;
  final Color color;

  const VoiceNotePlayButton({
    required this.taskId,
    required this.path,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: VoiceNoteService.instance.currentlyPlayingTaskId,
      builder: (context, playingId, _) {
        final playing = playingId == taskId;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            VoiceNoteService.instance.togglePlayback(taskId, path);
          },
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(
              playing
                  ? Icons.stop_circle_rounded
                  : Icons.play_circle_fill_rounded,
              size: 17,
              color: playing ? color : color.withOpacity(0.7),
            ),
          ),
        );
      },
    );
  }
}

// ─── Action sheet row ─────────────────────────────────────────────────────────

/// One tappable row in a task action sheet — either the "Delete" action
/// (an icon in a tinted circle) or a "move to quadrant" option (a small
/// colored dot standing in for that quadrant's chip color). Both share the
/// same tinted-card treatment so the sheet reads as a set of modern,
/// generously-spaced options instead of a cramped classic menu. Public so
/// TaskDetailSheet can reuse it for its own Delete/Move rows instead of
/// duplicating this styling.
class ActionRow extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final Color? dotColor;
  final String label;
  final String? subtitle;
  final Color? labelColor;
  final VoidCallback onTap;

  const ActionRow({
    this.icon,
    this.iconColor,
    this.dotColor,
    required this.label,
    this.subtitle,
    this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final tint = iconColor ?? dotColor ?? GameColors.gold;
    return Material(
      color: tint.withOpacity(0.07),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint.withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
                child: icon != null
                    ? Icon(icon, size: 17, color: iconColor)
                    : Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                            color: dotColor, shape: BoxShape.circle),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: labelColor ?? gp.textPrimary)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: TextStyle(fontSize: 11.5, color: gp.textSec)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
