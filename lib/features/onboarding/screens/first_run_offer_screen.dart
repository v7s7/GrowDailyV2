import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/first_run_offer_provider.dart';
import '../../../core/providers/home_tab_provider.dart';
import '../../../core/theme/game_theme.dart';
import '../../habits/notifiers/custom_habits_notifier.dart' show habitListProvider;
import '../notifiers/guide_steps_provider.dart';
import 'app_guide_screen.dart' show startGuideLesson;

/// The one screen that asks, instead of deciding: "want to see how it works
/// first?", with two real answers.
///
/// ── Why this exists at all, given the history ──────────────────────────────
///
/// This app has removed first-run teaching twice, deliberately, and both notes
/// are still in the tree. [app_guide_provider.dart] records deleting an
/// `autoShowAppGuideProvider` that pushed the guide over the Grid uninvited.
/// [OnboardingScreen] records cutting two of four slides because "three
/// teaching layers stacked in front of a person who had not yet done a single
/// thing is what made the app feel complicated to start."
///
/// Neither note says teaching is bad. Both say the same narrower thing: do not
/// put teaching in front of someone who did not ask for it, and do not say the
/// same words twice. This screen is the opposite shape of both. It teaches
/// nothing, it says nothing the Grid will repeat, and it cannot proceed until
/// a person chooses. Saying «بعدين» leaves the Grid byte for byte as it ships.
///
/// ── Why it is not a third onboarding slide ─────────────────────────────────
///
/// That was the cheaper option and it was genuinely close: no new gate, no new
/// Hive key, and onboarding_seen_v1 would have gated it for free. It loses on
/// two counts. OnboardingScreen's chrome is built around one primary button
/// and a corner Skip ([OnboardingScreen] builds both off `isLast`), and a
/// question needs two equal-weight answers and no corner escape, because a
/// corner escape is what turns a question into an ad you flick past without
/// reading. And that screen's own doc comment scopes it to "what is this, and
/// why would I come back", explicitly NOT "how do I use it". A question about
/// teaching is the second thing, and putting it inside the first would blur a
/// boundary that screen draws on purpose.
///
/// ── What each answer does ──────────────────────────────────────────────────
///
/// «ورّيني أول خطوة» arms the app's REAL coach mark on the REAL add-habit
/// button through the same [startGuideLesson] entry point Settings and the Get
/// Started card already use, so the person lands on the Grid with one thing
/// lit and everything else dimmed. That is the whole of "show me": no
/// bespoke overlay, no preview, no second dim pointing at the card that
/// launches the first. The alternative considered and rejected was
/// spotlighting the Get Started card itself, which would have been a coach
/// mark pointing at a coach-mark launcher and would have re-created, almost
/// exactly, the first-run spotlight this app already deleted for duplicating
/// that card's own wording.
///
/// «بعدين» writes nothing but the fact of having been asked. The answer itself
/// lives in memory for the rest of the launch (see [firstRunAnswerProvider]),
/// which is what guarantees that no cold start can ever produce a dim.
class FirstRunOfferScreen extends ConsumerStatefulWidget {
  const FirstRunOfferScreen({super.key});

  @override
  ConsumerState<FirstRunOfferScreen> createState() =>
      _FirstRunOfferScreenState();
}

class _FirstRunOfferScreenState extends ConsumerState<FirstRunOfferScreen> {
  // Latch, so a double tap cannot answer twice. Both handlers write state and
  // the second write would land after the gate has already rebuilt.
  bool _answered = false;

  Future<void> _yes() async {
    if (_answered) return;
    _answered = true;
    HapticFeedback.lightImpact();

    // Arm BEFORE flipping the gate: activeAppGuideLessonProvider is plain
    // state that GridScreen reads in build, so setting it first means the
    // Grid's very first frame already has the coach mark, with no flash of
    // an un-dimmed Grid in between.
    //
    // Guarded on nextGuideStepProvider rather than assumed: a reinstall into
    // an account that Firestore is about to restore may already have habits,
    // and circling "add a habit" for somebody who has eleven would be the app
    // arguing with what it can plainly see. If the guide is already finished
    // there is nothing to point at, and this becomes a plain "later".
    final next = ref.read(nextGuideStepProvider);
    if (next != null) {
      startGuideLesson(
        context,
        ref,
        next.lesson,
        habitsEmpty: ref.read(habitListProvider).isEmpty,
        // Nothing to pop. This is a branch of main.dart's AnimatedSwitcher,
        // not a pushed route.
        popFirst: false,
      );
      // startGuideLesson also asks for a tab, and HomeShell consumes that
      // request with ref.listen, which only fires on a CHANGE while it is
      // already listening. HomeShell does not exist yet at this point: it is
      // the thing this screen is about to be replaced BY. So the request just
      // sat there unread, and the next code to ask for tab 0 (the guide card's
      // own row for a Grid lesson) set it to the value it already held, which
      // is not a change, so that jump did nothing.
      //
      // Clearing it is the whole fix, and nothing is lost: the tab this
      // screen hands over to is 0, which is where HomeShell opens anyway.
      ref.read(requestedHomeTabProvider.notifier).state = null;
      ref.read(requestedHomeTabInstantProvider.notifier).state = false;
    }
    await answerFirstRunOffer(ref, FirstRunAnswer.yes);
  }

  Future<void> _later() async {
    if (_answered) return;
    _answered = true;
    HapticFeedback.selectionClick();
    await answerFirstRunOffer(ref, FirstRunAnswer.later);
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final isAr = s.isAr;

    return Scaffold(
      backgroundColor: gp.bg,
      body: SafeArea(
        child: Padding(
          // Matches OnboardingScreen's page padding, so the screen the person
          // just left and this one share a text column.
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              // 5 above, 4 below. This screen carries no art, so the text
              // block is the only object on it: sitting it at a third of the
              // way down (the ratio the onboarding slides use, where a 250pt
              // illustration fills the space above) left a third of the screen
              // empty above AND a third empty between the body and the
              // buttons. Slightly past the optical centre reads as composed
              // rather than stranded.
              const Spacer(flex: 5),
              const _StepRail()
                  .animate(delay: 120.ms)
                  .fadeIn(duration: 400.ms),
              const SizedBox(height: 34),
              Text(
                s.firstRunOfferTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                  color: gp.textPrimary,
                  // Onboarding hardcodes -0.3 for both languages. At 26pt
                  // negative tracking pulls Arabic glyphs into their
                  // neighbours' joins, so it is zeroed here.
                  letterSpacing: isAr ? 0 : -0.3,
                ),
              )
                  .animate(delay: 200.ms)
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),
              const SizedBox(height: 14),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: s.firstRunOfferBodyLead),
                  const TextSpan(text: ' '),
                  // The emphasis is weight only. No colour flare, no pill, no
                  // underline: this is the "don't miss it" line, and dressing
                  // it up is what would turn an invitation into a warning.
                  TextSpan(
                    text: s.firstRunOfferBodyEmphasis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: gp.textPrimary,
                    ),
                  ),
                ]),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                  color: gp.textSec,
                ),
              )
                  .animate(delay: 280.ms)
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),
              const Spacer(flex: 4),
              // Wrapped once so the pair travels together rather than as two
              // separate arrivals under a decision.
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        backgroundColor: GameColors.gold,
                        // onGold, not Colors.black: some presets ship a gold
                        // that black text fails contrast on, which is exactly
                        // why that token exists.
                        foregroundColor: GameColors.onGold,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(GameSpacing.cardRadius),
                        ),
                      ),
                      onPressed: _yes,
                      child: Text(
                        s.firstRunOfferYes,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Stacked, not side by side. Side by side implies parity,
                    // and under RTL it makes which button the eye meets first
                    // a coin flip. textSec and not textTert: tert is the tone
                    // onboarding's Skip uses, and an honest exit should not
                    // look disabled.
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: _later,
                      child: Text(
                        s.firstRunOfferLater,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: gp.textSec,
                        ),
                      ),
                    ),
                  ],
                ),
              )
                  .animate(delay: 380.ms)
                  .fadeIn(duration: 300.ms)
                  .slideY(begin: 0.20, end: 0, curve: Curves.easeOutCubic),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four segments, the first one filling.
///
/// It rhymes with the progress bar on the Get Started card this screen is
/// about to hand the person over to (same 4pt-ish gold on gp.surfaceHL, same
/// radius 3), so the shape is already familiar when the card appears. It
/// deliberately does NOT rhyme with onboarding's week-of-squares mock: a row
/// of squares filling in would read as onboarding slide 3, and the one thing
/// this screen must not be is the tour continuing.
class _StepRail extends StatelessWidget {
  const _StepRail();

  static const double _segW = 44;
  static const double _segH = 6;

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              width: _segW,
              height: _segH,
              child: ColoredBox(
                color: gp.surfaceHL,
                child: i != 0
                    ? null
                    // widthFactor, not width: the rail's total width never
                    // changes as it fills, so nothing on the screen shifts.
                    // AlignmentDirectional.centerStart makes it fill from the
                    // reading edge in both languages, and the plain Row above
                    // mirrors from ambient Directionality, so segment one
                    // lands on the right in Arabic for free.
                    : const _FillingSegment(width: _segW, height: _segH),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FillingSegment extends StatelessWidget {
  final double width;
  final double height;
  const _FillingSegment({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    // ScaleEffect's alignment is a physical Alignment, not a directional one,
    // so the reading edge has to be resolved here by hand. Getting this wrong
    // is invisible in English and backwards in Arabic, which is the whole
    // class of bug this app keeps finding in painted and transformed widgets:
    // the surrounding Row mirrors from ambient Directionality, the transform
    // inside it does not.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return ColoredBox(
      color: GameColors.gold,
      child: SizedBox(width: width, height: height),
    )
        .animate(delay: 260.ms)
        .scaleX(
          begin: 0,
          end: 1,
          alignment: rtl ? Alignment.centerRight : Alignment.centerLeft,
          curve: Curves.easeOutCubic,
          duration: 420.ms,
        );
  }
}
