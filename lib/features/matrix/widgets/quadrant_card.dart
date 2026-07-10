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

  // `tasks` only ever holds pending tasks — the caller (MatrixScreen)
  // filters out done ones before handing the list to this card, so a
  // finished task disappears from the quadrant instead of sitting
  // crossed-out forever. It isn't lost: it moves to the Completed history,
  // reachable from the screen header.
  int get _pending => tasks.length;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final isAr = S.of(context).isAr;
    final ordered = tasks;
    // A dedicated drag-handle icon on each tile (see _TaskTile) is the only
    // thing that starts a drag, so this target never fights the card's own
    // tap/long-press/swipe handling.
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) => onMove(details.data, quadrant),
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
                // just the row that changed, since a done task drops out of
                // `tasks` (filtered upstream) and changed the key every time.
                : ListView.separated(
                    key: const ValueKey('list'),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: ordered.length + 1,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: gp.divider, indent: 10, endIndent: 10),
                    itemBuilder: (ctx, i) {
                      if (i == ordered.length) {
                        return _AddAnotherRow(
                          color: _color,
                          onTap: onAddTapped,
                        );
                      }
                      final t = ordered[i];
                      return _TaskTile(
                        key: ValueKey(t.id),
                        task: t,
                        accentColor: _color,
                        onToggle: () => onToggle(t.id),
                        onDelete: () => onDelete(t.id),
                        selectionMode: selectionMode,
                        selected: selectedIds.contains(t.id),
                        onSelectionToggle: () => onSelectionToggle(t.id),
                        onSelectionStart: () => onSelectionStart(t.id),
                        onMove: (q) => onMove(t.id, q),
                        onToggleToday: () => onToggleToday(t.id),
                      )
                          .animate(delay: (i * 35).ms)
                          .fadeIn(duration: 260.ms)
                          .slideY(begin: -0.08, curve: Curves.easeOutCubic);
                    },
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
                              color: widget.accentColor, width: 1),
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
