import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../models/own_category.dart';

/// «فئة جديدة»: a name and an icon for a category of one's own, with the
/// pill it will be shown as drawn live at the top. Returns the category, or
/// null when the sheet is closed without saving.
///
/// Nothing is written here. The category is saved with the habit it is
/// picked for (see OwnCategory), which is what makes it come back for the
/// next habit.
Future<OwnCategory?> showOwnCategorySheet(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<OwnCategory>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const OwnCategorySheet(),
  );
}

class OwnCategorySheet extends StatefulWidget {
  const OwnCategorySheet({super.key});

  @override
  State<OwnCategorySheet> createState() => _OwnCategorySheetState();
}

class _OwnCategorySheetState extends State<OwnCategorySheet> {
  final _name = TextEditingController();
  String _icon = kOwnCategoryIcons.keys.first;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _typed => _name.text.trim();

  void _save() {
    if (_typed.isEmpty) return;
    HapticFeedback.mediumImpact();
    Navigator.pop(context, OwnCategory(name: _typed, icon: _icon));
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: gp.surfaceHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: gp.border, width: 0.5),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            20 + MediaQuery.of(context).padding.bottom,
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
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.ownCategoryNew,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded,
                        size: 20, color: gp.textSec),
                  ),
                ],
              ),
              Text(
                s.ownCategoryNote,
                style: TextStyle(fontSize: 12, color: gp.textTert, height: 1.4),
              ),
              const SizedBox(height: 18),
              // The pill as it will appear in the category row, drawn from
              // what is typed and picked right now.
              Center(child: _preview(s)),
              const SizedBox(height: 18),
              TextField(
                selectionWidthStyle: GameTextStyles.selectionWidthStyle,
                controller: _name,
                maxLength: kOwnCategoryNameMax,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: gp.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: s.ownCategoryNameHint,
                  counterText: '',
                  prefixIcon: Icon(Icons.edit_rounded,
                      size: 18, color: gp.textTert),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                s.ownCategoryPickIcon,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: gp.textTert,
                ),
              ),
              const SizedBox(height: 10),
              _iconGrid(),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _typed.isEmpty ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(s.ownCategorySave),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(S s) {
    final empty = _typed.isEmpty;
    return AnimatedContainer(
      duration: GameMotion.quick,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
      decoration: BoxDecoration(
        color: GameColors.gold.withOpacity(0.14),
        borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
        border: Border.all(color: GameColors.gold.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: GameMotion.quick,
            transitionBuilder: (child, a) =>
                ScaleTransition(scale: a, child: child),
            child: Icon(
              ownCategoryIcon(_icon),
              key: ValueKey(_icon),
              size: 18,
              color: context.gp.goldInk,
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              empty ? s.ownCategoryNew : _typed,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: empty
                    ? context.gp.goldInk.withOpacity(0.55)
                    : context.gp.goldInk,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Six to a row, every cell the same square, the picked one lit.
  Widget _iconGrid() {
    final gp = context.gp;
    final keys = kOwnCategoryIcons.keys.toList();
    return LayoutBuilder(
      builder: (context, box) {
        const columns = 6;
        const gap = 8.0;
        final cell = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final key in keys)
              Semantics(
                button: true,
                selected: key == _icon,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _icon = key);
                  },
                  child: AnimatedContainer(
                    duration: GameMotion.quick,
                    width: cell,
                    height: cell,
                    decoration: BoxDecoration(
                      color: key == _icon
                          ? GameColors.gold.withOpacity(0.16)
                          : gp.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: key == _icon
                            ? GameColors.gold.withOpacity(0.6)
                            : gp.border,
                        width: key == _icon ? 1.4 : 0.5,
                      ),
                    ),
                    child: Icon(
                      ownCategoryIcon(key),
                      size: 22,
                      color: key == _icon ? context.gp.goldInk : gp.textSec,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
