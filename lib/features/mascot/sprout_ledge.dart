import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/game_constants.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/services/local_store_service.dart';
import '../../core/theme/game_theme.dart';
import '../../core/utils/reduced_motion.dart';
import '../../shared/widgets/snack_bar_watch.dart';
import 'day_card_sprout.dart';
import 'sprout.dart';
import 'sprout_echo.dart';
import 'sprout_mood.dart';

part 'sprout_bottom.dart';

// ─── The sprout on the board's edge ─────────────────────────────────────────
//
// Aziz, 2026-09-28, choosing from the "Sprout on the Grid" canvas
// (https://claude.ai/artifact/XMonTkt6mxDtP6AyngN96a): the sprout leaves the
// day card, where it hung 12pt off the card's edge and fought the ring, and
// peeks over the top edge of the habit board instead (option D). Then, in his
// words: "attach to the line, on all phones, and user can slide it left and
// right, smooth and no glitches", "drop it down to hide it", "a pop up says
// are you sure, and you can bring it back in setting".
//
// So it lives in a lane between the day card and the board. The lane's
// bottom IS the board's top edge (the Grid lays the two out with nothing
// between), and everything of the sprout below that line is clipped, so it
// always reads as standing behind the board, looking over it, whatever the
// phone.

/// The front pose's height on the ledge, like Sprout(height:). Every other
/// pose is drawn at the same scale (see SproutPose).
const double kLedgeSproutHeight = 80;

/// The lane between the day card and the board. With [kLedgePeek] it shows
/// the sprout from its leaves to the top of its belly, the whole face: the
/// files draw the face down to 0.62 of the front pose's height and the belly
/// starts at 0.66, and (44 + 8 + 1.4) / 80 cuts at 0.668.
const double kLedgeLaneHeight = 44;

/// The gap the board kept above it before the sprout moved here, and keeps
/// again while the sprout is hidden.
const double kLedgeClosedHeight = 14;

/// How far the leaves rise above the lane, over the day card's foot. The
/// card's ring stops 9pt above the card's bottom edge, so 8 never touches it.
const double kLedgePeek = 8;

// The files keep a transparent margin above the leaves: 0.018 of the front
// pose's height (12px of 767, measured on every pose).
const double _kArtTop = 0.018 * kLedgeSproutHeight;

/// How much of the sprout shows above the line at rest.
const double _kVisible = kLedgeLaneHeight + kLedgePeek;

/// How far below the line the pose box's bottom (its feet) sits at rest.
const double _kFeetBelowLine = kLedgeSproutHeight - _kArtTop - _kVisible;

/// Sunk this far, the leaves are below the line too: gone.
const double _kMaxSink = _kVisible + 6;

/// Let go past half of it and the sprout asks to be hidden.
const double _kHideAt = _kVisible * 0.5;

/// The sleeping pose lies down, so its face is lower in its box: lifted by
/// this much it sleeps on the board's edge instead of under it.
const double _kSleepLift = 12;

/// Half the front pose's width: the sprout's centre never goes closer than
/// this to the ends of the line, so it never hangs past the board.
final double _kHalfWidth =
    Sprout.sizeOf(SproutPose.frontWave, kLedgeSproutHeight).width / 2;

/// How far a finger must travel from where it touched the sprout before it
/// picks the sprout up, at most. Measured as a straight distance from the
/// touch, not along the path, so a tap that wobbles back and forth stays a
/// tap (the laugh); on an iPhone a tap can wander 12pt and still be one.
///
/// It also has to stay under the page's own threshold, or the page scrolls
/// (or the tabs swipe) under a finger that started on the sprout. That is
/// NOT one number: iOS leaves it at kTouchSlop (18), Android reports its
/// own, 8dp on most phones (ViewConfiguration.getScaledTouchSlop, passed in
/// through MediaQuery's gestureSettings). So the pick-up is 12, or one point
/// under the device's slop when that is smaller: 7 on Android (Aziz,
/// 2026-09-28: "easily click on the pet, not by mistake slide the screen").
const double _kPickUpSlop = 12;

// ─── Settings ───────────────────────────────────────────────────────────────
//
// Both live on this device (Hive), read synchronously from the settings box
// main() opens before the first frame, so the Grid never draws the sprout
// for one frame and then takes it away, or draws it in one place and then
// jumps. A device setting like the dark-mode switch beside it: hidden on one
// phone is not a decision about another.

const _kHiddenKey = 'grid_sprout_hidden_v1';
const _kSpotKey = 'grid_sprout_spot_v1';

Box<dynamic>? _settingsBox() => LocalStoreService.settingsBoxOpen
    ? Hive.box<dynamic>(GameConstants.boxSettings)
    : null;

/// Whether the sprout stands on the Grid. Hidden by pulling it down behind
/// the board (after a question) or by the switch in Settings › الشكل; the
/// switch is also the way back. Only "hidden" is ever stored.
class GridSproutShownNotifier extends StateNotifier<bool> {
  GridSproutShownNotifier() : super(_settingsBox()?.get(_kHiddenKey) != true);

  Future<void> set(bool shown) async {
    if (state == shown) return;
    state = shown;
    final box = _settingsBox();
    if (box == null) return;
    try {
      if (shown) {
        await box.delete(_kHiddenKey);
      } else {
        await box.put(_kHiddenKey, true);
      }
    } catch (_) {}
  }
}

final gridSproutShownProvider =
    StateNotifierProvider<GridSproutShownNotifier, bool>(
  (ref) => GridSproutShownNotifier(),
);

/// Where along the board's edge the person left the sprout: 0 at the start
/// end of the line, 1 at the far end. A share of the line rather than
/// points, so it lands in the same place on every phone, and measured from
/// the reading start, so it stays over the same weekday if the language
/// changes. Null until the sprout is first moved: it stands over today's
/// column until then (see SproutLedge.todayFromStart).
class GridSproutSpotNotifier extends StateNotifier<double?> {
  GridSproutSpotNotifier()
      : super((_settingsBox()?.get(_kSpotKey) as num?)?.toDouble());

  Future<void> set(double spot) async {
    final clamped = spot.clamp(0.0, 1.0).toDouble();
    state = clamped;
    final box = _settingsBox();
    if (box == null) return;
    try {
      await box.put(_kSpotKey, clamped);
    } catch (_) {}
  }
}

final gridSproutSpotProvider =
    StateNotifierProvider<GridSproutSpotNotifier, double?>(
  (ref) => GridSproutSpotNotifier(),
);

// ─── The ledge ──────────────────────────────────────────────────────────────

/// The lane above the habit board where the sprout lives: a [DayCardSprout]
/// (everything it says and does is still its own) that can be slid along the
/// board's edge and pulled down behind it to be hidden.
///
/// Gestures, all on the sprout itself:
///   - slide sideways: it follows the finger, glides a little on release and
///     settles on a spring; past either end it pulls against a rubber band.
///     The spot is saved on release (see [GridSproutSpotNotifier]);
///   - pull down: it sinks behind the board. Let go past half way (or flick
///     it down) and it ducks out of sight and asks «تخفي النبتة؟»; «خلّها»
///     brings it back up with a bounce, «أخفها» closes the lane. A pull up
///     lifts it a little against resistance and lets it drop back;
///   - tap: it laughs, as it always did.
///
/// The drag decides its direction once, on pick-up, so a slide never sinks
/// it by accident and a pull never slides it.
class SproutLedge extends ConsumerStatefulWidget {
  const SproutLedge({
    super.key,
    required this.greens,
    required this.owed,
    required this.ratio,
    required this.perfectDay,
    required this.live,
    this.todayFromStart,
    this.drawLine = false,
    this.clock = DateTime.now,
    this.stage,
    this.namesFromStart,
  });

  /// The day's numbers, for [DayCardSprout] (see its fields).
  final int greens;
  final int owed;
  final double ratio;
  final bool perfectDay;
  final bool live;

  /// Where today's column sits on a board this wide, from its start edge,
  /// or null when the board would scroll sideways. Where the sprout stands
  /// until it is first moved; without it, it stands at the end of the line.
  final double? Function(double width)? todayFromStart;

  /// Draws the line itself. When the board is split into sections a heading,
  /// not the board's edge, comes under the lane, and the sprout still needs
  /// something to stand behind.
  final bool drawLine;

  /// The wall clock; replaced in tests.
  final DateTime Function() clock;

  /// Where Doum is, shared with [SproutBottomPeek] at the foot of the
  /// screen. With one, this ledge watches where its line is on screen and
  /// sends him down there while it is scrolled away (see sprout_bottom.dart);
  /// without one he simply stays here.
  final SproutStage? stage;

  /// Where the habit names are on a board this wide (namesColumnFromStart),
  /// or null when there is no fixed place for them: then there is no spot
  /// at the foot of the screen either, and he stays here.
  final ({double centre, double squaresFrom})? Function(
    double boardWidth, {
    required bool rtl,
  })? namesFromStart;

  @override
  ConsumerState<SproutLedge> createState() => _SproutLedgeState();
}

enum _Axis { slide, pull }

class _SproutLedgeState extends ConsumerState<SproutLedge>
    with TickerProviderStateMixin {
  /// The sprout's centre, from the lane's LEFT edge (physical, so the maths
  /// is one maths in both directions; only the saved spot is directional).
  late final AnimationController _x = AnimationController.unbounded(
    vsync: this,
  );

  /// How far below its resting place the sprout is: 0 at rest, positive
  /// sinking behind the board, negative lifted.
  late final AnimationController _sink = AnimationController.unbounded(
    vsync: this,
  );

  /// The lane itself: 1 open, 0 closed down to the old gap.
  late final AnimationController _open;

  /// What the sprout is saying (see DayCardSprout.onBubble): the stage's,
  /// so it can be drawn at the foot of the screen too, or this ledge's own.
  final _ownSpeech = ValueNotifier<String?>(null);
  ValueNotifier<String?> get _speech => widget.stage?.speech ?? _ownSpeech;

  /// True while a finger holds the sprout: the bubble steps aside.
  final _held = ValueNotifier<bool>(false);

  double _width = 0;
  double? _restFor;
  bool _bubbleOnRight = true;

  _Axis? _axis;
  Offset _downAt = Offset.zero;
  double _fromX = 0;
  double _fromSink = 0;
  Offset _moved = Offset.zero;
  bool _pastHide = false;
  bool _asking = false;
  bool _reduced = false;

  /// The Grid's vertical scroll, read to know where this ledge's line is
  /// on screen (never the board's sideways scroll, nor the tab pages').
  ScrollPosition? _position;

  /// Whether this ledge has made its first call on where Doum is: that one
  /// is not animated (the board may be built already scrolled).
  bool _decided = false;

  /// Why the foot of the screen was not his, the last time this looked.
  SproutSpotBlock _lastBlock = SproutSpotBlock.none;

  /// Whether his mood had him asleep, the last time this looked.
  bool _wasAsleep = false;

  /// Where Doum was when this ledge last looked: at the foot of the screen.
  bool _atBottom = false;

  /// He has ducked all the way out of sight up here while he is down there:
  /// this body is then not painted at all (Offstage), so nothing of it can
  /// show over the board's edge, whatever pose his mood gives him.
  bool _tucked = false;
  Timer? _climbBack;

  static final _glide = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.86,
  );
  static final _bounce = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 380,
    ratio: 0.62,
  );

  @override
  void initState() {
    super.initState();
    final shown = ref.read(gridSproutShownProvider);
    _open = AnimationController(
      vsync: this,
      value: shown ? 1 : 0,
      duration: const Duration(milliseconds: 320),
    );
    if (!shown) _sink.value = _kMaxSink;
    _speech.addListener(_pickBubbleSide);
    final stage = widget.stage;
    if (stage != null) {
      stage.claim(this);
      stage.addListener(_onStage);
      _atBottom = stage.atBottom;
      if (_atBottom) {
        _sink.value = _kMaxSink;
        _tucked = true;
      }
      // After every frame the app draws: a scroll, a card above folding
      // away, the lane opening, the split board's line coming, all redraw,
      // and nothing has moved the line without one. Still screens cost
      // nothing (see FrameWatch).
      FrameWatch.add(_check);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The nearest VERTICAL scrollable: the Grid's own page. The board's
    // sideways scroll is not an ancestor of the ledge, and HomeShell's tab
    // pages scroll sideways, so neither is ever this one.
    // The position is replaced whenever the scroll view's own dependencies
    // change (a theme or language switch), so it is looked up again here.
    final position = widget.stage == null
        ? null
        : Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (!identical(position, _position)) {
      _position?.isScrollingNotifier.removeListener(_mirrorScrolling);
      _position = position;
      _position?.isScrollingNotifier.addListener(_mirrorScrolling);
      _mirrorScrolling();
    }
  }

  /// Tells the foot of the screen whether the page is moving (see
  /// SproutStage.scrolling). A glide can start or end while the page is
  /// laid out, where nothing may be marked dirty, so then it waits for the
  /// frame's end.
  void _mirrorScrolling() {
    void mirror() {
      final stage = widget.stage;
      if (!mounted || stage == null) return;
      stage.scrolling.value = _position?.isScrollingNotifier.value ?? false;
    }

    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) => mirror());
      return;
    }
    mirror();
  }

  @override
  void didUpdateWidget(covariant SproutLedge old) {
    super.didUpdateWidget(old);
    if (!identical(old.stage, widget.stage)) {
      (old.stage?.speech ?? _ownSpeech).removeListener(_pickBubbleSide);
      _speech.addListener(_pickBubbleSide);
      old.stage?.removeListener(_onStage);
      old.stage?.release(this);
      widget.stage?.claim(this);
      widget.stage?.addListener(_onStage);
      if (old.stage == null) FrameWatch.add(_check);
      if (widget.stage == null) FrameWatch.remove(_check);
      _decided = false;
    }
  }

  @override
  void dispose() {
    _speech.removeListener(_pickBubbleSide);
    _position?.isScrollingNotifier.removeListener(_mirrorScrolling);
    FrameWatch.remove(_check);
    _climbBack?.cancel();
    widget.stage?.removeListener(_onStage);
    widget.stage?.release(this);
    _x.dispose();
    _sink.dispose();
    _open.dispose();
    _ownSpeech.dispose();
    _held.dispose();
    super.dispose();
  }

  // ── Following the page down ─────────────────────────────────────────────

  /// Where this ledge's line (the board's top edge) is, from the top of the
  /// Grid's scroll view, where the page's pixels say it is: the offset that
  /// would bring the lane to the top, less the pixels scrolled. A bounce
  /// past either end is not a scroll anyone meant, so it is not counted.
  double? _lineOnScreen() {
    final position = _position;
    final box = context.findRenderObject();
    if (position == null ||
        box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    final reveal = viewport.getOffsetToReveal(box, 0.0).offset;
    final pixels = position.pixels
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    // On a split board the lane draws its own line 6pt above its foot.
    final below = widget.drawLine ? 6.0 : 0.0;
    return reveal - pixels + box.size.height - below;
  }

  /// Sends Doum to the foot of the screen when the line nears the top, and
  /// back when it is well in view again (see _kLeaveAt, _kComeBackAt). He
  /// stays up here while he is held or asked about, while the lane is
  /// opening or closing, when the board has no fixed place for the names,
  /// while the spot down there is someone else's, and while he is asleep:
  /// he sleeps on his edge, not at the foot of the page.
  void _check() {
    final stage = widget.stage;
    if (stage == null || !mounted || _held.value || _asking) return;
    final line = _lineOnScreen();
    if (line == null) return;
    final block = stage.block.value;
    final asleep = dayCardMoodFor(
          greens: widget.greens,
          owed: widget.owed,
          perfectDay: widget.perfectDay,
          hour: widget.clock().hour,
        ).pose ==
        SproutPose.sleeping;
    // Falling asleep while he waits down there (the day made perfect after
    // bedtime) is the one mood change with words on it: he stays for them,
    // and goes up to sleep on his edge once they have been said, instead of
    // leaving mid-sentence with the line lost.
    final sleepyButTalking =
        asleep && stage.atBottom && stage.speech.value != null;
    final hasSpot = ref.read(gridSproutShownProvider) &&
        _open.value >= 1 &&
        _width > 0 &&
        block == SproutSpotBlock.none &&
        (!asleep || sleepyButTalking) &&
        (widget.namesFromStart?.call(_width, rtl: _rtl) != null);
    final bool down;
    if (!hasSpot) {
      down = false;
    } else if (stage.atBottom) {
      down = line <= _kComeBackAt;
    } else {
      down = line < _kLeaveAt;
    }
    // Not seen: the first call a board makes, and the keyboard's coming and
    // going (a sheet is over the page).
    final quiet = !_decided ||
        block == SproutSpotBlock.quietly ||
        _lastBlock == SproutSpotBlock.quietly;
    // Woken by a square done down there (the first one of the small hours):
    // the praise for it goes down with him.
    final woke = _decided && _wasAsleep && !asleep;
    _decided = true;
    _lastBlock = block;
    _wasAsleep = asleep;
    stage.moveTo(bottom: down, animate: !quiet, keepSpeech: woke);
  }

  /// The stage moved him (this ledge decided, or its board went away): duck
  /// out of sight here, or climb back up a moment after the foot of the
  /// screen has started its own duck.
  void _onStage() {
    final stage = widget.stage;
    if (stage == null || stage.atBottom == _atBottom) return;
    // Rebuilt so his moves, taps and screen-reader node follow him (see
    // _lane).
    setState(() => _atBottom = stage.atBottom);
    _climbBack?.cancel();
    _reduced = prefersReducedMotion(context);
    final shown = ref.read(gridSproutShownProvider);
    if (_atBottom) {
      // A glide along the line is left to finish out of sight: stopped here,
      // he would come back short of the spot the glide just saved.
      if (!stage.animate || _reduced) {
        _sink.stop();
        _sink.value = _kMaxSink;
        _tuck(true);
      } else {
        _sink
            .animateTo(_kMaxSink, duration: _kDuck, curve: Curves.easeIn)
            .then((_) {
          if (mounted && _atBottom) _tuck(true);
        });
      }
      return;
    }
    if (!shown) {
      _tuck(false);
      return;
    }
    if (_reduced && stage.animate) {
      // No travel: he appears up here once the foot's fade has taken him
      // away there, never both at once.
      _climbBack = Timer(_kCalmFade, () {
        if (!mounted || _atBottom) return;
        _tuck(false);
        _sink.stop();
        _sink.value = 0;
      });
      return;
    }
    _tuck(false);
    if (!stage.animate) {
      _sink.stop();
      _sink.value = 0;
      return;
    }
    // Turned back mid-duck, still partly in view: straight back up from
    // where he is, with the speed he had, no pause.
    if (_sink.value < _kMaxSink - 0.5) {
      final velocity = _sink.velocity;
      _sink.stop();
      _settle(_sink, _bounce, 0, velocity);
      return;
    }
    _climbBack = Timer(_kHandoffGap, () {
      if (mounted && !_atBottom) _settleSink(0);
    });
  }

  void _tuck(bool tucked) {
    if (_tucked != tucked && mounted) setState(() => _tucked = tucked);
  }

  bool get _rtl => Directionality.of(context) == TextDirection.rtl;

  double get _minX => _kHalfWidth;
  double get _maxX => math.max(_kHalfWidth, _width - _kHalfWidth);

  double _clampX(double x) => x.clamp(_minX, _maxX).toDouble();

  double _xForSpot(double spot) {
    final fromStart = _minX + spot * (_maxX - _minX);
    return _rtl ? _width - fromStart : fromStart;
  }

  double _spotForX(double x) {
    final span = _maxX - _minX;
    if (span <= 0) return 0.5;
    final fromStart = _rtl ? _width - x : x;
    return ((fromStart - _minX) / span).clamp(0.0, 1.0).toDouble();
  }

  /// Where the sprout rests: the saved spot, else today's column, else the
  /// end of the line (where it stood on the day card).
  double _restX() {
    final spot = ref.read(gridSproutSpotProvider);
    if (spot != null) return _xForSpot(spot);
    final fromStart = widget.todayFromStart?.call(_width) ??
        (_width - _kHalfWidth - 8);
    final clamped = fromStart.clamp(_minX, _maxX).toDouble();
    return _rtl ? _width - clamped : clamped;
  }

  /// Keeps the sprout on its resting place as the lane is laid out: placed
  /// outright the first time and whenever the width changes (a rotation, a
  /// split screen), eased there when only the rest itself moved (midnight
  /// moves today's column).
  void _place(double width) {
    if (_held.value) return;
    final widthChanged = width != _width;
    _width = width;
    final rest = _restX();
    if (widthChanged || _restFor == null) {
      _x.stop();
      _x.value = rest;
    } else if ((rest - _restFor!).abs() > 0.5 &&
        ref.read(gridSproutSpotProvider) == null) {
      _settleX(rest, 0);
    }
    _restFor = rest;
    _pickBubbleSide();
  }

  /// The bubble goes on the reading side of the sprout when it fits there,
  /// else on the other. Decided when it starts to speak and when it is let
  /// go, never mid-flight, so it cannot flip sides while it slides.
  void _pickBubbleSide() {
    if (_width <= 0) return;
    final x = _held.value ? _x.value : (_restFor ?? _x.value);
    final roomRight = _width - (x + _kHalfWidth);
    final roomLeft = x - _kHalfWidth;
    const fits = 120.0;
    final preferRight = _rtl;
    if (preferRight) {
      _bubbleOnRight = roomRight >= fits || roomRight >= roomLeft;
    } else {
      _bubbleOnRight = !(roomLeft >= fits || roomLeft >= roomRight);
    }
  }

  /// What the sprout says, passed on to the bubble. The sprout speaks from
  /// inside a build too (a celebration starts in its didUpdateWidget), and
  /// the bubble is not below it in the tree, so marking the bubble dirty
  /// then is the framework's "setState during build". Mid-frame, the line
  /// waits for the frame's end, one frame nobody can see; otherwise it goes
  /// at once, because a post-frame callback alone would wait for a frame
  /// that nothing else might ask for.
  void _hear(String? text) {
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) {
        if (mounted) _speech.value = text;
      });
      return;
    }
    _speech.value = text;
  }

  // ── Motion ──────────────────────────────────────────────────────────────

  void _settleX(double target, double velocity) {
    _settle(_x, _glide, target, velocity);
  }

  void _settleSink(double velocity) {
    // Waiting at the foot of the screen: he stays out of sight up here.
    if (_atBottom) return;
    _settle(_sink, _bounce, 0, velocity);
  }

  /// A spring home, or a short straight move under Reduce Motion. A spring
  /// stops within a thousandth of a point of its target, so a finished one
  /// is set exactly on it: the resting place is one place, not a smear of
  /// nearly-equal ones. A settle cut short by a new drag never completes and
  /// sets nothing.
  void _settle(
    AnimationController c,
    SpringDescription spring,
    double target,
    double velocity,
  ) {
    final run = _reduced
        ? c.animateTo(target, duration: const Duration(milliseconds: 150))
        : c.animateWith(SpringSimulation(spring, c.value, target, velocity));
    run.then((_) {
      if (mounted) c.value = target;
    });
  }

  /// Past either end of the line the sprout still follows, but less and
  /// less, up to 24pt: a rubber band, not a wall.
  double _rubber(double x) {
    double give(double over) => 24 * (1 - 1 / (over / 60 + 1));
    if (x < _minX) return _minX - give(_minX - x);
    if (x > _maxX) return _maxX + give(x - _maxX);
    return x;
  }

  // ── The drag ────────────────────────────────────────────────────────────

  void _down(DragDownDetails d) => _downAt = d.globalPosition;

  void _start(DragStartDetails d) {
    // Ducking down to the foot of the screen: not to be picked up here.
    if (_asking || _atBottom) return;
    _x.stop();
    _sink.stop();
    _fromX = _x.value;
    _fromSink = _sink.value;
    _moved = Offset.zero;
    _pastHide = false;
    // The movement that picked it up decides it: mostly down or up is a
    // pull, anything else a slide.
    final first = d.globalPosition - _downAt;
    _axis = first.dy.abs() > first.dx.abs() * 1.1 ? _Axis.pull : _Axis.slide;
    _held.value = true;
    HapticFeedback.selectionClick();
  }

  void _update(DragUpdateDetails d) {
    if (!_held.value) return;
    _moved += d.delta;
    if (_axis == _Axis.slide) {
      _x.value = _rubber(_fromX + _moved.dx);
      return;
    }
    final raw = _fromSink + _moved.dy;
    // Up only lifts a little, against resistance (at most 10pt); down
    // follows the finger until the leaves are gone.
    final sink = raw < 0
        ? -10 * (1 - 1 / (-raw / 30 + 1))
        : math.min(raw, _kMaxSink).toDouble();
    _sink.value = sink;
    final past = sink >= _kHideAt;
    if (past != _pastHide) {
      _pastHide = past;
      // A tick where letting go changes what happens.
      past ? HapticFeedback.lightImpact() : HapticFeedback.selectionClick();
    }
  }

  void _end(DragEndDetails d) {
    if (!_held.value) return;
    final v = d.velocity.pixelsPerSecond;
    if (_axis == _Axis.slide) {
      // A little glide in the direction of the flick, then home.
      final target = _clampX(_x.value + v.dx * 0.12);
      _restFor = target;
      final spot = _spotForX(target);
      unawaited(ref.read(gridSproutSpotProvider.notifier).set(spot));
      _held.value = false;
      _pickBubbleSide();
      _settleX(target, v.dx);
      return;
    }
    _held.value = false;
    final sink = _sink.value;
    if (sink >= _kHideAt || (v.dy > 700 && sink > 10)) {
      _duckAndAsk();
    } else {
      _settleSink(v.dy);
    }
  }

  void _cancel() {
    if (!_held.value) return;
    _held.value = false;
    _settleX(_clampX(_x.value), 0);
    _settleSink(0);
  }

  /// Out of sight first, then the question, so the pop-up asks about
  /// something that has already happened and «خلّها» undoes it.
  Future<void> _duckAndAsk() async {
    if (_asking) return;
    _asking = true;
    try {
      await _sink
          .animateTo(
            _kMaxSink,
            duration: Duration(milliseconds: _reduced ? 1 : 170),
            curve: Curves.easeIn,
          )
          .orCancel;
    } on TickerCanceled {
      _asking = false;
      return;
    }
    if (!mounted) return;
    final hide = await _askToHide(context);
    _asking = false;
    if (!mounted) return;
    if (hide) {
      unawaited(HapticFeedback.mediumImpact());
      unawaited(ref.read(gridSproutShownProvider.notifier).set(false));
    } else {
      _settleSink(0);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _reduced = prefersReducedMotion(context);
    ref.listen<bool>(gridSproutShownProvider, (prev, next) {
      if (next == prev) return;
      if (next) {
        // Back from Settings: the lane opens, then the sprout climbs up
        // from behind the board.
        _sink.value = _kMaxSink;
        _open
            .animateTo(1, curve: Curves.easeInOutCubic)
            .orCancel
            .then((_) {
          if (mounted) _settleSink(0);
        }).catchError((_) {});
      } else {
        _held.value = false;
        // The sprout is about to go, mid-sentence perhaps, and never gets
        // to clear its bubble: without this the old line would be waiting
        // when it comes back.
        _speech.value = null;
        _open.animateTo(0, curve: Curves.easeInOutCubic);
      }
    });
    final shown = ref.watch(gridSproutShownProvider);

    // The board splits into sections the moment a habit is paused today,
    // and unsplits when it resumes: the drawn line and the 6pt under it
    // (room for the first heading) come and go smoothly rather than
    // jolting the board by 6pt.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.drawLine ? 6.0 : 0.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOutCubic,
      builder: (context, below, _) => AnimatedBuilder(
        animation: _open,
        builder: (context, _) {
          final t = _open.value;
          final height =
              lerpDouble(kLedgeClosedHeight, kLedgeLaneHeight + below, t)!;
          if (t <= 0 && !shown) return SizedBox(height: height);
          return SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (context, box) {
                _place(box.maxWidth);
                return _lane(context, height, height - below * t, below * t);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _lane(BuildContext context, double height, double line, double under) {
    final gp = context.gp;
    final s = S.of(context);
    final sleeping = dayCardMoodFor(
          greens: widget.greens,
          owed: widget.owed,
          perfectDay: widget.perfectDay,
          hour: widget.clock().hour,
        ).pose ==
        SproutPose.sleeping;

    // Built once per ledge build and handed to the moving part as a child,
    // so a drag frame moves a picture and rebuilds nothing inside it.
    //
    // While he waits at the foot of the screen this body makes no moves
    // (bodyAway), takes no touches, is left out for screen readers, and once
    // it has ducked out of sight is not painted at all; the wrappers are
    // always here, so none of that rebuilds his mind.
    final sprout = Offstage(
      offstage: _tucked,
      child: IgnorePointer(
        ignoring: _atBottom,
        child: RepaintBoundary(
          child: RawGestureDetector(
            gestures: <Type, GestureRecognizerFactory>{
              _PickUpRecognizer:
                  GestureRecognizerFactoryWithHandlers<_PickUpRecognizer>(
                () => _PickUpRecognizer(debugOwner: this),
                (r) => r
                  // The device's own slop (8 on Android), which the pick-up
                  // stays under; see [_kPickUpSlop].
                  ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
                  ..dragStartBehavior = DragStartBehavior.start
                  ..onDown = _down
                  ..onStart = _start
                  ..onUpdate = _update
                  ..onEnd = _end
                  ..onCancel = _cancel,
              ),
            },
            // Down at the foot of the screen, that body is the one a screen
            // reader finds; this one is out of sight behind the board.
            child: ExcludeSemantics(
              excluding: _atBottom,
              child: Semantics(
                // Pulling it down is a gesture a screen reader cannot make;
                // this is the same question, one action away.
                customSemanticsActions: {
                  CustomSemanticsAction(label: s.gridSproutHideYes): () {
                    if (!_asking) _duckAndAsk();
                  },
                },
                child: DayCardSprout(
                  greens: widget.greens,
                  owed: widget.owed,
                  ratio: widget.ratio,
                  perfectDay: widget.perfectDay,
                  live: widget.live,
                  height: kLedgeSproutHeight,
                  clock: widget.clock,
                  drawsBubble: false,
                  onBubble: _hear,
                  echo: widget.stage?.echo,
                  bodyAway: _atBottom,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Three children, always, keyed: a child that came and went (the drawn
    // line) would shift the sprout's place in this list, and Flutter would
    // build the sprout again from nothing, entrance and all.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          key: const ValueKey('line'),
          left: 0,
          right: 0,
          top: line - 0.5,
          height: 1,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: widget.drawLine ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: ColoredBox(color: gp.border),
            ),
          ),
        ),
        // Everything below the line is behind the board.
        Positioned.fill(
          key: const ValueKey('sprout'),
          child: ClipRect(
            clipper: _AboveLine(line),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedBuilder(
                  animation: Listenable.merge([_x, _sink]),
                  child: sprout,
                  builder: (context, child) => TweenAnimationBuilder<double>(
                    tween: Tween(end: sleeping ? _kSleepLift : 0),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: child,
                    builder: (context, lift, child) => Positioned(
                      left: _x.value,
                      bottom: under - _kFeetBelowLine + lift - _sink.value,
                      child: FractionalTranslation(
                        translation: const Offset(-0.5, 0),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        KeyedSubtree(key: const ValueKey('bubble'), child: _bubble(under)),
      ],
    );
  }

  /// SproutBubble beside the sprout, its bottom just above the line, the
  /// tail pointing at it. Hidden while the sprout is held, and while he
  /// waits at the foot of the screen (the bubble goes with him there).
  Widget _bubble(double under) {
    return AnimatedBuilder(
      animation: Listenable.merge([_x, _speech, _held]),
      builder: (context, _) {
        final text = _held.value || _atBottom ? null : _speech.value;
        final x = _x.value;
        final onRight = _bubbleOnRight;
        final room = onRight
            ? _width + 12 - (x + _kHalfWidth - 6)
            : (x - _kHalfWidth + 6) + 12;
        // SproutBubble's tail is on its bottom END corner unless told
        // otherwise; the corner that faces the sprout is bottom-left for a
        // bubble on its right, bottom-right for one on its left.
        final tailAtStart = onRight != _rtl;
        return Positioned(
          left: onRight ? x + _kHalfWidth - 6 : null,
          right: onRight ? null : _width - (x - _kHalfWidth + 6),
          bottom: under + 2,
          child: _speechSwitcher(
            text: text,
            maxWidth: room.clamp(60.0, 170.0).toDouble(),
            onRight: onRight,
            tailAtStart: tailAtStart,
            reduced: _reduced,
          ),
        );
      },
    );
  }
}

/// The bubble coming and going beside the sprout: a fade, and a small grow
/// from the corner that faces him unless Reduce Motion is on. IgnorePointer:
/// the squares under it stay tappable. Shared by the board's edge and the
/// foot of the screen.
Widget _speechSwitcher({
  required String? text,
  required double maxWidth,
  required bool onRight,
  required bool tailAtStart,
  required bool reduced,
}) {
  return IgnorePointer(
    child: ExcludeSemantics(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        reverseDuration: const Duration(milliseconds: 160),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: reduced
              ? child
              : ScaleTransition(
                  alignment:
                      onRight ? Alignment.bottomLeft : Alignment.bottomRight,
                  scale: Tween(begin: 0.8, end: 1.0).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                  ),
                  child: child,
                ),
        ),
        child: text == null
            ? const SizedBox.shrink(key: ValueKey('none'))
            : SproutBubble(
                key: ValueKey(text),
                text: text,
                maxWidth: maxWidth,
                tailAtStart: tailAtStart,
              ),
      ),
    ),
  );
}

/// Picks the sprout up once the finger is [_kPickUpSlop] away from where it
/// touched down (or one point under the device's own slop, when smaller), in
/// any direction.
///
/// Straight-line distance, not PanGestureRecognizer's globalDistanceMoved,
/// which for a pan is the length of the whole path: a tap that jiggles 3pt
/// left and right four times has travelled 12pt and gone nowhere.
class _PickUpRecognizer extends PanGestureRecognizer {
  _PickUpRecognizer({super.debugOwner});

  Offset? _downAt;
  Offset? _lastAt;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _downAt ??= event.position;
    _lastAt = event.position;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _lastAt = event.position;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    final down = _downAt;
    final last = _lastAt;
    if (down == null || last == null) return false;
    final slop = math.min(_kPickUpSlop, (deviceTouchSlop ?? kTouchSlop) - 1);
    return (last - down).distance > slop;
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _downAt = null;
    _lastAt = null;
    super.didStopTrackingLastPointer(pointer);
  }
}

/// Clips at [line] and nowhere else: the leaves may rise over the day card
/// and a wide pose may reach past the lane's ends, but nothing shows below
/// the board's edge.
class _AboveLine extends CustomClipper<Rect> {
  const _AboveLine(this.line);
  final double line;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-size.width, -400, size.width * 2, line);

  @override
  bool shouldReclip(_AboveLine old) => old.line != line;
}

/// «تخفي النبتة؟», in the app's one look for a question (the rest-day and
/// clear-mark dialogs): the sprout waving, the fact, and the way back.
Future<bool> _askToHide(BuildContext context) async {
  final gp = context.gp;
  final s = S.of(context);
  final hide = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: gp.surfaceHigh,
      icon: const Sprout(
        pose: SproutPose.frontWave,
        height: 84,
        entrance: SproutEntrance.none,
        idleBreaths: 0,
      ),
      title: Text(
        s.gridSproutHideTitle,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: gp.textPrimary,
        ),
      ),
      content: Text(
        s.gridSproutHideBody,
        style: TextStyle(fontSize: 13, color: gp.textSec, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(
            s.gridSproutHideNo,
            style: TextStyle(fontSize: 13, color: gp.textSec),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            s.gridSproutHideYes,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: gp.goldInk,
            ),
          ),
        ),
      ],
    ),
  );
  return hide ?? false;
}
