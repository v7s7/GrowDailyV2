part of 'sprout_ledge.dart';

// ─── Doum above the bottom bar ──────────────────────────────────────────────
//
// Aziz, 2026-09-29, choosing option A from the "Doum at the board's end"
// canvas (https://claude.ai/artifact/F2kgo6iiMmak47AhRt5qgZ): someone who
// scrolls down to fill the last rows of a long board used to leave Doum up
// on the board's top edge, off screen, so the squares that finished their
// day got no hop and no words. Now, as his spot on the edge nears the top of
// the screen, he ducks behind the board and pops up at the foot of the
// screen, peeking over the bottom bar the way he peeks over the board, over
// the habit NAMES (the one place at the foot of the screen that is never a
// square: the Grid's FAB was removed for covering squares). Scroll back up
// and he ducks there and climbs back onto the board. "Smooth and clean, not
// annoying, no errors."
//
// One Doum: his mind (DayCardSprout, with his talking limit, the praise he
// said lately and his greeting) never leaves the board's edge, and a
// SliverToBoxAdapter's child is laid out and kept even when scrolled far
// away. Down here is a second body that shows what the mind shows
// (SproutEcho). The body up there stops moving and is put out of sight
// while this one is shown, so there are never two of him.

/// Closer than this to the top of the screen, the board's edge sends Doum
/// down: his 52pt peek is then still fully in view, so the duck is seen.
const double _kLeaveAt = 64;

/// Further than this from the top, he comes back. The gap between the two
/// is what keeps a page nudged near the line from sending him up and down.
const double _kComeBackAt = 116;

/// The duck, in either place: the same one as when he is pulled down to be
/// hidden.
const Duration _kDuck = Duration(milliseconds: 170);

/// How long after one spot's duck starts the other spot's climb starts: he
/// visibly goes, then arrives.
const Duration _kHandoffGap = Duration(milliseconds: 90);

/// Reduce Motion: no travel at all, a fade in place.
const Duration _kCalmFade = Duration(milliseconds: 180);

/// How high a pop-up can carry him above the bar. The app's pop-ups are one
/// or two lines (about 64 to 90pt with their margin); a taller card covers
/// his feet rather than lifting him up the page.
const double _kMaxRide = 180;

/// A hold on him down here is his, before the habit name under him gets it
/// (a long-press there opens that habit's actions, at 500ms).
const Duration _kHoldFor = Duration(milliseconds: 400);

/// The height of the region at the foot of the Grid that [SproutBottomPeek]
/// draws in (GridScreen positions it): room for the peek, a jump, the
/// highest ride and a two-line bubble above it.
const double kSproutBottomHostHeight = 320;

// ── Making way ──────────────────────────────────────────────────────────────
//
// Aziz, 2026-09-29: down here he must not hide a habit's name, or the mark
// at its start (the category tile), unless the person put it there. While
// the page moves under their finger, rows pass behind him as they pass behind
// the bar. Once it stops, he stands only as tall as the room above the bar
// allows: all of him, just his leaves, or none (still here, behind the bar).
// He pops up to say something or to laugh, and makes way again after; a hop
// with no words plays only if it clears the names too. On a pop-up over the
// bar the same holds above the pop-up. Measured on the page, so it is the
// same in Arabic and in English. Each of those three heights ends where the
// drawings have no face to cut: his leaves alone are the top 13pt of every
// pose, his eyes start below 36.

/// How far he sinks to show only the tips of his leaves (13pt of the front
/// pose above the bar).
const double _kLeavesSink = 39;

/// How far he stays from a name or a tile, and the room kept for the small
/// dots that sit on a tile's lower corners.
const double _kClearBy = 3;

/// How much of a name (or its tile) has to show over the bar before it can
/// be read: less than half a line of its 11.5pt text is the tops of a few
/// letters, and he may stand in front of that. In points, not as a share of
/// the box, so a two-line name, whose first line is at the top of its box,
/// counts as soon as that line can be read.
const double _kReadableFrom = 6;

/// How long the page has to be still before he makes way or stands up
/// again: a finger that lifts to flick again does not move him.
const Duration _kStillFor = Duration(milliseconds: 150);

/// After a line or a laugh, how long before he makes way again: his bubble
/// has faded by then.
const Duration _kAfterTalking = Duration(milliseconds: 350);

// The iPhone's bottom bar is a pill 16pt in from the screen's sides with
// 28pt corners (GameNavBar's _GlassNavBar), and Doum's cut is a straight
// line at its top edge: over the curve of a corner there would be a sliver
// of nothing between the two. 38pt in, the curve is 0.65pt below the flat
// top, too little to see.
const double _kCornerClear = 38;

/// How far each pose's drawing reaches at [kLedgeSproutHeight], left and
/// right of his centre (the files face right), measured on the files
/// (pixels with alpha over 40): [left]/[right] over everything that can show
/// above the line, a hop included; [cutLeft]/[cutRight] over the last 3pt
/// above the line, where his cut meets the bar's edge.
const Map<SproutPose,
        ({double left, double right, double cutLeft, double cutRight})>
    _kReach = {
  SproutPose.frontWave:
      (left: 31.6, right: 31.6, cutLeft: 29.4, cutRight: 30.7),
  SproutPose.threeQuarterWave:
      (left: 29.7, right: 29.8, cutLeft: 24.8, cutRight: 29.5),
  SproutPose.happySparkles:
      (left: 35.1, right: 35.0, cutLeft: 33.3, cutRight: 30.0),
  SproutPose.laugh: (left: 32.9, right: 33.0, cutLeft: 32.4, cutRight: 33.0),
  SproutPose.sleeping:
      (left: 43.0, right: 42.9, cutLeft: 27.0, cutRight: 38.1),
};

/// Where Doum stands at the foot of the screen, from the page's start edge:
/// over the middle of the habit names, but never so far toward the squares
/// that the pose his mood gives him, or a laugh, reaches the first one; and
/// over the iPhone's rounded bar, as far from its corner as the squares
/// allow, so his cut meets the bar where it is flat. By the mood, never by
/// the pose shown for a moment, so a laugh never moves him.
///
/// Down here he faces into the page, toward the board and his own bubble,
/// not out at the screen's edge: the files face right, so in Arabic, where
/// the edge he stands by is the right one, he is drawn mirrored. Either way
/// the drawing's right side (as the files have it) is toward the squares and
/// its left toward the corner.
///
/// [names] is namesColumnFromStart's answer for the board (16pt inside the
/// page on each side).
double sproutBottomCentre({
  required ({double centre, double squaresFrom}) names,
  required SproutPose mood,
  required bool roundedBar,
}) {
  const wide = (left: 36.0, right: 36.0, cutLeft: 36.0, cutRight: 36.0);
  var toSquares = 0.0;
  var toCorner = 0.0;
  for (final pose in [mood, SproutPose.laugh]) {
    final r = _kReach[pose] ?? wide;
    toSquares = math.max(toSquares, r.right);
    toCorner = math.max(toCorner, r.cutLeft);
  }
  var centre = 16 + names.centre;
  if (roundedBar) centre = math.max(centre, _kCornerClear + toCorner);
  return math.min(centre, 16 + names.squaresFrom - 2 - toSquares);
}

/// Why the spot above the bar is not his for now.
enum SproutSpotBlock {
  /// It is his.
  none,

  /// The keyboard is up (from a sheet over the page): he is not there
  /// behind it, and is there again when it closes, with no fuss either way.
  quietly,

  /// Something else is standing there (a voice note's player, the bottom
  /// bar's one-time hint): he steps back onto the board's edge.
  visibly,
}

/// Where Doum is on the Grid, shared by the board's edge ([SproutLedge],
/// which decides, from where the edge is on screen) and the foot of the
/// screen ([SproutBottomPeek], which follows). GridScreen owns it for as
/// long as it lives.
class SproutStage extends ChangeNotifier {
  /// The second body's link to his mind.
  final SproutEcho echo = SproutEcho();

  /// What he is saying, drawn beside whichever spot he is at.
  final ValueNotifier<String?> speech = ValueNotifier<String?>(null);

  /// Whether the Grid's page is moving (being dragged, or gliding): a tap
  /// then only stops the page, as it does on the squares, and he is not
  /// tickled by it. The ledge mirrors the page's scroll here.
  final ValueNotifier<bool> scrolling = ValueNotifier<bool>(false);

  /// Whether the foot of the screen is his to go to (the foot sets it,
  /// the ledge reads it when it decides).
  final ValueNotifier<SproutSpotBlock> block =
      ValueNotifier<SproutSpotBlock>(SproutSpotBlock.none);

  bool _atBottom = false;
  bool _animate = true;
  Object? _owner;
  bool _disposed = false;

  /// The names and tiles on the page (see [SproutKeepClear]).
  final Set<_RenderKeepClear> _keepClear = <_RenderKeepClear>{};

  /// What he keeps clear of when he stands above the bar: every habit's name
  /// and the tile at its start, as the page has them now.
  Iterable<RenderBox> get keepClear => _keepClear;

  /// Whether he waits above the bottom bar rather than on the board's edge.
  bool get atBottom => _atBottom;

  /// Whether the last move is to be seen: false for the first decision a
  /// board makes, and for the keyboard's.
  bool get animate => _animate;

  /// The ledge that decides. A ledge built again takes over before the old
  /// one is disposed, and the old one's release then changes nothing.
  void claim(Object ledge) => _owner = ledge;

  /// The deciding ledge is going (from its dispose, while the tree is
  /// locked). Once the frame is over, what it was saying is dropped (its
  /// mind is gone and will never say "done"), and unless a new ledge has
  /// taken over by then, he is simply back on the edge.
  void release(Object ledge) {
    if (!identical(_owner, ledge)) return;
    _owner = null;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      speech.value = null;
      if (_owner == null) moveTo(bottom: false, animate: false);
    });
  }

  /// Sends him to one spot or the other. What he was saying stops: a line
  /// never jumps from one place to the other when the page moved him.
  /// [keepSpeech] is for the one move the page did not make: he woke up (the
  /// first square of the small hours) while the edge was out of sight, and
  /// the praise for that square is what he goes down there with.
  void moveTo({
    required bool bottom,
    required bool animate,
    bool keepSpeech = false,
  }) {
    if (_disposed || bottom == _atBottom) return;
    _atBottom = bottom;
    _animate = animate;
    if (!keepSpeech) speech.value = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    echo.dispose();
    speech.dispose();
    scrolling.dispose();
    block.dispose();
    super.dispose();
  }
}

/// Marks something on the page Doum must not stand in front of at the foot
/// of the screen once the page is still: a habit's tile and name, on the
/// Grid. Lays out and paints exactly as its child does.
class SproutKeepClear extends SingleChildRenderObjectWidget {
  const SproutKeepClear({
    super.key,
    required this.stage,
    this.reachAbove = 0,
    super.child,
  });

  /// The stage to tell; none, and it is only its child.
  final SproutStage? stage;

  /// How far above its box something of it is painted (a badge hovering
  /// over the tile), to be kept clear of too.
  final double reachAbove;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderKeepClear(stage)..reachAbove = reachAbove;

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderKeepClear)
      ..stage = stage
      ..reachAbove = reachAbove;
  }
}

class _RenderKeepClear extends RenderProxyBox {
  _RenderKeepClear(this._stage);

  SproutStage? _stage;
  double reachAbove = 0;

  set stage(SproutStage? value) {
    if (identical(value, _stage)) return;
    if (attached) _stage?._keepClear.remove(this);
    _stage = value;
    if (attached) _stage?._keepClear.add(this);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _stage?._keepClear.add(this);
  }

  @override
  void detach() {
    _stage?._keepClear.remove(this);
    super.detach();
  }
}

/// Doum at the foot of the Grid, peeking over the bottom bar above the
/// habit names while the board's top edge is scrolled away. Draws nothing
/// otherwise.
///
/// Stands on the bar's top edge (the bottom of the Grid's body), and on a
/// pop-up while one is up over it, rising and stepping down with the pop-up's
/// own animation (see snack_bar_watch.dart). Taps and holds on him are his
/// (a laugh), a sideways drag gives a little and springs back, and a drag up
/// or down that starts on him still scrolls the page.
///
/// Steps aside while the spot is someone else's: a voice note in the player
/// that floats right there, the bottom bar's one-time hint, or the keyboard
/// (which lifts the page's bottom); and is never here while Doum is hidden.
///
/// Makes way for the habits: once the page is still, he stands only as tall
/// as he can without hiding a name or its tile ([SproutKeepClear]), and pops
/// up to talk or laugh (see "Making way").
class SproutBottomPeek extends ConsumerStatefulWidget {
  const SproutBottomPeek({
    super.key,
    required this.stage,
    required this.namesFromStart,
    this.stepAside,
    this.hintShowing = false,
  });

  final SproutStage stage;

  /// Where the habit names are on a board this wide (namesColumnFromStart),
  /// or null when the board scrolls sideways and has no such place.
  final ({double centre, double squaresFrom})? Function(
    double boardWidth, {
    required bool rtl,
  }) namesFromStart;

  /// True while a voice note is in the player floating above the bar
  /// (VoiceNoteService.playerUp).
  final ValueListenable<bool>? stepAside;

  /// Whether the bottom bar's one-time hint is spotlighting the bar
  /// (shouldShowNavBarHint): its lit hole reaches 8pt above the bar.
  final bool hintShowing;

  @override
  ConsumerState<SproutBottomPeek> createState() => _SproutBottomPeekState();
}

class _SproutBottomPeekState extends ConsumerState<SproutBottomPeek>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Made in initState, not lazily: a lazy controller first touched in
  // dispose would be born there, asking a dead element for its TickerMode.

  /// How far below his resting place he is: 0 up, [_kMaxSink] out of sight.
  late final AnimationController _sink;

  /// How high above the bar a pop-up has carried him.
  late final AnimationController _lift;

  /// Reduce Motion's fade in place.
  late final AnimationController _fade;

  /// How far a sideways drag has pulled him (a little, then back).
  late final AnimationController _wobble;

  /// Where he is headed: up, or out of sight.
  bool _up = false;

  /// Whether his body is built at all: from the moment he starts up until
  /// he is fully out of sight again.
  bool _present = false;

  /// Whether his body plays the mind's moves: only once he is on his way
  /// up. Out of sight, a hop would lift his leaves back over the bar.
  bool _climbed = false;

  bool _watching = false;
  bool _syncQueued = false;
  bool _reconsiderQueued = false;
  bool _stageMove = false;
  bool _reduced = false;

  /// Where the stage had him at the last look: a change is the stage's move
  /// whichever listener hears of it first.
  bool _seenAtBottom = false;

  /// This body's moves: the mind's, played here only when they cannot lift
  /// him over a name (see [_onMove]).
  final SproutController _moves = SproutController();

  /// He stepped aside because the keyboard came up.
  bool _asideForKeyboard = false;
  Timer? _climb;
  double _pulled = 0;

  /// Where the pop-up's surface was at the last look, to see it being
  /// swiped down.
  double? _lastSurfaceTop;

  /// Whether nothing is carrying him up or down at the last look: no pop-up
  /// and his lift at rest, or a pop-up fully up and not moving.
  bool _rideSettled = true;

  /// The pop-up's direction at the last look. A ride's sink is laid over
  /// the rest of its travel from where he was ([_rideFrom]) and how far the
  /// ride had gone ([_rideDone0]) when he started sinking with it; [_riding]
  /// is whether he did at the last look, so a pause (the page moved, he
  /// talked) starts a fresh blend from wherever he then is, never a jump.
  AnimationStatus? _rideStatus;
  bool _riding = false;
  double _rideFrom = 0;
  double _rideDone0 = 0;

  /// Where he stands while he is here, as a sink: 0 is all of him, then his
  /// leaves, then none of him (behind the bar, still here). See "Making way".
  double _rest = 0;

  /// The page has been still long enough (and he has finished talking): he
  /// stands as tall as the room allows, and keeps doing so as the page
  /// changes under him.
  bool _still = false;
  Timer? _stillTimer;

  /// He talked or laughed since he last made way.
  bool _performed = false;

  @override
  void initState() {
    super.initState();
    _sink = AnimationController.unbounded(vsync: this, value: _kMaxSink);
    _lift = AnimationController.unbounded(vsync: this);
    _fade = AnimationController(vsync: this, value: 1, duration: _kCalmFade);
    _wobble = AnimationController.unbounded(vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _listenTo(widget.stage);
    widget.stepAside?.addListener(_queueSync);
    _queueSync();
  }

  void _listenTo(SproutStage stage) {
    stage.addListener(_onStage);
    stage.echo.addListener(_queueSync);
    stage.echo.echoMoves.addListener(_onMove);
    // Neither can change whether he is here, only how tall he stands: kept
    // apart from _sync, which also reads the stage's moves.
    stage.scrolling.addListener(_queueReconsider);
    stage.speech.addListener(_queueReconsider);
  }

  void _stopListening(SproutStage stage) {
    stage.removeListener(_onStage);
    stage.echo.removeListener(_queueSync);
    stage.echo.echoMoves.removeListener(_onMove);
    stage.scrolling.removeListener(_queueReconsider);
    stage.speech.removeListener(_queueReconsider);
  }

  @override
  void didUpdateWidget(covariant SproutBottomPeek old) {
    super.didUpdateWidget(old);
    if (!identical(old.stage, widget.stage)) {
      _stopListening(old.stage);
      _listenTo(widget.stage);
    }
    if (!identical(old.stepAside, widget.stepAside)) {
      old.stepAside?.removeListener(_queueSync);
      widget.stepAside?.addListener(_queueSync);
    }
    _queueSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopListening(widget.stage);
    widget.stepAside?.removeListener(_queueSync);
    _climb?.cancel();
    _stillTimer?.cancel();
    _unwatch();
    _sink.dispose();
    _lift.dispose();
    _fade.dispose();
    _wobble.dispose();
    _moves.dispose();
    super.dispose();
  }

  // The keyboard (from a sheet over the Grid) moves the body's bottom up
  // with it. The Grid's own MediaQuery never shows it (HomeShell's Scaffold
  // takes the inset out of its body's), so it is read from the view.
  @override
  void didChangeMetrics() => _queueSync();

  bool get _keyboardUp {
    final view = View.maybeOf(context);
    return view != null && view.viewInsets.bottom > 0;
  }

  SproutSpotBlock get _block {
    if (_keyboardUp) return SproutSpotBlock.quietly;
    if ((widget.stepAside?.value ?? false) || widget.hintShowing) {
      return SproutSpotBlock.visibly;
    }
    return SproutSpotBlock.none;
  }

  void _onStage() => _queueSync(fromStage: true);

  /// Whatever changed, it is looked at once, outside any build: a listener
  /// can be told mid-build, and starting an animation there would mark
  /// widgets dirty mid-build.
  void _queueSync({bool fromStage = false}) {
    _stageMove |= fromStage;
    if (_syncQueued) return;
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks ||
        scheduler.schedulerPhase == SchedulerPhase.midFrameMicrotasks) {
      _syncQueued = true;
      scheduler.addPostFrameCallback((_) {
        _syncQueued = false;
        if (mounted) _sync();
      });
      scheduler.ensureVisualUpdate();
      return;
    }
    _sync();
  }

  /// Like [_queueSync], for what only changes how tall he stands.
  void _queueReconsider() {
    if (_reconsiderQueued) return;
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks ||
        scheduler.schedulerPhase == SchedulerPhase.midFrameMicrotasks) {
      _reconsiderQueued = true;
      scheduler.addPostFrameCallback((_) {
        _reconsiderQueued = false;
        if (mounted) _reconsider();
      });
      scheduler.ensureVisualUpdate();
      return;
    }
    _reconsider();
  }

  void _sync() {
    final byStage =
        _stageMove || widget.stage.atBottom != _seenAtBottom;
    _stageMove = false;
    _seenAtBottom = widget.stage.atBottom;
    final block = _block;
    // The ledge decides with this too: while the spot is taken he is back
    // on the board's edge, where his words and his screen-reader node go.
    // It looks after a frame, and nothing else may be drawing one.
    if (widget.stage.block.value != block) {
      widget.stage.block.value = block;
      SchedulerBinding.instance.ensureVisualUpdate();
    }
    final want = widget.stage.atBottom &&
        widget.stage.echo.hasMind &&
        ref.read(gridSproutShownProvider) &&
        block == SproutSpotBlock.none;
    if (want == _up) {
      if (_up) _reconsider();
      return;
    }
    _up = want;
    _reduced = prefersReducedMotion(context);
    // A move the stage asked to be seen, or a step aside for a voice note or
    // the hint, is animated. The keyboard's is not, either way: it comes
    // with a sheet over the page, and he just is not there behind it, then
    // is there again when it closes. Nor is a board built already scrolled.
    final keyboard = block == SproutSpotBlock.quietly;
    final animate = byStage
        ? widget.stage.animate
        : !(keyboard || _asideForKeyboard);
    _asideForKeyboard = !want && keyboard;
    _climb?.cancel();
    if (want) {
      _rise(animate);
    } else {
      _duck(animate);
    }
  }

  void _setClimbed(bool climbed) {
    if (_climbed != climbed && mounted) setState(() => _climbed = climbed);
  }

  void _rise(bool animate) {
    _watch();
    if (!_present) setState(() => _present = true);
    // Where a pop-up up now will have him stand: looked at before the room
    // is (his lift was put down when he last left).
    _scan();
    // All of him while the page moves (the page is what sent him), or as
    // much as the room allows when it is still (a sheet closed, a voice note
    // ended).
    _rest = widget.stage.scrolling.value || _performing ? 0 : (_fit() ?? 0);
    if (!animate) {
      _sink.stop();
      _sink.value = _rest;
      _fade.value = 1;
      _setClimbed(true);
      _reconsider();
      return;
    }
    if (_reduced) {
      _sink.stop();
      _sink.value = _rest;
      _fade.value = 0;
      _fade.forward();
      _setClimbed(true);
      _reconsider();
      return;
    }
    _fade.value = 1;
    // Turned back mid-duck, still partly in view: straight back up from
    // where he is, with the speed he had, no pause.
    if (_sink.value < _kMaxSink - 0.5) {
      final velocity = _sink.velocity;
      _sink.stop();
      _springUp(velocity);
      return;
    }
    _sink.value = _kMaxSink;
    _climb = Timer(_kHandoffGap, () {
      if (mounted && _up) _springUp(0);
    });
  }

  void _springUp(double velocity) {
    _setClimbed(true);
    final to = _rest;
    _sink
        .animateWith(
      SpringSimulation(_SproutLedgeState._bounce, _sink.value, to, velocity),
    )
        .then((_) {
      // A spring stops within a hair of where it was going.
      if (mounted && _up && _rest == to) _sink.value = to;
    });
    _reconsider();
  }

  void _duck(bool animate) {
    _setClimbed(false);
    _stillTimer?.cancel();
    _still = false;
    _performed = false;
    void gone() {
      if (!mounted || _up) return;
      _rest = 0;
      _rideStatus = null;
      _riding = false;
      _lastSurfaceTop = null;
      _sink.value = _kMaxSink;
      _lift.stop();
      _lift.value = 0;
      _wobble.stop();
      _wobble.value = 0;
      _unwatch();
      setState(() => _present = false);
    }

    if (!animate || !_present) return gone();
    if (_reduced) {
      _fade.reverse().then((_) => gone());
      return;
    }
    _sink
        .animateTo(_kMaxSink, duration: _kDuck, curve: Curves.easeIn)
        .then((_) => gone());
  }

  // ── Making way ──────────────────────────────────────────────────────────

  /// Talking or laughing: he is all up for it, whatever is behind him.
  bool get _performing =>
      widget.stage.speech.value != null ||
      widget.stage.echo.pose == SproutPose.laugh;

  /// Something changed while he is here (the page moved or stopped, he
  /// started or stopped talking): whether, and when, to look at the room
  /// again.
  void _reconsider() {
    // Not while he is still on his way from the board's edge: he arrives
    // first.
    if (!_up || !_climbed || (_climb?.isActive ?? false)) return;
    if (_performing) {
      _stillTimer?.cancel();
      _still = false;
      _performed = true;
      _standAt(0);
      return;
    }
    if (widget.stage.scrolling.value) {
      // The page moves under the finger: he holds where he is, and rows go
      // behind him as they go behind the bar.
      _stillTimer?.cancel();
      _still = false;
      return;
    }
    if (_still || (_stillTimer?.isActive ?? false)) return;
    final wait = _performed ? _kAfterTalking : _kStillFor;
    _performed = false;
    _stillTimer = Timer(wait, () {
      if (!mounted || !_up) return;
      _still = true;
      _makeWay();
    });
  }

  /// Stands as tall as the room above his line allows, if the page is still
  /// and nothing is carrying him up or down (a pop-up fully up counts as
  /// still: he fits above it).
  void _makeWay() {
    if (!_still || _performing || widget.stage.scrolling.value) return;
    if (!_rideSettled) return;
    final fit = _fit();
    if (fit != null) _standAt(fit);
  }

  /// While a pop-up carries him up or down: the height the line he is headed
  /// for allows, if it is lower than his. He only ever sinks on the way, so
  /// no name is hidden while he travels; he stands up again once it is still.
  void _sinkFor(double line) {
    if (!_still || _performing || widget.stage.scrolling.value) return;
    final fit = _fit(line: line);
    if (fit != null && (fit > _rest || fit > _sink.value + 0.5)) _standAt(fit);
  }

  /// How far down he has to be to hide no habit's name or tile: 0 when all
  /// of him fits, [_kLeavesSink] when his leaves do, [_kMaxSink] when
  /// nothing does. Null while the page has no size or no names column.
  double? _fit({double? line}) {
    final room = _room(line: line);
    if (room == null) return null;
    if (room.blocked) return _kMaxSink;
    if (room.clear >= room.tall) return 0;
    if (room.clear >= room.tall - _kLeavesSink) return _kLeavesSink;
    return _kMaxSink;
  }

  /// The room over his [line] (his line now, if not given) in the column he
  /// stands in: [clear] is how high he may reach before a name or a tile,
  /// [blocked] when one that can be read is partly behind the bar (nothing
  /// of him fits then), and [tall] how far the top of his pose's box is over
  /// the line when all of him is up. Null while the page has no size or no
  /// names column.
  ({double clear, bool blocked, double tall})? _room({double? line}) {
    final host = context.findRenderObject();
    if (host is! RenderBox || !host.attached || !host.hasSize) return null;
    final pad = MediaQuery.maybePaddingOf(context) ?? EdgeInsets.zero;
    final width = host.size.width - pad.left - pad.right;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final names = widget.namesFromStart(width - 32, rtl: rtl);
    if (names == null) return null;
    final mood = widget.stage.echo.mood;
    final fromStart = sproutBottomCentre(
      names: names,
      mood: mood,
      roundedBar: defaultTargetPlatform == TargetPlatform.iOS,
    );
    // Where _stand puts him, across the host.
    final x = pad.left + (rtl ? width - fromStart : fromStart);
    // His widest reach either side, whichever pose is shown for a moment.
    var half = 0.0;
    for (final pose in [mood, SproutPose.laugh]) {
      final r = _kReach[pose];
      half = math.max(half, r == null ? 36.0 : math.max(r.left, r.right));
    }
    final at = line ?? host.size.height - _lift.value;
    // How far over the line the top of his pose's box is, all of him up: the
    // poses are drawn at one scale, so a taller drawing stands taller.
    final tall = Sprout.sizeOf(mood, kLedgeSproutHeight).height -
        _kFeetBelowLine +
        (mood == SproutPose.sleeping ? _kSleepLift : 0);
    var clear = double.infinity;
    for (final box in widget.stage._keepClear) {
      if (!box.attached || !box.hasSize) continue;
      final a = host.globalToLocal(box.localToGlobal(Offset.zero));
      final b = host.globalToLocal(
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      );
      var shape = Rect.fromPoints(a, b);
      if (shape.isEmpty) continue;
      shape = Rect.fromLTRB(
        shape.left,
        shape.top - box.reachAbove,
        shape.right,
        shape.bottom,
      );
      if (shape.right <= x - half || shape.left >= x + half) continue;
      if (shape.top >= at) continue;
      if (shape.bottom > at) {
        // Partly behind the bar: too little of it shows to be read, or
        // nothing of him fits in front of it.
        if (at - shape.top < _kReadableFrom) continue;
        return (clear: 0, blocked: true, tall: tall);
      }
      clear = math.min(clear, at - shape.bottom - _kClearBy);
    }
    return (clear: clear, blocked: false, tall: tall);
  }

  /// The mind moved (a hop, the big jump), relayed a frame later. The words
  /// or the laugh that come with a move land in that same frame's callbacks,
  /// so it is decided once they have all run: played here if he is up for
  /// them, or if, where he stands, its highest point still clears the names.
  /// A hop with no words while he makes way is let go: it would lift his
  /// leaves back over the name he sank for.
  void _onMove() {
    scheduleMicrotask(() {
      if (!mounted || !_up || !_climbed) return;
      final moves = widget.stage.echo.echoMoves;
      if (_performing) {
        _moves.repeat(moves);
        return;
      }
      final room = _room();
      if (room == null || room.blocked) return;
      final top = room.tall - math.min(_rest, _sink.value);
      final rise = moves.lastRise(widget.stage.echo.pose, kLedgeSproutHeight);
      if (top + rise <= room.clear) _moves.repeat(moves);
    });
  }

  /// Moves him to stand at [to] (a sink): up with the climb's bounce, down
  /// with an easy duck, at once under Reduce Motion.
  void _standAt(double to) {
    // Already there, or on the way (every animation here heads for _rest).
    // A ride cut short leaves him short of it: then he goes the rest.
    if (to == _rest &&
        (_sink.isAnimating || (_sink.value - to).abs() < 0.5)) {
      return;
    }
    _rest = to;
    if (prefersReducedMotion(context)) {
      _sink.stop();
      _sink.value = to;
      return;
    }
    if (to < _sink.value) {
      final velocity = _sink.isAnimating ? _sink.velocity : 0.0;
      _sink.stop();
      _sink
          .animateWith(
        SpringSimulation(_SproutLedgeState._bounce, _sink.value, to, velocity),
      )
          .then((_) {
        if (mounted && _up && _rest == to) _sink.value = to;
      });
    } else {
      _sink.animateTo(
        to,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  // ── Riding a pop-up ─────────────────────────────────────────────────────

  void _watch() {
    if (_watching) return;
    _watching = true;
    FrameWatch.add(_scan);
  }

  void _unwatch() {
    if (!_watching) return;
    _watching = false;
    FrameWatch.remove(_scan);
  }

  /// After every frame while he is here: how high the pop-up over the bar
  /// carries him, from its own animation. An M3 floating bar is laid out at
  /// full size from its first frame and revealed by a clip growing up from
  /// its foot (easeInOutQuart), invisible until 0.4 and opaque by 0.6; it
  /// leaves at full height, fading. His rise follows 0.3 to 1 of that,
  /// easing in and out: always at or under the bar's growing edge (so the
  /// bar, drawn over him, always hides his feet), never faster than that
  /// edge moves, and on the way out he is back on the bar by the time it has
  /// faded (under a point at 0.4). One pop-up replacing another: down with
  /// the old one, up with the new, as they go. A swipe moves the surface,
  /// and him with it.
  void _scan() {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final seen = sightSnackBar(context);
    // Flying with a route change: stay where he is until it lands.
    if (seen != null && seen.offstage) {
      _rideSettled = false;
      return;
    }
    if (seen == null) {
      _lastSurfaceTop = null;
      _rideStatus = null;
      _riding = false;
      if (_lift.value <= 0.25) {
        if (_lift.value != 0 && !_lift.isAnimating) _lift.value = 0;
      } else if (!_lift.isAnimating) {
        // Gone at once (swiped away, or a screen reader's instant hide):
        // he steps down rather than drops.
        if (prefersReducedMotion(context)) {
          _lift.value = 0;
        } else {
          _lift.animateTo(
            0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        }
      }
      _rideSettled = _lift.value == 0 && !_lift.isAnimating;
      if (_rideSettled) {
        // Still, and nothing carrying him: the page may have changed under
        // him (a row added, a name wrapped, selection mode), so he looks
        // again.
        _makeWay();
      } else {
        _sinkFor(box.size.height);
      }
      return;
    }
    final full = (box.size.height -
            box.globalToLocal(Offset(0, seen.surfaceTop)).dy)
        .clamp(0.0, _kMaxRide)
        .toDouble();
    final double share;
    if (prefersReducedMotion(context)) {
      share = seen.value >= 0.8 ? 1 : 0;
    } else {
      share = Curves.easeInOutCubic
          .transform(((seen.value - 0.3) / 0.7).clamp(0.0, 1.0));
    }
    var ride = full * share;
    // Being swiped down: what is read here is a frame old by the time it is
    // drawn, so he steps ahead by the last frame's travel, and his cut stays
    // at or under the bar's edge all the way down instead of hovering a
    // frame above it.
    final last = _lastSurfaceTop;
    _lastSurfaceTop = seen.surfaceTop;
    final swiped = seen.status == AnimationStatus.completed &&
        last != null &&
        seen.surfaceTop > last + 0.5;
    if (swiped) {
      ride = math.max(0.0, ride - (seen.surfaceTop - last));
    }
    if (_lift.isAnimating) _lift.stop();
    if ((_lift.value - ride).abs() > 0.25) _lift.value = ride;
    if (seen.status != _rideStatus) {
      _rideStatus = seen.status;
      _riding = false;
    }
    // Fully up and not moving: he fits above it, as he does above the bar.
    _rideSettled = seen.status == AnimationStatus.completed && !swiped;
    if (_rideSettled) {
      _riding = false;
      _makeWay();
    } else if (swiped) {
      _riding = false;
      _sinkFor(box.size.height);
    } else {
      // Coming up, he sinks for where it will carry him; going, for the bar
      // he goes back to. In step with its travel, so his top never rises
      // over a name on the way: at its start he is where he was, at its end
      // where the room there allows.
      final up = seen.status == AnimationStatus.forward;
      _rideSink(
        line: up ? box.size.height - full : box.size.height,
        done: up ? share : 1 - share,
      );
    }
  }

  /// Lays the sink a ride needs over the rest of the ride's own travel
  /// ([done], 0 to 1): from where he is when he starts sinking with it to
  /// where the line it takes him to allows, arriving as it does. Only ever
  /// down, and only while he is making way.
  void _rideSink({required double line, required double done}) {
    if (!_still || _performing || widget.stage.scrolling.value) {
      _riding = false;
      return;
    }
    final fit = _fit(line: line);
    if (fit == null) return;
    if (!_riding) {
      _riding = true;
      _rideFrom = _sink.value;
      _rideDone0 = done;
    }
    if (fit <= _rideFrom + 0.5) return;
    if (_rideDone0 > 0.15) {
      // Joined late (the page had been moving, or he was talking): what is
      // left of the ride may be quick, so an ordinary duck instead of
      // catching up with it.
      _standAt(fit);
      return;
    }
    final k = ((done - _rideDone0) / (1 - _rideDone0)).clamp(0.0, 1.0);
    _sink.stop();
    _sink.value = _rideFrom + (fit - _rideFrom) * k;
    // Arrived: that is where he stands now. Cut short, he is not there yet,
    // and the next look at the room takes him the rest of the way.
    if (k >= 1) _rest = fit;
  }

  // ── A sideways pull ─────────────────────────────────────────────────────
  //
  // On the board's edge a sideways drag slides him along it. Down here there
  // is nowhere to slide to, and a drag that started on him must not swipe
  // the page to another tab instead: he gives a little, and springs back.

  void _pullStart(DragStartDetails d) {
    _wobble.stop();
    _pulled = 0;
  }

  void _pullUpdate(DragUpdateDetails d) {
    _pulled += d.delta.dx;
    _wobble.value = _pulled.sign * 10 * (1 - 1 / (_pulled.abs() / 50 + 1));
  }

  void _pullEnd(DragEndDetails d) => _letGo(d.velocity.pixelsPerSecond.dx);

  void _pullCancel() => _letGo(0);

  void _letGo(double velocity) {
    if (prefersReducedMotion(context)) {
      _wobble.value = 0;
      return;
    }
    _wobble
        .animateWith(
      SpringSimulation(
        _SproutLedgeState._bounce,
        _wobble.value,
        0,
        velocity * 0.05,
      ),
    )
        .then((_) {
      // A spring stops within a hair of home; home is one place.
      if (mounted) _wobble.value = 0;
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(gridSproutShownProvider, (_, __) => _queueSync());
    if (!_present) return const SizedBox.shrink();
    final echo = widget.stage.echo;
    final s = S.of(context);
    // Built once per build and handed to the moving parts as a child, so a
    // frame of the climb or the ride moves a picture and rebuilds nothing.
    final body = ValueListenableBuilder<bool>(
      valueListenable: widget.stage.scrolling,
      builder: (context, scrolling, child) =>
          IgnorePointer(ignoring: scrolling, child: child),
      child: RepaintBoundary(
        child: RawGestureDetector(
          excludeFromSemantics: true,
          gestures: <Type, GestureRecognizerFactory>{
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                duration: _kHoldFor,
                debugOwner: this,
              ),
              (r) => r.onLongPress = echo.tickle,
            ),
            HorizontalDragGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                    HorizontalDragGestureRecognizer>(
              () => HorizontalDragGestureRecognizer(debugOwner: this),
              (r) => r
                ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
                ..onStart = _pullStart
                ..onUpdate = _pullUpdate
                ..onEnd = _pullEnd
                ..onCancel = _pullCancel,
            ),
          },
          child: ListenableBuilder(
            listenable: echo,
            builder: (context, _) => Sprout(
              pose: echo.pose,
              height: kLedgeSproutHeight,
              controller: _climbed ? _moves : null,
              entrance: SproutEntrance.none,
              onTap: echo.tickle,
              semanticLabel: s.sproutName,
              // Facing into the page (see sproutBottomCentre).
              mirror: Directionality.of(context) == TextDirection.rtl,
            ),
          ),
        ),
      ),
    );
    return _PassThroughHits(
      child: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, box) => _stand(context, box, body),
        ),
      ),
    );
  }

  Widget _stand(BuildContext context, BoxConstraints box, Widget body) {
    final width = box.maxWidth;
    final height = box.maxHeight;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final names = widget.namesFromStart(width - 32, rtl: rtl);
    if (names == null) return const SizedBox.shrink();
    final echo = widget.stage.echo;
    return ListenableBuilder(
      listenable: echo,
      builder: (context, _) {
        final mood = echo.mood;
        final fromStart = sproutBottomCentre(
          names: names,
          mood: mood,
          roundedBar: defaultTargetPlatform == TargetPlatform.iOS,
        );
        return TweenAnimationBuilder<double>(
          tween: Tween(end: fromStart),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          builder: (context, fromStart, _) {
            final x = rtl ? width - fromStart : fromStart;
            return TweenAnimationBuilder<double>(
              tween: Tween(end: mood == SproutPose.sleeping ? _kSleepLift : 0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              builder: (context, sleepLift, _) => AnimatedBuilder(
                animation: Listenable.merge([_sink, _lift, _fade, _wobble]),
                builder: (context, _) {
                  final line = height - _lift.value;
                  return Opacity(
                    opacity: _fade.value,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          key: const ValueKey('doum'),
                          child: ClipRect(
                            clipper: _AboveLine(line),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  left: x + _wobble.value,
                                  bottom: _lift.value -
                                      _kFeetBelowLine +
                                      sleepLift -
                                      _sink.value,
                                  child: FractionalTranslation(
                                    translation: const Offset(-0.5, 0),
                                    // Making way, all behind the bar: not
                                    // there for a screen reader either.
                                    child: ExcludeSemantics(
                                      excluding:
                                          _sink.value >= _kMaxSink - 0.5,
                                      child: body,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        KeyedSubtree(
                          key: const ValueKey('bubble'),
                          child: _speech(width, x, rtl),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  /// What he says, beside him toward the squares (the only side with room
  /// down here), its tail at the corner facing him, just above his line.
  Widget _speech(double width, double x, bool rtl) {
    return ValueListenableBuilder<String?>(
      valueListenable: widget.stage.speech,
      builder: (context, text, _) {
        // Only once he is up: never beside a Doum still on his way.
        final shown = _up && _sink.value < 20 ? text : null;
        final onRight = !rtl;
        final room = onRight
            ? width - (x + _kHalfWidth - 6) - 12
            : (x - _kHalfWidth + 6) - 12;
        return Positioned(
          left: onRight ? x + _kHalfWidth - 6 : null,
          right: onRight ? null : width - (x - _kHalfWidth + 6),
          bottom: _lift.value + 2,
          child: _speechSwitcher(
            text: shown,
            maxWidth: room.clamp(60.0, 170.0).toDouble(),
            onRight: onRight,
            tailAtStart: true,
            reduced: _reduced,
          ),
        );
      },
    );
  }
}

/// Hit-tests its child and then says "missed", so the widgets under it are
/// hit as well: a tap or a hold on Doum is his (the gesture arena gives a
/// tap to the first recognizer it met, his, and his hold's deadline is the
/// shorter), and a drag up or down that starts on him still reaches the
/// page's scroll view under him and scrolls it.
class _PassThroughHits extends SingleChildRenderObjectWidget {
  const _PassThroughHits({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPassThroughHits();
}

class _RenderPassThroughHits extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.contains(position)) {
      hitTestChildren(result, position: position);
    }
    return false;
  }
}
