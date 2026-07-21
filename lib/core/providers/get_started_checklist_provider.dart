import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';

// ─── "Get Started" checklist — first habit + first task ────────────────────
//
// Same persisted-once-dismissed shape as homeSpotlightSeenProvider (see that
// file's doc comment), but this one isn't "seen once and gone" on a timer -
// it's gone once BOTH real steps are done (habitListProvider non-empty AND
// matrixProvider's tasks non-empty - see GetStartedChecklistCard, which
// watches those directly rather than duplicating their state here), or the
// person explicitly dismisses it early. Only the "explicitly dismissed
// early" case needs persisting; the "both done" case is already true from
// real data every time the app opens, nothing to remember.
//
// Why a dedicated checklist instead of leaning harder on the existing
// spotlight/slide-tour: research on first-run UX is consistent that a
// feature tour (what the 5-slide OnboardingScreen already is, kept as-is)
// gets skimmed or skipped, while getting someone to their first real
// completed action is what actually predicts they come back - see the
// GetStartedChecklistCard doc comment for the fuller reasoning.

const _kGetStartedDismissedKey = 'get_started_checklist_dismissed_v1';

final getStartedDismissedProvider = StateProvider<bool>((ref) => false);

/// Marks the checklist as explicitly dismissed early (before both steps were
/// done) and persists it so it never comes back on this device.
Future<void> markGetStartedDismissed(WidgetRef ref) async {
  ref.read(getStartedDismissedProvider.notifier).state = true;
  final box = await LocalStoreService.settingsBox();
  await box.put(_kGetStartedDismissedKey, true);
}

/// Reads the persisted flag, if any. Called once at boot (see main.dart) to
/// seed [getStartedDismissedProvider] before the first frame - mirrors
/// loadPersistedHomeSpotlightSeen.
Future<bool> loadPersistedGetStartedDismissed() async {
  final box = await LocalStoreService.settingsBox();
  return box.get(_kGetStartedDismissedKey) as bool? ?? false;
}
