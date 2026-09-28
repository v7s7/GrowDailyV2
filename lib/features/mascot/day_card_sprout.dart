import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/utils/reduced_motion.dart';
import 'sprout.dart';
import 'sprout_mood.dart';
import 'sprout_signals.dart';

/// The sprout on the Grid's day card: its home in the app.
///
/// It reacts to what the day DOES, from the same two sources the rest of the
/// screen already trusts, never from a tap of its own:
///   - the card's numbers rose (ratio, partial credit included, so a walk in
///     progress or a 2x habit at 1 of 2 counts): a hop, and where the day
///     stands. A square turned green from the board, a widget, a
///     notification action or another screen all arrive here the same way;
///   - the day just earned its streak point ([sproutStreakPointProvider],
///     bumped on the exact tap the heavy haptic, the burst and «يوم كامل!
///     يومك انحسب في سلسلتك.» fire on): the celebration, saying «يوم كامل!»
///     with them. No haptic of its own there, the board's is already on that
///     tap;
///   - every square is green, the card's own «يوم مثالي»: the celebration
///     again, «يوم مثالي!». With four habits or fewer 80% IS 100%, both
///     land on one tap, and the sprout jumps once and says the bigger thing;
///   - tapped: it laughs for a moment. The one thing on the card that exists
///     only to be fun.
///
/// It speaks in a bubble that shows for [_bubbleFor] and fades, never
/// permanently: the card's height is spoken for (see _SummaryCard), so the
/// bubble floats above the card for a moment and leaves nothing behind. It
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

  /// Whether this app launch has greeted yet. Reset between tests.
  static bool greetedThisLaunch = false;

  @override
  ConsumerState<DayCardSprout> createState() => _DayCardSproutState();
}

class _DayCardSproutState extends ConsumerState<DayCardSprout> {
  static const _bubbleFor = Duration(milliseconds: 3000);
  static const _laughFor = Duration(milliseconds: 1400);

  /// Two celebrations inside this window are one moment (the streak point
  /// and the perfect day on the same tap): the jump plays once, and the
  /// bubble takes the later, bigger line.
  static const _oneMoment = Duration(milliseconds: 1500);

  final _moves = SproutController();
  Timer? _bubbleTimer;
  Timer? _laughTimer;
  String? _bubble;
  bool _laughing = false;
  bool _precached = false;
  DateTime? _lastParty;

  @override
  void initState() {
    super.initState();
    _greetOnce();
  }

  /// The once-per-launch hello, only once the numbers are today's real ones.
  /// The card is built while the week is still loading (0 of N), so a hello
  /// timed from the first frame would say «هلا! نبدأ؟» over a day that is
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
    if (!old.live && widget.live) {
      // The week just landed: a hello if this launch has had none, and no
      // reaction to the jump from 0, which nobody did.
      _greetOnce();
      return;
    }
    if (!old.live || !widget.live) return;
    if (widget.perfectDay && !old.perfectDay) {
      _celebrate(DayCardLine.perfectDay);
    } else if (widget.ratio > old.ratio + 1e-6 && !_justPartied) {
      _moves.hop();
      _say(_lineText(_mood().line));
    }
  }

  bool get _justPartied {
    final last = _lastParty;
    return last != null && DateTime.now().difference(last) < _oneMoment;
  }

  void _celebrate(DayCardLine line) {
    if (!_justPartied) {
      _lastParty = DateTime.now();
      _moves.celebrate();
      _say(_lineText(line));
      return;
    }
    // The second half of one moment: the bigger line, no second jump.
    if (line == DayCardLine.perfectDay) _say(_lineText(line));
  }

  DayCardMood _mood() => dayCardMoodFor(
        greens: widget.greens,
        owed: widget.owed,
        perfectDay: widget.perfectDay,
        hour: widget.clock().hour,
      );

  String _lineText(DayCardLine line) {
    final s = S.of(context);
    return switch (line) {
      DayCardLine.morning => s.sproutMorning,
      DayCardLine.hello => s.sproutHello,
      DayCardLine.firstDone => s.sproutFirstDone,
      DayCardLine.progress => s.sproutProgress(widget.greens, widget.owed),
      DayCardLine.fullDay => s.sproutFullDay,
      DayCardLine.perfectDay => s.sproutPerfectDay,
      DayCardLine.goodNight => s.sproutGoodNight,
      DayCardLine.lateNight => s.sproutLateNight,
      DayCardLine.restDay => s.sproutRestDay,
    };
  }

  void _say(String text) {
    _bubbleTimer?.cancel();
    setState(() => _bubble = text);
    _bubbleTimer = Timer(_bubbleFor, () {
      if (mounted) setState(() => _bubble = null);
    });
  }

  void _tickle() {
    HapticFeedback.lightImpact();
    _laughTimer?.cancel();
    setState(() => _laughing = true);
    _moves.hop();
    _say(S.of(context).sproutTickle);
    _laughTimer = Timer(_laughFor, () {
      if (mounted) setState(() => _laughing = false);
    });
  }

  @override
  void dispose() {
    _bubbleTimer?.cancel();
    _laughTimer?.cancel();
    _moves.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The streak point, one bump per moment (see sproutStreakPointProvider).
    ref.listen<int>(sproutStreakPointProvider, (prev, next) {
      if (next != prev) _celebrate(DayCardLine.fullDay);
    });

    final s = S.of(context);
    final mood = _mood();
    final pose = _laughing ? SproutPose.laugh : mood.pose;
    final box = Sprout.sizeOf(SproutPose.frontWave, widget.height);
    final reduced = prefersReducedMotion(context);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Sprout(
          pose: pose,
          height: widget.height,
          controller: _moves,
          onTap: _tickle,
          semanticLabel: s.sproutName,
        ),
        // The bubble's tail corner (bottom-end) sits just above the sprout's
        // head, and the bubble grows toward the start, over the card.
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
