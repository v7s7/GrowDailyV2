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

  int get _pending => tasks.where((t) => !t.isDone).length;

  /// Pending tasks first (in their existing order), finished ones pushed to
  /// the bottom — so checking a task off doesn't just cross it out, it also
  /// clears it out of the way of what's still left to do.
  List<MatrixTask> get _orderedTasks {
    final pending = tasks.where((t) => !t.isDone);
    final done = tasks.where((t) => t.isDone);
    return [...pending, ...done];
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final isAr = S.of(context).isAr;
    final ordered = _orderedTasks;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gp.border, width: 0.5),
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
                            letterSpacing: 0.8),
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: tasks.isEmpty
                ? _EmptyQuadrantBody(
                    key: const ValueKey('empty'),
                    color: _color,
                    onTap: onAddTapped,
                  )
                : ListView.separated(
                    key: ValueKey(ordered.map((t) => '${t.id}:${t.isDone}').join('|')),
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
                      )
                          .animate(delay: (i * 35).ms)
                          .fadeIn(duration: 260.ms)
                          .slideY(begin: t.isDone ? 0.12 : -0.08, curve: Curves.easeOutCubic);
                    },
                  ),
            ),
          ),
        ],
      ),
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
            ],
          ),
        ),
      ),
    );
  }

  void _showTaskActions(BuildContext context) {
    final others =
        MatrixQuadrant.values.where((q) => q != widget.task.quadrant).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final mgp = ctx.gp;
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            decoration: BoxDecoration(
              color: mgp.surfaceHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: mgp.border, width: 0.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: GameColors.error, size: 20),
                  title: Text(
                    S.of(context).matrixDeleteTask,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: GameColors.error,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onDelete();
                  },
                ),
                Divider(height: 1, color: mgp.divider),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Text(
                    S.of(context).matrixMoveToQuadrant,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: mgp.textSec,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Divider(height: 1, color: mgp.divider),
                ...others.map((q) {
                      final isAr = S.of(context).isAr;
                      return ListTile(
                      dense: true,
                      leading: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: _colorFor(q),
                              shape: BoxShape.circle)),
                      title: Text(q.localLabel(isAr),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: mgp.textPrimary)),
                      subtitle: Text(q.localSubtitle(isAr),
                          style: TextStyle(
                              fontSize: 11, color: mgp.textSec)),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onMove(q);
                      },
                    );
                    }),
                const SizedBox(height: 8),
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
