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

class MatrixScreen extends ConsumerWidget {
  const MatrixScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gp = context.gp;
    final s = S.of(context);
    final tasks = ref.watch(matrixProvider);

    return Scaffold(
      backgroundColor: gp.bg,
      bottomNavigationBar: const GameNavBar(currentIndex: 3),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
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
              ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05),
            ),
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
                                    onDelete: (id) {
                                      HapticFeedback.mediumImpact();
                                      ref
                                          .read(matrixProvider.notifier)
                                          .delete(id);
                                    },
                                    onMove: (id, q) {
                                      HapticFeedback.selectionClick();
                                      ref
                                          .read(matrixProvider.notifier)
                                          .move(id, q);
                                    },
                                    onAddTapped: () => _showAdd(
                                        context,
                                        ref,
                                        MatrixQuadrant.doFirst),
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
                                    onDelete: (id) {
                                      HapticFeedback.mediumImpact();
                                      ref
                                          .read(matrixProvider.notifier)
                                          .delete(id);
                                    },
                                    onMove: (id, q) {
                                      HapticFeedback.selectionClick();
                                      ref
                                          .read(matrixProvider.notifier)
                                          .move(id, q);
                                    },
                                    onAddTapped: () => _showAdd(
                                        context,
                                        ref,
                                        MatrixQuadrant.schedule),
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
                                    onDelete: (id) {
                                      HapticFeedback.mediumImpact();
                                      ref
                                          .read(matrixProvider.notifier)
                                          .delete(id);
                                    },
                                    onMove: (id, q) {
                                      HapticFeedback.selectionClick();
                                      ref
                                          .read(matrixProvider.notifier)
                                          .move(id, q);
                                    },
                                    onAddTapped: () => _showAdd(
                                        context,
                                        ref,
                                        MatrixQuadrant.delegate),
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
                                    onDelete: (id) {
                                      HapticFeedback.mediumImpact();
                                      ref
                                          .read(matrixProvider.notifier)
                                          .delete(id);
                                    },
                                    onMove: (id, q) {
                                      HapticFeedback.selectionClick();
                                      ref
                                          .read(matrixProvider.notifier)
                                          .move(id, q);
                                    },
                                    onAddTapped: () => _showAdd(
                                        context,
                                        ref,
                                        MatrixQuadrant.eliminate),
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
        onAdd: (title) {
          HapticFeedback.mediumImpact();
          ref.read(matrixProvider.notifier).add(title, quadrant);
        },
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
