import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';

// ─── "Get Started" checklist — first habit + first task ────────────────────
//
// This isn't "seen once and gone" - it's gone once BOTH real steps are done
// (habitListProvider non-empty AND matrixProvider's tasks non-empty - see
// GetStartedChecklistCard, which watches those directly rather than
// duplicating their state here), or the person explicitly dismisses it
// early. Only the "explicitly dismissed early" case needs persisting; the
// "both done" case is already true from real data every time the app opens,
// nothing to remember.
//
// This checklist is now the ONLY thing teaching a first-time user what to do.
// It used to be one of four: a slide tour, a dimming spotlight that repeated
// this card's own wording, the App Guide screen auto-pushed over the Grid,
// and this. The other three either went or stopped showing up uninvited.
// The reasoning is the one below, applied properly: a feature tour before
// you've used anything reliably gets skimmed or skipped, while getting
// someone to their first real completed action is what actually predicts
// they come back - see the
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

/// Puts the checklist back, for the Undo on the dismiss snackbar.
///
/// The X on that card is a 16pt grey glyph sitting next to a step counter, in
/// the corner where every app in the world puts "close this notice". Tapping
/// it removed the ONLY thing teaching a first-time user what to do, forever,
/// on that device, silently, with no confirmation. Somebody who taps it by
/// reflex and then wonders where the list went has no route back except
/// Settings, App Guide, which is exactly the place a person who dismisses
/// things by reflex will not go looking.
///
/// A confirmation dialog would be the wrong fix: it puts friction on the
/// people who meant it, to protect the people who did not. An Undo puts the
/// cost on nobody. This app already uses that pattern for pausing and for
/// deleting habits.
Future<void> undoGetStartedDismissed(WidgetRef ref) async {
  ref.read(getStartedDismissedProvider.notifier).state = false;
  final box = await LocalStoreService.settingsBox();
  await box.put(_kGetStartedDismissedKey, false);
}

/// Reads the persisted flag, if any. Called once at boot (see main.dart) to
/// seed [getStartedDismissedProvider] before the first frame.
Future<bool> loadPersistedGetStartedDismissed() async {
  final box = await LocalStoreService.settingsBox();
  return box.get(_kGetStartedDismissedKey) as bool? ?? false;
}
