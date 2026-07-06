import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../auth/notifiers/auth_notifier.dart';

/// Confirmation sheet for permanently deleting the signed-in account.
/// Requires the user to re-enter their password (Firebase needs a recent
/// sign-in before it will delete a user, and re-entering a password is also
/// a reasonable "are you sure" gate for a destructive, irreversible action).
void showDeleteAccountSheet(BuildContext context, WidgetRef ref) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _DeleteAccountSheet(),
  );
}

class _DeleteAccountSheet extends ConsumerStatefulWidget {
  const _DeleteAccountSheet();

  @override
  ConsumerState<_DeleteAccountSheet> createState() =>
      _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<_DeleteAccountSheet> {
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final password = _passwordController.text;
    if (password.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final s = S.of(context);
    await ref.read(authNotifierProvider.notifier).deleteAccount(password);
    final result = ref.read(authNotifierProvider);

    if (!mounted) return;

    final failure = result.hasError ? result.error : null;
    if (failure != null) {
      setState(() {
        _submitting = false;
        _error = failure is FirebaseAuthException &&
                (failure.code == 'wrong-password' ||
                    failure.code == 'invalid-credential')
            ? s.deleteAccountWrongPassword
            : s.errGeneric;
      });
      return;
    }

    Navigator.of(context).pop();
    ref.read(guestModeProvider.notifier).state = false;
    Navigator.of(context)
        .pushNamedAndRemoveUntil('/', (_) => false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.deleteAccountSuccess),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
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
          border: Border.all(color: GameColors.error.withOpacity(0.4)),
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
                  color: GameColors.error.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_rounded,
                    size: 28, color: GameColors.error),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              s.deleteAccountWarningTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: gp.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.deleteAccountWarningBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: gp.textSec, height: 1.4),
            ),
            const SizedBox(height: 20),
            Text(
              s.deleteAccountPasswordLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: gp.textSec,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: true,
              autofocus: false,
              enabled: !_submitting,
              onSubmitted: (_) => _confirm(),
              decoration: InputDecoration(
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
                style: const TextStyle(
                    fontSize: 12.5, color: GameColors.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submitting ? null : _confirm,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.delete_forever_rounded, size: 18),
              label: Text(s.deleteAccountConfirmCta),
              style: FilledButton.styleFrom(
                backgroundColor: GameColors.error,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _submitting ? null : () => Navigator.pop(context),
              child: Text(s.guestLimitMaybeLater),
            ),
          ],
        ),
      ),
    );
  }
}
