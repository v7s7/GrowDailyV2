import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/onboarding_provider.dart';
import '../../../core/theme/game_theme.dart';

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
    //  - Rooms: the reason to come back, and the one pillar the Get Started
    //    checklist never mentions.
    // Habits and Tasks are both taught at the moment of action instead, by
    // that checklist — which is the more effective place for them anyway;
    // see GetStartedChecklistCard's doc comment on why a tour gets skimmed
    // and a first real action does not.
    final pages = [
      _OnboardingPage(
        visual: const _MockWeekRow(),
        title: s.onboardingGridTitle,
        body: s.onboardingGridBody,
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
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 150,
                          child: Center(child: page.visual),
                        )
                            .animate(key: ValueKey('visual-$i'))
                            .fadeIn(duration: 400.ms)
                            .scale(
                              begin: const Offset(0.85, 0.85),
                              end: const Offset(1, 1),
                              curve: Curves.easeOutBack,
                              duration: 450.ms,
                            ),
                        const SizedBox(height: 26),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
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
                            fontSize: 14,
                            height: 1.5,
                            color: gp.textSec,
                          ),
                        )
                            .animate(key: ValueKey('body-$i'), delay: 180.ms)
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),
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
                  foregroundColor: Colors.black,
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

/// Slide 2: a three-row leaderboard — crowned leader, streak flames — the
/// Rooms pitch without a word of text.
class _MockLeaderboard extends StatelessWidget {
  const _MockLeaderboard();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    Widget row({required int rank, required bool crowned, required double w}) {
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
            Container(
              width: w,
              height: 8,
              decoration: BoxDecoration(
                color: gp.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Spacer(),
            Icon(Icons.local_fire_department_rounded,
                size: 14, color: GameColors.iconStreak),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row(rank: 1, crowned: true, w: 92),
        row(rank: 2, crowned: false, w: 70),
        row(rank: 3, crowned: false, w: 80),
      ],
    );
  }
}
