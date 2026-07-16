import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../habits/widgets/habit_color_picker.dart';
import '../models/matrix_task.dart';
import '../notifiers/matrix_notifier.dart';

/// Bottom sheet for renaming a Matrix quadrant and/or giving it its own
/// color — reached by long-pressing a quadrant's header, in both the
/// compact 2x2 grid (QuadrantCard) and the near-fullscreen view
/// (QuadrantExpandedScreen). Same sheet chrome as EditNameSheet
/// (surfaceHigh card, drag handle, icon circle), with a color-swatch
/// suffixIcon on the text field matching AddHabitSheet's own color picker
/// entry point — both existing patterns, combined rather than reinvented.
///
/// Both edits save together as one MatrixNotifier.updateQuadrant() call
/// when Save is tapped; nothing is written while the sheet is still open,
/// so backing out with the system back gesture leaves the quadrant
/// untouched.
void showEditQuadrantSheet(
  BuildContext context,
  WidgetRef ref, {
  required MatrixQuadrant quadrant,
  required String currentTitle,
  required String? currentColorHex,
}) {
  HapticFeedback.selectionClick();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditQuadrantSheet(
      quadrant: quadrant,
      currentTitle: currentTitle,
      currentColorHex: currentColorHex,
    ),
  );
}

class _EditQuadrantSheet extends ConsumerStatefulWidget {
  final MatrixQuadrant quadrant;
  final String currentTitle;
  final String? currentColorHex;

  const _EditQuadrantSheet({
    required this.quadrant,
    required this.currentTitle,
    required this.currentColorHex,
  });

  @override
  ConsumerState<_EditQuadrantSheet> createState() =>
      _EditQuadrantSheetState();
}

class _EditQuadrantSheetState extends ConsumerState<_EditQuadrantSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.currentTitle);
  late String? _colorHex = widget.currentColorHex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _previewColor => _colorHex != null
      ? Color(0xFF000000 | int.parse(_colorHex!, radix: 16))
      : widget.quadrant.defaultColor;

  void _save() {
    final typed = _controller.text.trim();
    // An emptied field means "go back to the built-in label" — more
    // discoverable than a separate hidden reset action, and mirrors how
    // the color swatch's own picker already treats "Use default color".
    ref.read(matrixProvider.notifier).updateQuadrant(
          widget.quadrant,
          title: typed.isEmpty ? null : typed,
          clearTitle: typed.isEmpty,
          colorHex: _colorHex,
          clearColor: _colorHex == null,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: gp.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: gp.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _previewColor.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.edit_rounded, size: 26, color: _previewColor),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              s.matrixEditQuadrantTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.matrixEditQuadrantBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: gp.textSec, height: 1.4),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: widget.quadrant.localLabel(s.isAr),
                filled: true,
                fillColor: gp.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: gp.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: gp.border),
                ),
                // Same tappable color-swatch pattern AddHabitSheet uses for
                // a habit's own icon color — one tap opens the full
                // drag+hex picker, right where the user is already typing.
                suffixIcon: Padding(
                  padding: const EdgeInsets.all(9),
                  child: GestureDetector(
                    onTap: () async {
                      HapticFeedback.selectionClick();
                      final picked = await showHabitColorPicker(
                        context,
                        initialHex: _colorHex,
                        title: s.matrixQuadrantColorTitle,
                        subtitle: s.matrixQuadrantColorHint,
                      );
                      if (picked == null || !mounted) return;
                      setState(() {
                        _colorHex = picked.isEmpty ? null : picked;
                      });
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _previewColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: gp.border, width: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(s.matrixEditQuadrantSave),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.matrixEditQuadrantCancel),
            ),
          ],
        ),
      ),
    );
  }
}
