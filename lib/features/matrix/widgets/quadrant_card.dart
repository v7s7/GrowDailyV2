import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/game_theme.dart';
import '../models/matrix_task.dart';

class QuadrantCard extends StatelessWidget {
  final MatrixQuadrant quadrant;
  final List<MatrixTask> tasks;
  final void Function(String id) onToggle;
  final void Function(String id) onDelete;
  final void Function(String id, MatrixQuadrant q) onMove;
  final VoidCallback onAddTapped;

  const QuadrantCard({
    super.key,
    required this.quadrant,
    required this.tasks,
    required this.onToggle,
    required this.onDelete,
    required this.onMove,
    required this.onAddTapped,
  });

  Color get _color => switch (quadrant) {
        MatrixQuadrant.doFirst => GameColors.error,
        MatrixQuadrant.schedule => GameColors.xpBlue,
        MatrixQuadrant.delegate => GameColors.streakOrange,
        MatrixQuadrant.eliminate => GameColors.textTertiary,
      };

  int get _pending => tasks.where((t) => !t.isDone).length;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: onAddTapped,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: _color.withOpacity(0.1),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(13)),
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
                      quadrant.label,
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
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_circle_outline_rounded,
                            size: 20, color: gp.textTert),
                        const SizedBox(height: 4),
                        Text('Tap + to add',
                            style: TextStyle(
                                fontSize: 11, color: gp.textTert)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: gp.divider, indent: 10, endIndent: 10),
                    itemBuilder: (ctx, i) {
                      final t = tasks[i];
                      return _TaskTile(
                        key: ValueKey(t.id),
                        task: t,
                        accentColor: _color,
                        onToggle: () => onToggle(t.id),
                        onDelete: () => onDelete(t.id),
                        onMove: (q) => onMove(t.id, q),
                      )
                          .animate(delay: (i * 35).ms)
                          .fadeIn(duration: 260.ms)
                          .slideX(begin: 0.05, curve: Curves.easeOut);
                    },
                  ),
          ),
        ],
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
  final void Function(MatrixQuadrant) onMove;

  const _TaskTile({
    super.key,
    required this.task,
    required this.accentColor,
    required this.onToggle,
    required this.onDelete,
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
    _spring.forward(from: 0.0);
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Dismissible(
      key: ValueKey('dismiss-${widget.task.id}'),
      direction: DismissDirection.endToStart,
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
        onLongPress: () => _showMoveMenu(context),
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
                      color: widget.task.isDone
                          ? widget.accentColor
                          : Colors.transparent,
                      border: Border.all(
                        color: widget.task.isDone
                            ? widget.accentColor
                            : gp.border,
                        width: 1.5,
                      ),
                      boxShadow: widget.task.isDone
                          ? [
                              BoxShadow(
                                  color:
                                      widget.accentColor.withOpacity(0.35),
                                  blurRadius: 6)
                            ]
                          : null,
                    ),
                    child: widget.task.isDone
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

  void _showMoveMenu(BuildContext context) {
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Text(
                    'MOVE TO QUADRANT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: mgp.textSec,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                Divider(height: 1, color: mgp.divider),
                ...others.map((q) => ListTile(
                      dense: true,
                      leading: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: _colorFor(q),
                              shape: BoxShape.circle)),
                      title: Text(q.label,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: mgp.textPrimary)),
                      subtitle: Text(q.subtitle,
                          style: TextStyle(
                              fontSize: 11, color: mgp.textSec)),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onMove(q);
                      },
                    )),
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
