import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/onboarding_provider.dart';
import '../../../core/theme/game_theme.dart';
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
// live theme (light/dark, preset colors) automatically, need zero image
// assets, and contain no text — so one visual serves both languages and
// never goes stale against a redesigned screen the way a baked-in PNG would.

/// Slide 1: a week of Grid squares — some green-and-checked, today's ringed
/// gold, the rest waiting. The core loop at a glance.
class _MockWeekRow extends StatelessWidget {
  const _MockWeekRow();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 7; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: i < 4
                    ? GameColors.emerald.withOpacity(gp.dark ? 0.55 : 0.75)
                    : gp.surface,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: i == 4 ? GameColors.gold : gp.border,
                  width: i == 4 ? 1.6 : 0.5,
                ),
              ),
              child: i < 4
                  ? const Icon(Icons.check_rounded,
                      size: 18, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Slide 2: the four boxes, with their real names and their real colours.
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
class _MockMatrix extends StatelessWidget {
  const _MockMatrix();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final isAr = S.of(context).isAr;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              q.localLabel(isAr),
              // Every label carries its OWN quadrant colour, filled or not.
              // Tinting only the filled one made the other three read as
              // disabled, which is the opposite of true: all four are places
              // a task can go, and the app colour-codes them everywhere else.
              // The hierarchy is carried by the fill and the border instead.
              style: TextStyle(
                fontSize: 13,
                fontWeight: filled ? FontWeight.w800 : FontWeight.w700,
                color: c,
              ),
            ),
            // A short bar rather than fake task text: a line of lorem in a
            // 116pt box is unreadable at slide scale and reads as a loading
            // skeleton, which is the exact mistake the leaderboard mock above
            // was changed to stop making.
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
      );
    }

    return Column(
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
    );
  }
}

/// Slide 3: a three-row leaderboard, crowned leader and streak flames, the
/// Rooms pitch without a word of text.
class _MockLeaderboard extends StatelessWidget {
  const _MockLeaderboard();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    // Names, not grey bars. This is the ONLY picture a brand-new user gets of
    // what a Room is, and three anonymous grey rectangles do not say "you and
    // your people on a leaderboard" — they say "loading". The names are
    // deliberately ordinary first names rather than the user's own, since we
    // do not have one yet at this point in onboarding.
    final names = S.of(context).isAr
        ? const ['عبد العزيز', 'سعود', 'خالد']
        : const ['Abdulaziz', 'Saud', 'Khalid'];
    final streaks = const [12, 9, 7];

    Widget row({required int rank, required bool crowned}) {
      return Container(
        width: 250,
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: gp.surface,
          borderRadius: BorderRadius.circular(GameSpacing.buttonRadius),
          border: Border.all(
            color: crowned ? GameColors.gold.withOpacity(0.5) : gp.border,
            width: crowned ? 1 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: crowned
                    ? GameColors.gold.withOpacity(0.16)
                    : gp.border.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: crowned
                  ? Icon(Icons.emoji_events_rounded,
                      size: 13, color: GameColors.gold)
                  : Text(
                      '$rank',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: gp.textSec,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Text(
              names[rank - 1],
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: crowned ? FontWeight.w800 : FontWeight.w600,
                color: gp.textPrimary,
              ),
            ),
            const Spacer(),
            Icon(Icons.local_fire_department_rounded,
                size: 14, color: GameColors.iconStreak),
            const SizedBox(width: 4),
            Text(
              '${streaks[rank - 1]}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: GameColors.iconStreak,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row(rank: 1, crowned: true),
        row(rank: 2, crowned: false),
        row(rank: 3, crowned: false),
      ],
    );
  }
}
