import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';

// ─── "Fold the weekly recap away" ──────────────────────────────────────────
//
// The Friday recap card is the tallest thing on Profile by a wide margin —
// header, three stats, an encouragement line, a per-habit row for every habit
// you own, and four trend bars. On a full week that is most of a screen, and
// it lands on the one tab people open to check a number and leave.
//
// Collapsed rather than dismissed, on purpose. A dismiss needs an answer to
// "for how long?" and every answer is wrong for someone: hide-this-week loses
// it for people who wanted it gone permanently, hide-forever loses the whole
// feature to one mis-tap, and either way the control is destructive enough
// that it needs a confirm, which is a lot of ceremony for tidying a card.
// Collapsing has no such question. Nothing is lost, the way back is the same
// control you just used, and the header stays on screen carrying the week's
// headline number — so a collapsed card still does the card's main job.
//
// One bool, not a per-week key: "I like this folded" is a preference about
// the card, not a fact about a particular week. Persisted so it survives a
// restart, which is the whole point of a preference.

const _kWeeklyRecapCollapsedKey = 'weekly_recap_collapsed_v1';

/// Whether the Friday recap card is folded to its header.
///
/// Seeded at boot from [loadPersistedWeeklyRecapCollapsed] (see main.dart) so
/// the first frame already knows, rather than rendering expanded and then
/// snapping shut.
final weeklyRecapCollapsedProvider = StateProvider<bool>((ref) => false);

/// Flips and persists the fold state. Called by the card's own chevron.
Future<void> setWeeklyRecapCollapsed(WidgetRef ref, bool collapsed) async {
  if (ref.read(weeklyRecapCollapsedProvider) == collapsed) return;
  ref.read(weeklyRecapCollapsedProvider.notifier).state = collapsed;
  final box = await LocalStoreService.settingsBox();
  await box.put(_kWeeklyRecapCollapsedKey, collapsed);
}

/// Reads the persisted preference, if any. Called once at boot (see
/// main.dart) to seed [weeklyRecapCollapsedProvider] before the first frame.
Future<bool> loadPersistedWeeklyRecapCollapsed() async {
  final box = await LocalStoreService.settingsBox();
  return box.get(_kWeeklyRecapCollapsedKey) as bool? ?? false;
}
