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
                      borderRadius: BorderRadius.circular(8),
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
                                  borderRadius: BorderRadius.circular(100),
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
  // True only inside QuadrantExpandedScreen — swaps the title to
  // _expandedTitleStyle (bigger, bolder) instead of the compact grid's
  // small inline style. See _AnimatedTaskStack.expanded's doc comment.
  final bool expanded;
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
    required this.expanded,
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
    // Playback is intentionally NOT stopped here anymore — the floating
    // global player (docked above GameNavBar) is designed to survive
    // exactly this: a tile going away, a quadrant re-filtering, the whole
    // Matrix screen being left. See VoiceNoteService.stopPlayback's doc
    // comment.
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
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
                              ? (widget.selected
                                  ? GameColors.gold
                                  : Colors.transparent)
                              : widget.task.isDone
                                  ? widget.accentColor
                                  : Colors.transparent,
                          border: Border.all(
                            color: widget.selectionMode
                                ? (widget.selected
                                    ? GameColors.gold
                                    : gp.border)
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
                      style: (widget.expanded
                              ? _expandedTitleStyle
                              : const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ))
                          .copyWith(
                        color:
                            widget.task.isDone ? gp.textTert : gp.textPrimary,
                        decoration: widget.task.isDone
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: gp.textTert,
                      ),
                      // No maxLines/overflow cap — the title wraps to as
                      // many lines as it needs (see _rowHeightFor, which
                      // reserves exactly that much space) instead of being
                      // clipped with an ellipsis.
                      child: Text(widget.task.title),
                    ),
                  ),
                ],
              ),
              // Row 2: everything that isn't the title gets its own strip
              // underneath instead of squeezing into the title's row.
              // Cramming checkbox+title+4-icons into one Row caused two
              // problems: the title's Expanded routinely had under ~40px
              // of real width left on a narrow, two-column quadrant card
              // (forcing an unreadable mid-word wrap), and each icon's tap
              // target was squeezed to a ~32x26 box — small enough that a
              // slightly-off tap missed it and fell through to the row's
              // own tap-to-complete instead. Giving the title a whole row
              // to itself fixes the first; giving these icons their own
              // row — with room for a real 34x34 tap circle each, matching
              // ActionRow's precedent elsewhere in the app — fixes the
              // second. Kept in sync with
              // _AnimatedTaskStackState._rowHeightFor, which reserves
              // exactly this much extra height whenever this row renders.
              if (!widget.selectionMode) ...[
                const SizedBox(height: 4),
                // Every icon gets an equal Expanded share of the row's
                // *full* width (33% each for 3, 25% each for 4 with a
                // voice note) instead of a fixed-width circle clustered to
                // one side — the tap target is the whole cell, not just
                // the small circle drawn in its middle, so there's far
                // more margin for error than before and the row actually
                // uses the space it was given instead of leaving most of
                // it empty.
                Row(
                  children: [
                    if (widget.task.voiceNotes.isNotEmpty) ...[
                      Expanded(
                        child: _VoiceNoteIndicator(
                          notes: widget.task.voiceNotes,
                          color: widget.accentColor,
                          onOpenDetails: widget.onOpenDetails,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Flags this task as a favorite — a plain, sticky
                    // bool, not a due date, so it's one tap and never
                    // opens a picker, and it never expires on its own.
                    Expanded(
                      child: _TileIconButton(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onToggleFav();
                        },
                        icon: widget.task.isFav
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        iconColor: widget.task.isFav
                            ? GameColors.gold
                            : gp.textTert,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Dragging is scoped to this small handle rather than
                    // the whole tile so it never fights the row's own
                    // long-press (which starts multi-select) or its
                    // swipe-to-delete.
                    Expanded(
                      child: LongPressDraggable<String>(
                        data: widget.task.id,
                        // Default long-press-to-drag takes 500ms, which
                        // reads as sluggish for something you want to
                        // reorder quickly and often — a third of that is
                        // still deliberate enough to not fire on an
                        // ordinary tap.
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
                        childWhenDragging: Center(
                          child: Icon(Icons.drag_indicator_rounded,
                              size: 18,
                              color: gp.textTert.withOpacity(0.25)),
                        ),
                        // This icon only *does* something on a long-press
                        // (the drag itself, via LongPressDraggable above)
                        // — a quick tap has no action of its own. Without
                        // a recognizer of its own to claim that quick
                        // tap, it fell straight through to the row's own
                        // tap-to-complete, so grazing the drag handle
                        // silently checked the task off — so it gets
                        // both: a real tap target, and a no-op tap that
                        // simply absorbs the touch instead of leaking
                        // through.
                        child: _TileIconButton(
                          onTap: () {},
                          icon: Icons.drag_indicator_rounded,
                          iconColor: gp.textTert,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Was a pencil — but tapping this opens
                    // TaskDetailSheet (title, description, voice note,
                    // Delete/Move), which is a details view first and an
                    // edit surface second. An outline info glyph matches
                    // what it actually does better than an "edit" pencil
                    // does.
                    Expanded(
                      child: _TileIconButton(
                        onTap: widget.onOpenDetails,
                        icon: Icons.info_outline_rounded,
                        iconColor: gp.textTert,
                      ),
                    ),
                  ],
                ),
              ],
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

/// A real, generously-sized tap target for one of row 2's icon buttons
/// (favorite/drag-handle/info) — a filled 34x34 circle (matching
/// ActionRow's precedent elsewhere in the app) instead of a bare glyph, so
/// the visible boundary and the actual hit box are the same size and a
/// thumb doesn't have to land pixel-perfectly on a 16px icon to register.
class _TileIconButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _TileIconButton({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // Center fills whatever width its parent gives it (a whole 1/3 or
      // 1/4 of the row when wrapped in Expanded — see _TaskTile.build())
      // and, since the GestureDetector above is opaque, that entire
      // filled area is tappable — not just the small 34x34 circle drawn
      // in the middle of it, which stays fixed-size purely for a compact,
      // uncluttered look.
      child: Center(
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: gp.textTert.withOpacity(0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: iconColor),
        ),
      ),
    );
  }
}

// ─── Voice note indicator ──────────────────────────────────────────────────

/// Compact row-2 icon for this task's recordings — a real play/pause
/// button (the exact same look-and-feel as each row's button inside
/// TaskDetailSheet's recordings list — see VoiceNoteRow in
/// voice_note_player.dart), not just a status glyph, so hearing a quick
/// recap never requires opening the details sheet first. Tapping surfaces
/// the same floating global player every other play button in the app
/// does (VoiceNoteService.play → GlobalVoiceNotePlayerOverlay) — nothing
/// extra to wire up here.
///
/// Only unambiguous when there's exactly one recording, so that's the only
/// time a tap plays anything directly. With more than one (see the count
/// badge), there's no single note a tap here could mean — so it opens
/// TaskDetailSheet's full list instead, same destination as the info icon
/// next to it, where each one has its own play button.
class _VoiceNoteIndicator extends StatelessWidget {
  final List<VoiceNote> notes;
  final Color color;
  final VoidCallback onOpenDetails;

  const _VoiceNoteIndicator({
    required this.notes,
    required this.color,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final first = notes.first;
    final s = S.of(context);
    final displayName =
        first.name.isNotEmpty ? first.name : s.voiceNoteDefaultName(1);
    final svc = VoiceNoteService.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([svc.nowPlaying, svc.isPlaying]),
      builder: (context, _) {
        final nowPlayingId = svc.nowPlaying.value?.noteId;
        final active =
            nowPlayingId != null && notes.any((n) => n.id == nowPlayingId);
        final playing = active && svc.isPlaying.value;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            if (notes.length > 1) {
              onOpenDetails();
              return;
            }
            svc.togglePlayback(
              first.id,
              first.path,
              title: displayName,
              color: color,
              durationSeconds: first.durationSeconds,
              audioBase64: first.audioBase64,
            );
          },
          // Same fill-the-cell-but-draw-a-small-circle treatment as
          // _TileIconButton (its neighbors in row 2) — Center expands to
          // whatever width Expanded gives this in _TaskTile.build(), so
          // the whole cell is tappable, not just the 34x34 circle.
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(playing ? 0.2 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 16,
                    color: color,
                  ),
                  if (notes.length > 1)
                    Positioned(
                      top: -7,
                      right: -11,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          '${notes.length}',
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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

// ─── Expanded (near-fullscreen) quadrant view ──────────────────────────────

/// Pushed when a quadrant's header — or its new expand icon — is tapped
/// (see MatrixScreen._openQuadrantExpanded). The same task-list rendering
/// [_AnimatedTaskStack]/[_EmptyQuadrantBody] already do, just given the
/// whole screen instead of one cell of a cramped 2x2 grid: titles that
/// would truncate or wrap awkwardly at half-width get real room, and every
/// row's tap targets end up noticeably larger — directly the "read
/// clearly, see the buttons clearly" ask this screen exists for.
///
/// A ConsumerWidget that watches [matrixProvider] itself, rather than
/// receiving a fixed task list via constructor the way [QuadrantCard]
/// does — completing a task, adding one, or moving one out of this
/// quadrant while this screen is open all show up immediately instead of
/// leaving it stuck on a stale snapshot from the moment it was opened.
///
/// Deliberately doesn't support multi-select: MatrixScreen's selection
/// state lives on the previous, now-offstage route with no live link back
/// to this one, so trying to reflect it here would mean a selection UI
/// that can silently drift out of sync. Selecting/bulk-deleting stays a
/// compact-grid-only action; this screen is about reading clearly and
/// acting on one task at a time.
class QuadrantExpandedScreen extends ConsumerWidget {
  final MatrixQuadrant quadrant;
  // Same Today/Fav/All + carried-over lens MatrixScreen's own body is
  // currently showing (see MatrixScreen._isVisibleUnderFilter) — captured
  // once at the moment this screen is opened. It can't go stale the way a
  // task *list* snapshot could: the toggle that would change it lives on
  // the covered route, entirely unreachable while this one is on top, so
  // there's no way for it to change out from under this screen.
  final bool Function(MatrixTask task) isVisible;
  final void Function(String id) onToggle;
  final void Function(String id) onDelete;
  final void Function(String id, MatrixQuadrant q) onMove;
  final void Function(String id, MatrixQuadrant q, String? beforeId)
      onReorder;
  final void Function(String id) onToggleFav;
  final VoidCallback onAddTapped;
  final void Function(MatrixTask task) onOpenDetails;

  const QuadrantExpandedScreen({
    super.key,
    required this.quadrant,
    required this.isVisible,
    required this.onToggle,
    required this.onDelete,
    required this.onMove,
    required this.onReorder,
    required this.onToggleFav,
    required this.onAddTapped,
    required this.onOpenDetails,
  });

  // Unlike QuadrantCard (a plain StatelessWidget that receives title/color
  // as resolved props from its parent), this screen is already a
  // ConsumerWidget — so it watches matrixProvider directly instead (see
  // build() below: `matrixState.colorFor`/`titleFor`). That matters here
  // specifically: the Edit Quadrant sheet is reachable from this exact
  // screen's own header (long-press, wired below), and a static
  // constructor prop wouldn't pick up a just-saved rename/recolor without
  // leaving and reopening this screen. ref.watch makes that update show
  // immediately, same frame the sheet closes.

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final matrixState = ref.watch(matrixProvider);
    final color = matrixState.colorFor(quadrant);
    final title = matrixState.titleFor(quadrant, isAr);
    // Same active-first-then-done split QuadrantCard.build() uses (see its
    // `ordered` local) — sorting the combined list by `order` alone would
    // let a done task's old (often lower) order value put it above a
    // still-pending one, so the two views could show this same quadrant in
    // two different sequences.
    final quadrantTasks =
        matrixState.tasks.where((t) => t.quadrant == quadrant && isVisible(t));
    final active = quadrantTasks.where((t) => !t.isDone).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final done = quadrantTasks.where((t) => t.isDone).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final tasks = [...active, ...done];

    // Long-press on the title below still works exactly as before — this
    // closure also backs the new pen icon in the header, so this
    // popped-up/maximized page has a second, more discoverable way to
    // reach the same rename+recolor sheet without removing the long-press.
    void openEditSheet() => showEditQuadrantSheet(
          context,
          ref,
          quadrant: quadrant,
          currentTitle: title,
          currentColorHex: matrixState.quadrantColors[quadrant.name],
        );

    return Scaffold(
      backgroundColor: gp.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(4, 6, 16, 6),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: gp.textSec),
                    tooltip: s.matrixCollapseQuadrant,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context);
                    },
                  ),
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        // Long-press to rename/recolor — same gesture as
                        // the compact card's header (see QuadrantCard).
                        // The pen icon in this header (below) opens the
                        // same sheet on a plain tap, for discoverability.
                        onLongPress: openEditSheet,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: gp.textPrimary,
                                    letterSpacing: isAr ? 0 : -0.2),
                              ),
                              Text(
                                quadrant.localSubtitle(isAr),
                                style: TextStyle(
                                    fontSize: 11.5, color: gp.textSec),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Only shown here on the expanded/maximized page — the
                  // compact grid card keeps long-press as its sole entry
                  // point, unchanged. This is purely an added, more
                  // discoverable shortcut to the exact same sheet.
                  IconButton(
                    icon: Icon(Icons.edit_rounded, color: gp.textSec),
                    tooltip: s.matrixEditQuadrantTitle,
                    onPressed: openEditSheet,
                  ),
                  Material(
                    color: color.withOpacity(0.14),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onAddTapped,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child:
                            Icon(Icons.add_rounded, size: 20, color: color),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: tasks.isEmpty
                    ? _EmptyQuadrantBody(color: color, onTap: onAddTapped)
                    : _AnimatedTaskStack(
                        quadrant: quadrant,
                        tasks: tasks,
                        accentColor: color,
                        onToggle: onToggle,
                        onDelete: onDelete,
                        selectionMode: false,
                        selectedIds: const {},
                        onSelectionToggle: (_) {},
                        onSelectionStart: (_) {},
                        onMove: onMove,
                        onReorder: onReorder,
                        onToggleFav: onToggleFav,
                        onAddTapped: onAddTapped,
                        onOpenDetails: onOpenDetails,
                        expanded: true,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
