import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/utils/reduced_motion.dart';
import '../habits/notifiers/custom_habits_notifier.dart'
    show allHabitsEverProvider;
import 'pet_settings.dart';
import 'sprout.dart';
import 'sprout_echo.dart';
import 'sprout_mood.dart';
import 'sprout_praise.dart';
import 'sprout_signals.dart';

/// How often the sprout may put praise into words, built in: at most once in
/// this long, counted from the last line it actually said. Every square done
/// still gets its hop; only the words wait. The streak point and the perfect
/// day always speak (Aziz, 2026-09-28: five prayers ticked in a row flashed
/// five lines nobody could read). The admin's «دوم» page can change it
/// (PetSettings.praiseEvery, read at the moment of speaking).
const Duration kSproutPraiseEvery = Duration(seconds: kPetPraiseEverySeconds);

/// The sprout on the Grid's day card: its home in the app.
///
/// It reacts to what the day DOES, from the same two sources the rest of the
/// screen already trusts, never from a tap of its own:
///   - the card's numbers rose (ratio, partial credit included, so a walk in
///     progress or a 2x habit at 1 of 2 counts): a hop, and praise that fits
///     what was done, «تقبّل الله» for a prayer, «يعطيك العافية» for a
///     workout (sprout_praise.dart), in words at most once per
///     [kSproutPraiseEvery] and the hop alone inside it. A square turned
///     green on the board says which habit it was ([sproutDoneProvider]); a
///     rise from a widget, a notification action or another screen gets the
///     general lines;
///   - the day just earned its streak point ([sproutStreakPointProvider],
///     bumped on the exact tap the heavy haptic, the burst and «يومك انحسب
///     في سلسلتك.» fire on): the celebration, saying «سلسلتك زادت» with
///     them. A streak pass, not a full day (Aziz, 2026-09-28). No haptic of
///     its own there, the board's is already on that tap;
///   - every habit the day asked for is done, the card's own «يوم مثالي»:
///     the celebration again, «يوم مثالي». With four habits or fewer 80% IS
///     100%, both land on one tap, and the sprout jumps once and says the
///     bigger thing;
///   - tapped: it laughs for a moment. The one thing on the card that exists
///     only to be fun.
///
/// It speaks in a bubble that shows for a moment (PetSettings.bubbleFor, 3
/// seconds built in) and fades, never permanently: the card's height is
/// spoken for (see _SummaryCard), so the bubble floats above the card for a
/// moment and leaves nothing behind. It
/// greets once per app launch, not on every rebuild of the tab, and only
/// once today's week has loaded.
class DayCardSprout extends ConsumerStatefulWidget {
  const DayCardSprout({
    super.key,
    required this.greens,
    required this.owed,
    required this.ratio,
    required this.perfectDay,
    this.live = true,
    this.height = 100,
    this.clock = DateTime.now,
    this.drawsBubble = true,
    this.onBubble,
    this.echo,
    this.bodyAway = false,
  });

  final int greens;
  final int owed;

  /// The ring's own ratio, partial credit included.
  final double ratio;
  final bool perfectDay;

  /// Whether these numbers are TODAY's, loaded. The card also rebuilds when
  /// the week finishes loading at launch and when someone browses back to
  /// this week from another, and both look exactly like a rise from 0: a
  /// hop, or a whole celebration, for nothing anyone did. The sprout reacts
  /// only between two live readings.
  final bool live;
  final double height;

  /// The wall clock; replaced in tests.
  final DateTime Function() clock;

  /// Whether this widget draws its own bubble above the sprout. Off when the
  /// host draws it somewhere else (a sprout that moves along the board's
  /// edge puts the bubble beside itself), with [onBubble] saying what to show.
  final bool drawsBubble;

  /// Told the bubble's text each time the sprout speaks, and null when the
  /// bubble goes, for a host that draws the bubble itself.
  final ValueChanged<String?>? onBubble;

  /// A second body that stands in for this sprout elsewhere (above the
  /// bottom bar, when the board's edge has scrolled away): told the pose
  /// shown here, moved by the same moves, and a tap on it tickles this one.
  /// This widget stays the only mind (see SproutEcho).
  final SproutEcho? echo;

  /// This body is out of sight while the stand-in is shown: it makes no
  /// moves (a hop would lift its leaves back over the board's edge) and
  /// resumes, with nothing replayed, when he is back.
  final bool bodyAway;

  /// Whether this app launch has greeted yet. Reset between tests.
  static bool greetedThisLaunch = false;

  @override
  ConsumerState<DayCardSprout> createState() => _DayCardSproutState();
}

class _DayCardSproutState extends ConsumerState<DayCardSprout> {
  static const _laughFor = Duration(milliseconds: 1400);

  /// How long a square turned green on the board still names the habit a
  /// rise is praised for: the rise lands a frame or two after the tap.
  static const _doneFreshFor = Duration(seconds: 3);

  /// Two celebrations inside this window are one moment (the streak point
  /// and the perfect day on the same tap): the jump plays once, and the
  /// bubble takes the later, bigger line.
  static const _oneMoment = Duration(milliseconds: 1500);

  final _ownMoves = SproutController();

  /// The echo's controller when there is one, so the stand-in hops with
  /// this body; this body's own otherwise.
  SproutController get _moves => widget.echo?.moves ?? _ownMoves;
  Timer? _bubbleTimer;
  Timer? _laughTimer;
  String? _bubble;
  bool _laughing = false;
  bool _precached = false;
  DateTime? _lastParty;

  /// When the sprout last put praise or a big moment into words: the talking
  /// limit counts from here. The hello and the laugh do not count, so the
  /// first square after them is still praised.
  DateTime? _lastSpokeAt;

  /// The last praise said, and when, so a big moment on the same tap can
  /// keep it (see [_praiseJustSaid]).
  String? _lastPraise;
  DateTime? _lastPraiseAt;

  /// The widget's wall clock, for every "how long ago" here.
  DateTime get _now => widget.clock();

  @override
  void initState() {
    super.initState();
    widget.echo?.attach(this, _tickle);
    _greetOnce();
  }

  /// The once-per-launch hello, only once the numbers are today's real ones.
  /// The card is built while the week is still loading (0 of N), so a hello
  /// timed from the first frame would say «هلا، نبدأ؟» over a day that is
  /// already 7 of 10 on a slow launch.
  void _greetOnce() {
    if (DayCardSprout.greetedThisLaunch || !widget.live) return;
    DayCardSprout.greetedThisLaunch = true;
    // After the entrance pop has landed, not during it.
    _bubbleTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _say(_lineText(_mood().line));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    // Every pose this card can switch to, decoded ahead of the switch, so a
    // square turning green never shows a blank frame where the sprout was.
    final scale = sproutScaleFor(widget.height);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 3;
    for (final pose in const [
      SproutPose.frontWave,
      SproutPose.threeQuarterWave,
      SproutPose.happySparkles,
      SproutPose.laugh,
      SproutPose.sleeping,
    ]) {
      precacheImage(sproutImage(pose, scale, dpr), context);
    }
  }

  @override
  void didUpdateWidget(covariant DayCardSprout old) {
    super.didUpdateWidget(old);
    if (!identical(old.echo, widget.echo)) {
      old.echo?.detach(this);
      widget.echo?.attach(this, _tickle);
    }
    if (!old.live && widget.live) {
      // The week just landed: a hello if this launch has had none, and no
      // reaction to the jump from 0, which nobody did.
      _greetOnce();
      return;
    }
    if (!old.live || !widget.live) return;
    if (widget.perfectDay && !old.perfectDay) {
      _celebrate(DayCardLine.perfectDay);
    } else if (_somethingWasDone(old) && !_justPartied) {
      _moves.hop();
      if (_mayPraise) _sayPraise();
    }
  }

  /// Whether praise may speak now: nothing said for the talking limit.
  bool get _mayPraise {
    final last = _lastSpokeAt;
    return last == null ||
        !_now.isBefore(last.add(PetSettings.current.praiseEvery));
  }

  void _sayPraise() {
    final line = _praise(S.of(context));
    _lastPraise = line;
    _lastPraiseAt = _now;
    _lastSpokeAt = _now;
    _say(line);
  }

  /// The praise said a moment ago, for a big moment landing on the same tap
  /// after it: a «جزئي» that crosses the streak point is painted, and
  /// praised, before the streak is counted. The celebration keeps that line
  /// under its own rather than saying a second one, so the sprout never
  /// seems to change its mind.
  String? get _praiseJustSaid {
    final at = _lastPraiseAt;
    if (at == null || _now.difference(at) >= _oneMoment) return null;
    return _lastPraise;
  }

  /// Whether the rise came from something DONE. A راحة, or a quota resting
  /// on its day, takes a habit out of the day: the ring rises with nothing
  /// done, and praising that would be exactly the mistake the sprout must
  /// never make. So: a square more is green, or the ring rose on the same
  /// day (a جزئي, a count, steps), never a ring that rose because the day
  /// asked for less.
  bool _somethingWasDone(DayCardSprout old) =>
      widget.greens > old.greens ||
      (widget.owed >= old.owed && widget.ratio > old.ratio + 1e-6);

  bool get _justPartied {
    final last = _lastParty;
    return last != null && _now.difference(last) < _oneMoment;
  }

  /// A big moment: it always speaks, whatever the talking limit, and the
  /// limit counts again from it.
  void _celebrate(DayCardLine line) {
    if (!_justPartied) {
      _lastParty = _now;
      _moves.celebrate();
      _lastSpokeAt = _now;
      _say(_lineText(line));
      return;
    }
    // The second half of one moment: the bigger line, no second jump.
    if (line == DayCardLine.perfectDay) {
      _lastSpokeAt = _now;
      _say(_lineText(line));
    }
  }

  DayCardMood _mood() => dayCardMoodFor(
        greens: widget.greens,
        owed: widget.owed,
        perfectDay: widget.perfectDay,
        hour: widget.clock().hour,
      );

  /// Praise for what was just done, in the reader's own form (or in words
  /// that fit anyone, when the app cannot tell): the habit's
  /// own group when its square turned green on the board a moment ago
  /// ([sproutDoneProvider]), the general lines otherwise, and never a line
  /// said lately (see PraisePicker). Read here, at the moment of speaking,
  /// rather than watched on every build: the card builds many times a day and
  /// speaks a handful.
  String _praise(S s) {
    var group = PraiseGroup.general;
    final done = ref.read(sproutDoneProvider);
    if (done != null && DateTime.now().difference(done.at) < _doneFreshFor) {
      try {
        final habit =
            ref.read(allHabitsEverProvider).where((h) => h.id == done.habitId);
        if (habit.isNotEmpty) group = praiseGroupFor(habit.first);
      } catch (_) {}
    }
    return pickPraise(
      s,
      ref.read(sproutPraisePickerProvider),
      group,
      form: _form(),
    );
  }

  /// How to address the reader, read at the moment of speaking; unknown on
  /// any doubt (see sproutAddressProvider).
  PraiseForm _form() {
    try {
      return ref.read(sproutAddressProvider);
    } catch (_) {
      return PraiseForm.unknown;
    }
  }

  String _lineText(DayCardLine line) {
    final s = S.of(context);
    return switch (line) {
      DayCardLine.morning => s.sproutMorning,
      DayCardLine.hello => s.sproutHello,
      DayCardLine.firstDone => s.sproutFirstDone,
      DayCardLine.progress => switch (_form()) {
          PraiseForm.man => s.sproutProgress(widget.greens, widget.owed),
          PraiseForm.woman => s.sproutProgressF(widget.greens, widget.owed),
          PraiseForm.unknown =>
            s.sproutProgressWe(widget.greens, widget.owed),
        },
      // The two big moments say what happened, then the words under it: the
      // streak point takes praise in turn, the perfect day always «ما شاء
      // الله تبارك الله» (Aziz, 2026-09-28), and a perfect day is always
      // told it is one.
      DayCardLine.streakPoint =>
        '${s.sproutStreakPoint}\n${_praiseJustSaid ?? _praise(s)}',
      DayCardLine.perfectDay =>
        '${s.sproutPerfectDay}\n${s.sproutPerfectDayBlessing}',
      DayCardLine.goodNight => s.sproutGoodNight,
      DayCardLine.lateNight => s.sproutLateNight,
      DayCardLine.restDay => s.sproutRestDay,
    };
  }

  void _say(String text) {
    _bubbleTimer?.cancel();
    setState(() => _bubble = text);
    widget.onBubble?.call(text);
    _bubbleTimer = Timer(PetSettings.current.bubbleFor, () {
      if (!mounted) return;
      setState(() => _bubble = null);
      widget.onBubble?.call(null);
    });
  }

  void _tickle() {
    HapticFeedback.lightImpact();
    _laughTimer?.cancel();
    setState(() => _laughing = true);
    _moves.hop();
    _say(pickTickle(S.of(context)));
    _laughTimer = Timer(_laughFor, () {
      if (mounted) setState(() => _laughing = false);
    });
  }

  @override
  void dispose() {
    _bubbleTimer?.cancel();
    _laughTimer?.cancel();
    widget.echo?.detach(this);
    _ownMoves.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The streak point, one bump per moment (see sproutStreakPointProvider).
    ref.listen<int>(sproutStreakPointProvider, (prev, next) {
      if (next != prev) _celebrate(DayCardLine.streakPoint);
    });

    final s = S.of(context);
    final mood = _mood();
    final pose = _laughing ? SproutPose.laugh : mood.pose;
    widget.echo?.report(pose, mood: mood.pose);
    final box = Sprout.sizeOf(SproutPose.frontWave, widget.height);
    final reduced = prefersReducedMotion(context);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Sprout(
          pose: pose,
          height: widget.height,
          controller: widget.bodyAway ? null : _moves,
          onTap: _tickle,
          semanticLabel: s.sproutName,
        ),
        // The bubble's tail corner (bottom-end) sits just above the sprout's
        // head, and the bubble grows toward the start, over the card.
        if (widget.drawsBubble)
          PositionedDirectional(
            end: box.width * 0.5,
            bottom: box.height * 0.9,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  reverseDuration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: reduced
                        ? child
                        : ScaleTransition(
                            alignment: AlignmentDirectional.bottomEnd
                                .resolve(Directionality.of(context)),
                            scale: Tween(begin: 0.8, end: 1.0).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutBack,
                              ),
                            ),
                            child: child,
                          ),
                  ),
                  child: _bubble == null
                      ? const SizedBox.shrink(key: ValueKey('none'))
                      : SproutBubble(key: ValueKey(_bubble), text: _bubble!),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
