import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../../shared/widgets/app_snackbar.dart';

/// Confirmation sheet for permanently deleting the signed-in account.
///
/// Firebase needs a recent sign-in before it will delete a user, so the sheet
/// re-verifies first. HOW it re-verifies depends on the account: a password
/// account types its password, which doubles as a reasonable "are you sure"
/// gate for a destructive, irreversible action; a Google or Apple account has
/// no password to type and runs its provider's sheet again instead.
///
/// The password field used to be unconditional, and that was not merely
/// untidy. A Google or Apple account cannot satisfy it at all, so the sheet
/// was a dead end for those users and the app did not really offer in-app
/// account deletion to them, which App Store guideline 5.1.1(v) requires.
void showDeleteAccountSheet(BuildContext context, WidgetRef ref) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // Keeps the sheet's top clear of the status bar and notch. The bottom
    // inset is the sheet's own job: the card's outer margin adds MediaQuery
    // padding.bottom, so the footer button clears the gesture bar.
    useSafeArea: true,
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

  /// Resolved once, here, rather than on every build: nothing can change the
  /// signed-in account's providers while this sheet is up, and re-reading it
  /// mid-flow could swap the field out from under a half-typed password.
  late final AuthMethod _method = AuthNotifier.currentAuthMethod();

  bool get _needsPassword => _method == AuthMethod.password;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_submitting) return;
    final password = _passwordController.text;
    if (_needsPassword && password.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final s = S.of(context);
    final completed = await ref
        .read(authNotifierProvider.notifier)
        .deleteAccount(password: _needsPassword ? password : null);
    final result = ref.read(authNotifierProvider);

    if (!mounted) return;

    // The person backed out of Google's or Apple's sheet. That is an answer,
    // not a failure: drop back to the idle sheet with no error showing, so
    // they can either try again or close it.
    if (!completed) {
      setState(() => _submitting = false);
      return;
    }

    final failure = result.hasError ? result.error : null;
    if (failure != null) {
      setState(() {
        _submitting = false;
        _error = failure is FirebaseAuthException &&
                (failure.code == 'wrong-password' ||
                    failure.code == 'invalid-credential')
            // Only a password account can get this wrong by typing. For a
            // social account the same codes mean the provider handed back
            // something Firebase would not accept, which is not a
            // "wrong password" and must not be described as one.
            ? (_needsPassword ? s.deleteAccountWrongPassword : s.errGeneric)
            : s.errGeneric;
      });
      return;
    }

    // Both captured BEFORE the pop and the await. The pop below tears this
    // sheet down, so its own context is on its way out: reaching back
    // through it afterwards either trips the mounted guard and silently
    // skips everything that follows — the account is deleted but the user
    // is left sitting on the old screen with no confirmation and no return
    // to the root — or throws for using a defunct element. Holding the
    // Navigator and the messenger directly sidesteps both; neither depends
    // on this widget still being in the tree.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    navigator.pop();
    await setGuestMode(ref, false);
    navigator.pushNamedAndRemoveUntil('/', (_) => false);
    messenger.showOne(
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
        bottom: 24 +
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
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
                  borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
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
                child: Icon(Icons.warning_rounded,
                    size: 28, color: context.gp.errorInk),
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
            if (_needsPassword) ...[
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
                selectionWidthStyle: GameTextStyles.selectionWidthStyle,
                controller: _passwordController,
                obscureText: true,
                autofocus: false,
                enabled: !_submitting,
                onSubmitted: (_) => _confirm(),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: gp.surface,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(GameSpacing.buttonRadius),
                    borderSide: BorderSide(color: gp.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(GameSpacing.buttonRadius),
                    borderSide: BorderSide(color: gp.border),
                  ),
                ),
              ),
            ] else
              // No password to ask for. Say plainly what the confirm button
              // is about to do, so the provider's own sheet appearing over
              // the top of this one is expected rather than alarming at the
              // exact moment someone is deleting everything they have.
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: gp.surface,
                  borderRadius:
                      BorderRadius.circular(GameSpacing.buttonRadius),
                  border: Border.all(color: gp.border, width: 0.5),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 15,
                      color: gp.textTert,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _method == AuthMethod.apple
                            ? s.deleteAccountVerifyApple
                            : s.deleteAccountVerifyGoogle,
                        style: TextStyle(
                          fontSize: 12,
                          color: gp.textSec,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                    fontSize: 12.5, color: context.gp.errorInk),
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
