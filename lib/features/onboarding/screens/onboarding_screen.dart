import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/onboarding_provider.dart';
import '../../../core/theme/game_theme.dart';

/// One slide's content: a small hand-built mock of the real UI element it
/// introduces (language-neutral — icons and shapes only, so EN/AR need no
/// separate art), a benefit-first title/body, and a "where to tap" hint
/// naming the exact button/tab the slide is talking about.
class _OnboardingPage {
  final Widget visual;
  final String title;
  final String body;
  final IconData hintIcon;
  final String hint;
  const _OnboardingPage({
    required this.visual,
    required this.title,
    required this.body,
    required this.hintIcon,
    required this.hint,
  });
}

/// Shown once per device, right after language + auth/guest are settled
/// (see `_AuthGate` in main.dart) and before the very first Grid screen —
/// five short pages walking a brand-new user through the core surfaces
/// (Grid, habits, tasks, achievements, Rooms), each with a mock of the real
/// UI and a pointer to where it lives, since they'd otherwise land cold on
/// a grid of empty squares with no context. Skippable at any point.
/// Finishing (or skipping) marks [onboardingSeenProvider] true, which is
/// what actually reveals the Grid — this screen doesn't navigate anywhere
/// itself.
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

  void _next(int pageCount) {
    HapticFeedback.selectionClick();
    if (_page == pageCount - 1) {
      markOnboardingSeen(ref);
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final pages = [
      _OnboardingPage(
        visual: const _MockWeekRow(),
        title: s.onboardingGridTitle,
        body: s.onboardingGridBody,
        hintIcon: Icons.grid_view_rounded,
        hint: s.onboardingGridHint,
      ),
      _OnboardingPage(
        visual: const _MockHabitCard(),
        title: s.onboardingHabitsTitle,
        body: s.onboardingHabitsBody,
        hintIcon: Icons.add_rounded,
        hint: s.onboardingHabitsHint,
      ),
      _OnboardingPage(
        visual: const _MockMatrix(),
        title: s.onboardingTasksTitle,
        body: s.onboardingTasksBody,
        hintIcon: Icons.view_quilt_rounded,
        hint: s.onboardingTasksHint,
      ),
      _OnboardingPage(
        visual: const _MockAchievements(),
        title: s.onboardingAchievementsTitle,
        body: s.onboardingAchievementsBody,
        hintIcon: Icons.person_rounded,
        hint: s.onboardingAchievementsHint,
      ),
      _OnboardingPage(
        visual: const _MockLeaderboard(),
        title: s.onboardingRoomsTitle,
        body: s.onboardingRoomsBody,
        hintIcon: Icons.groups_rounded,
        hint: s.onboardingRoomsHint,
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
                    onPressed: isLast ? null : () => markOnboardingSeen(ref),
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
                        const SizedBox(height: 18),
                        // "Where to tap" — the one line that turns each
                        // slide from a promise into a direction.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: GameColors.gold.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                                color: GameColors.gold.withOpacity(0.35),
                                width: 0.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.touch_app_rounded,
                                  size: 14, color: GameColors.gold),
                              const SizedBox(width: 6),
                              Icon(page.hintIcon,
                                  size: 14, color: GameColors.gold),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  page.hint,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: GameColors.gold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                            .animate(key: ValueKey('hint-$i'), delay: 260.ms)
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.2, end: 0, curve: Curves.easeOut),
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
                  duration: const Duration(milliseconds: 250),
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
                      borderRadius: BorderRadius.circular(16)),
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

/// Slide 2: a habit card in miniature — icon tile, name/subtitle bars, and
/// the emerald action pill, mirroring HabitCard's real anatomy.
class _MockHabitCard extends StatelessWidget {
  const _MockHabitCard();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: gp.border,
            borderRadius: BorderRadius.circular(h / 2),
          ),
        );
    return Container(
      width: 270,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gp.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gp.border, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: GameColors.gold.withOpacity(0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child:
                Icon(Icons.auto_stories_rounded, size: 19, color: GameColors.gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(90, 9),
                const SizedBox(height: 7),
                bar(56, 7),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: GameColors.emerald,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check_rounded,
                size: 15, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// Slide 3: the Goals Matrix's four quadrants as colored icon tiles —
/// do-first, schedule, delegate, later.
class _MockMatrix extends StatelessWidget {
  const _MockMatrix();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    Widget tile(IconData icon, Color color) => Container(
          width: 62,
          height: 52,
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withOpacity(gp.dark ? 0.16 : 0.12),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: color.withOpacity(0.4), width: 0.5),
          ),
          child: Icon(icon, size: 21, color: color),
        );
    // Colors mirror MatrixQuadrant.defaultColor exactly (doFirst=error,
    // schedule=iconXp, delegate=iconStreak, eliminate=textTertiary) so the
    // mock matches what the Tasks screen will actually look like.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tile(Icons.bolt_rounded, GameColors.error),
            tile(Icons.event_rounded, GameColors.iconXp),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tile(Icons.group_rounded, GameColors.iconStreak),
            tile(Icons.delete_outline_rounded, GameColors.textTertiary),
          ],
        ),
      ],
    );
  }
}

/// Slide 4: a trophy badge flanked by an XP chip and a gold chip — the
/// reward loop in one image.
class _MockAchievements extends StatelessWidget {
  const _MockAchievements();

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    Widget chip(IconData icon, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: gp.surface,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: color.withOpacity(0.45), width: 0.5),
          ),
          child: Icon(icon, size: 17, color: color),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        chip(Icons.bolt_rounded, GameColors.iconXp),
        const SizedBox(width: 14),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: GameColors.gold.withOpacity(0.14),
            shape: BoxShape.circle,
            border:
                Border.all(color: GameColors.gold.withOpacity(0.5), width: 1),
          ),
          child:
              Icon(Icons.emoji_events_rounded, size: 40, color: GameColors.gold),
        ),
        const SizedBox(width: 14),
        chip(Icons.local_fire_department_rounded, GameColors.iconStreak),
      ],
    );
  }
}

/// Slide 5: a three-row leaderboard — crowned leader, streak flames — the
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
          borderRadius: BorderRadius.circular(12),
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
