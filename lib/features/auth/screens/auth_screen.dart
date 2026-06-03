import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/game_theme.dart';
import '../notifiers/auth_notifier.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isSignIn = true;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<void>>(authNotifierProvider, (_, next) {
      next.whenOrNull(
        error: (e, _) {
          if (!mounted) return;
          final s = S.of(context);
          String msg = s.errGeneric;
          if (e is FirebaseAuthException) {
            msg = switch (e.code) {
              'user-not-found' || 'wrong-password' || 'invalid-credential' =>
                s.errInvalidCredential,
              'email-already-in-use' => s.errEmailInUse,
              'invalid-email' => s.errInvalidEmail,
              'weak-password' => s.errWeakPassword,
              'network-request-failed' => s.errNetwork,
              _ => s.errGeneric,
            };
          }
          setState(() => _errorMessage = msg);
        },
      );
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = S.of(context);
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    setState(() => _errorMessage = null);

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = s.errFillAll);
      return;
    }
    if (!_isSignIn && pass != _confirmCtrl.text) {
      setState(() => _errorMessage = s.errPasswordsMismatch);
      return;
    }
    if (!_isSignIn && pass.length < 6) {
      setState(() => _errorMessage = s.errPasswordTooShort);
      return;
    }

    HapticFeedback.mediumImpact();
    final notifier = ref.read(authNotifierProvider.notifier);
    if (_isSignIn) {
      await notifier.signIn(email, pass);
    } else {
      await notifier.register(email, pass);
    }
  }

  void _continueAsGuest() {
    HapticFeedback.mediumImpact();
    ref.read(guestModeProvider.notifier).state = true;
  }

  void _switchMode(bool isSignIn) {
    HapticFeedback.selectionClick();
    setState(() {
      _isSignIn = isSignIn;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isLoading = ref.watch(authNotifierProvider).isLoading;

    return Scaffold(
      backgroundColor: gp.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 64),

              // Logo
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: GameColors.gold.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: GameColors.gold.withOpacity(0.3), width: 1),
                      ),
                      child: const Icon(Icons.trending_up_rounded,
                          size: 38, color: GameColors.gold),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'GrowDaily',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.tagline,
                      style: TextStyle(
                          fontSize: 14,
                          color: gp.textSec,
                          fontWeight: FontWeight.w400),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: -0.04, curve: Curves.easeOut),

              const SizedBox(height: 48),

              // Tab toggle
              Container(
                height: 46,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: gp.surface,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: gp.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    _TabBtn(
                      label: s.signIn,
                      active: _isSignIn,
                      onTap: () => _switchMode(true),
                    ),
                    _TabBtn(
                      label: s.createAccount,
                      active: !_isSignIn,
                      onTap: () => _switchMode(false),
                    ),
                  ],
                ),
              ).animate(delay: 100.ms).fadeIn(duration: 400.ms),

              const SizedBox(height: 24),

              // Email
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                style: TextStyle(fontSize: 16, color: gp.textPrimary),
                decoration: InputDecoration(
                  labelText: s.email,
                  prefixIcon: Icon(Icons.mail_outline_rounded,
                      size: 20, color: gp.textSec),
                ),
              ).animate(delay: 150.ms).fadeIn(duration: 350.ms).slideY(begin: 0.04),

              const SizedBox(height: 14),

              // Password
              TextField(
                controller: _passCtrl,
                obscureText: _obscurePass,
                textInputAction:
                    _isSignIn ? TextInputAction.done : TextInputAction.next,
                onSubmitted: _isSignIn ? (_) => _submit() : null,
                style: TextStyle(fontSize: 16, color: gp.textPrimary),
                decoration: InputDecoration(
                  labelText: s.password,
                  prefixIcon: Icon(Icons.lock_outline_rounded,
                      size: 20, color: gp.textSec),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 20,
                      color: gp.textSec,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ).animate(delay: 190.ms).fadeIn(duration: 350.ms).slideY(begin: 0.04),

              // Confirm password (register only)
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: _isSignIn
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: TextField(
                          controller: _confirmCtrl,
                          obscureText: _obscureConfirm,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          style:
                              TextStyle(fontSize: 16, color: gp.textPrimary),
                          decoration: InputDecoration(
                            labelText: s.confirmPassword,
                            prefixIcon: Icon(Icons.lock_outline_rounded,
                                size: 20, color: gp.textSec),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                                color: gp.textSec,
                              ),
                              onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                        ),
                      ),
              ),

              // Error
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: _errorMessage == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                size: 15, color: GameColors.error),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: GameColors.error,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),

              const SizedBox(height: 28),

              // Submit button
              FilledButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : Text(
                        _isSignIn ? s.signInAction : s.createAccountAction,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0),
                      ),
              ).animate(delay: 230.ms).fadeIn(duration: 350.ms).slideY(begin: 0.06),

              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: isLoading ? null : _continueAsGuest,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(s.tryAsGuest),
              ).animate(delay: 280.ms).fadeIn(duration: 350.ms).slideY(begin: 0.06),
              const SizedBox(height: 8),
              Text(
                s.guestDescription,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: gp.textTert, height: 1.35),
              ),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabBtn(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: active ? gp.surfaceHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.07),
                        blurRadius: 4,
                        offset: const Offset(0, 1))
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? gp.textPrimary : gp.textSec,
            ),
          ),
        ),
      ),
    );
  }
}
