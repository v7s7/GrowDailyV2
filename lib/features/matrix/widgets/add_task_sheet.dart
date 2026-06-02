import 'package:flutter/material.dart';
import '../../../core/theme/game_theme.dart';
import '../models/matrix_task.dart';

class AddTaskSheet extends StatefulWidget {
  final MatrixQuadrant quadrant;
  final void Function(String title) onAdd;

  const AddTaskSheet({
    super.key,
    required this.quadrant,
    required this.onAdd,
  });

  @override
  State<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<AddTaskSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  Color get _color => switch (widget.quadrant) {
        MatrixQuadrant.doFirst => GameColors.error,
        MatrixQuadrant.schedule => GameColors.xpBlue,
        MatrixQuadrant.delegate => GameColors.streakOrange,
        MatrixQuadrant.eliminate => GameColors.textTertiary,
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_ctrl.text.trim().isEmpty) return;
    widget.onAdd(_ctrl.text.trim());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: GameColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: GameColors.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: _color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.quadrant.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _color,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.quadrant.subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: GameColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              focusNode: _focus,
              onSubmitted: (_) => _submit(),
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: GameColors.textPrimary,
              ),
              decoration: const InputDecoration(
                hintText: 'What needs to be done?',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: _submit,
              child: const Text(
                'ADD TASK',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
