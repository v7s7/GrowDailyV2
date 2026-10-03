import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/l10n/wording_edits.dart';
import '../../core/theme/game_theme.dart';
import '../../core/utils/reduced_motion.dart';
import 'sprout.dart';

part 'doum_language_squares.dart';

/// What Doum wears: nothing (the everyday Doum), or the look of a language
/// (Aziz, 2026-10-01, the canvas "Doum picks the language"): a thobe, a
/// ghutra and an agal for Arabic, a suit and tie for English.
enum DoumLook { plain, thobe, suit }

/// The look for an app language: the thobe for Arabic, the suit otherwise.
DoumLook doumLookFor(String languageCode) =>
    languageCode == 'ar' ? DoumLook.thobe : DoumLook.suit;

/// The language a look speaks: what his «هلا» or "Hi" is said in. The
/// everyday Doum has none of his own and speaks the app's.
String? _languageOf(DoumLook look) => switch (look) {
      DoumLook.thobe => 'ar',
      DoumLook.suit => 'en',
      DoumLook.plain => null,
    };

enum _Angle { front, threeQuarter, side, back, greet, jump }

/// Each look's pictures by angle. Plain only ever starts a turn (the
/// curtain's Doum, landing on the sign-in screen, turns round into his
/// look), so it has no greeting or jump of its own.
SproutPose _poseOf(DoumLook look, _Angle angle) => switch (look) {
      DoumLook.plain => switch (angle) {
          _Angle.front || _Angle.greet || _Angle.jump => SproutPose.frontWave,
          _Angle.threeQuarter => SproutPose.threeQuarterWave,
          _Angle.side => SproutPose.sideRight,
          _Angle.back => SproutPose.back,
        },
      DoumLook.thobe => switch (angle) {
          _Angle.front => SproutPose.langThobeFront,
          _Angle.threeQuarter => SproutPose.langThobeThreeQuarter,
          _Angle.side => SproutPose.langThobeSide,
          _Angle.back => SproutPose.langThobeBack,
          _Angle.greet => SproutPose.langThobeGreet,
          _Angle.jump => SproutPose.langThobeJump,
        },
      DoumLook.suit => switch (angle) {
          _Angle.front => SproutPose.langSuitFront,
          _Angle.threeQuarter => SproutPose.langSuitThreeQuarter,
          _Angle.side => SproutPose.langSuitSide,
          _Angle.back => SproutPose.langSuitBack,
          // His wave, not the bow (Aziz, 2026-10-02: "no bow, just hand
          // on chest, and being lovely"). The suit sheet has no hand on the
          // chest, so the suit greets the way the thobe would if it could
          // not: waving, with the hop and the "Hi" (see [_DoumLanguageLookState._greet]).
          _Angle.greet => SproutPose.langSuitFront,
          _Angle.jump => SproutPose.langSuitJump,
        },
    };

/// Where his feet are across each picture (the middle of the span of green
/// at the bottom of the file, measured 2026-10-01), so every frame of the
/// turn stands on the same spot: the side views carry the ghutra or the
/// jacket behind him, which would otherwise slide him sideways as he turns.
const Map<SproutPose, double> kDoumFeetCentre = {
  SproutPose.frontWave: .483,
  SproutPose.threeQuarterWave: .456,
  SproutPose.sideRight: .495,
  SproutPose.back: .503,
  SproutPose.langThobeFront: .502,
  SproutPose.langThobeThreeQuarter: .560,
  SproutPose.langThobeSide: .662,
  SproutPose.langThobeBack: .498,
  SproutPose.langThobeGreet: .526,
  SproutPose.langThobeJump: .516,
  SproutPose.langSuitFront: .482,
  SproutPose.langSuitThreeQuarter: .518,
  SproutPose.langSuitSide: .551,
  SproutPose.langSuitBack: .501,
  SproutPose.langSuitGreet: .565,
  SproutPose.langSuitJump: .495,
};

/// The layer that draws the turn's frames while he turns, for tests.
const kDoumTurnKey = ValueKey('doum-turn');

/// How a turn commits the language it turns to: [setLocaleIn], which
/// keeps it on the device and mirrors it to the account. A provider so a
/// test can keep the change in memory (the real one writes the settings box
/// and asks Firebase who is signed in).
final doumLocaleCommitProvider =
    Provider<Future<void> Function(ProviderContainer, Locale)>(
  (ref) => setLocaleIn,
);

/// Starts Doum's turn from outside him: the language switch beside him (the
/// sign-in screen's pill, the Settings sheet's cards) asks him to change
/// the language rather than changing it itself, and the screen fades its
/// words out and in around the moment he swaps ([wordsVisible]).
class DoumLookController extends ChangeNotifier {
  _DoumLanguageLookState? _host;

  bool _wordsVisible = true;

  /// False for the moment the language changes behind his back: the screen's
  /// words fade out just before and back in, in the new language, just
  /// after, so the switch reads as his doing and the layout's flip from
  /// right-to-left to left-to-right is never seen.
  bool get wordsVisible => _wordsVisible;

  String? _pending;

  /// The language he is turning round to, until it has taken effect: what
  /// the switch shows as chosen meanwhile.
  String? get pendingLanguage => _pending;

  /// Whether he is in the middle of a turn.
  bool get turning => _host?._turning ?? false;

  /// Turns him round into [languageCode]'s look and changes the app's
  /// language while his back is turned. False when no Doum is on screen to
  /// do it, so the caller changes the language itself.
  bool switchTo(String languageCode) =>
      _host?._switchTo(languageCode) ?? false;

  /// From the plain Doum the launch curtain landed, into his language's
  /// look (see DoumLanguageLook.startPlain).
  void arriveDressed() => _host?._arriveDressed();

  /// A small hop onto his greeting (a hand on his chest in the thobe, a
  /// wave in the suit) and his «هلا» or "Hi": the language squares' answer
  /// to being picked (DoumLanguageSquares). Nothing while he is turning.
  void greet() => _host?._greet();

  void _words(bool visible, {bool notify = true}) {
    if (_wordsVisible == visible) return;
    _wordsVisible = visible;
    if (notify) notifyListeners();
  }

  void _setPending(String? code, {bool notify = true}) {
    if (_pending == code) return;
    _pending = code;
    if (notify) notifyListeners();
  }
}

/// Doum dressed for the app's language, turning round into the other one
/// when it changes.
///
/// ── The turn ───────────────────────────────────────────────────────────
///
/// About a second, in Doum's own numbers (sprout.dart): he sinks on his
/// feet, turns away through three-quarter and side to his back, swaps his
/// look there (the app's language changes in that frame, see
/// [DoumLookController.wordsVisible]), turns back the other way in the new
/// look, sinks again, jumps, and lands on his greeting (a hand on his chest
/// in the thobe, a wave in the suit) with a «هلا» or a "Hi". A moment
/// later he is back on his wave and still. The frames are cuts, 80 ms
/// apart, every one standing on the same spot ([kDoumFeetCentre]) and
/// decoded before he first shows, so none of them ever blinks.
///
/// Reduce Motion: no turn and no jump. The language changes at once and the
/// new look crossfades in (Sprout's own 180 ms fade).
///
/// If his screen goes away mid-turn (the sheet swiped down, a sign-in
/// button pressed) before his back is turned, the language still changes:
/// the person asked for it.
class DoumLanguageLook extends ConsumerStatefulWidget {
  const DoumLanguageLook({
    super.key,
    required this.height,
    this.controller,
    this.startPlain = false,
    this.entrance = SproutEntrance.pop,
    this.onTurned,
    this.look,
    this.helloAbove = false,
  });

  /// Sprout's reference height: how tall the everyday Doum would stand. The
  /// looks are drawn at the same scale, so the suit (his leaves up) stands
  /// 86% of it and the thobe 76%.
  final double height;

  final DoumLookController? controller;

  /// Starts as the everyday Doum, the one the launch curtain lands here
  /// (LaunchDoumHandoff), until [DoumLookController.arriveDressed].
  final bool startPlain;

  /// How he first appears (Sprout's entrance). Ignored with [startPlain]:
  /// that Doum arrives by flying in.
  final SproutEntrance entrance;

  /// Called when a turn asked for by [DoumLookController.switchTo] has
  /// landed (at once under Reduce Motion).
  final VoidCallback? onTurned;

  /// Always this look, whatever the app's language: each of the language
  /// squares' two Doums (DoumLanguageSquares) stands for his own language.
  /// Null follows the app's language, as he always did.
  final DoumLook? look;

  /// His «هلا» or "Hi" over his head rather than beside it, for a box with
  /// no room at the side (each language square is about his own width).
  final bool helloAbove;

  /// The box he takes at [height]: wide enough for the widest frame of the
  /// turn either side of his feet, as tall as the everyday Doum.
  static Size sizeOf(double height) => Size(height * .95, height);

  @override
  ConsumerState<DoumLanguageLook> createState() => _DoumLanguageLookState();
}

class _DoumLanguageLookState extends ConsumerState<DoumLanguageLook>
    with SingleTickerProviderStateMixin {
  static const _turnMs = 1050.0;

  /// When the look swaps, his back to the reader.
  static const _swapMs = 330.0;

  /// When the words start to fade, a moment before the swap.
  static const _wordsOutMs = 250.0;

  /// (from ms, angle, mirrored, in the new look). Away to the right through
  /// his back, round the other side mirrored, then the jump.
  static const _frames = <(double, _Angle, bool, bool)>[
    (0, _Angle.front, false, false),
    (90, _Angle.threeQuarter, false, false),
    (170, _Angle.side, false, false),
    (250, _Angle.back, false, false),
    (_swapMs, _Angle.back, false, true),
    (410, _Angle.side, true, true),
    (490, _Angle.threeQuarter, true, true),
    (570, _Angle.front, false, true),
    (650, _Angle.jump, false, true),
  ];

  /// (ms, lift in jump units, scaleX, scaleY), eased per segment like
  /// Sprout's own keys: the wind-up, the turn, the sink and the jump. The
  /// landing's squash is Sprout's pose swap onto the greeting.
  static const _keys = <List<double>>[
    [0, 0, 1.00, 1.00],
    [90, 0, 1.08, 0.88],
    [170, 0, 1.00, 1.00],
    [570, 0, 1.00, 1.00],
    [650, 0, 1.08, 0.88],
    [760, -22, 0.94, 1.08],
    [870, -25, 1.00, 1.00],
    [_turnMs, 0, 1.03, 0.96],
  ];

  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  )
    ..addListener(_onTick)
    ..addStatusListener(_onTurnStatus);

  final SproutController _moves = SproutController();
  final List<Timer> _timers = [];

  late DoumLook _look;
  late SproutPose _rest;
  DoumLook? _from;
  DoumLook? _to;

  /// The language this turn commits at the swap; null once committed, and
  /// for an arrival, which changes no language.
  String? _toCode;

  /// Whether this turn changes the language (a switch), as opposed to an
  /// arrival, which only dresses him.
  bool _changesLanguage = false;
  bool _swapped = false;
  bool _hello = false;
  bool _reduced = false;
  double? _precachedFor;
  ProviderContainer? _container;

  /// [doumLocaleCommitProvider], kept for [dispose], where ref is gone.
  Future<void> Function(ProviderContainer, Locale)? _commitFn;

  bool get _turning => _from != null;

  @override
  void initState() {
    super.initState();
    widget.controller?._host = this;
    _look = widget.startPlain
        ? DoumLook.plain
        : widget.look ?? doumLookFor(ref.read(localeProvider).languageCode);
    _rest = _poseOf(_look, _Angle.front);
    // The hello after his pop (an arrival says it after the turn instead).
    if (!widget.startPlain && widget.entrance != SproutEntrance.none) {
      _after(const Duration(milliseconds: 450), _sayHello);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
    _commitFn = ref.read(doumLocaleCommitProvider);
    _reduced = prefersReducedMotion(context);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    if (_precachedFor != dpr) {
      _precachedFor = dpr;
      final scale = sproutScaleFor(widget.height);
      for (final look in [
        if (widget.startPlain) DoumLook.plain,
        DoumLook.thobe,
        DoumLook.suit,
      ]) {
        for (final angle in _Angle.values) {
          precacheImage(
            sproutImage(_poseOf(look, angle), scale, dpr),
            context,
            onError: (_, __) {},
          );
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant DoumLanguageLook old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._host == this) old.controller!._host = null;
      widget.controller?._host = this;
    }
  }

  void _after(Duration delay, VoidCallback run) => _timers.add(
        Timer(delay, () {
          if (mounted) run();
        }),
      );

  void _cancelTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  /// The «هلا» or "Hi", for a moment.
  void _sayHello() {
    setState(() => _hello = true);
    _after(const Duration(milliseconds: 2600), () {
      setState(() => _hello = false);
    });
  }

  /// Picked: a hop onto his greeting with his hello, then back to his wave.
  /// Under Reduce Motion the pose and the hello without the hop.
  void _greet() {
    if (!mounted || _turning || _look == DoumLook.plain) return;
    _cancelTimers();
    setState(() {
      _hello = false;
      _rest = _poseOf(_look, _Angle.greet);
    });
    if (!_reduced) _moves.hop();
    _sayHello();
    _after(const Duration(milliseconds: 1800), () {
      setState(() => _rest = _poseOf(_look, _Angle.front));
    });
  }

  bool _switchTo(String code) {
    if (!mounted) return false;
    final to = doumLookFor(code);
    if (_turning) {
      // Still dressing after his landing, his back not yet turned: he
      // turns round into the language just picked instead, and changes it
      // at the swap. Otherwise one turn at a time, and the tap is spent.
      if (!_changesLanguage && !_swapped) {
        final live = ref.read(localeProvider).languageCode;
        setState(() {
          _to = to;
          _rest = _poseOf(to, _Angle.front);
          _toCode = code == live ? null : code;
          _changesLanguage = _toCode != null;
        });
        widget.controller?._setPending(_toCode);
      }
      return true;
    }
    final current = ref.read(localeProvider).languageCode;
    if (code == current && to == _look) return true;
    if (_reduced) {
      _commit(code);
      _cancelTimers();
      setState(() {
        _look = to;
        _rest = _poseOf(to, _Angle.front);
      });
      _sayHello();
      widget.onTurned?.call();
      return true;
    }
    _begin(from: _look, to: to, code: code);
    return true;
  }

  void _arriveDressed() {
    if (!mounted || _turning || _look != DoumLook.plain) return;
    final to =
        widget.look ?? doumLookFor(ref.read(localeProvider).languageCode);
    if (_reduced) {
      setState(() {
        _look = to;
        _rest = _poseOf(to, _Angle.front);
      });
      _sayHello();
      return;
    }
    _begin(from: DoumLook.plain, to: to);
  }

  void _begin({required DoumLook from, required DoumLook to, String? code}) {
    _cancelTimers();
    setState(() {
      _from = from;
      _to = to;
      _toCode = code;
      _changesLanguage = code != null;
      _swapped = false;
      _hello = false;
      // Behind the turn, so the swap Sprout plays for it has settled by the
      // landing and he lands from his own look's front.
      _rest = _poseOf(to, _Angle.front);
    });
    widget.controller?._setPending(code);
    _turn.forward(from: 0);
  }

  void _onTick() {
    if (!_turning) return;
    final ms = _turn.value * _turnMs;
    if (!_swapped && ms >= _swapMs) {
      _swapped = true;
      final code = _toCode;
      if (code != null) _commit(code);
      if (_changesLanguage) widget.controller?._words(true);
    } else if (!_swapped && _changesLanguage && ms >= _wordsOutMs) {
      widget.controller?._words(false);
    }
  }

  void _onTurnStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_turning) return;
    final to = _to!;
    final asked = _changesLanguage;
    setState(() {
      _look = to;
      _rest = _poseOf(to, _Angle.greet);
      _from = null;
      _to = null;
    });
    _sayHello();
    if (asked) widget.onTurned?.call();
    _after(const Duration(milliseconds: 1600), () {
      setState(() => _rest = _poseOf(_look, _Angle.front));
    });
  }

  void _commit(String code) {
    _toCode = null;
    widget.controller?._setPending(null);
    final container = _container;
    if (container != null) {
      unawaited(ref.read(doumLocaleCommitProvider)(container, Locale(code)));
    }
  }

  @override
  void dispose() {
    // Gone before his back was turned: the language still changes. Quietly,
    // since the screen around him is going too, and just after this frame:
    // a dispose runs while the tree is being finalised, where changing a
    // provider the app's widgets watch is refused.
    final code = _toCode;
    final container = _container;
    final commit = _commitFn;
    if (code != null && container != null && commit != null) {
      // Never an error out of a microtask: the app's container outlives
      // every screen, but a container torn down with the screen (a test's)
      // would refuse the write, and that must not surface elsewhere.
      scheduleMicrotask(() {
        try {
          unawaited(
            commit(container, Locale(code)).catchError((Object _) {}),
          );
        } catch (_) {}
      });
    }
    final c = widget.controller;
    if (c != null) {
      c._words(true, notify: false);
      c._setPending(null, notify: false);
      if (c._host == this) c._host = null;
    }
    _cancelTimers();
    _turn.dispose();
    _moves.dispose();
    super.dispose();
  }

  static List<double> _keyAt(double ms) {
    for (var i = 1; i < _keys.length; i++) {
      final b = _keys[i];
      if (ms <= b[0]) {
        final a = _keys[i - 1];
        final span = b[0] - a[0];
        final u =
            Curves.easeInOut.transform(span <= 0 ? 1 : (ms - a[0]) / span);
        return [
          for (var k = 1; k < 4; k++) lerpDouble(a[k], b[k], u)!,
        ];
      }
    }
    final last = _keys.last;
    return [last[1], last[2], last[3]];
  }

  Widget _frame(Size box, double dpr) {
    final ms = _turn.value * _turnMs;
    var step = _frames.first;
    for (final f in _frames) {
      if (ms >= f.$1) step = f;
    }
    final pose = _poseOf(step.$4 ? _to! : _from!, step.$2);
    final mirror = step.$3;
    final size = Sprout.sizeOf(pose, widget.height);
    final cx = kDoumFeetCentre[pose] ?? .5;
    final left = box.width / 2 - (mirror ? 1 - cx : cx) * size.width;
    final k = _keyAt(ms);
    final unit = widget.height / 150;
    Widget picture = Image(
      image: sproutImage(pose, sproutScaleFor(widget.height), dpr),
      width: size.width,
      height: size.height,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      excludeFromSemantics: true,
    );
    if (mirror) picture = Transform.flip(flipX: true, child: picture);
    return Transform(
      alignment: Alignment.bottomCenter,
      transform: Matrix4.translationValues(0, k[0] * unit, 0)
        ..multiply(Matrix4.diagonal3Values(k[1], k[2], 1)),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: left,
            bottom: 0,
            width: size.width,
            height: size.height,
            child: picture,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // His language changed some other way (the account's, adopted after a
    // sign-in): he changes with it, without a turn.
    ref.listen<Locale>(localeProvider, (_, next) {
      if (_turning || _look == DoumLook.plain || widget.look != null) return;
      final want = doumLookFor(next.languageCode);
      if (want != _look) {
        setState(() {
          _look = want;
          _rest = _poseOf(want, _Angle.front);
        });
      }
    });

    final s = S.of(context);
    // Each look says hello in its own language: the thobe «هلا», the suit
    // "Hi", whichever language the app is in (the two squares stand side by
    // side, one for each).
    final speaks = _languageOf(_look);
    final hi = speaks == null
        ? s.doumHi
        : S.edited(Locale(speaks), WordingScope.of(context)).doumHi;
    final h = widget.height;
    final box = DoumLanguageLook.sizeOf(h);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final restSize = Sprout.sizeOf(_rest, h);
    final restCx = kDoumFeetCentre[_rest] ?? .5;
    final centre = box.width / 2;
    final unit = h / 150;
    // The hello sits beside his head on the side reading ends on, its tail
    // at its start corner, pointing back at him.
    final helloInset = centre + .30 * h;
    final hello = AnimatedOpacity(
      opacity: _hello ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: AnimatedScale(
        scale: _hello || _reduced ? 1 : .85,
        alignment:
            rtl ? Alignment.bottomRight : Alignment.bottomLeft,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: SproutBubble(text: hi, tailAtStart: true),
      ),
    );

    return IgnorePointer(
      child: Semantics(
        label: s.sproutName,
        image: true,
        excludeSemantics: true,
        child: SizedBox(
          width: box.width,
          height: box.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // His shadow, under whichever picture is up; it narrows as he
              // jumps.
              Positioned(
                left: centre - 40 * unit,
                width: 80 * unit,
                bottom: -4 * unit,
                height: 9 * unit,
                child: AnimatedBuilder(
                  animation: _turn,
                  builder: (_, __) {
                    final lift = _turning
                        ? (_keyAt(_turn.value * _turnMs)[0] / -25)
                            .clamp(0.0, 1.0)
                        : 0.0;
                    return Transform.scale(
                      scaleX: 1 - .35 * lift,
                      child: Opacity(
                        opacity: 1 - .5 * lift,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0x1F28283C),
                            borderRadius: BorderRadius.all(
                              Radius.elliptical(40 * unit, 4.5 * unit),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                left: centre - restCx * restSize.width,
                bottom: 0,
                child: Opacity(
                  opacity: _turning ? 0 : 1,
                  child: Sprout(
                    pose: _rest,
                    height: h,
                    controller: _moves,
                    entrance: widget.startPlain
                        ? SproutEntrance.none
                        : widget.entrance,
                    idleBreaths: 2,
                  ),
                ),
              ),
              if (_turning)
                Positioned.fill(
                  key: kDoumTurnKey,
                  child: AnimatedBuilder(
                    animation: _turn,
                    builder: (_, __) => _frame(box, dpr),
                  ),
                ),
              if (widget.helloAbove)
                Positioned(
                  bottom: restSize.height + 2 * unit,
                  left: -box.width,
                  right: -box.width,
                  child: Center(child: hello),
                )
              else
                Positioned(
                  bottom: restSize.height * .5,
                  left: rtl ? null : helloInset,
                  right: rtl ? helloInset : null,
                  child: hello,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
