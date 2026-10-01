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
import '../../core/providers/day_clock_provider.dart'
    show dayClockSourceProvider;
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
    this.clock,
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

  /// The wall clock; replaced in tests. Without one, the app's
  /// dayClockSourceProvider (DateTime.now in the app), so a test that pins
  /// that provider pins the hour his mood is read at too.
  final DateTime Function()? clock;

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
  /// [SproutLedge.clock], else the app's day clock source.
  DateTime Function() get _clock =>
      widget.clock ?? ref.read(dayClockSourceProvider);

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

  /// He is all the way out of sight up here (the hand-off has him at the
  /// foot, or on his way there past the middle): this body is then not
  /// painted at all (Offstage), so nothing of it can show over the board's
  /// edge, whatever pose his mood gives him.
  bool _tucked = false;

  /// Reduce Motion, back from the foot: kept out of sight here until the
  /// foot's fade has taken him away there.
  bool _calmTucked = false;
  Timer? _climbBack;

  // ── The hand-off (see "The page carries him" in sprout_bottom.dart) ──────

  /// Moves [SproutStage.handoff] with the page, a frame at a time, while the
  /// page moves or he is on his way; stopped otherwise, so a still Grid
  /// draws nothing.
  late final Ticker _follower;
  Duration? _lastTick;

  /// The hand-off's speed (units a second), where the page's rate limit has
  /// got its aim to ([_goal]), and how far the page's own map of it is off
  /// from where he is since he last finished a way ([_bias], worn off by
  /// the page moving). [_lastBand] is where the page had him last, [_side]
  /// the end he last finished at or was sent to (0 or 2).
  double _handoffSpeed = 0;
  double _goal = 0;
  double _bias = 0;
  double? _lastBand;
  double _side = 0;

  /// The page moved since the last frame of the hand-off, and how long ago
  /// it last did: a page moved with no scroll behind it (a mouse wheel, a
  /// jump) counts as moving for [_kMovedFor], so he follows it as he does a
  /// finger, then finishes his way.
  bool _pixelsMoved = false;
  double _sinceMoved = 1;

  /// Where this ledge's line is in the page's content (the line on screen
  /// is this less the pixels scrolled), from the last frame's layout.
  double? _lineInPage;

  /// Whether the foot of the screen is his, as of the last frame.
  bool _hasSpot = false;

  /// He woke up while the edge was out of sight: what he says for it goes
  /// down with him on his way to the foot.
  bool _keepSpeechOnWay = false;

  /// How fast the page moves (pt/s), and the fingers on the screen: the end
  /// of a glide is his to make way in (SproutStage.settling).
  double _pageSpeed = 0;
  double? _lastPixels;
  final Set<int> _fingers = <int>{};

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
    _follower = createTicker(_follow);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    _speech.addListener(_pickBubbleSide);
    final stage = widget.stage;
    if (stage != null) {
      stage.claim(this);
      stage.addListener(_onStage);
      _atBottom = stage.atBottom;
      _tucked = stage.handoff.value >= 1;
      _goal = stage.handoff.value;
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
      _position?.removeListener(_onPixels);
      _position = position;
      _position?.isScrollingNotifier.addListener(_mirrorScrolling);
      _position?.addListener(_onPixels);
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

    _wake();
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) => mirror());
      return;
    }
    mirror();
  }

  /// The page moved. A move with no scroll behind it (a jump to a place) is
  /// a move and a stop at once, as far as the foot is concerned.
  void _onPixels() {
    final stage = widget.stage;
    if (stage == null || !mounted) return;
    _pixelsMoved = true;
    if (!(_position?.isScrollingNotifier.value ?? false)) stage.jumps.value++;
    _wake();
  }

  /// Every finger on the screen, wherever it is: one on the page means the
  /// page is held, not gliding on its own.
  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      _fingers.add(event.pointer);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _fingers.remove(event.pointer);
    }
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
    _position?.removeListener(_onPixels);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    FrameWatch.remove(_check);
    _follower.dispose();
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

  /// Where this ledge's line (the board's top edge) sits in the page's
  /// content: the offset that would bring the lane to the top, plus the
  /// lane. Taken from the last frame's layout; the line on screen is this
  /// less the pixels scrolled (see [_lineNow]).
  double? _lineInPageNow() {
    final position = _position;
    final box = context.findRenderObject();
    if (position == null || box is! RenderBox || !box.attached || !box.hasSize) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    final reveal = viewport.getOffsetToReveal(box, 0.0).offset;
    // On a split board the lane draws its own line 6pt above its foot.
    final below = widget.drawLine ? 6.0 : 0.0;
    return reveal + box.size.height - below;
  }

  /// Where the line is, from the top of the Grid's scroll view, where the
  /// page's pixels say it is now. A bounce past either end is not a scroll
  /// anyone meant, so it is not counted.
  double? _lineNow() {
    final inPage = _lineInPage;
    final position = _position;
    if (inPage == null ||
        position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions) {
      return null;
    }
    final pixels = position.pixels
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    return inPage - pixels;
  }

  /// Where the page puts him for a line this far down: 0 on the edge, 1
  /// behind the board, 2 all the way up at the foot; past either end, more.
  static double _band(double line) =>
      (_kComeBackAt - line) / (_kComeBackAt - _kLeaveAt);

  bool get _pageScrolling => _position?.isScrollingNotifier.value ?? false;

  /// Whether the page counts as moving: scrolled, or moved some other way
  /// within the last [_kMovedFor].
  bool get _pageMoving =>
      _pageScrolling || _pixelsMoved || _sinceMoved < _kMovedFor;

  /// Where the hand-off is headed with the page's line at [band]. While the
  /// page moves, where the page has him ([follow]), taken with [bias]: how
  /// far off the page's map he was left the last time he finished a way,
  /// worn off as the page moves, so the next scroll takes him on from where
  /// he is, never with a jump. Once it stops, the page decides the end
  /// ([target] 0 or 2) from where its line is, not from where he is: the
  /// nearer side, with [_kStayBy] of margin toward the side he was last at,
  /// so a nudge never flips him and short scrolls add up. No spot at the
  /// foot: the edge, whatever the page.
  ({double bias, double target, bool follow}) _aim(double band) {
    if (!_hasSpot) return (bias: 0.0, target: 0.0, follow: false);
    final map = band.clamp(0.0, 2.0).toDouble();
    final moved = (band - (_lastBand ?? band)).abs();
    final bias = _bias > 0
        ? math.max(0.0, _bias - moved)
        : math.min(0.0, _bias + moved);
    final want = (map + bias).clamp(0.0, 2.0).toDouble();
    final double end;
    if (_side > 1) {
      end = map < 1 - _kStayBy ? 0 : 2;
    } else {
      end = map > 1 + _kStayBy ? 2 : 0;
    }
    // A move with no scroll behind it is followed only where it has him
    // part-way: one that leaves him where he is has nothing to follow.
    if (_pageScrolling || (_pageMoving && want != end)) {
      return (bias: bias, target: want, follow: true);
    }
    return (bias: end - map, target: end, follow: false);
  }

  /// Looks after every drawn frame: where the line is in the page, and
  /// whether the foot of the screen is his (he stays up here while he is
  /// held or asked about, while the lane is opening or closing, when the
  /// board has no fixed place for the names, while the spot down there is
  /// someone else's, and while he is asleep: he sleeps on his edge, not at
  /// the foot of the page). Then wakes the follower if he has anywhere to
  /// go. The first look a board takes, and the keyboard's coming and going,
  /// are not seen: he is simply put where the page has him.
  void _check() {
    final stage = widget.stage;
    if (stage == null || !mounted || _held.value || _asking) return;
    _lineInPage = _lineInPageNow();
    final line = _lineNow();
    if (line == null) return;
    final block = stage.block.value;
    final asleep = dayCardMoodFor(
          greens: widget.greens,
          owed: widget.owed,
          perfectDay: widget.perfectDay,
          hour: _clock().hour,
        ).pose ==
        SproutPose.sleeping;
    // Falling asleep while he waits down there (the day made perfect after
    // bedtime) is the one mood change with words on it: he stays for them,
    // and goes up to sleep on his edge once they have been said, instead of
    // leaving mid-sentence with the line lost.
    final sleepyButTalking =
        asleep && stage.atBottom && stage.speech.value != null;
    _hasSpot = ref.read(gridSproutShownProvider) &&
        _open.value >= 1 &&
        _width > 0 &&
        block == SproutSpotBlock.none &&
        (!asleep || sleepyButTalking) &&
        (widget.namesFromStart?.call(_width, rtl: _rtl) != null);
    final quiet = !_decided ||
        block == SproutSpotBlock.quietly ||
        _lastBlock == SproutSpotBlock.quietly;
    // Woken by a square done down there (the first one of the small hours):
    // the praise for it goes down with him.
    final woke = _decided && _wasAsleep && !asleep;
    _decided = true;
    _lastBlock = block;
    _wasAsleep = asleep;
    final band = _band(line);
    if (quiet) {
      _stopFollowing();
      _keepSpeechOnWay = woke;
      final end = _hasSpot && band > 1 ? 2.0 : 0.0;
      _bias = _hasSpot ? end - band.clamp(0.0, 2.0) : 0;
      _lastBand = band;
      _side = end;
      _goal = end;
      _handoffSpeed = 0;
      _setHandoff(end, animate: false);
      _keepSpeechOnWay = false;
      return;
    }
    final aim = _aim(band);
    // Only if it takes him down there; a line said up here stays here.
    if (woke) _keepSpeechOnWay = aim.target > 1;
    // Anything to do: the page moved, or he is not where it has him. A
    // finger holding the page still with him in place is nothing to do.
    if (_pixelsMoved ||
        _handoffSpeed != 0 ||
        (aim.target - stage.handoff.value).abs() > 1e-6 ||
        (aim.target - _goal).abs() > 1e-6) {
      _wake();
    }
  }

  void _wake() {
    if (widget.stage == null || !mounted || _follower.isActive) return;
    _lastTick = null;
    _lastPixels = null;
    _follower.start();
  }

  void _stopFollowing() {
    if (_follower.isActive) _follower.stop();
    _lastTick = null;
    _lastPixels = null;
    _pageSpeed = 0;
    _sinceMoved = _kMovedFor;
    _keepSpeechOnWay = false;
    widget.stage?.settling.value = false;
  }

  /// A frame of the hand-off: toward where the page has him on a light
  /// spring while it moves, then to the end the page decides on a softer
  /// one, never faster than [_kMostHandoffPerSecond]; under Reduce Motion
  /// from one end to the other at once. Stops once he is there and the page
  /// is still, or held still under a finger (a move wakes it again).
  void _follow(Duration elapsed) {
    final stage = widget.stage;
    final position = _position;
    if (stage == null || !mounted || position == null || !position.hasPixels) {
      _stopFollowing();
      return;
    }
    final last = _lastTick;
    _lastTick = elapsed;
    final dt = last == null
        ? 0.0
        : ((elapsed - last).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
    final scrolling = _pageScrolling;
    // The page's own speed, for the foot: the slow end of a glide with no
    // finger on the page is his to make way in.
    final pixels = position.pixels;
    final lastPixels = _lastPixels;
    if (dt > 0 && lastPixels != null) {
      _pageSpeed = _pageSpeed * 0.6 + (pixels - lastPixels) / dt * 0.4;
    }
    _lastPixels = pixels;
    final pageStill = lastPixels != null && pixels == lastPixels;
    if (_pixelsMoved) {
      _pixelsMoved = false;
      _sinceMoved = 0;
    } else {
      _sinceMoved += dt;
    }
    stage.settling.value = scrolling &&
        _fingers.isEmpty &&
        _pageSpeed.abs() < _kSettlingSpeed;
    final line = _lineNow();
    if (_held.value || _asking || line == null) {
      _stopFollowing();
      return;
    }
    final band = _band(line);
    final aim = _aim(band);
    _lastBand = band;
    _bias = aim.bias;
    if (!aim.follow) _side = aim.target;
    var h = stage.handoff.value;
    if (_reduced) {
      // No travel: at once to one end or the other, and back only once the
      // page is well on its way back, so a finger trembling at the middle
      // does not flicker him between the two.
      final t = aim.target;
      if (aim.follow) {
        h = h >= 1 ? (t < 0.5 ? 0 : 2) : (t > 1 ? 2 : 0);
      } else {
        h = t;
      }
      _goal = h;
      _handoffSpeed = 0;
    } else {
      final most = _kMostHandoffPerSecond * dt;
      _goal += (aim.target - _goal).clamp(-most, most);
      final w = aim.follow ? _kFollowW : _kFinishW;
      var v = _handoffSpeed;
      if (dt > 0) {
        // Critically damped, in 2ms steps.
        final steps = math.max(1, (dt / 0.002).ceil());
        final step = dt / steps;
        for (var i = 0; i < steps; i++) {
          v += (w * w * (_goal - h) - 2 * w * v) * step;
          h += v * step;
        }
      }
      // There: set exactly on it (a spring stops within a hair of it). A
      // follow that has caught up counts only once the page stands still
      // under the finger.
      if ((!aim.follow || pageStill) &&
          _goal == aim.target &&
          (h - aim.target).abs() < 5e-4 &&
          v.abs() < 5e-3) {
        h = aim.target;
        v = 0;
      }
      _handoffSpeed = v;
      h = h.clamp(0.0, 2.0).toDouble();
    }
    _setHandoff(h, animate: true);
    if (_handoffSpeed != 0 || h != aim.target) return;
    // At rest and there; or a finger holding the page still with him where
    // it has him (the next move of the page wakes this again).
    if (!aim.follow || (scrolling && pageStill && !_pixelsMoved)) {
      _stopFollowing();
    }
  }

  /// Moves him to [h] on the stage: out of sight up here from 1 on, and
  /// the stage's move (his words, his taps, his screen-reader node) as he
  /// crosses 1, where neither body shows.
  void _setHandoff(double h, {required bool animate}) {
    final stage = widget.stage;
    if (stage == null) return;
    stage.handoff.value = h;
    _tuck(h >= 1 || _calmTucked);
    final bottom = h > 1;
    if (bottom == stage.atBottom) return;
    final keep = bottom && _keepSpeechOnWay;
    _keepSpeechOnWay = false;
    stage.moveTo(bottom: bottom, animate: animate, keepSpeech: keep);
  }

  /// The stage moved him (the hand-off crossed the middle, or his board
  /// went away): this body stops or starts making his moves and taking his
  /// taps. The hand-off itself has him out of sight here from the middle
  /// on; under Reduce Motion, with no travel, he shows up here once the
  /// foot's fade has taken him away there, never both at once.
  void _onStage() {
    final stage = widget.stage;
    if (stage == null || stage.atBottom == _atBottom) return;
    // Rebuilt so his moves, taps and screen-reader node follow him (see
    // _lane).
    setState(() => _atBottom = stage.atBottom);
    _climbBack?.cancel();
    _reduced = prefersReducedMotion(context);
    final calm = !_atBottom &&
        stage.animate &&
        _reduced &&
        ref.read(gridSproutShownProvider);
    _calmTucked = calm;
    _tuck(stage.handoff.value >= 1 || calm);
    if (!calm) return;
    _climbBack = Timer(_kCalmFade, () {
      if (!mounted || _atBottom) return;
      _calmTucked = false;
      _tuck((widget.stage?.handoff.value ?? 0) >= 1);
    });
  }

  void _tuck(bool tucked) {
    if (_tucked != tucked && mounted) setState(() => _tucked = tucked);
  }

  /// How far below its resting place this body is drawn: its own sink (a
  /// pull, the way back from Settings), taken on down behind the board by
  /// the hand-off as the page carries him toward the foot of the screen.
  double get _drawnSink {
    final away = (widget.stage?.handoff.value ?? 0).clamp(0.0, 1.0);
    return _sink.value + (_kMaxSink - _sink.value) * away;
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
    // On his way to the foot of the screen, or there: not to be picked up
    // here.
    if (_asking || _atBottom || (widget.stage?.handoff.value ?? 0) > 0) return;
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
          hour: _clock().hour,
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
                  clock: _clock,
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
                  animation: Listenable.merge([
                    _x,
                    _sink,
                    if (widget.stage != null) widget.stage!.handoff,
                  ]),
                  child: sprout,
                  builder: (context, child) => TweenAnimationBuilder<double>(
                    tween: Tween(end: sleeping ? _kSleepLift : 0),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: child,
                    builder: (context, lift, child) => Positioned(
                      left: _x.value,
                      bottom: under - _kFeetBelowLine + lift - _drawnSink,
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
      animation: Listenable.merge([
        _x,
        _speech,
        _held,
        if (widget.stage != null) widget.stage!.handoff,
      ]),
      builder: (context, _) {
        // Gone with him once most of his face is behind the board.
        final away = (widget.stage?.handoff.value ?? 0) >= 0.5;
        final text = _held.value || _atBottom || away ? null : _speech.value;
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
