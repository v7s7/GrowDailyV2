import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';

// ─── First-run offer: "want to see how it works?" ───────────────────────────
//
// Asked exactly once, on the screen between the last onboarding slide and the
// Grid. It is a QUESTION with two real answers, and that word is doing all the
// work here, because this app has deleted uninvited first-run teaching twice
// and wrote down why both times.
//
// The deleted `autoShowAppGuideProvider` (see the note in app_guide_provider
// .dart) was a flag onboarding set on finish, which main.dart then consumed by
// pushing the whole App Guide over the Grid half a second after a new user got
// there. Nobody asked for it and there was no way to not get it. The rule that
// replaced it is the one this file has to keep: nothing dims the Grid that a
// tap in the same gesture did not ask for.
//
// So the split below is deliberate. What is persisted is only "has this device
// been asked", a fact about the past that must survive a restart. The ANSWER
// is memory-only in [firstRunAnswerProvider]: it exists for the length of one
// launch, is consumed by the first screen that acts on it, and can never be
// replayed by a cold start. A launch cannot produce a spotlight, because there
// is no persisted state that means "spotlight pending".

const _kFirstRunOfferAskedKey = 'first_run_offer_asked_v1';

/// Whether this device has already been asked. Defaults to **true**, which is
/// the terminal, do-nothing value.
///
/// The safe direction matters more here than it does for
/// [onboardingSeenProvider], which defaults false: if that override is ever
/// missed, the worst case is a returning user seeing the walkthrough again.
/// If THIS one defaulted to false, a missed override would put a beginner
/// question in front of the entire installed base on their next launch. So it
/// starts at "already asked" and only a positive read at boot can move it.
final firstRunOfferAskedProvider = StateProvider<bool>((ref) => true);

/// What they said, for the rest of this launch only.
enum FirstRunAnswer {
  /// "Show me the first step." The Grid arms the real add-habit coach mark.
  yes,

  /// "Later." The Grid is untouched; the Get Started card draws the eye to
  /// itself three times and then stops. See [GetStartedChecklistCard].
  later,
}

/// The answer, held in memory and consumed once by whichever surface acts on
/// it. Never persisted, never seeded at boot, deliberately: see this file's
/// header for why that is the property that keeps this feature from becoming
/// the thing that was deleted.
final firstRunAnswerProvider = StateProvider<FirstRunAnswer?>((ref) => null);

/// Records the answer: the fact of having asked goes to disk, the answer
/// itself stays in memory.
///
/// Memory first, disk second, matching [markOnboardingSeen]: the provider
/// flips on the synchronous line so the gate rebuilds immediately, and the
/// Hive write trails it.
Future<void> answerFirstRunOffer(WidgetRef ref, FirstRunAnswer answer) async {
  ref.read(firstRunAnswerProvider.notifier).state = answer;
  ref.read(firstRunOfferAskedProvider.notifier).state = true;
  final box = await LocalStoreService.settingsBox();
  await box.put(_kFirstRunOfferAskedKey, true);
}

/// Reads the persisted flag, or null when this device has no answer on record.
///
/// Null rather than false on purpose: main.dart needs to tell "never asked"
/// apart from "asked", because an install that predates this feature has no
/// key at all and must be treated as already asked. See the derivation at the
/// call site.
Future<bool?> loadPersistedFirstRunOfferAsked() async {
  final box = await LocalStoreService.settingsBox();
  return box.get(_kFirstRunOfferAskedKey) as bool?;
}

/// The value [firstRunOfferAskedProvider] should boot with, given whether this
/// device has already finished onboarding.
///
/// The null-coalesce IS the migration, and it is the one trap in this feature.
/// Every install that predates this key already has onboarding_seen_v1 true
/// and no key of its own, so reading a bare false there would put a beginner
/// question in front of the entire installed base on their next launch.
/// Deriving from the old flag gives them "already asked": no screen, nothing.
///
/// A named function rather than an inline expression at the call site so the
/// migration is covered by a test rather than by having been read carefully
/// once. There is precedent for a boot value derived from a neighbouring key
/// rather than owning one, at languageChosenProvider.
Future<bool> resolveFirstRunOfferAsked({required bool onboardingSeen}) async =>
    await loadPersistedFirstRunOfferAsked() ?? onboardingSeen;
