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
    return Container(
      decoration: BoxDecoration(
        color: GameColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GameColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tappable header
          GestureDetector(
            onTap: onAddTapped,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: _color.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13)),
                border: Border(
                  bottom: BorderSide(
                      color: _color.withOpacity(0.15), width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: _color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      quadrant.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _color,
                        letterSpacing: 0.8,
                      ),
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
                      child: Text(
                        '$_pending',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: _color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Icon(Icons.add_rounded, size: 14, color: _color),
                ],
              ),
            ),
          ),
          // Tasks
          Expanded(
            child: tasks.isEmpty
                ? const Center(
                    child: Text(
                      'Tap + to add',
                      style: TextStyle(
                          fontSize: 11, color: GameColors.textTertiary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: tasks.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: GameColors.divider,
                      indent: 10,
                      endIndent: 10,
                    ),
                    itemBuilder: (ctx, i) {
                      final t = tasks[i];
                      return _TaskTile(
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

class _TaskTile extends StatelessWidget {
  final MatrixTask task;
  final Color accentColor;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final void Function(MatrixQuadrant) onMove;

  const _TaskTile({
    required this.task,
    required this.accentColor,
    required this.onToggle,
    required this.onDelete,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 14),
        color: GameColors.error.withOpacity(0.12),
        child: const Icon(Icons.delete_outline_rounded,
            color: GameColors.error, size: 16),
      ),
      child: InkWell(
        onTap: onToggle,
        onLongPress: () => _showMoveMenu(context),
        splashColor: Colors.transparent,
        highlightColor: GameColors.surfaceElevated.withOpacity(0.5),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      task.isDone ? accentColor : Colors.transparent,
                  border: Border.all(
                    color:
                        task.isDone ? accentColor : GameColors.border,
                    width: 1.5,
                  ),
                ),
                child: task.isDone
                    ? const Icon(Icons.check_rounded,
                        size: 9, color: Colors.black)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                    color: task.isDone
                        ? GameColors.textTertiary
                        : GameColors.textPrimary,
                    decoration: task.isDone
                        ? TextDecoration.lineThrough
                        : null,
                    decorationColor: GameColors.textTertiary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
        MatrixQuadrant.values.where((q) => q != task.quadrant).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          decoration: BoxDecoration(
            color: GameColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: GameColors.border, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  'MOVE TO QUADRANT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: GameColors.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Divider(height: 1),
              ...others.map((q) => ListTile(
                    dense: true,
                    leading: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: _colorFor(q),
                          shape: BoxShape.circle),
                    ),
                    title: Text(
                      q.label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: GameColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      q.subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: GameColors.textSecondary,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      onMove(q);
                    },
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Color _colorFor(MatrixQuadrant q) => switch (q) {
        MatrixQuadrant.doFirst => GameColors.error,
        MatrixQuadrant.schedule => GameColors.xpBlue,
        MatrixQuadrant.delegate => GameColors.streakOrange,
        MatrixQuadrant.eliminate => GameColors.textTertiary,
      };
}
