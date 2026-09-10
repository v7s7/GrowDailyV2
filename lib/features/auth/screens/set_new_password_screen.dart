import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../notifiers/auth_notifier.dart';

/// Setting a new password from a reset link, inside the app.
///
/// The link in the reset email is an App Link on this app's host, so a phone
/// hands it straight here and the web page in `public/reset/` is never drawn.
/// That page exists for a computer, and for a phone without the app, and it
/// says the same things in the same order on purpose.
///
/// Pushed by main.dart's [_handleDeepLink] over whatever is on screen, which
/// is usually the auth screen but does not have to be: a link can arrive
/// while someone is signed in with Google, and putting a password on that
/// account is exactly what it is for.
class SetNewPasswordScreen extends ConsumerStatefulWidget {
  /// From the reset email: a one-time code, and nobody signed in.
  const SetNewPasswordScreen({super.key, required this.oobCode})
      : accountEmail = null;

  /// From a provider sign-in that just cost this account its password. The
  /// person is already signed in and already proven, so there is no code and
  /// nothing to verify: the password is LINKED onto the open session.
  const SetNewPasswordScreen.addToAccount({
    super.key,
    required String email,
  })  : accountEmail = email,
        oobCode = null;

  /// Firebase's one-time code out of the link, or null in the add-to-account
  /// case.
  final String? oobCode;

  /// The address to attach a password to, or null in the reset case.
  final String? accountEmail;

  bool get isAdd => accountEmail != null;

  @override
  ConsumerState<SetNewPasswordScreen> createState() =>
      _SetNewPasswordScreenState();
}

enum _Stage { checking, ready, dead }

class _SetNewPasswordScreenState extends ConsumerState<SetNewPasswordScreen> {
  _Stage _stage = _Stage.checking;
  String _email = '';
  String? _error;
  bool _obscure = true;
  bool _saving = false;
  final _passCtrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.isAdd) {
      // Nothing to check: the session in hand IS the proof.
      _email = widget.accountEmail!;
      _stage = _Stage.ready;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
      return;
    }
    _verify();
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Checks the code before showing a field, so an expired link says so
  /// immediately instead of after someone has thought of a password and
  /// typed it twice.
  ///
  /// verifyPasswordResetCode does NOT consume the code; only
  /// confirmPasswordReset does.
  Future<void> _verify() async {
    try {
      final email = await FirebaseAuth.instance
          .verifyPasswordResetCode(widget.oobCode!);
      if (!mounted) return;
      setState(() {
        _email = email;
        _stage = _Stage.ready;
      });
      // The field is the only thing on the screen to do; opening the keyboard
      // saves a tap and tells the eye where to go.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    } on FirebaseAuthException {
      if (mounted) setState(() => _stage = _Stage.dead);
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.dead);
    }
  }

  Future<void> _save() async {
    final s = S.of(context);
    final pass = _passCtrl.text;
    if (pass.length < 6) {
      setState(() => _error = s.errPasswordTooShort);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    HapticFeedback.mediumImpact();

    try {
      if (widget.isAdd) {
        await ref.read(authNotifierProvider.notifier).addPassword(pass);
      } else {
        await FirebaseAuth.instance
            .confirmPasswordReset(code: widget.oobCode!, newPassword: pass);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (e.code == 'expired-action-code' || e.code == 'invalid-action-code') {
          _stage = _Stage.dead;
        } else if (e.code == 'provider-already-linked' ||
            e.code == 'credential-already-in-use') {
          _error = s.addPasswordAlready;
        } else if (e.code == 'weak-password') {
          _error = s.errWeakPassword;
        } else if (e.code == 'network-request-failed') {
          _error = s.errNetwork;
        } else {
          _error = s.errGeneric;
        }
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = s.errGeneric;
      });
      return;
    }

    // The password exists at this point, so nothing below may report
    // failure as if it did not. In the add case the session is already open
    // and there is nothing left to do; in the reset case, signing in is a
    // convenience on top: it is what the person came here to be able to do,
    // and they just proved they own the address. If it does not work, the
    // reset still stands and the auth screen is right there.
    if (!widget.isAdd) {
      await ref.read(authNotifierProvider.notifier).signIn(_email, pass);
    }
    if (!mounted) return;
    // Before the pop, and not only for tidiness: maybePop does nothing if
    // this screen is the only route, and a spinner left running forever is
    // the difference between "saved" and "still saving" on the one path
    // where the screen stays on screen.
    setState(() => _saving = false);
    final messenger = ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).maybePop();
    messenger?.showSnackBar(SnackBar(
      content: Text(widget.isAdd ? s.addPasswordDone : s.setPasswordDone),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);

    return Scaffold(
      backgroundColor: gp.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: IconButton(
                onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded),
                color: gp.textSec,
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: switch (_stage) {
                  _Stage.checking => _checking(s),
                  _Stage.dead => _dead(s),
                  _Stage.ready => _form(s),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _icon(IconData icon) {
    final gp = context.gp;
    return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: GameColors.gold.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(18),
        ),
      child: Icon(icon, size: 26, color: gp.goldInk),
    );
  }

  Widget _checking(S s) {
    final gp = context.gp;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _icon(Icons.lock_reset_rounded),
          const SizedBox(height: 22),
          Text(
            s.setPasswordChecking,
            style: TextStyle(fontSize: 15, color: gp.textSec, height: 1.5),
          ),
          const SizedBox(height: 20),
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ],
    );
  }

  Widget _dead(S s) {
    final gp = context.gp;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _icon(Icons.link_off_rounded),
          const SizedBox(height: 22),
          Text(
            s.resetLinkDeadTitle,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: gp.textPrimary),
          ),
          const SizedBox(height: 10),
          Text(
            s.resetLinkDeadBody,
            style: TextStyle(fontSize: 15, color: gp.textSec, height: 1.55),
          ),
          const SizedBox(height: 28),
          // Back to the screen that has the "forgot password?" link on it.
          // There is nothing this screen can do with a dead code, and asking
          // again is one tap from there.
          FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(s.resetLinkDeadCta),
          ),
        ],
    );
  }

  Widget _form(S s) {
    final gp = context.gp;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _icon(widget.isAdd ? Icons.password_rounded : Icons.lock_reset_rounded),
          const SizedBox(height: 22),
          Text(
            widget.isAdd ? s.addPasswordTitle : s.setPasswordTitle,
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: gp.textPrimary),
          ),
          const SizedBox(height: 8),
          if (widget.isAdd) ...[
            Text(
              s.addPasswordBody,
              style: TextStyle(fontSize: 15, color: gp.textSec, height: 1.55),
            ),
            const SizedBox(height: 6),
          ],
          // The address is never Arabic, so it carries its own direction the
          // same way the email FIELD does on the auth screen.
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${s.setPasswordSubject} '),
              TextSpan(
                text: _email,
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: gp.textPrimary),
              ),
            ]),
            textDirection: Directionality.of(context),
            style: TextStyle(fontSize: 15, color: gp.textSec, height: 1.55),
          ),
          const SizedBox(height: 26),
          TextField(
            selectionWidthStyle: GameTextStyles.selectionWidthStyle,
            controller: _passCtrl,
            focusNode: _focus,
            obscureText: _obscure,
            textDirection: TextDirection.ltr,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _saving ? null : _save(),
            style: TextStyle(fontSize: 16, color: gp.textPrimary),
            decoration: InputDecoration(
              labelText: s.password,
              prefixIcon:
                  Icon(Icons.lock_outline_rounded, size: 20, color: gp.textSec),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                  color: gp.textSec,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.setPasswordHint,
            style: TextStyle(fontSize: 12, color: gp.textTert, height: 1.5),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, size: 15, color: gp.errorInk),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                        fontSize: 13,
                        color: gp.errorInk,
                        fontWeight: FontWeight.w500,
                        height: 1.35),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 26),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                : Text(
                    s.setPasswordSave,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0),
                  ),
          ),
          const SizedBox(height: 22),
          // The one-time-link warning belongs to the reset only. In the add
          // case the way out is what matters instead: this is an offer, not
          // a gate, and the account works either way.
          if (widget.isAdd)
            Center(
              child: TextButton(
                onPressed:
                    _saving ? null : () => Navigator.of(context).maybePop(),
                style: TextButton.styleFrom(
                  foregroundColor: gp.textSec,
                  minimumSize: const Size(0, 48),
                ),
                child: Text(s.addPasswordLater),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 15, color: gp.textTert),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    s.setPasswordNote,
                    style: TextStyle(
                        fontSize: 12.5, color: gp.textSec, height: 1.5),
                  ),
                ),
              ],
            ),
        ],
    );
  }
}
