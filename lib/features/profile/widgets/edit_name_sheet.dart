import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';

/// Bottom sheet for setting/changing the name shown on the Profile hero
/// header — reached by tapping the name (or its pencil icon) there. Same
/// sheet chrome as DeleteAccountSheet (surfaceHigh card, drag handle, icon
/// circle) minus the destructive styling, since this is a low-stakes edit.
void showEditNameSheet(
  BuildContext context,
  WidgetRef ref,
  String currentName,
) {
  HapticFeedback.selectionClick();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditNameSheet(currentName: currentName),
  );
}

class _EditNameSheet extends ConsumerStatefulWidget {
  final String currentName;
  const _EditNameSheet({required this.currentName});

  @override
  ConsumerState<_EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends ConsumerState<_EditNameSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.currentName);
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text;
    if (name.trim().isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final success =
        await ref.read(dashboardProvider.notifier).setDisplayName(name);
    if (!mounted) return;

    if (!success) {
      setState(() {
        _submitting = false;
        _error = S.of(context).profileEditNameError;
      });
      return;
    }
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
                  color: GameColors.gold.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                // Not `const` — GameColors.gold is a mutable `static Color`
                // (preset-driven), not a compile-time constant.
                child: Icon(Icons.badge_rounded,
                    size: 28, color: GameColors.gold),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              s.profileEditNameTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.profileEditNameBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: gp.textSec, height: 1.4),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_submitting,
              maxLength: DashboardNotifier.maxDisplayNameLength,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: s.profileEditNameHint,
                counterText: '',
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
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12.5, color: GameColors.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submitting ? null : _save,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(s.profileEditNameSave),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _submitting ? null : () => Navigator.pop(context),
              child: Text(s.profileEditNameCancel),
            ),
          ],
        ),
      ),
    );
  }
}
