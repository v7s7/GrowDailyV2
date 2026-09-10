import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/services/local_store_service.dart';
import '../../../core/utils/reduced_motion.dart';
import '../../../core/theme/game_theme.dart';
import '../../../shared/widgets/app_logo.dart';
import '../notifiers/auth_notifier.dart';
import '../notifiers/guest_reconnect_provider.dart';
import '../services/social_auth_service.dart';
import '../widgets/language_toggle.dart';
import '../widgets/social_sign_in_buttons.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isSignIn = true;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _isSendingReset = false;
  /// Shown in the banner slot instead of an error after a reset email is
  /// requested. Cleared on any mode switch or new submit, like the error.
  bool _resetSent = false;
  final _emailCtrl = TextEditingController();
  /// Used to bring the revealed form into view, and to put the caret in the
  /// first field. Without both, tapping "Continue with email" on a small
  /// phone changes nothing anyone can see: the form opens below the fold and
  /// the screen sits exactly where it was.
  final _scrollCtrl = ScrollController();
  final _emailFocus = FocusNode();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _errorMessage;

  /// The submit button, so that a message which pushes it down can pull it
  /// back up into view. See [_revealSubmit].
  final _submitKey = GlobalKey();

  /// Which of the two banner slots the current message belongs to.
  ///
  /// True for anything the email form itself said, which renders directly
  /// under the password field; false for a Google or Apple failure, which
  /// renders below the whole stack because it has to be able to speak while
  /// the form is still closed. Set by whichever path is about to produce a
  /// message, before its await, so the listener in initState does not have
  /// to work out where the error came from.
  bool _bannerInForm = false;

  /// Whether this device still holds guest progress, which is what the
  /// fresh-start warning below is about. Resolved once, in initState:
  /// nothing can create or destroy guest data while this screen is up.
  bool _hasGuestProgress = false;

  @override
  void initState() {
    super.initState();
    LocalStoreService.hasGuestProgress().then((has) {
      if (mounted && has) setState(() => _hasGuestProgress = true);
    });
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
              // Social sign-in adds these two. The first is the common one:
              // the address behind the Google or Apple account already has a
              // password account here, and the way out is entirely in their
              // hands. The second only fires when the provider is switched
              // off in the Firebase console, so it must not read as their
              // mistake or invite a retry that will fail identically.
              'account-exists-with-different-credential' =>
                s.errAccountExistsWithEmail,
              'operation-not-allowed' => s.errSignInMethodUnavailable,
              'apple-account-required' => s.errAppleAccountRequired,
              _ => s.errGeneric,
            };
          }
          setState(() => _errorMessage = msg);
          if (_bannerInForm) _revealSubmit();
        },
      );
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _scrollCtrl.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = S.of(context);
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    setState(() {
      _bannerInForm = true;
      _errorMessage = null;
      _resetSent = false;
    });

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _errorMessage = s.errFillAll);
      _revealSubmit();
      return;
    }
    if (!_isSignIn && pass != _confirmCtrl.text) {
      setState(() => _errorMessage = s.errPasswordsMismatch);
      _revealSubmit();
      return;
    }
    if (!_isSignIn && pass.length < 6) {
      setState(() => _errorMessage = s.errPasswordTooShort);
      _revealSubmit();
      return;
    }

    HapticFeedback.mediumImpact();
    final notifier = ref.read(authNotifierProvider.notifier);
    if (_isSignIn) {
      await notifier.signIn(email, pass);
      return;
    }
    // Armed BEFORE the await, and that ordering is the whole point.
    //
    // createUserWithEmailAndPassword makes authStateChanges emit the new
    // user immediately, part-way through register(). _AuthGate (main.dart)
    // routes on that emission, so this screen is disposed while the await
    // is still running and NOTHING after it is guaranteed to execute. Arming
    // afterwards behind the usual `if (!mounted) return` meant the flag was
    // never set on the one path it exists for, and the sheet never appeared.
    //
    // Arming early is safe because the offer provider independently requires
    // a signed-in uid, so a flag set before a registration that then fails
    // shows nothing; the disarm below clears it anyway, and that one DOES
    // run, since a failed registration never emits and never disposes this
    // screen.
    if (_hasGuestProgress) {
      ref.read(justRegisteredProvider.notifier).state = true;
    }
    await notifier.register(email, pass);
    if (!mounted) return;
    if (ref.read(authNotifierProvider).hasError) {
      ref.read(justRegisteredProvider.notifier).state = false;
    }
  }

  Future<void> _sendReset() async {
    final s = S.of(context);
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() {
        _bannerInForm = true;
        _errorMessage = s.errEnterEmailForReset;
        _resetSent = false;
      });
      _revealSubmit();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _bannerInForm = true;
      _isSendingReset = true;
      _errorMessage = null;
    });
    final outcome =
        await ref.read(authNotifierProvider.notifier).sendPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _isSendingReset = false;
      // Same confirmation whether the address exists or not - see
      // sendPasswordReset's doc comment. Each failure now says its own thing:
      // this used to blame the network for all of them, so a rate limit read
      // as "your wifi is down".
      _resetSent = outcome == ResetOutcome.sent;
      _errorMessage = switch (outcome) {
        ResetOutcome.sent => null,
        ResetOutcome.network => s.errNetwork,
        ResetOutcome.tooMany => s.errTooManyRequests,
        ResetOutcome.failed => s.errGeneric,
      };
    });
    _revealSubmit();
  }

  /// Whether the email form is showing.
  ///
  /// Closed by default. Everything the form contains (both tabs, both
  /// fields, the confirm field, the forgot link, the submit button) used to
  /// be on screen at first paint, which put eleven controls in front of
  /// someone who has not decided anything yet and pushed the guest button
  /// below the fold on a 390x844 phone. The guest button is how most people
  /// meet this app, so that was the wrong thing to lose.
  ///
  /// The email path is still a full-size button in the same stack as Apple
  /// and Google rather than a text link: somewhere between one in seven and
  /// one in three people still want it, which is far too many to hide behind
  /// low-affordance treatment, and a bare text link would also miss the
  /// 44pt/48dp platform tap-target minimums.
  bool _emailOpen = false;

  /// Which provider's sheet is currently open, or null.
  ///
  /// Tracked separately from the notifier's own loading state so the spinner
  /// lands on the button that was actually tapped. The notifier only knows
  /// that *something* is in flight, and a single shared flag would have spun
  /// both buttons at once.
  SocialProvider? _socialBusy;

  Future<void> _social(SocialProvider provider) async {
    HapticFeedback.mediumImpact();
    setState(() {
      _bannerInForm = false;
      _socialBusy = provider;
      _errorMessage = null;
      _resetSent = false;
    });
    await ref.read(authNotifierProvider.notifier).signInWithSocial(provider);
    // A sign-in that succeeded has already disposed this screen, so reaching
    // here at all usually means it failed or was cancelled. The error banner
    // itself is the listener's job (see initState); this only has to put the
    // buttons back.
    if (!mounted) return;
    setState(() => _socialBusy = null);
  }

  void _setEmailOpen(bool open) {
    HapticFeedback.selectionClick();
    setState(() {
      _emailOpen = open;
      // A banner left over from the other path would read as if it belonged
      // to this one.
      _errorMessage = null;
      _resetSent = false;
    });
    if (!open) {
      // Going back up: drop the keyboard and return to the top, so the three
      // buttons are where they were before the detour.
      _emailFocus.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        _scrollCtrl.animateTo(
          0,
          duration: GameMotion.relaxed,
          curve: Curves.easeOutCubic,
        );
      });
      return;
    }
    // Opening: the form is laid out BELOW the button that was just tapped,
    // and on a 375x667 phone that is off the bottom of the screen, so
    // without this the tap looks like it did nothing at all. Focusing the
    // first field is what does the scrolling, because the framework keeps
    // the focused editable on screen, and it is also what someone who just
    // asked for the email form wants next.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _emailFocus.requestFocus();
    });
  }

  /// Holds the submit button on screen while a message opens above it.
  ///
  /// The message is worth the height it costs, but on a 375x667 phone the
  /// button's bottom edge already sits 12pt off the fold, so any message at
  /// all pushes the button that was just pressed off the screen, and an
  /// answer you can read next to a button you cannot reach is only half a
  /// fix.
  ///
  /// It corrects the scroll on EVERY frame of the banner's growth rather
  /// than waiting for the growth to finish and then animating: the button is
  /// pinned to the bottom edge as the box opens, so the whole thing is one
  /// motion, the message growing while the screen above it slides up by the
  /// same amount at the same rate. Waiting first was measurably worse in two
  /// ways. It looked like two events with a pause between them, the box
  /// opening and then the screen jumping; and the scroll it computed came
  /// from a box that had not finished growing, which on a 375x667 phone left
  /// the button 5pt below the edge, with the right delay differing per phone
  /// anyway since the message wraps to a different number of lines.
  ///
  /// The frame loop watches maxScrollExtent, NOT the button's own position,
  /// and that is the whole reason it works: the button's bottom is the thing
  /// being pinned, so it stops moving immediately and would read as "the
  /// layout has settled" while the banner was still opening. The extent
  /// tracks the content's height, which only stops changing when the growth
  /// really is over.
  ///
  /// Nothing happens while the button is fully on screen, and that guard is
  /// not an optimisation: ensureVisible ALIGNS, it does not scroll the
  /// minimum, so without it a message would yank a comfortably visible
  /// button down to the bottom edge and drag the whole screen with it.
  void _revealSubmit() {
    double? previousExtent;
    var frames = 0;
    void keepInView(Duration _) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final ctx = _submitKey.currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (ctx == null || box == null || !box.hasSize) return;
      final media = MediaQuery.of(context);
      // With the keyboard up, the window ends where the keyboard starts.
      final visibleBottom = media.size.height - media.viewInsets.bottom;
      final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      if (bottom > visibleBottom - 8) {
        // Zero duration on purpose: this runs every frame, so each step is a
        // few points and the sequence IS the animation. An animated scroll
        // here would be a second curve fighting the banner's own.
        Scrollable.ensureVisible(ctx, alignment: 1.0, duration: Duration.zero);
      }
      // 30 frames is half a second at 60fps, comfortably longer than the
      // banner takes and short enough that a layout which never settles
      // gives up rather than polling for the life of the screen.
      final extent = _scrollCtrl.position.maxScrollExtent;
      if (extent != previousExtent && frames < 30) {
        previousExtent = extent;
        frames++;
        WidgetsBinding.instance
          ..addPostFrameCallback(keepInView)
          ..scheduleFrame();
      }
    }

    WidgetsBinding.instance
      ..addPostFrameCallback(keepInView)
      ..scheduleFrame();
  }

  /// One line of the pair under the buttons: a bolded lead, then the fact.
  ///
  /// Text.rich rather than two widgets so the lead and the fact wrap as one
  /// paragraph. At 200% text the fact runs to a second line and has to flow
  /// under the lead, which a Row would not let it do.
  Widget _fact(BuildContext context, String lead, String rest) {
    final gp = context.gp;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: lead,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: gp.textPrimary,
            ),
          ),
          TextSpan(text: ' $rest'),
        ],
      ),
      textAlign: TextAlign.start,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        // 4.99:1 on the cream background, so it clears AA for normal text.
        color: gp.textSec,
        height: 1.45,
      ),
    );
  }

  Future<void> _continueAsGuest() async {
    HapticFeedback.mediumImpact();
    await setGuestMode(ref, true);
  }

  void _switchMode(bool isSignIn) {
    HapticFeedback.selectionClick();
    setState(() {
      _isSignIn = isSignIn;
      _errorMessage = null;
      _resetSent = false;
    });
  }

  /// The reset confirmation and the error, as one slot rendered in two
  /// places: [inForm] under the password field for anything the email form
  /// said, and once more below the whole stack for a social failure.
  ///
  /// Both copies are always in the tree and at most one of them is ever
  /// non-empty, which is what [_bannerInForm] decides. Built here rather
  /// than written out twice so the two can never drift apart, and the slot
  /// whose turn it is not collapses its AnimatedSize to zero rather than
  /// holding height.
  Widget _banner(BuildContext context, {required bool inForm}) {
    final s = S.of(context);
    final mine = _bannerInForm == inForm;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reset-sent confirmation - same slot and motion as the error
        // below, opposite tone, and mutually exclusive with it (_sendReset
        // and _submit each clear the other's flag).
        AnimatedSize(
          duration: GameMotion.standard,
          curve: Curves.easeOutCubic,
          // Grows from the TOP, not the centre. AnimatedSize defaults to
          // centre, which slides the content up as the box opens and reads
          // as the banner arriving from two directions at once; the row
          // below it is being pushed down either way.
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            // The size alone was not enough: the text used to reach full
            // strength on the first frame and be revealed by the growing
            // clip, which wipes rather than fades. Traced on the simulator,
            // the ink hit full red at 240ms while the box was still opening
            // until ~400ms.
            duration: GameMotion.standard,
            child: !(mine && _resetSent)
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.mark_email_read_outlined,
                            size: 15, color: context.gp.emeraldInk),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            s.authResetSent,
                            style: TextStyle(
                                fontSize: 13,
                                color: context.gp.emeraldInk,
                                fontWeight: FontWeight.w500,
                                height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),

        // Error
        AnimatedSize(
          duration: GameMotion.standard,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: GameMotion.standard,
            child: !mine || _errorMessage == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    // Keyed on the message so one error replacing another
                    // cross-fades too, rather than swapping the words inside
                    // a box that never moved.
                    key: ValueKey(_errorMessage),
                    padding: const EdgeInsets.only(top: 14),
                    child: Row(
                      // Start, not centre: errInvalidCredential runs to two
                      // lines now that it names the social way in, and a
                      // centred icon would float against the middle of the
                      // paragraph instead of sitting on its first line.
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            size: 15, color: context.gp.errorInk),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                                fontSize: 13,
                                color: context.gp.errorInk,
                                fontWeight: FontWeight.w500,
                                height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isLoading = ref.watch(authNotifierProvider).isLoading;
    final appleAvailable = SocialAuthService.instance.appleAvailable;
    final googleAvailable = SocialAuthService.instance.googleAvailable;
    // Measured, not guessed: with the form closed the content ends 56% down
    // a 402x874 iPhone, leaving 382pt of dead space, while the same column
    // reaches 98% on a 375x667 phone at 1.6x text. So the slack is real on
    // big phones and absent on small ones, and one fixed layout cannot serve
    // both. Two values move with the viewport; everything else stays put.
    //
    // Deliberately NOT bottom-anchored and NOT proportionally distributed:
    // both push the guest button toward the fold on the small phone, which
    // is the exact regression the collapsed form exists to prevent.
    // Reduce Motion removes the MOVEMENT, not the cross-fade. Apple's own
    // guidance and WCAG both treat a fade as the correct replacement for a
    // slide, so every entrance below keeps its fadeIn and only loses its
    // travel. Collapsing the distance to zero is also why this is one
    // expression rather than a second code path: there is no arrangement of
    // widgets that only exists in the calm build, so nothing can drift.
    final calm = prefersReducedMotion(context);
    final tallPhone = MediaQuery.sizeOf(context).height >= 780;
    final topGap = tallPhone ? 88.0 : 40.0;
    final logoSize = tallPhone ? 88.0 : 72.0;
    // Every control on the screen goes flat while ANY sign-in is running.
    // Two flows racing each other is not a state Firebase or the guest
    // handover has an answer for: a provider sheet open over a submitted
    // email form could resolve in either order and leave the reconnect
    // offer armed for the wrong account.
    final busy = isLoading || _socialBusy != null;

    return Scaffold(
      backgroundColor: gp.bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The language switch lives INSIDE the gap that was already
              // blank above the logo, rather than in a row of its own. This
              // screen's vertical budget is measured, not guessed (see the
              // tallPhone comment above), and already overflows a 375x667
              // phone at 1.6x text: a row added to this column would push the
              // guest button toward the fold, which is the exact regression
              // the collapsed email form exists to prevent. Reusing the gap
              // costs nothing, because topGap is 40 at its smallest and the
              // toggle draws 32.
              //
              // Hidden while a sign-in is running, for the same reason every
              // other control here goes flat: changing the language mid
              // flight rebuilds the screen under the request.
              SizedBox(
                height: topGap,
                child: busy
                    ? null
                    : const Align(
                        alignment: AlignmentDirectional.topEnd,
                        child: LanguageToggle(),
                      ),
              ),

              // Logo
              Center(
                child: Column(
                  children: [
                    // The real app icon, not a gold-tinted box with a
                    // Material grid glyph in it. This is the first screen
                    // after tapping the icon on the home screen, so showing
                    // anything else here breaks the one visual thread the
                    // person was actually following.
                    AppLogo(size: logoSize),
                    const SizedBox(height: 18),
                    Text(
                      'Grow Daily',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: gp.textPrimary,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Treated as the lockup's subhead rather than as body
                    // copy: one step up in size and weight, and a capped
                    // measure so that when it wraps it wraps where a
                    // designer put the break, not wherever the phone is wide.
                    // w500 because only 400/500/600/700 of IBM Plex Sans
                    // Arabic are bundled, and anything else silently fetches
                    // a font over the network on the app's first screen.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Text(
                        s.tagline,
                        style: TextStyle(
                          fontSize: 15,
                          color: gp.textSec,
                          fontWeight: FontWeight.w500,
                          height: 1.45,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: calm ? 0 : -0.04, curve: Curves.easeOut),

              const SizedBox(height: 32),

              // One-tap providers, above the email form.
              //
              // Above rather than below, and that ordering is the whole
              // point of adding them: a returning user's fastest path in is
              // the button they used last time, and a new user's is the
              // account they already have. Burying them under a form nobody
              // has filled in yet turns a one-tap sign-in into a scroll.
              //
              // Apple before Google on iOS. Guideline 4.8 asks for Sign in
              // with Apple to be presented as an equivalent option wherever
              // another social login is offered, and "equivalent" is judged
              // on prominence: putting it first is the unambiguous reading,
              // and it is also what the person on an iPhone most likely
              // wants. The pair does not appear at all on a platform where
              // neither provider works, which is why the divider and the
              // spacing are inside the same conditional rather than
              // stranded above an empty gap.
              if (appleAvailable) ...[
                SocialSignInButton.apple(
                  label: s.continueWithApple,
                  loading: _socialBusy == SocialProvider.apple,
                  onPressed: busy ? null : () => _social(SocialProvider.apple),
                ).animate(delay: 120.ms).fadeIn(duration: 350.ms).slideY(
                      begin: calm ? 0 : 0.06,
                    ),
                const SizedBox(height: 10),
              ],
              if (googleAvailable) ...[
                SocialSignInButton.google(
                  label: s.continueWithGoogle,
                  loading: _socialBusy == SocialProvider.google,
                  onPressed: busy ? null : () => _social(SocialProvider.google),
                ).animate(delay: 160.ms).fadeIn(duration: 350.ms).slideY(
                      begin: calm ? 0 : 0.06,
                    ),
              ],
              // The email path, as a third button in the same stack as Apple
              // and Google. Styled neutrally so it reads as the quieter of
              // the three without becoming fine print, and deliberately NOT
              // the gold OutlinedButton the guest action uses further down,
              // which would make two different decisions look identical.
              if (!_emailOpen) ...[
                const SizedBox(height: 10),
                // No icon, and that is a correctness fix as much as a
                // tidiness one. The Apple and Google buttons place their
                // marks with PositionedDirectional inside a Stack, so their
                // LABELS are centred in the full button width. `.icon`
                // centres icon-plus-label as a group instead, which put this
                // label at x=210.1 while Apple's sat at 201.0 on a 402pt
                // screen: a 9pt stagger that grows with text size.
                //
                // The leading column is also the wrong place for a Material
                // glyph. It holds two brand marks that Apple and Google both
                // forbid restyling, so nothing that CAN be restyled belongs
                // beside them.
                OutlinedButton(
                  onPressed: busy ? null : () => _setEmailOpen(true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: gp.textPrimary,
                    backgroundColor: gp.surface,
                    // divider rather than border: at gp.border this and the
                    // white Google button above read as a matched pair of
                    // light outlined controls, ranking a brand option and a
                    // fallback as equals. The lighter rule lets it recede.
                    side: BorderSide(color: gp.divider),
                    textStyle: GameTextStyles.labelLarge
                        .copyWith(fontWeight: FontWeight.w500),
                  ),
                  child: Text(s.continueWithEmail),
                ).animate(delay: 200.ms).fadeIn(duration: 350.ms).slideY(
                      begin: calm ? 0 : 0.06,
                    ),
              ],

              // Everything below is the email form, revealed in place. It
              // opens under the buttons it belongs with rather than on a
              // second screen, so nothing is navigated away from and the
              // fast paths stay visible above it.
              if (_emailOpen) ...[
                if (appleAvailable || googleAvailable) ...[
                  const SizedBox(height: GameSpacing.xl),
                  LabelledDivider(label: s.authOrDivider)
                      .animate()
                      .fadeIn(duration: 250.ms),
                  const SizedBox(height: GameSpacing.xl),
                ] else
                  const SizedBox(height: 16),

                // Tab toggle. It governs the email form underneath it and
                // nothing above it, since with a provider there is no such
                // thing as a separate "sign in" and "create account".
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
              ).animate(delay: 0.ms).fadeIn(duration: 400.ms),

              const SizedBox(height: 24),

              // Email
              TextField(
                selectionWidthStyle: GameTextStyles.selectionWidthStyle,
                controller: _emailCtrl,
                focusNode: _emailFocus,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                // An email address is never Arabic. Left to inherit the
                // ambient RTL direction, the field lays the value out as an
                // RTL paragraph: the caret starts on the right and the dots
                // and the @ resolve to the wrong side while it is typed.
                // Only the VALUE is forced; the label, hint and icon stay in
                // the ambient direction so the field still reads as part of
                // an Arabic form.
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 16, color: gp.textPrimary),
                decoration: InputDecoration(
                  labelText: s.email,
                  prefixIcon: Icon(Icons.mail_outline_rounded,
                      size: 20, color: gp.textSec),
                ),
              ).animate(delay: 40.ms).fadeIn(duration: 350.ms).slideY(begin: calm ? 0 : 0.04),

              const SizedBox(height: 14),

              // Password
              TextField(
                selectionWidthStyle: GameTextStyles.selectionWidthStyle,
                controller: _passCtrl,
                obscureText: _obscurePass,
                // Same reasoning as the email field above.
                textDirection: TextDirection.ltr,
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
              ).animate(delay: 80.ms).fadeIn(duration: 350.ms).slideY(begin: calm ? 0 : 0.04),

              // Whatever the form has to say goes HERE, against the fields
              // it is about, rather than at the bottom of the screen under
              // the way back out. "Wrong email or password" printed below
              // the "other ways in" link sat four elements away from the
              // field it referred to, with the submit button in between, so
              // the form read as if it had done nothing at all. Here it also
              // lands directly above the forgot-password link, which is the
              // next thing to reach for once it appears.
              _banner(context, inForm: true),

              // Forgot password (sign-in only). AlignmentDirectional so the
              // link hugs the trailing edge in both directions - end is
              // where the eye lands after the password field in each script.
              if (_isSignIn)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: _isSendingReset ? null : _sendReset,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      minimumSize: const Size(44, 32),
                    ),
                    child: _isSendingReset
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            s.authForgotPassword,
                            style: TextStyle(
                                fontSize: 12.5, color: gp.textSec),
                          ),
                  ),
                ),

              // Confirm password (register only)
              AnimatedSize(
                duration: GameMotion.relaxed,
                curve: Curves.easeOutCubic,
                child: _isSignIn
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: TextField(
                          selectionWidthStyle: GameTextStyles.selectionWidthStyle,
                          controller: _confirmCtrl,
                          obscureText: _obscureConfirm,
                          textDirection: TextDirection.ltr,
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

              // Fresh-start warning for a guest who is creating the
              // account (register mode only): their local progress will
              // NOT carry over, and this is the last moment that fact can
              // still change their decision.
              //
              // Gated on the DATA existing, not on guestModeProvider. That
              // flag is always false here and this warning therefore never
              // rendered once, in either direction: _AuthGate (main.dart)
              // only builds this screen when guest mode is off, and every
              // path that sends a guest here - the Rooms gate, the guest
              // limit sheet, sign-out - calls setGuestMode(ref, false)
              // before it navigates. The registered '/auth' route is never
              // pushed by anything. Asking LocalStoreService instead is
              // both reachable and the better question: what matters is
              // whether there is progress on this device to lose.
              if (!_isSignIn && _hasGuestProgress)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: gp.surface,
                      borderRadius:
                          BorderRadius.circular(GameSpacing.buttonRadius),
                      border: Border.all(color: gp.border, width: 0.5),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 15, color: gp.textTert),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.guestFreshStartWarning,
                            style: TextStyle(
                                fontSize: 12,
                                color: gp.textSec,
                                height: 1.45),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 28),

              // Submit button
              FilledButton(
                key: _submitKey,
                onPressed: busy ? null : _submit,
                // The spinner belongs to the EMAIL flow only. Without the
                // second half of this condition, tapping Google spun this
                // button too, so the screen showed two things loading and
                // pointed at the wrong one.
                child: isLoading && _socialBusy == null
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
              ).animate(delay: 120.ms).fadeIn(duration: 350.ms).slideY(begin: calm ? 0 : 0.06),

                // The way back out. Worded as what it reveals rather than
                // as "back", because nothing was navigated away from: the
                // form opened in place, under the buttons it belongs with.
                Center(
                  child: TextButton.icon(
                    onPressed: busy ? null : () => _setEmailOpen(false),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                    label: Text(s.authOtherWays),
                    style: TextButton.styleFrom(
                      foregroundColor: gp.textSec,
                      // 48 clears both platform tap-target minimums
                      // (44pt iOS, 48dp Android) and WCAG 2.2 SC 2.5.8,
                      // which a bare Text would not.
                      minimumSize: const Size(0, 48),
                      tapTargetSize: MaterialTapTargetSize.padded,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ).animate().fadeIn(duration: 250.ms),
              ],

              // The banner slot for the OTHER path: a cancelled or failed
              // Apple or Google sign-in, which has to be able to speak while
              // the form is still closed, and that is the most common way
              // either of them is seen. Anything the email form itself says
              // renders in its own slot, under the password field.
              _banner(context, inForm: false),


              // The caption sits ABOVE its button now, not under it. Read
              const SizedBox(height: 12),
              // A tonal button, NOT the theme's default OutlinedButton, and
              // this is a legibility fix rather than a style preference.
              //
              // game_theme.dart sets OutlinedButton's foregroundColor AND
              // its side to GameColors.gold. On the cream light background
              // that puts the label, the icon and the border all at gold on
              // cream, which measures 1.86:1: far under the 4.5:1 a label
              // needs and under the 3:1 a border needs. In dark mode the
              // same pair is 10.09:1 and fine, which is exactly why it went
              // unnoticed.
              //
              // A gold TINT with the normal ink label fixes it without
              // making this the loudest control on the screen: a solid gold
              // fill would out-shout Apple and Google, and "try without an
              // account" should not outrank signing in. Measured: ink on the
              // tint is 14.06:1 light and 13.11:1 dark, and the goldDim
              // border is 4.13:1 light, 10.09:1 dark.
              //
              // Scoped to this button on purpose. Every OutlinedButton in
              // the app inherits the same 1.86:1 pair in light mode, but
              // that is an app-wide theme change and its own piece of work.
              // Same reasoning as the email button for the missing icon,
              // plus one of its own: a play triangle is a media glyph, and
              // this is an account decision, not a video.
              FilledButton(
                onPressed: busy ? null : _continueAsGuest,
                style: FilledButton.styleFrom(
                  backgroundColor: GameColors.gold.withValues(alpha: 0.16),
                  foregroundColor: gp.textPrimary,
                  // gp.goldEdge, not a hand-rolled brightness ternary: it is
                  // the token that already means "the accent, held to the
                  // 3:1 a border has to clear", and unlike a literal it
                  // follows whichever preset the person is on.
                  side: BorderSide(color: gp.goldEdge),
                  // w600 to match the Apple and Google labels. The theme's
                  // labelLarge is w700, so left alone this button and the
                  // email one shouted over the two vendor buttons they sit
                  // under, which is backwards.
                  textStyle: GameTextStyles.labelLarge
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                child: Text(s.tryAsGuest),
              ).animate(delay: 280.ms).fadeIn(duration: 350.ms).slideY(begin: calm ? 0 : 0.06),

              // The one thing the screen never said: what each path does
              // with your progress. It goes BELOW the buttons, not between
              // the wordmark and them, for two reasons. Anything inserted
              // above delays the only decision this screen exists to
              // collect, and it costs the same height on the small phone
              // that is already tight as it does on the tall phone with
              // 382pt going spare. Below, it lands in the empty band and
              // replaces the old one-line caption rather than adding to it.
              //
              // Start-aligned, and that is the point: it is the only
              // start-aligned element here, so the two leads line up on the
              // leading edge and the pair reads as a pair. Centring them
              // would leave the leads ragged and the parallel would die.
              // That alignment is the separation between the account paths
              // and the guest path, at zero height and with no rule drawn.
              const SizedBox(height: 22),
              Center(
                child: ConstrainedBox(
                  // A fixed pt cap, deliberately not scaled with text: it is
                  // what keeps the measure short when someone is at 200%.
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _fact(context, s.authAccountLead, s.authAccountFact),
                      const SizedBox(height: 6),
                      _fact(context, s.authGuestLead, s.authGuestFact),
                    ],
                  ),
                ),
              ).animate(delay: 320.ms).fadeIn(duration: 350.ms),

              const SizedBox(height: 40),
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
          duration: GameMotion.standard,
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
