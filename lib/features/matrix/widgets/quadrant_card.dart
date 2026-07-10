import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/l10n/app_strings.dart';
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
  final void Function(String id) onToggleToday;
  final VoidCallback onAddTapped;
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
    required this.onToggleToday,
    required this.onAddTapped,
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
                    onToggleToday: onToggleToday,
                    onAddTapped: onAddTapped,
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
  final void Function(String id) onToggleToday;
  final VoidCallback onAddTapped;

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
    required this.onToggleToday,
    required this.onAddTapped,
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
  // checkbox/star/drag-handle/menu icons reserve (and so overestimating
  // row height) just costs a few harmless extra pixels of padding;
  // underestimating it risks measuring a title as "fits on one line" when
  // the real row actually wraps it to two, clipping text.
  static const double _rowChromeWidth = 130;
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

  void _setHover(String? beforeId) {
    if (!mounted || (_isHovering && _insertionBeforeId == beforeId)) return;
    setState(() {
      _isHovering = true;
      _insertionBeforeId = beforeId;
    });
  }

  void _clearHover(String? beforeId) {
    if (!mounted || !_isHovering || _insertionBeforeId != beforeId) return;
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

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                height: totalHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Do NOT chain `.animate()` (flutter_animate) onto this
                    // AnimatedPositioned, even for a harmless-looking
                    // entrance fade. `Positioned`/`AnimatedPositioned` must
                    // be a DIRECT Stack child with nothing but
                    // Stateless/Stateful widgets between it and the Stack —
                    // `.animate()` wraps it in a widget that paints its own
                    // Opacity/Transform, which sits *between* this
                    // AnimatedPositioned and the Stack. That silently
                    // breaks positioning: every row falls back to being
                    // laid out unpositioned, on top of the others, instead
                    // of at tops[i] — which is exactly the "overlapping,
                    // garbled" row bug from July 2026. If a row needs an
                    // entrance effect, animate something *inside* this
                    // subtree (e.g. wrap the Container below), never this
                    // widget itself.
                    for (var i = 0; i < tasks.length; i++)
                      AnimatedPositioned(
                        key: ValueKey(tasks[i].id),
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        top: tops[i],
                        left: 0,
                        right: 0,
                        height: tasks[i].id == _draggingId ? 0 : heights[i],
                        // Each row is its own drop target — dropping
                        // another task here means "put it right before
                        // this one," in this quadrant, regardless of
                        // which quadrant it came from. Clipped so a
                        // collapsing row's content shrinks cleanly rather
                        // than overflowing its shrinking box.
                        child: ClipRect(
                          child: DragTarget<String>(
                            onWillAcceptWithDetails: (details) =>
                                details.data != tasks[i].id,
                            onMove: (details) => _setHover(tasks[i].id),
                            onLeave: (data) => _clearHover(tasks[i].id),
                            onAcceptWithDetails: (details) {
                              _endDrag();
                              widget.onReorder(
                                  details.data, widget.quadrant, tasks[i].id);
                            },
                            builder: (context, candidateData, rejectedData) {
                              return AnimatedOpacity(
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
                                    onToggleToday: () =>
                                        widget.onToggleToday(tasks[i].id),
                                    onDragStart: () =>
                                        _beginDrag(tasks[i].id),
                                    onDragEnd: _endDrag,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    // Insertion line — marks exactly where a dropped task
                    // will land, instead of tinting a whole existing row.
                    // Explicitly keyed (unlike relying on list position) so
                    // it's never confused with one of the per-task
                    // AnimatedPositioned entries above as tasks.length
                    // changes and shifts everyone's position in this list.
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
              // Dropping on the trailing "add another" row means "put it
              // last" — same as dropping on empty space used to.
              DragTarget<String>(
                onWillAcceptWithDetails: (details) => true,
                onMove: (details) => _setHover(null),
                onLeave: (data) => _clearHover(null),
                onAcceptWithDetails: (details) {
                  _endDrag();
                  widget.onReorder(details.data, widget.quadrant, null);
                },
                builder: (context, candidateData, rejectedData) =>
                    _AddAnotherRow(
                        color: widget.accentColor,
                        onTap: widget.onAddTapped),
              ),
            ],
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
  final VoidCallback onToggleToday;
  // Bubble a drag's start/end up to the enclosing list, which uses them to
  // collapse this row out of the way while it's the one being dragged
  // (see _AnimatedTaskStackState._draggingId).
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

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
    required this.onToggleToday,
    this.onDragStart,
    this.onDragEnd,
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
              // Flags this task for the Today filter — a plain bool, not a
              // due date, so it's one tap and never opens a picker. Hidden
              // in selection mode along with drag/move, same as those.
              if (!widget.selectionMode)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onToggleToday();
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      widget.task.isToday
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 16,
                      color: widget.task.isToday
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
                  onTap: () => _showTaskActions(context),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.more_vert_rounded,
                        size: 16, color: gp.textTert),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTaskActions(BuildContext context) {
    final others =
        MatrixQuadrant.values.where((q) => q != widget.task.quadrant).toList();
    final isAr = S.of(context).isAr;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final mgp = ctx.gp;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Container(
            decoration: BoxDecoration(
              color: mgp.surfaceHigh,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: mgp.border, width: 0.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 4),
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                        color: mgp.border,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionRow(
                        icon: Icons.delete_outline_rounded,
                        iconColor: GameColors.error,
                        label: S.of(context).matrixDeleteTask,
                        labelColor: GameColors.error,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onDelete();
                        },
                      ),
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            S.of(context).matrixMoveToQuadrant,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: mgp.textTert,
                              // Letter-spacing disconnects Arabic glyphs
                              // (the script is cursive/joined) — only the
                              // Latin small-caps label wants that look.
                              letterSpacing: isAr ? 0 : 1.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...others.map((q) => Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: _ActionRow(
                              dotColor: _colorFor(q),
                              label: q.localLabel(isAr),
                              subtitle: q.localSubtitle(isAr),
                              onTap: () {
                                Navigator.pop(context);
                                widget.onMove(q);
                              },
                            ),
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _colorFor(MatrixQuadrant q) => switch (q) {
        MatrixQuadrant.doFirst => GameColors.error,
        MatrixQuadrant.schedule => GameColors.xpBlue,
        MatrixQuadrant.delegate => GameColors.streakOrange,
        MatrixQuadrant.eliminate => GameColors.textTertiary,
      };
}

// ─── Action sheet row ─────────────────────────────────────────────────────────

/// One tappable row in the task action sheet — either the "Delete" action
/// (an icon in a tinted circle) or a "move to quadrant" option (a small
/// colored dot standing in for that quadrant's chip color). Both share the
/// same tinted-card treatment so the sheet reads as a set of modern,
/// generously-spaced options instead of a cramped classic menu.
class _ActionRow extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final Color? dotColor;
  final String label;
  final String? subtitle;
  final Color? labelColor;
  final VoidCallback onTap;

  const _ActionRow({
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
