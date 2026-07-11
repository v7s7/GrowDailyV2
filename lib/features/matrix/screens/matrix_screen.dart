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
import '../widgets/task_detail_sheet.dart';
import 'matrix_history_screen.dart';

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class MatrixScreen extends ConsumerStatefulWidget {
  const MatrixScreen({super.key});

  @override
  ConsumerState<MatrixScreen> createState() => _MatrixScreenState();
}

class _MatrixScreenState extends ConsumerState<MatrixScreen> {
  final Set<String> _selectedIds = {};
  // Defaults to false (show everything) rather than true — this ships to
  // people with existing tasks that all predate the isFav field, so
  // defaulting to the Fav filter would open on what looks like an empty
  // board. Users opt into the filtered view themselves.
  bool _favOnly = false;
  // A second, independent filter layered on top of "All" (mutually
  // exclusive with _favOnly — see the toggle's onChanged below): tasks
  // that are still open and were created before today. Unlike isFav, this
  // one really is date-based, computed fresh from createdAt/isDone on
  // every build rather than stored on the task — nothing to migrate, and
  // it can never go stale the way a stored flag could.
  bool _carriedOverOnly = false;

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

  void _moveTask(String id, MatrixQuadrant q) {
    HapticFeedback.selectionClick();
    ref.read(matrixProvider.notifier).move(id, q);
  }

  // Drag-and-drop specifically — unlike _moveTask (used by the "..." sheet's
  // plain "move to quadrant" option, which always appends to the end),
  // this carries *where* the task was dropped, so it can land at a precise
  // row instead of always landing last.
  void _reorderTask(String id, MatrixQuadrant q, String? beforeId) {
    HapticFeedback.selectionClick();
    ref.read(matrixProvider.notifier).reorder(id, q, beforeId: beforeId);
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
    final now = DateTime.now();
    bool doneToday(MatrixTask t) =>
        t.isDone && t.completedAt != null && _isSameDay(t.completedAt!, now);

    // A task stays on its own board — struck through, not gone — for the
    // rest of the day it was finished on. That's the "proof you did it"
    // moment a lot of task apps lose by yanking the row away the instant
    // you check it. Only once the local date rolls past midnight does it
    // drop off here for good, at which point it's still reachable (forever)
    // in Completed history via the header icon.
    final visible =
        matrixState.tasks.where((t) => !t.isDone || doneToday(t)).toList();
    final completedCount = matrixState.tasks.where((t) => t.isDone).length;
    final favCount = visible.where((t) => t.isFav && !t.isDone).length;
    // Still open, and was already sitting on the board before today — the
    // stuff that's easy to lose track of in a long "All" list. Based on
    // createdAt rather than isFav on purpose: favoriting something doesn't
    // protect it from going stale, and this is meant to catch exactly that,
    // starred or not.
    final carriedOver = visible
        .where((t) => !t.isDone && !_isSameDay(t.createdAt, now))
        .toList();
    final tasks = _favOnly
        ? visible.where((t) => t.isFav || t.isDone).toList()
        : _carriedOverOnly
            ? carriedOver
            : visible;

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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _FavFilterToggle(
                      favOnly: _favOnly,
                      favCount: favCount,
                      onChanged: (v) => setState(() {
                        _favOnly = v;
                        // Fav and carried-over are two separate lenses on
                        // the same board — switching either segment backs
                        // out of the other one instead of trying to
                        // combine them.
                        _carriedOverOnly = false;
                      }),
                    ),
                    if (!_favOnly && carriedOver.isNotEmpty)
                      _CarriedOverChip(
                        count: carriedOver.length,
                        active: _carriedOverOnly,
                        onTap: () => setState(
                            () => _carriedOverOnly = !_carriedOverOnly),
                      ),
                  ],
                ),
              ),
            ).animate(delay: 50.ms).fadeIn(duration: 300.ms),
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
            const SizedBox(height: 14),
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
                                    onReorder: _reorderTask,
                                    onToggleFav: (id) => ref
                                        .read(matrixProvider.notifier)
                                        .toggleFav(id),
                                    onAddTapped: () => _showAdd(
                                        context,
                                        ref,
                                        MatrixQuadrant.doFirst),
                                    onOpenDetails: (task) =>
                                        _openTaskDetails(context, ref, task),
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
                                    onReorder: _reorderTask,
                                    onToggleFav: (id) => ref
                                        .read(matrixProvider.notifier)
                                        .toggleFav(id),
                                    onAddTapped: () => _showAdd(
                                        context,
                                        ref,
                                        MatrixQuadrant.schedule),
                                    onOpenDetails: (task) =>
                                        _openTaskDetails(context, ref, task),
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
                                    onReorder: _reorderTask,
                                    onToggleFav: (id) => ref
                                        .read(matrixProvider.notifier)
                                        .toggleFav(id),
                                    onAddTapped: () => _showAdd(
                                        context,
                                        ref,
                                        MatrixQuadrant.delegate),
                                    onOpenDetails: (task) =>
                                        _openTaskDetails(context, ref, task),
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
                                    onReorder: _reorderTask,
                                    onToggleFav: (id) => ref
                                        .read(matrixProvider.notifier)
                                        .toggleFav(id),
                                    onAddTapped: () => _showAdd(
                                        context,
                                        ref,
                                        MatrixQuadrant.eliminate),
                                    onOpenDetails: (task) =>
                                        _openTaskDetails(context, ref, task),
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

  void _showAdd(BuildContext context, WidgetRef ref, MatrixQuadrant quadrant) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddTaskSheet(
        quadrant: quadrant,
        onAdd: (title,
            {description, voiceNotePath, voiceNoteDurationSeconds}) {
          HapticFeedback.mediumImpact();
          ref.read(matrixProvider.notifier).add(
                title,
                quadrant,
                description: description,
                voiceNotePath: voiceNotePath,
                voiceNoteDurationSeconds: voiceNoteDurationSeconds,
              );
        },
      ),
    );
  }

  // Pencil icon on an existing task (see quadrant_card.dart's _TaskTile) —
  // the richer counterpart to _showAdd: editing title/description/voice on
  // something already in the matrix, plus Delete/Move (migrated here from
  // the old "..." menu). TaskDetailSheet only ever talks to callbacks, same
  // as QuadrantCard/_TaskTile below — it never touches matrixProvider
  // directly, so this screen stays the one place that owns provider access
  // for the whole feature.
  void _openTaskDetails(
      BuildContext context, WidgetRef ref, MatrixTask task) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TaskDetailSheet(
        task: task,
        onRename: (id, title) =>
            ref.read(matrixProvider.notifier).rename(id, title),
        onUpdateDetails: (
          id, {
          description,
          clearDescription,
          voiceNotePath,
          voiceNoteDurationSeconds,
          clearVoiceNote,
        }) =>
            ref.read(matrixProvider.notifier).updateDetails(
                  id,
                  description: description,
                  clearDescription: clearDescription ?? false,
                  voiceNotePath: voiceNotePath,
                  voiceNoteDurationSeconds: voiceNoteDurationSeconds,
                  clearVoiceNote: clearVoiceNote ?? false,
                ),
        onDelete: () => _deleteTask(task.id),
        onMove: (q) => _moveTask(task.id, q),
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

// ─── Fav/All filter toggle ──────────────────────────────────────────────────

/// Filters all four quadrants down to just tasks flagged as favorites —
/// plain client-side filter over isFav, no separate query/screen. Defaults
/// to All (see _MatrixScreenState._favOnly) so nobody's existing board
/// looks empty the first time they see this.
class _FavFilterToggle extends StatelessWidget {
  final bool favOnly;
  final int favCount;
  final ValueChanged<bool> onChanged;

  const _FavFilterToggle({
    required this.favOnly,
    required this.favCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: gp.surfaceHL,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FilterSegment(
            active: favOnly,
            onTap: () => onChanged(true),
            // Same star glyph used to flag a task on each row — ties this
            // filter visually to "my starred tasks" instead of reading like
            // a separate due-date/scheduling concept of its own.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_rounded, size: 13),
                const SizedBox(width: 4),
                Text('${s.matrixFav} · $favCount'),
              ],
            ),
          ),
          _FilterSegment(
            active: !favOnly,
            onTap: () => onChanged(false),
            child: Text(s.matrixAll),
          ),
        ],
      ),
    );
  }
}

// ─── Carried-over chip ──────────────────────────────────────────────────────

/// Sits beside the Fav/All toggle, only when there's actually something to
/// show — a task left unfinished from before today is worth a nudge, but an
/// empty chip every single day would just be noise. Tapping it filters the
/// board to exactly that set (see _MatrixScreenState._carriedOverOnly);
/// tapping again (or switching the Fav/All toggle) clears it.
class _CarriedOverChip extends StatelessWidget {
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _CarriedOverChip({
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    // Not `const` — GameColors.streakOrange is a mutable `static Color`
    // (preset-driven), not a compile-time constant.
    final color = GameColors.streakOrange;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.18) : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: color.withOpacity(active ? 0.6 : 0.3),
              width: active ? 1.2 : 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded, size: 13, color: color),
              const SizedBox(width: 5),
              Text(
                s.matrixCarriedOverCount(count),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: gp.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterSegment extends StatelessWidget {
  final Widget child;
  final bool active;
  final VoidCallback onTap;

  const _FilterSegment({
    required this.child,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final color = active ? GameColors.gold : gp.textSec;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active
                ? GameColors.gold.withOpacity(0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: GameColors.gold.withOpacity(0.18),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: color, size: 13),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                scale: active ? 1.0 : 0.96,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
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
