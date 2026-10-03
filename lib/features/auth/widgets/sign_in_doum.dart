import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../launch/launch_curtain_up.dart';
import '../../launch/launch_doum_handoff.dart';
import '../../mascot/doum_language_look.dart';
import '../../mascot/sprout.dart';

/// The language squares at the head of the sign-in screen, where the app
/// icon used to be: Doum in the suit for English on the left, in the thobe
/// for العربية on the right, both on screen at once (Aziz, 2026-10-02; see
/// DoumLanguageSquares). They replaced the «العربية / EN» pill and the one
/// Doum who turned round from one look into the other.
///
/// How the two Doums first appear depends on what is in front of the
/// screen:
///  - the very first open's launch scene: the curtain flies its Doum into
///    the square of the app's language, where he lands as the everyday Doum
///    and turns round into its look (LaunchDoumHandoff); the other square's
///    Doum pops up beside him;
///  - any other launch scene: both pop up once the curtain lifts, not under
///    it, where their pop and their hello would play unseen;
///  - no curtain (a sign-out, a return to this screen): both pop up at once.
class SignInDoum extends ConsumerStatefulWidget {
  const SignInDoum({
    super.key,
    required this.height,
    required this.doumHeight,
    required this.controller,
    this.enabled = true,
  });

  /// Each square's height: the head's whole box.
  final double height;

  /// Sprout's reference height for each Doum (DoumLanguageLook.height), and
  /// so the size the curtain's flying Doum lands at.
  final double doumHeight;

  /// The screen's: its words fade around a change of language.
  final DoumLookController controller;

  /// False while a sign-in is running: changing the language mid flight
  /// rebuilds the screen under the request.
  final bool enabled;

  @override
  ConsumerState<SignInDoum> createState() => _SignInDoumState();
}

class _SignInDoumState extends ConsumerState<SignInDoum> {
  /// Doum's box in the square of the app's language, registered with the
  /// curtain as the spot its Doum lands on.
  final GlobalKey _stand = GlobalKey();
  late final LaunchDoumHandoff _handoff;
  late DoumSquaresArrival _arrival;

  @override
  void initState() {
    super.initState();
    _handoff = ref.read(launchDoumHandoffProvider);
    _handoff.register(_stand, widget.doumHeight);
    _arrival = _decide();
    ref.listenManual<DoumHandoffPhase>(
      launchDoumHandoffProvider.select((h) => h.phase),
      (_, phase) {
        if (phase == DoumHandoffPhase.landed) return _landed();
        if (_arrival == DoumSquaresArrival.waiting) {
          setState(() => _arrival = _decide());
        }
      },
    );
    ref.listenManual<bool>(launchCurtainUpProvider, (_, up) {
      if (!up && _arrival == DoumSquaresArrival.waiting) {
        setState(() => _arrival = _decide());
      }
    });
  }

  DoumSquaresArrival _decide() {
    final phase = _handoff.phase;
    if (phase == DoumHandoffPhase.expected ||
        phase == DoumHandoffPhase.flying) {
      return DoumSquaresArrival.waiting;
    }
    if (ref.read(launchCurtainUpProvider)) return DoumSquaresArrival.waiting;
    return DoumSquaresArrival.pop;
  }

  void _landed() {
    if (_arrival == DoumSquaresArrival.landed || !mounted) return;
    // Built in the very frame the curtain's Doum was last drawn, in the
    // same place: a breath, then he turns round into his look (the squares
    // time that, see DoumSquaresArrival.landed).
    setState(() => _arrival = DoumSquaresArrival.landed);
    // Spent: the next sign-in screen pops its Doums in as usual. After this
    // notification, not inside it.
    scheduleMicrotask(_handoff.done);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decoded while he waits, so neither the landing (the everyday Doum,
    // drawn in the frame the curtain's last one was) nor the pop shows an
    // empty box first.
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    final scale = sproutScaleFor(widget.doumHeight);
    for (final pose in const [
      SproutPose.frontWave,
      SproutPose.langThobeFront,
      SproutPose.langSuitFront,
    ]) {
      precacheImage(
        sproutImage(pose, scale, dpr),
        context,
        onError: (_, __) {},
      );
    }
  }

  @override
  void didUpdateWidget(covariant SignInDoum old) {
    super.didUpdateWidget(old);
    if (old.doumHeight != widget.doumHeight) {
      _handoff.register(_stand, widget.doumHeight);
    }
  }

  @override
  void dispose() {
    _handoff.unregister(_stand);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DoumLanguageSquares(
        height: widget.height,
        doumHeight: widget.doumHeight,
        controller: widget.controller,
        enabled: widget.enabled,
        arrival: _arrival,
        standKey: _stand,
      );
}
