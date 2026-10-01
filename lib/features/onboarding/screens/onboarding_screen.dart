import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/onboarding_provider.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/utils/reduced_motion.dart';
import '../../mascot/sprout.dart';
import '../../matrix/models/matrix_task.dart';

/// One slide's content: a small hand-built mock of the real UI element it
/// introduces (language-neutral — icons and shapes only, so EN/AR need no
/// separate art) plus a benefit-first title/body.
class _OnboardingPage {
  final Widget visual;
  final String title;
  final String body;
  const _OnboardingPage({
    required this.visual,
    required this.title,
    required this.body,
  });
}

/// Shown once per device, right after language + auth/guest are settled
/// (see `_AuthGate` in main.dart) and before the very first Grid screen —
/// two short pages, each with a mock of the real UI, so nobody lands cold on
/// a grid of empty squares with no context. Skippable at any point.
///
/// Its whole job is "what is this, and why would I come back" — deliberately
/// NOT "how do I use it". The how is taught one step at a time by the Grid's
/// Get Started checklist, at the moment each step is actually being taken.
/// See the note above [pages] in build() for why this stopped being four
/// slides, and main.dart for why finishing no longer throws the App Guide on
/// top of the Grid as well.
///
/// Finishing (or skipping) marks [onboardingSeenProvider] true, which is what
/// actually reveals the Grid. This screen never navigates anywhere itself;
/// _OnboardingOrGrid in main.dart owns that.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Shared by the last page's "Get Started" button and the Skip button —
  // both mean "onboarding is over" for this device.
  //
  // This used to also queue a one-time auto-open of the App Guide screen,
  // which landed on top of the Grid moments after the person got there. It
  // no longer does: the Grid's own Get Started checklist is the single
  // first-run teacher now, and the guide waits in Settings for whoever wants
  // it. See the note where main.dart used to consume that flag.
  void _finish() {
    markOnboardingSeen(ref);
  }

  void _next(int pageCount) {
    HapticFeedback.selectionClick();
    if (_page == pageCount - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: GameMotion.slow,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    // Two slides, not four. This used to walk through Grid, Habits, Tasks
    // and Rooms before anyone had touched anything — and then the Grid
    // repeated the same ground twice more (a dimming spotlight and the Get
    // Started checklist, which said the same words as each other). Three
    // teaching layers stacked in front of a person who had not yet done a
    // single thing is what made the app feel complicated to start.
    //
    // What survives is the part a checklist cannot do: say what this app IS,
    // and why it is worth coming back to.
    //  - Grid: the whole idea in one picture. Its body already covers habits
    //    ("Every habit you finish colors a square"), so the separate Habits
    //    slide was restating it.
    //  - Tasks: the second pillar, and nothing else in first run shows it.
    //  - Rooms: the reason to come back.
    //
    // Three slides, not two, and this is not a walk back to the four that
    // were cut. The problem with four was REPETITION, not coverage: the
    // Habits slide restated the Grid slide almost word for word, and an
    // Achievements slide restated the gold and XP the Habits slide had
    // already mentioned. What is here now is three pillars, three pictures,
    // no sentence said twice. Leaving Tasks out entirely meant a person could
    // finish onboarding without ever learning the app has a second half: the
    // guide's third step («أضف مهمة») names it, but by then they have already
    // formed a picture of what this app is, and half of it is missing from
    // that picture.
    final pages = [
      _OnboardingPage(
        visual: const _MockWeekRow(),
        title: s.onboardingGridTitle,
        body: s.onboardingGridBody,
      ),
      _OnboardingPage(
        visual: const _MockMatrix(),
        title: s.onboardingTasksTitle,
        body: s.onboardingTasksBody,
      ),
      _OnboardingPage(
        visual: const _MockLeaderboard(),
        title: s.onboardingRoomsTitle,
        body: s.onboardingRoomsBody,
      ),
    ];
    final isLast = _page == pages.length - 1;

    return Scaffold(
      backgroundColor: gp.bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                child: Opacity(
                  opacity: isLast ? 0 : 1,
                  child: TextButton(
                    onPressed: isLast ? null : _finish,
                    child: Text(s.onboardingSkip,
                        style: TextStyle(color: gp.textTert, fontSize: 13)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final page = pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      children: [
                        // Composed rather than centred. The whole block used
                        // to be MainAxisAlignment.center around a 150pt
                        // visual, which left roughly 600pt of empty screen
                        // above it and read as unfinished rather than
                        // spacious. The art now takes real space and the
                        // block sits above centre, which is where the eye
                        // expects a title to be.
                        const Spacer(flex: 2),
                        SizedBox(
                          height: 250,
                          // The art is built from fixed-size widgets, so the
                          // taller box alone would not enlarge it.
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: page.visual,
                          ),
                        )
                            .animate(key: ValueKey('visual-$i'))
                            .fadeIn(duration: 400.ms)
                            .scale(
                              begin: const Offset(0.85, 0.85),
                              end: const Offset(1, 1),
                              curve: Curves.easeOutBack,
                              duration: 450.ms,
                            ),
                        const SizedBox(height: 38),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            color: gp.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        )
                            .animate(key: ValueKey('title-$i'), delay: 100.ms)
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),
                        const SizedBox(height: 12),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.55,
                            color: gp.textSec,
                          ),
                        )
                            .animate(key: ValueKey('body-$i'), delay: 180.ms)
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),
                        const Spacer(flex: 3),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                pages.length,
                (i) => AnimatedContainer(
                  duration: GameMotion.relaxed,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? GameColors.gold : gp.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: GameColors.gold,
                  // onGold, not Colors.black. That token exists precisely
                  // because some theme presets ship a gold that black text
                  // fails contrast on, and this is the most pressed button in
                  // the app's first thirty seconds.
                  foregroundColor: GameColors.onGold,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(GameSpacing.cardRadius)),
                ),
                onPressed: () => _next(pages.length),
                child: Text(
                  isLast ? s.onboardingGetStarted : s.onboardingNext,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Slide visuals ───────────────────────────────────────────────────────────
//
// Small hand-built mocks of the real UI, not screenshots: they inherit the
// live theme (light/dark, preset colors) automatically and contain no text
// but the Tasks boxes' real names, so one visual serves both languages and
// never goes stale against a redesigned screen the way a baked-in PNG would.
//
// Doum stands on each one and acts its idea out (Aziz, 2026-10-01, the
// canvas "Doum picks the language"): he fills the week's squares with his
// pencil, stamps a task into «الآن», and claps for the room. He stands on
// the picture's top edge, never over what it shows, and moves once (a hop)
// then rests. Reduce Motion shows each picture finished, with him still.

/// Doum on a slide's picture: his feet at [feetX] along its top edge (from
/// the left, already resolved for the reading direction), [feetY] above its
/// bottom. Hops once, [hopAfter] after he is built; nothing under Reduce
/// Motion.
class _SlideDoum extends StatefulWidget {
  const _SlideDoum({
    required this.pose,
    required this.height,
    required this.feetCentre,
    required this.hopAfter,
  });

  final SproutPose pose;
  final double height;

  /// Where his feet are across the picture (0 to 1 from its left).
  final double feetCentre;
  final Duration hopAfter;

  @override
  State<_SlideDoum> createState() => _SlideDoumState();
}

class _SlideDoumState extends State<_SlideDoum> {
  final _moves = SproutController();
  Timer? _hop;

  @override
  void initState() {
    super.initState();
    _hop = Timer(widget.hopAfter, _moves.hop);
  }

  @override
  void dispose() {
    _hop?.cancel();
    _moves.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Sprout(
        pose: widget.pose,
        height: widget.height,
        controller: _moves,
        // The slide's picture arrives with its own scale-in; a pop on top
        // of it would move him twice.
        entrance: SproutEntrance.none,
        idleBreaths: 1,
      );
}

/// Places [doum] so his feet land at [feetX] (from the left) on a line
/// [feetY] above the bottom of a [width] wide picture.
Widget _standing({
  required double width,
  required double feetX,
  required double feetY,
  required _SlideDoum doum,
}) {
  final size = Sprout.sizeOf(doum.pose, doum.height);
  // The files keep a few transparent pixels under his feet (about 14 of
  // 770), so he is lowered by as much to stand ON the edge.
  final under = size.height * 14 / 770;
  return Positioned(
    left: feetX - doum.feetCentre * size.width,
    bottom: feetY - under,
    width: size.width,
    height: size.height,
    child: IgnorePointer(child: doum),
  );
}

/// Slide 1: a week of Grid squares filling one by one, today's ringed, the
/// rest waiting; Doum stands on today's square with his pencil and hops
/// once the four before it are done. The core loop at a glance.
class _MockWeekRow extends StatefulWidget {
  const _MockWeekRow();

  @override
  State<_MockWeekRow> createState() => _MockWeekRowState();
}

class _MockWeekRowState extends State<_MockWeekRow> {
  static const _done = 4;
  int _filled = 0;
  final List<Timer> _timers = [];
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (prefersReducedMotion(context)) {
      _filled = _done;
      return;
    }
    for (var i = 0; i < _done; i++) {
      _timers.add(
        Timer(Duration(milliseconds: 350 + 180 * i), () {
          if (mounted) setState(() => _filled = i + 1);
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    const width = 280.0, square = 34.0, step = 40.0;
    const doumHeight = 110.0;
    final doumBox = Sprout.sizeOf(SproutPose.pencil, doumHeight);
    // Today's square (the fifth), from the start edge.
    const today = 3 + 4 * step + square / 2;
    return SizedBox(
      width: width,
      height: square + doumBox.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 7; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOut,
                      width: square,
                      height: square,
                      decoration: BoxDecoration(
                        color: i < _filled
                            ? GameColors.emerald
                                .withOpacity(gp.dark ? 0.55 : 0.75)
                            : gp.surface,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: i == _done
                              ? GameColors.gold
                              : i < _filled
                                  ? GameColors.emerald.withOpacity(0)
                                  : gp.border,
                          width: i == _done ? 1.6 : 0.5,
                        ),
                      ),
                      child: AnimatedScale(
                        scale: i < _filled ? 1 : 0.4,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutBack,
                        child: AnimatedOpacity(
                          opacity: i < _filled ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(Icons.check_rounded,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _standing(
            width: width,
            feetX: rtl ? width - today : today,
            feetY: square,
            doum: const _SlideDoum(
              pose: SproutPose.pencil,
              height: doumHeight,
              feetCentre: .436,
              hopAfter: Duration(milliseconds: 1250),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide 2: the four boxes, with their real names and their real colours,
/// and Doum on the box «الآن» stamping a task into it: he hops, and on his
/// landing a check lands in the box.
///
/// Labels come from [MatrixQuadrant.localLabel] rather than being written out
/// here, so the picture can never teach a word the Tasks screen does not use.
/// Same for the colours: [MatrixQuadrant.defaultColor] is what an untouched
/// account actually sees, and a person who later recolours a quadrant is long
/// past onboarding.
///
/// One card is drawn as filled and the other three as outlines. A person meets
/// this picture for two seconds, and four equally weighted boxes read as a
/// colour swatch; one filled box reads as "this is where today's thing goes",
/// which is the actual idea.
class _MockMatrix extends StatefulWidget {
  const _MockMatrix();

  @override
  State<_MockMatrix> createState() => _MockMatrixState();
}

class _MockMatrixState extends State<_MockMatrix> {
  static const _hopAt = Duration(milliseconds: 900);
  bool _stamped = false;
  Timer? _stamp;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (prefersReducedMotion(context)) {
      _stamped = true;
      return;
    }
    // His hop lands about three quarters through it (sprout.dart's keys).
    _stamp = Timer(
      _hopAt + Sprout.hopDuration * .74,
      () {
        if (mounted) setState(() => _stamped = true);
      },
    );
  }

  @override
  void dispose() {
    _stamp?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final isAr = S.of(context).isAr;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    Widget cell(MatrixQuadrant q, {required bool filled}) {
      final c = q.defaultColor;
      return Container(
        width: 116,
        height: 62,
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: filled ? c.withOpacity(gp.dark ? 0.22 : 0.14) : gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          border: Border.all(
            color: filled ? c.withOpacity(0.55) : gp.border,
            width: filled ? 1.2 : 0.5,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  q.localLabel(isAr),
                  // Every label carries its OWN quadrant colour, filled or
                  // not. Tinting only the filled one made the other three
                  // read as disabled, which is the opposite of true: all four
                  // are places a task can go, and the app colour-codes them
                  // everywhere else. The hierarchy is carried by the fill and
                  // the border instead.
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: filled ? FontWeight.w800 : FontWeight.w700,
                    color: c,
                  ),
                ),
                // A short bar rather than fake task text: a line of lorem in
                // a 116pt box is unreadable at slide scale and reads as a
                // loading skeleton, which is the exact mistake the
                // leaderboard mock below was changed to stop making.
                Container(
                  width: filled ? 58 : 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: c.withOpacity(filled ? 0.55 : 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
            // The task Doum stamped in: a check, at the box's end.
            if (filled)
              PositionedDirectional(
                end: 0,
                top: 8,
                child: AnimatedScale(
                  scale: _stamped ? 1 : 0.3,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutBack,
                  child: AnimatedOpacity(
                    opacity: _stamped ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: GameColors.emerald,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          size: 15, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    const width = 248.0, grid = 140.0;
    const doumHeight = 112.0;
    final doumBox = Sprout.sizeOf(SproutPose.stampCheck, doumHeight);
    // «الآن» is the first box: the start column's middle.
    const now = 62.0;
    return SizedBox(
      width: width,
      height: grid + doumBox.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cell(MatrixQuadrant.doFirst, filled: true),
                    cell(MatrixQuadrant.schedule, filled: false),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cell(MatrixQuadrant.delegate, filled: false),
                    cell(MatrixQuadrant.eliminate, filled: false),
                  ],
                ),
              ],
            ),
          ),
          _standing(
            width: width,
            feetX: rtl ? width - now : now,
            // On the box's top edge, inside the grid's 4pt margin.
            feetY: grid - 4,
            doum: const _SlideDoum(
              pose: SproutPose.stampCheck,
              height: doumHeight,
              feetCentre: .423,
              hopAfter: _hopAt,
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide 3: a three-row leaderboard with streak flames, and Doum on the top
/// row clapping for it: the Rooms pitch without a word of text. The first
/// place shows its number, not a cup: no medals or crowns beside Doum
/// (design/mascot/POSES.md, rule 5).
class _MockLeaderboard extends StatelessWidget {
  const _MockLeaderboard();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // Names, not grey bars. This is the ONLY picture a brand-new user gets of
    // what a Room is, and three anonymous grey rectangles do not say "you and
    // your people on a leaderboard" — they say "loading". The names are
    // deliberately ordinary first names rather than the user's own, since we
    // do not have one yet at this point in onboarding.
    final names = S.of(context).isAr
        ? const ['عبد العزيز', 'سعود', 'خالد']
        : const ['Abdulaziz', 'Saud', 'Khalid'];
    final streaks = const [12, 9, 7];

    Widget row({required int rank, required bool leading}) {
      return Container(
        width: 250,
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          border: Border.all(
            color: leading ? GameColors.gold.withOpacity(0.5) : gp.border,
            width: leading ? 1 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: leading
                    ? GameColors.gold.withOpacity(0.16)
                    : gp.border.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: leading ? context.gp.goldInk : gp.textSec,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              names[rank - 1],
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: leading ? FontWeight.w800 : FontWeight.w600,
                color: gp.textPrimary,
              ),
            ),
            const Spacer(),
            Icon(Icons.local_fire_department_rounded,
                size: 14, color: context.gp.iconStreak),
            const SizedBox(width: 4),
            Text(
              '${streaks[rank - 1]}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: context.gp.iconStreak,
              ),
            ),
          ],
        ),
      );
    }

    // Three rows of 42 with 3 above and below each.
    const width = 250.0, board = 144.0;
    const doumHeight = 100.0;
    final doumBox = Sprout.sizeOf(SproutPose.clap, doumHeight);
    // Over the top row's flame and number, at its end.
    const flame = 228.0;
    return SizedBox(
      width: width,
      height: board + doumBox.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                row(rank: 1, leading: true),
                row(rank: 2, leading: false),
                row(rank: 3, leading: false),
              ],
            ),
          ),
          _standing(
            width: width,
            feetX: rtl ? width - flame : flame,
            // On the top row's edge, inside its 3pt margin.
            feetY: board - 3,
            doum: const _SlideDoum(
              pose: SproutPose.clap,
              height: doumHeight,
              feetCentre: .465,
              hopAfter: Duration(milliseconds: 1100),
            ),
          ),
        ],
      ),
    );
  }
}
