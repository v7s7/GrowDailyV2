import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';

/// The one-time "arrange your bar" coach-mark on the bottom bar.
///
/// Settings and the FAQ are the documented ways into NavBarSettingsScreen;
/// the press-and-hold on the bar is the one people keep, and nothing in the
/// app pointed at it. This is that pointer: a single coach-mark hugging the
/// bar, shown once, retired the moment it is dismissed or the customiser is
/// opened by any route at all.
///
/// Same persistence shape as the App Guide's seen-flags in
/// app_guide_provider.dart: a boot-seeded StateProvider over one Hive key.
const _kNavBarHintSeenKey = 'nav_bar_hint_seen_v1';

final navBarHintSeenProvider = StateProvider<bool>((ref) => false);

Future<void> markNavBarHintSeen(WidgetRef ref) async {
  ref.read(navBarHintSeenProvider.notifier).state = true;
  final box = await LocalStoreService.settingsBox();
  await box.put(_kNavBarHintSeenKey, true);
}

/// Reads the persisted flag, if any. Called once at boot (see main.dart) to
/// seed [navBarHintSeenProvider] before the first frame.
Future<bool> loadPersistedNavBarHintSeen() async {
  final box = await LocalStoreService.settingsBox();
  return box.get(_kNavBarHintSeenKey) as bool? ?? false;
}

/// How many habit completions someone has before the hint may show. Three
/// is "past the first session": the Get Started card and the first-run
/// offer have had their moment, and a person who has coloured a few squares
/// is settled enough to be told about a Premium nicety instead of having
/// it stacked onto day one. New installs carry the trial, so without this
/// the hint would land on the very first launch of every install.
const int kNavBarHintAfterCompletions = 3;

/// Pure, so the timing is a unit test rather than a device session.
///
/// Never shows to a free account (it points at a Premium feature), never
/// twice, never over an App Guide lesson (two spotlights at once is one too
/// many), and never to someone who has already arranged the bar: they found
/// it, which is all the hint was for.
bool shouldShowNavBarHint({
  required bool premium,
  required bool seen,
  required bool customised,
  required bool lessonActive,
  required int completions,
}) =>
    premium &&
    !seen &&
    !customised &&
    !lessonActive &&
    completions >= kNavBarHintAfterCompletions;
