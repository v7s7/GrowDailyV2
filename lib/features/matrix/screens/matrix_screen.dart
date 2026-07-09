import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/game_nav_bar.dart';
import '../models/matrix_task.dart';
import '../notifiers/matrix_notifier.dart';
import '../widgets/add_task_sheet.dart';
import '../widgets/quadrant_card.dart';
import 'matrix_history_screen.dart';

class MatrixScreen extends ConsumerStatefulWidget {
  const MatrixScreen({super.key});

  @override
  ConsumerState<MatrixScreen> createState() => _MatrixScreenState();
}

class _MatrixScreenState extends ConsumerState<MatrixScreen> {
  final Set<String> _selectedIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _startSelection(String id) {
    setState(() => _selectedIds.add(id));
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  void _clearSelection() {
    setState(_selectedIds.clear);
  }

  void _deleteSelected() {
    if (_selectedIds.isEmpty) return;
    HapticFeedback.mediumImpact();
    final notifier = ref.read(matrixProvider.notifier);
    final removed = ref
        .read(matrixProvider)
        .tasks
        .where((t) => _selectedIds.contains(t.id))
        .toList();
    final count = removed.length;
    notifier.deleteMany(_selectedIds);
    _clearSelection();
    _showUndoSnackbar(
      message: S.of(context).matrixTasksDeleted(count),
      onUndo: () => notifier.restoreMany(removed),
    );
  }

  MatrixTask? _findTask(String id) {
    for (final t in ref.read(matrixProvider).tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _deleteTask(String id) {
    final task = _findTask(id);
    if (task == null) return;
    HapticFeedback.mediumImpact();
    ref.read(matrixProvider.notifier).delete(id);
    _showUndoSnackbar(
      message: S.of(context).matrixTaskDeleted,
      onUndo: () => ref.read(matrixProvider.notifier).restore(task),
    );
  }

  void _moveTask(String id, MatrixQuadrant? q) {
    HapticFeedback.selectionClick();
    ref.read(matrixProvider.notifier).move(id, q);
  }

  void _showUndoSnackbar({
    required String message,
    required VoidCallback onUndo,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: S.of(context).matrixUndo,
          onPressed: onUndo,
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final matrixState = ref.watch(matrixProvider);
    final tasks = matrixState.tasks.where((t) => !t.isDone).toList();
    final completedCount = matrixState.tasks.length - tasks.length;

    if (matrixState.isLoading) {
      return Scaffold(
        backgroundColor: gp.bg,
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(
              color: GameColors.gold,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: gp.bg,
      bottomNavigationBar: const GameNavBar(currentIndex: 2),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.goalsMatrix,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: gp.textPrimary,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.matrixSubtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: gp.textSec,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Badge(
                      label: Text('$completedCount'),
                      isLabelVisible: completedCount > 0,
                      backgroundColor: GameColors.gold,
                      textColor: Colors.black,
                      child: Icon(Icons.check_circle_outline_rounded,
                          color: gp.textSec),
                    ),
                    tooltip: s.matrixCompletedTitle,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const MatrixHistoryScreen()),
                      );
                    },
                  ),
                ],
              ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05),
            ),
            if (_selectionMode) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _SelectionBar(
                  count: _selectedIds.length,
                  onClear: _clearSelection,
                  onDelete: _deleteSelected,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _InboxSection(
                tasks: tasks.where((t) => t.quadrant == null).toList(),
                onToggle: (id) {
                  HapticFeedback.lightImpact();
                  ref.read(matrixProvider.notifier).toggle(id);
                },
                onDelete: _deleteTask,
                onDropToInbox: (id) => _moveTask(id, null),
                onAddTapped: () => _showAdd(context, ref, null),
              ),
            ).animate(delay: 100.ms).fadeIn(duration: 300.ms),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                      child: _AxisLabel(
                          label: s.matrixUrgent, icon: Icons.bolt_rounded)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _AxisLabel(
                          label: s.matrixNotUrgent,
                          icon: Icons.schedule_rounded)),
                ],
              ).animate(delay: 100.ms).fadeIn(duration: 300.ms),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      children: [
                        Expanded(
                            child: _RotatedAxisLabel(label: s.matrixImportant)),
                        const SizedBox(height: 8),
                        Expanded(
                            child:
                                _RotatedAxisLabel(label: s.matrixNotImportant)),
                      ],
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: QuadrantCard(
                                    quadrant: MatrixQuadrant.doFirst,
                                    tasks: tasks
                                        .where((t) =>
                                            t.quadrant ==
                                            MatrixQuadrant.doFirst)
                                        .toList(),
                                    onToggle: (id) {
                                      HapticFeedback.lightImpact();
                                      ref
                                          .read(matrixProvider.notifier)
                                          .toggle(id);
                                    },
                                    onDelete: _deleteTask,
                                    onMove: _moveTask,
                                    onAddTapped: () => _showAdd(
                                        context,
                                        ref,
                                        MatrixQuadrant.doFirst),
                                    selectionMode: _selectionMode,
                                    selectedIds: _selectedIds,
                                    onSelectionToggle: _toggleSelection,
                                    onSelectionStart: _startSelection,
                                  )
                                      .animate(delay: 150.ms)
                                      .fadeIn(duration: 350.ms)
                                      .scaleXY(
                                          begin: 0.96,
                                          end: 1,
                                          curve: Curves.easeOutBack),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: QuadrantCard(
                                    quadrant: MatrixQuadrant.schedule,
                                    tasks: tasks
                                        .where((t) =>
                                            t.quadrant ==
                                            MatrixQuadrant.schedule)
                                        .toList(),
                                    onToggle: (id) {
                                      HapticFeedback.lightImpact();
                                      ref
                                          .read(matrixProvider.notifier)
                                          .toggle(id);
                                    },
                                    onDelete: _deleteTask,
                                    onMove: _moveTask,
                                    onAddTapped: () => _showAdd(
                                        context,
                                        ref,
                                        MatrixQuadrant.schedule),
                                    selectionMode: _selectionMode,
                                    selectedIds: _selectedIds,
                                    onSelectionToggle: _toggleSelection,
                                    onSelectionStart: _startSelection,
                                  )
                                      .animate(delay: 200.ms)
                                      .fadeIn(duration: 350.ms)
                                      .scaleXY(
                                          begin: 0.96,
                                          end: 1,
                                          curve: Curves.easeOutBack),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: QuadrantCard(
                                    quadrant: MatrixQuadrant.delegate,
                                    tasks: tasks
                                        .where((t) =>
                                            t.quadrant ==
                                            MatrixQuadrant.delegate)
                                        .toList(),
                                    onToggle: (id) {
                                      HapticFeedback.lightImpact();
                                      ref
                                          .read(matrixProvider.notifier)
                                          .toggle(id);
                                    },
                                    onDelete: _deleteTask,
                                    onMove: _moveTask,
                                    onAddTapped: () => _showAdd(
                                        context,
                                        ref,
                                        MatrixQuadrant.delegate),
                                    selectionMode: _selectionMode,
                                    selectedIds: _selectedIds,
                                    onSelectionToggle: _toggleSelection,
                                    onSelectionStart: _startSelection,
                                  )
                                      .animate(delay: 250.ms)
                                      .fadeIn(duration: 350.ms)
                                      .scaleXY(
                                          begin: 0.96,
                                          end: 1,
                                          curve: Curves.easeOutBack),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: QuadrantCard(
                                    quadrant: MatrixQuadrant.eliminate,
                                    tasks: tasks
                                        .where((t) =>
                                            t.quadrant ==
                                            MatrixQuadrant.eliminate)
                                        .toList(),
                                    onToggle: (id) {
                                      HapticFeedback.lightImpact();
                                      ref
                                          .read(matrixProvider.notifier)
                                          .toggle(id);
                                    },
                                    onDelete: _deleteTask,
                                    onMove: _moveTask,
                                    onAddTapped: () => _showAdd(
                                        context,
                                        ref,
                                        MatrixQuadrant.eliminate),
                                    selectionMode: _selectionMode,
                                    selectedIds: _selectedIds,
                                    onSelectionToggle: _toggleSelection,
                                    onSelectionStart: _startSelection,
                                  )
                                      .animate(delay: 300.ms)
                                      .fadeIn(duration: 350.ms)
                                      .scaleXY(
                                          begin: 0.96,
                                          end: 1,
                                          curve: Curves.easeOutBack),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAdd(BuildContext context, WidgetRef ref, MatrixQuadrant? quadrant) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddTaskSheet(
        quadrant: quadrant,
        onAdd: (title) {
          HapticFeedback.mediumImpact();
          ref.read(matrixProvider.notifier).add(title, quadrant);
        },
      ),
    );
  }
}


class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final VoidCallback onDelete;

  const _SelectionBar({
    required this.count,
    required this.onClear,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: GameColors.gold.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GameColors.gold.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: gp.textSec),
            onPressed: onClear,
          ),
          Expanded(
            child: Text(
              s.matrixSelectedCount(count),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 17),
            label: Text(s.matrixDeleteSelected),
            style: TextButton.styleFrom(foregroundColor: GameColors.error),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 180.ms).slideY(begin: -0.15);
  }
}

class _AxisLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _AxisLabel({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 11, color: gp.textTert),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: gp.textTert,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _RotatedAxisLabel extends StatelessWidget {
  final String label;
  const _RotatedAxisLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Center(
      child: RotatedBox(
        quarterTurns: 3,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: gp.textTert,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

// ─── Inbox ──────────────────────────────────────────────────────────────────

/// Quick-capture lands here, not straight into a quadrant — deciding what's
/// urgent/important can wait until the thought is already safely saved.
/// Chips can be dragged into a quadrant below to triage them (see
/// QuadrantCard's DragTarget), or dropped back here to un-triage.
class _InboxSection extends StatelessWidget {
  final List<MatrixTask> tasks;
  final void Function(String id) onToggle;
  final void Function(String id) onDelete;
  final void Function(String id) onDropToInbox;
  final VoidCallback onAddTapped;

  const _InboxSection({
    required this.tasks,
    required this.onToggle,
    required this.onDelete,
    required this.onDropToInbox,
    required this.onAddTapped,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) => onDropToInbox(details.data),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: isHovering ? GameColors.gold.withOpacity(0.1) : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isHovering ? GameColors.gold : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Row(
                  children: [
                    Icon(Icons.inbox_rounded, size: 13, color: gp.textTert),
                    const SizedBox(width: 4),
                    Text(s.matrixInbox,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: gp.textTert,
                            letterSpacing: 0.8)),
                  ],
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ...tasks.map((t) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: LongPressDraggable<String>(
                              data: t.id,
                              feedback: Material(
                                color: Colors.transparent,
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 200),
                                  child: _InboxChip(
                                    task: t,
                                    onTap: () {},
                                    onDelete: () {},
                                    showDelete: false,
                                  ),
                                ),
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.25,
                                child: _InboxChip(
                                  task: t,
                                  onTap: () {},
                                  onDelete: () {},
                                ),
                              ),
                              child: _InboxChip(
                                task: t,
                                onTap: () => onToggle(t.id),
                                onDelete: () => onDelete(t.id),
                              ),
                            ),
                          )),
                      GestureDetector(
                        onTap: onAddTapped,
                        child: Container(
                          height: 34,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: gp.surfaceHL,
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: gp.border, width: 0.5),
                          ),
                          child: Icon(Icons.add_rounded,
                              size: 16, color: gp.textSec),
                        ),
                      ),
                    ],
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

class _InboxChip extends StatelessWidget {
  final MatrixTask task;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool showDelete;

  const _InboxChip({
    required this.task,
    required this.onTap,
    required this.onDelete,
    this.showDelete = true,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: EdgeInsets.only(left: 12, right: showDelete ? 4 : 12),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              task.isDone
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              size: 14,
              color: task.isDone ? GameColors.gold : gp.textTert,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: gp.textPrimary,
                  decoration: task.isDone
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  decorationColor: gp.textTert,
                ),
              ),
            ),
            if (showDelete)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDelete,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.close_rounded,
                      size: 14, color: gp.textTert),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
