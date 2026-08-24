import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_guide_provider.dart';
import 'guide_steps_provider.dart';

/// What happens the instant a guide step is actually completed.
///
/// ── The problem this fixes ────────────────────────────────────────────────
///
/// Every host screen used to clear the lesson the moment its goal was met and
/// chain nothing. So somebody who answered «ورّيني أول خطوة» added a habit,
/// watched the circle vanish, and the guide was silently over. Reaching step
/// two meant noticing the Get Started card again and tapping it again. Four
/// times, with nothing anywhere saying the guide had more in it.
///
/// ── Why this is not the auto-tour that was deleted ───────────────────────
///
/// This app removed an `autoShowAppGuideProvider` that pushed the guide over
/// the Grid uninvited, and the rule that replaced it is: nothing dims the
/// screen that a tap in the same gesture did not ask for. THE PROPERTY THAT
/// KEEPS THAT TRUE HERE, and it is worth stating exactly, is:
///
///   this function can only ever CONTINUE a run, never start one.
///
/// It reads [activeAppGuideLessonProvider] and returns immediately when it is
/// null. That provider is memory only, is never persisted and is never seeded
/// at boot, so there is no state a cold start can restore that would make this
/// produce a dim. The only thing that can put a lesson in it is a tap:
/// Settings, the Get Started card, or the first-run question. A person who
/// never tapped any of those completes steps in total silence, exactly as
/// before. Defended by guide_chain_test.dart.
///
/// ── Why it only ever hands off once ──────────────────────────────────────
///
/// It advances only when the next step lives on the SAME tab. In practice
/// that is one handoff, addHabit into colorSquare, and it is the one that
/// matters: you add a habit and the square you just created is immediately
/// circled, which is the whole loop the app is named after.
///
/// When the next step lives elsewhere the chain stops. Jumping somebody to
/// another tab because they finished something is the uninvited tour wearing
/// a different hat, and it is not needed: the Get Started card renders on BOTH
/// the Grid and the Tasks screen (grid_screen.dart:676,
/// matrix_screen.dart:491), so the next step is already sitting there,
/// one tap away, on whichever of the two they are looking at.
void advanceGuideAfter(WidgetRef ref, AppGuideLesson completed) {
  // Not a run: this person never asked for the guide. Say nothing.
  if (ref.read(activeAppGuideLessonProvider) != completed) return;

  final next = guideStepAfter(ref.read(guideStepsProvider), completed);
  if (next == null || guideLessonTab(next) != guideLessonTab(completed)) {
    ref.read(activeAppGuideLessonProvider.notifier).state = null;
    return;
  }

  // Same tab, so the next target is already on screen. Handing over on the
  // next frame rather than in this one lets the completing action finish
  // first: the habit row has to exist before its square can be circled.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Re-check rather than assume. Between the two frames the person may have
    // pressed تخطّي, or navigated away, and either means the run is over.
    if (ref.read(activeAppGuideLessonProvider) != completed) return;
    ref.read(activeAppGuideLessonProvider.notifier).state = next;
  });
}
