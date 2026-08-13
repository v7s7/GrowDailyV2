part of 'quadrant_card.dart';


// ─── Header icon button ─────────────────────────────────────────────────────

/// A small, explicit icon button for the quadrant header's trailing edge
/// (expand / add) — kept deliberately compact (this header shares its
/// width with a label and a count badge, inside one cell of a 2x2 grid on
/// a phone screen) but still a real Material+InkWell hit target of its
/// own, not a bare Icon, so it's reliably tappable rather than a
/// pixel-hunt. Each caller owns its own haptic (see onAddTapped/onExpand's
/// call sites) rather than firing one here, so tapping "+" doesn't double
/// up with the haptic _showAdd already fires.
class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? tooltip;

  const _HeaderIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: color.withOpacity(0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
    return tooltip == null
        ? button
        : Tooltip(message: tooltip!, child: button);
  }
}

// ─── Animated task stack ───────────────────────────────────────────────────

// Shared by _AnimatedTaskStackState (measures each row's real height off
// this style — see _rowHeightFor) and _TaskTile (the text actually
// rendered) — QuadrantExpandedScreen's larger, bolder title style. One
// top-level constant instead of duplicating the numbers in both places, so
// they can't quietly drift apart the way the compact card's own
// _titleStyle/_TaskTile pair are already documented (see _rowHeightFor) to
// require careful manual syncing for.
const _expandedTitleStyle = TextStyle(
  fontSize: 17,
  fontWeight: FontWeight.w600,
  height: 1.25,
);

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
  // True only for QuadrantExpandedScreen's near-fullscreen view. Swaps in
  // _expandedTitleStyle (bigger, bolder) for the row-height measurement
  // and the rendered title alike — every row is still sized to its own
  // content, exactly like the compact grid, so "fixed rows" means no
  // wasted padding rather than every row being an identical height.
  // Defaults to false so the compact 2x2 QuadrantCard grid, which still
  // needs the space-hungry small/dynamic layout to fit a narrow cell, is
  // completely untouched.
  final bool expanded;

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
    this.expanded = false,
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
  // _TaskTile now renders in two rows instead of one: row 1 is just the
  // checkbox + title, row 2 (favorite/drag-handle/info[/voice-note], each
  // a 34x34 tap circle) sits underneath and only exists outside selection
  // mode. These constants mirror that row's real height/gap exactly, so
  // the height reserved here — used to absolutely-position every row in
  // the Stack below — always matches what actually renders. Letting the
  // two drift apart either clips row 2's icons or leaves dead space under
  // a short title.
  static const double _iconRowHeight = 34;
  static const double _iconRowGap = 4;
  // A little generous on purpose, same reasoning as before: a title with
  // slightly more room than it strictly needs just costs a few harmless
  // extra pixels; a little less risks measuring "fits on one line" for a
  // title that actually wraps to two, clipping text.
  static const double _oneLineTitleHeight = 17;
  // 8px top + 8px bottom tile padding — see _TaskTile's AnimatedContainer.
  static const double _tileVerticalPadding = 16;
  // The Container each row is wrapped in (see build() below) paints a
  // 1px bottom divider via BoxDecoration.border with no explicit padding
  // of its own — Container silently reserves that 1px out of *this* row's
  // own allocated height to paint the border without the row's content
  // overlapping it, rather than growing to accommodate it. Missing this
  // is exactly what caused a real "RenderFlex overflowed by 1.00 pixels"
  // in production: the old, more generous height budget always had a
  // pixel of slack to absorb it silently; this tighter one doesn't.
  static const double _dividerBorderHeight = 1;
  // Checkbox (17) + its gap to the title (9) + the tile's own 10px-a-side
  // horizontal padding (20). This used to be 175: the
  // favorite/drag-handle/info/voice-note icons lived in the *title's* row
  // too, and budgeting enough width for all four of them regularly left a
  // title under ~40px of real text width on a narrow, two-column quadrant
  // card — not enough room for even one normal word, which is exactly what
  // forced the mid-word hard-wrap this two-row layout replaced. Now that
  // those icons sit on their own row underneath (row 2, sized separately
  // above), the title only has to share its row with the checkbox.
  static const double _titleRowChromeWidth = 46;
  static const double _insertionGap = 16;
  static const _titleStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );
  // A cushion added on top of _rowHeightFor's exact TextPainter
  // measurement. Two separate "RenderFlex overflowed by 1.00 pixels" bugs
  // have now come from a row's reserved height matching its content's
  // *measured* height with zero slack (see _dividerBorderHeight above for
  // the first one) — any tiny mismatch between that measurement and what
  // the real Text widget renders (a custom font not fully loaded yet,
  // sub-pixel rounding, etc.) has nowhere to go and overflows by exactly
  // a pixel or two. A few spare pixels is invisible but absorbs that
  // drift for good, in both the compact grid and the maximized view.
  static const double _heightSafetyMargin = 3;

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

  // Measures [title] with no line cap — titles wrap to as many lines as
  // they need (see _TaskTile's Text, which renders with that same absence
  // of a cap) instead of being clipped to a guessed line count. [style]
  // must be the same style that row will actually render with (_titleStyle
  // for the compact grid, _expandedTitleStyle for the maximized view) so
  // this measurement and the real render can't disagree about how tall the
  // text is.
  double _rowHeightFor(
    BuildContext context,
    String title,
    double maxWidth,
    bool selectionMode, {
    required TextStyle style,
  }) {
    final textWidth = maxWidth - _titleRowChromeWidth;
    final tp = TextPainter(
      text: TextSpan(text: title, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: textWidth < 40 ? 40 : textWidth);
    // Row 2 (see _TaskTile.build()) only takes up real height outside
    // selection mode.
    final row2Chrome = selectionMode ? 0.0 : (_iconRowGap + _iconRowHeight);
    final fixedChrome = row2Chrome + _tileVerticalPadding + _dividerBorderHeight;
    final height = tp.size.height + fixedChrome + _heightSafetyMargin;
    final minHeight = _oneLineTitleHeight + fixedChrome;
    return height < minHeight ? minHeight : height;
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
        final rowStyle = widget.expanded ? _expandedTitleStyle : _titleStyle;
        final heights = [
          for (final t in tasks)
            _rowHeightFor(
                context, t.title, constraints.maxWidth, widget.selectionMode,
                style: rowStyle),
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
                  duration: GameMotion.standard,
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
                          duration: GameMotion.standard,
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
                          //
                          // The OverflowBox just inside ClipRect matters
                          // for the same collapse: while this row's own
                          // height above is animating from heights[i] down
                          // toward 0 (drag start) — or jumping between the
                          // selection-mode and normal heights — the actual
                          // tile content (checkbox+title row, plus the icon
                          // row underneath) doesn't get any smaller, only
                          // less visible. Without OverflowBox, _TaskTile's
                          // own Column is laid out with *that* animating
                          // height as its hard limit and throws a real
                          // RenderFlex-overflow assertion the moment the
                          // content no longer fits — even though ClipRect
                          // was always going to hide the excess anyway.
                          // Giving it heights[i] (its real, steady-state
                          // height) instead means it always has room to lay
                          // out correctly; ClipRect (unchanged) still clips
                          // whatever doesn't fit in the currently-animating
                          // box to nothing, so the visual result — a tile
                          // that smoothly shrinks away — is identical.
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: 0,
                              maxHeight: heights[i],
                              child: AnimatedOpacity(
                                duration: GameMotion.quick,
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
                                    expanded: widget.expanded,
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
                        duration: GameMotion.standard,
                        curve: Curves.easeOutCubic,
                        top: lineTop ?? 0,
                        left: 4,
                        right: 4,
                        height: 3,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            duration: GameMotion.quick,
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
