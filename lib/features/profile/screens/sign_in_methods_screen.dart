import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../../auth/models/sign_in_methods.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../auth/screens/auth_screen.dart';
import '../../auth/screens/set_new_password_screen.dart';
import '../../auth/services/social_auth_service.dart';

/// Profile, Settings, Account, "How you sign in": every way into the account
/// that is signed in right now, and the two actions that end the two ways a
/// person can lose their way back in.
///
/// 1. **The password Firebase deleted.** An account whose address was never
///    verified loses its password the moment that address signs in with
///    Google or Apple. The app notices and offers a new one, but only on the
///    sign-in where it happens: tap Later and the offer never returns, and
///    accounts that lost theirs before that detector shipped never saw it.
///    "Add a password" here is the standing version of that offer.
/// 2. **The duplicate account Apple's Hide My Email creates.** A relay
///    address matches no existing account, so Apple opens a second, empty
///    one and the habits look gone. Connecting Apple from INSIDE the real
///    account is the only join Firebase offers, and after it the Apple
///    button lands on the real data every time.
///
/// Deliberately not gated on Premium, and deliberately not hidden behind a
/// problem: a person who has just discovered they cannot get in is in no
/// state to hunt for a screen that only appears when the app agrees
/// something is wrong.
class SignInMethodsScreen extends ConsumerStatefulWidget {
  const SignInMethodsScreen({super.key});

  @override
  ConsumerState<SignInMethodsScreen> createState() =>
      _SignInMethodsScreenState();
}

class _SignInMethodsScreenState extends ConsumerState<SignInMethodsScreen> {
  /// One at a time: every action here runs a provider sheet or a network
  /// call, and two of them at once could unlink the last way in.
  bool _busy = false;

  void _refresh() =>
      ref.read(signInMethodsRefreshProvider.notifier).state++;

  void _say(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _connect(SocialProvider provider) async {
    if (_busy) return;
    final s = S.of(context);
    final name = provider == SocialProvider.google ? 'Google' : 'Apple';
    setState(() => _busy = true);
    try {
      await ref.read(authNotifierProvider.notifier).connectProvider(provider);
      _refresh();
      if (mounted) _say(s.signInMethodConnected(name));
    } on SocialSignInCancelled {
      // Dismissing the provider sheet is an answer, not a failure.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'provider-already-linked') {
        _refresh();
        _say(s.signInMethodConnected(name));
      } else if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use' ||
          e.code == 'account-exists-with-different-credential') {
        _say(s.signInMethodInUse(name));
      } else {
        // The auth screen already words every provider failure, including
        // the ones a retry cannot fix (no Apple Account on the device,
        // provider switched off, too many attempts).
        _say(AuthScreen.errorMessageFor(s, e, fromSocial: true));
      }
    } catch (_) {
      if (mounted) _say(s.errGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String providerId, String name) async {
    if (_busy) return;
    final s = S.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.gp.surface,
        title: Text(s.signInMethodRemoveTitle(name)),
        content: Text(s.signInMethodRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.signOutConfirmCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: ctx.gp.errorInk),
            child: Text(s.signInMethodRemove),
          ),
        ],
      ),
    );
    // Re-read after the dialog: another action may have finished while it
    // was open, and removing what is by then the last way in would lock the
    // account out of itself.
    if (yes != true || !mounted || _busy) return;
    if (ref.read(signInMethodsProvider).isLastWayIn) {
      _say(s.signInMethodsFooter);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(authNotifierProvider.notifier).removeProvider(providerId);
      _refresh();
      if (mounted) _say(s.signInMethodRemoved(name));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'no-such-provider') {
        // It was already gone. Nothing failed, the list was just behind.
        _refresh();
        _say(s.signInMethodRemoved(name));
      } else if (e.code == 'requires-recent-login') {
        _say(s.signInMethodRemoveStale);
      } else {
        _say(e.code == 'network-request-failed' ? s.errNetwork : s.errGeneric);
      }
    } catch (_) {
      if (mounted) _say(s.errGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPassword(String email) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SetNewPasswordScreen.addToAccount(email: email),
    ));
    // The screen pops itself on success and says nothing on the way back, so
    // re-reading the providers is how this list learns what happened. The
    // reload is a courtesy; linking already updated the live user, and this
    // future is not awaited by the caller, so it must not throw.
    if (!mounted) return;
    try {
      await FirebaseAuth.instance.currentUser?.reload();
    } catch (_) {}
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final m = ref.watch(signInMethodsProvider);
    // No ways in at all means no account behind this screen: a guest who
    // reached it somehow, or the frame after a sign-out. Offering Connect
    // there would only produce "no current user" from Firebase.
    final signedIn = m.count > 0;

    return Scaffold(
      backgroundColor: gp.bg,
      appBar: AppBar(
        backgroundColor: gp.bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Text(
          s.signInMethodsTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: gp.textPrimary,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
            s.signInMethodsIntro,
            style: TextStyle(fontSize: 12.5, height: 1.5, color: gp.textSec),
          ),
          const SizedBox(height: 16),
          _MethodCard(
            children: [
              _MethodRow(
                icon: Icons.mail_outline_rounded,
                label: s.signInMethodPassword,
                detail: m.hasPassword
                    ? (m.accountEmail.isEmpty ? null : m.accountEmail)
                    : (m.emailIsHidden
                        ? s.signInMethodPasswordHidden
                        : s.signInMethodPasswordHint),
                connected: m.hasPassword,
                onlyWayIn: m.hasPassword && m.isLastWayIn,
                busy: _busy,
                actionLabel: m.hasPassword
                    ? s.signInMethodRemove
                    : s.signInMethodSetPassword,
                // A password needs an address it belongs to, and a reset mail
                // needs one that reaches a real inbox: Apple's relay has
                // neither, so the row explains instead of offering.
                onAction: m.hasPassword
                    ? (m.isLastWayIn
                        ? null
                        : () => _remove(
                            passwordProviderId, s.signInMethodPassword))
                    : (m.canAddPassword
                        ? () => _addPassword(m.accountEmail)
                        : null),
              ),
              if (m.hasGoogle || SocialAuthService.instance.googleAvailable)
                _MethodRow(
                  icon: Icons.g_mobiledata_rounded,
                  label: 'Google',
                detail: m.hasGoogle ? m.googleEmail : s.signInMethodConnectHint,
                connected: m.hasGoogle,
                onlyWayIn: m.hasGoogle && m.isLastWayIn,
                busy: _busy,
                actionLabel: m.hasGoogle
                    ? s.signInMethodRemove
                    : s.signInMethodConnect,
                onAction: m.hasGoogle
                    ? (m.isLastWayIn
                        ? null
                        : () => _remove(googleProviderId, 'Google'))
                    : (signedIn ? () => _connect(SocialProvider.google) : null),
              ),
              if (m.hasApple || SocialAuthService.instance.appleAvailable)
                _MethodRow(
                  icon: Icons.apple_rounded,
                  label: 'Apple',
                detail: m.hasApple ? m.appleEmail : s.signInMethodConnectHint,
                connected: m.hasApple,
                onlyWayIn: m.hasApple && m.isLastWayIn,
                busy: _busy,
                actionLabel:
                    m.hasApple ? s.signInMethodRemove : s.signInMethodConnect,
                onAction: m.hasApple
                    ? (m.isLastWayIn
                        ? null
                        : () => _remove(appleProviderId, 'Apple'))
                    : (signedIn ? () => _connect(SocialProvider.apple) : null),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            s.signInMethodsFooter,
            style: TextStyle(fontSize: 11.5, height: 1.5, color: gp.textSec),
          ),
        ],
      ),
    );
  }
}

/// The same card the settings groups use, without their section label: this
/// screen's title is the label.
class _MethodCard extends StatelessWidget {
  const _MethodCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Material(
      color: gp.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
        side: BorderSide(color: gp.border, width: 0.5),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Container(height: 0.5, color: gp.divider),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.icon,
    required this.label,
    required this.connected,
    required this.actionLabel,
    required this.busy,
    this.detail,
    this.onlyWayIn = false,
    this.onAction,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final bool connected;
  final bool onlyWayIn;
  final bool busy;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon,
              size: 20,
              color: connected ? gp.textPrimary : gp.textSec),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: gp.textPrimary,
                  ),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: TextStyle(fontSize: 11, height: 1.4, color: gp.textSec),
                  ),
                ],
                if (onlyWayIn) ...[
                  const SizedBox(height: 2),
                  Text(
                    s.signInMethodOnlyWayIn,
                    style: TextStyle(
                      fontSize: 11,
                      color: gp.textSec,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // No action at all rather than a disabled button when there is
          // nothing this row can offer (the last way in, or a password on a
          // hidden address): the explanation above it is the answer.
          if (onAction != null)
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onAction!.call();
                    },
              style: TextButton.styleFrom(
                foregroundColor: connected ? gp.errorInk : gp.emeraldInk,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
