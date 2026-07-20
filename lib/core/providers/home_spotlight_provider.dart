import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';

// ─── One-time "here's where things are" nav spotlight ──────────────────────
//
// Same shape as onboardingSeenProvider (see onboarding_provider.dart), but
// deliberately a separate flag rather than reusing that one: this exists to
// reach people who already finished (or skipped) onboarding under an older
// build, not just brand-new installs — "I don't know where to go" was
// reported by existing users too, and their onboardingSeenProvider is
// already permanently true, so it alone could never show them anything new.
// A device that has never seen *this* flag starts `false` regardless of
// how long ago onboarding happened, so HomeShell shows the spotlight
// exactly once — on whichever app open first has this code — and never
// again after that.

const _kHomeSpotlightSeenKey = 'home_spotlight_seen_v1';

final homeSpotlightSeenProvider = StateProvider<bool>((ref) => false);

/// Marks the nav spotlight as seen and persists it so it never shows again
/// on this device.
Future<void> markHomeSpotlightSeen(WidgetRef ref) async {
  ref.read(homeSpotlightSeenProvider.notifier).state = true;
  final box = await LocalStoreService.settingsBox();
  await box.put(_kHomeSpotlightSeenKey, true);
}

/// Reads the persisted flag, if any. Called once at boot (see main.dart) to
/// seed [homeSpotlightSeenProvider] before the first frame — mirrors
/// loadPersistedOnboardingSeen.
Future<bool> loadPersistedHomeSpotlightSeen() async {
  final box = await LocalStoreService.settingsBox();
  return box.get(_kHomeSpotlightSeenKey) as bool? ?? false;
}
