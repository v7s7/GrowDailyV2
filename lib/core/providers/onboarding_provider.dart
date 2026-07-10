import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';

// ─── First-run onboarding gate ──────────────────────────────────────────────
//
// Same shape as languageChosenProvider in app_strings.dart: a fresh install
// has never seen the walkthrough, so this starts `false` and _AuthGate shows
// it once, right after language + auth/guest are settled (see main.dart);
// once shown it's `true` forever after on this device.

const _kOnboardingSeenKey = 'onboarding_seen_v1';

final onboardingSeenProvider = StateProvider<bool>((ref) => false);

/// Marks the walkthrough as seen and persists it so it never shows again on
/// this device.
Future<void> markOnboardingSeen(WidgetRef ref) async {
  ref.read(onboardingSeenProvider.notifier).state = true;
  final box = await LocalStoreService.settingsBox();
  await box.put(_kOnboardingSeenKey, true);
}

/// Reads the persisted flag, if any. Called once at boot (see main.dart) to
/// seed [onboardingSeenProvider] before the first frame — mirrors
/// loadPersistedLocale.
Future<bool> loadPersistedOnboardingSeen() async {
  final box = await LocalStoreService.settingsBox();
  return box.get(_kOnboardingSeenKey) as bool? ?? false;
}
