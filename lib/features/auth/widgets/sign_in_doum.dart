import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../launch/launch_curtain_up.dart';
import '../../launch/launch_doum_handoff.dart';
import '../../mascot/doum_language_look.dart';
import '../../mascot/sprout.dart';

enum _Arrival {
  /// Not on screen yet: the launch curtain covers the page, or is flying
  /// the curtain's own Doum here.
  waiting,

  /// Pops up in his language's look.
  pop,

  /// The curtain's Doum landed here: the everyday Doum, who then turns
  /// round into his look.
  landed,
}

/// Doum at the head of the sign-in screen, where the app icon used to be
/// (Aziz, 2026-10-01, the canvas "Doum picks the language").
///
/// He wears the look of the app's language and turns round into the other
/// one when the language pill beside him is tapped (see DoumLanguageLook and
/// [controller]). How he first appears depends on what is in front of the
/// screen:
///  - the very first open's launch scene: the curtain flies its Doum into
///    this spot and he lands as the everyday Doum, then turns round into his
///    look (LaunchDoumHandoff);
///  - any other launch scene: he pops up once the curtain lifts, not under
///    it, where his pop and his hello would play unseen;
///  - no curtain (a sign-out, a return to this screen): he pops up at once.
class SignInDoum extends ConsumerStatefulWidget {
  const SignInDoum({super.key, required this.height, required this.controller});

  /// Sprout's reference height for him here (DoumLanguageLook.height).
  final double height;
  final DoumLookController controller;

  @override
  ConsumerState<SignInDoum> createState() => _SignInDoumState();
}

class _SignInDoumState extends ConsumerState<SignInDoum> {
  /// The box he lands on, registered with the curtain.
  final GlobalKey _stand = GlobalKey();
  late final LaunchDoumHandoff _handoff;
  late _Arrival _arrival;
  Timer? _dress;

  @override
  void initState() {
    super.initState();
    _handoff = ref.read(launchDoumHandoffProvider);
    _handoff.register(_stand, widget.height);
    _arrival = _decide();
    ref.listenManual<DoumHandoffPhase>(
      launchDoumHandoffProvider.select((h) => h.phase),
      (_, phase) {
        if (phase == DoumHandoffPhase.landed) return _landed();
        if (_arrival == _Arrival.waiting) {
          setState(() => _arrival = _decide());
        }
      },
    );
    ref.listenManual<bool>(launchCurtainUpProvider, (_, up) {
      if (!up && _arrival == _Arrival.waiting) {
        setState(() => _arrival = _decide());
      }
    });
  }

  _Arrival _decide() {
    final phase = _handoff.phase;
    if (phase == DoumHandoffPhase.expected ||
        phase == DoumHandoffPhase.flying) {
      return _Arrival.waiting;
    }
    if (ref.read(launchCurtainUpProvider)) return _Arrival.waiting;
    return _Arrival.pop;
  }

  void _landed() {
    if (_arrival == _Arrival.landed || !mounted) return;
    // Built in the very frame the curtain's Doum was last drawn, in the
    // same place: a breath, then he turns round into his look.
    setState(() => _arrival = _Arrival.landed);
    _dressSoon();
    // Spent: the next sign-in screen pops its Doum in as usual. After this
    // notification, not inside it.
    scheduleMicrotask(_handoff.done);
  }

  void _dressSoon() {
    _dress?.cancel();
    _dress = Timer(const Duration(milliseconds: 300), () {
      if (mounted) widget.controller.arriveDressed();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decoded while he waits, so neither the landing (the everyday Doum,
    // drawn in the frame the curtain's last one was) nor the pop shows an
    // empty box first.
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    final scale = sproutScaleFor(widget.height);
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
    if (old.height != widget.height) {
      _handoff.register(_stand, widget.height);
    }
  }

  @override
  void dispose() {
    _dress?.cancel();
    _handoff.unregister(_stand);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final box = DoumLanguageLook.sizeOf(widget.height);
    return SizedBox(
      key: _stand,
      width: box.width,
      height: box.height,
      child: switch (_arrival) {
        _Arrival.waiting => null,
        _Arrival.pop => DoumLanguageLook(
            height: widget.height,
            controller: widget.controller,
          ),
        _Arrival.landed => DoumLanguageLook(
            height: widget.height,
            controller: widget.controller,
            startPlain: true,
            entrance: SproutEntrance.none,
          ),
      },
    );
  }
}
