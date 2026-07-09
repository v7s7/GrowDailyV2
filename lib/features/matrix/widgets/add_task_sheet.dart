import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../models/matrix_task.dart';

/// Stays open after each add so a quick brain-dump ("buy milk" ⏎ "wash car"
/// ⏎ "call mom" ⏎ …) doesn't mean reopening this sheet for every single
/// item. The field clears and keeps focus after each add; the primary
/// button reads "Add" while there's text to submit and "Done" once the
/// field is empty, so the same button (or the keyboard's enter key) both
/// adds and — once you're finished — closes the sheet.
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
  final List<String> _addedTitles = [];
  bool _hasText = false;

  Color get _color => switch (widget.quadrant) {
        MatrixQuadrant.doFirst => GameColors.error,
        MatrixQuadrant.schedule => GameColors.xpBlue,
        MatrixQuadrant.delegate => GameColors.streakOrange,
        MatrixQuadrant.eliminate => GameColors.textTertiary,
      };

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final has = _ctrl.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Adds the current text and keeps the sheet open for the next one, or —
  /// if the field is already empty — closes it. Shared by the primary
  /// button and the keyboard's submit action so both always agree on what
  /// pressing "go" does at any given moment.
  void _submit() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      Navigator.pop(context);
      return;
    }
    HapticFeedback.mediumImpact();
    widget.onAdd(text);
    setState(() {
      _addedTitles.add(text);
      _ctrl.clear();
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: gp.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: _color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text(widget.quadrant.localLabel(isAr),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _color,
                          letterSpacing: 1.2)),
                  const SizedBox(width: 8),
                  Text(widget.quadrant.localSubtitle(isAr),
                      style: TextStyle(fontSize: 11, color: gp.textSec)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                onSubmitted: (_) => _submit(),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: gp.textPrimary,
                    height: 1.4),
                maxLines: 3,
                minLines: 1,
                decoration: InputDecoration(
                  hintText: s.matrixWhatToDo,
                  hintStyle: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      color: gp.textTert.withOpacity(0.7)),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            if (_addedTitles.isEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  s.matrixAddMultipleHint,
                  style: TextStyle(fontSize: 11, color: gp.textTert),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              // Fresh open with nothing typed and nothing added yet still
              // shows a disabled "ADD TASK" (same as before this sheet
              // could stay open) — a "Done" button is only the right
              // primary action once there's actually something to be done
              // with.
              child: Builder(builder: (_) {
                final showDone = !_hasText && _addedTitles.isNotEmpty;
                final active = _hasText || showDone;
                return FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: active ? _color : gp.surfaceHL,
                    foregroundColor: active ? Colors.black : gp.textTert,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: active ? _submit : null,
                  child: Text(showDone ? s.matrixDone : s.matrixAddTask,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4)),
                );
              }),
            ),
            if (_addedTitles.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: gp.divider, indent: 20, endIndent: 20),
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  shrinkWrap: true,
                  itemCount: _addedTitles.length,
                  itemBuilder: (context, i) {
                    // Reversed so the just-added item appears right under
                    // the input every time, not at the bottom of a list
                    // that's scrolled out of view.
                    final title = _addedTitles[_addedTitles.length - 1 - i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_rounded,
                              size: 14, color: _color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5, color: gp.textSec),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 200.ms);
                  },
                ),
              ),
            ],
          ],
        ),
      ).animate().slideY(
          begin: 0.08,
          duration: 280.ms,
          curve: Curves.easeOutCubic).fadeIn(duration: 200.ms),
    );
  }
}
