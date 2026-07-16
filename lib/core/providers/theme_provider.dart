import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';
import '../theme/game_theme.dart';
import '../theme/theme_preset.dart';

// ─── Theme mode (light / dark / system) ────────────────────────────────────

const _kThemeModeKey = 'theme_mode_v1';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  // Default is light mode regardless of the device's system setting. Users
  // can still switch to dark mode via the toggle, and that choice persists.
  ThemeModeNotifier([ThemeMode initial = ThemeMode.light]) : super(initial);

  // Set once sign-in resolves (see the ref.listen block in GrowDailyApp,
  // main.dart) — null for a guest, so set()/toggle() below only ever touch
  // this device's own Hive storage until then, same guest/account split
  // every other notifier in the app already uses. Deliberately NOT threaded
  // through the constructor/provider like DashboardNotifier's uid: this
  // provider's *initial* value has to be seeded synchronously, before the
  // first frame, from the boot-time override in main.dart (see
  // loadPersistedThemeMode's doc comment) — recreating the whole notifier
  // whenever auth state changes would fight that and risk a flash back to
  // the hardcoded default. Setting this field after construction instead
  // leaves that boot path completely untouched.
  String? _uid;

  void toggle() => _apply(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  void set(ThemeMode mode) => _apply(mode);

  void _apply(ThemeMode mode, {bool persistToAccount = true}) {
    state = mode;
    _persist(persistToAccount: persistToAccount);
  }

  Future<void> _persist({bool persistToAccount = true}) async {
    final box = await LocalStoreService.settingsBox();
    await box.put(_kThemeModeKey, state.name);
    if (persistToAccount && _uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({'themeMode': state.name}, SetOptions(merge: true))
          .catchError((_) {});
    }
  }

  /// Called once a signed-in uid is known — pulls this account's saved
  /// theme mode, if any, and applies it here too so a second device
  /// matches the first instead of always starting at the light-mode
  /// default. A no-op if the account has never set one (brand-new account,
  /// or one that's only ever used a device's own default).
  Future<void> pullFromAccount(String uid) async {
    _uid = uid;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final saved = snap.data()?['themeMode'] as String?;
      if (saved == null) return;
      final matches = ThemeMode.values.where((m) => m.name == saved);
      if (matches.isEmpty || matches.first == state) return;
      _apply(matches.first, persistToAccount: false);
    } catch (_) {
      // Offline or blocked - keep whatever's already active on this device.
    }
  }

  /// Signed out - future set()/toggle() calls go back to being device-local
  /// only, same as a guest.
  void detachAccount() => _uid = null;
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
        (ref) => ThemeModeNotifier());

/// Reads the persisted theme mode, if any. Called once at boot (see
/// main.dart) — previously the dark-mode toggle silently reverted to
/// `ThemeMode.system` on every cold start because nothing persisted it.
Future<ThemeMode?> loadPersistedThemeMode() async {
  final box = await LocalStoreService.settingsBox();
  final name = box.get(_kThemeModeKey) as String?;
  if (name == null) return null;
  return ThemeMode.values.firstWhere((m) => m.name == name,
      orElse: () => ThemeMode.light);
}

// ─── Theme preset (app-wide color template, e.g. Ocean, Rose & Ink) ───────

const _kThemePresetKey = 'theme_preset_v1';

class ThemePresetNotifier extends StateNotifier<String> {
  ThemePresetNotifier([String initial = ThemePresets.defaultId])
      : super(initial);

  // See ThemeModeNotifier's identical field for why this is set after
  // construction rather than threaded through the provider.
  String? _uid;

  /// Sets the active preset, applies its colors to [GameColors] so every
  /// screen picks them up on next rebuild, and persists the choice.
  Future<void> set(String presetId) => _apply(presetId);

  Future<void> _apply(String presetId, {bool persistToAccount = true}) async {
    state = presetId;
    GameColors.applyPreset(ThemePresets.byId(presetId));
    final box = await LocalStoreService.settingsBox();
    await box.put(_kThemePresetKey, presetId);
    if (persistToAccount && _uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({'themePreset': presetId}, SetOptions(merge: true))
          .catchError((_) {});
    }
  }

  /// Called once a signed-in uid is known — pulls this account's saved
  /// preset, if any, same idea as ThemeModeNotifier.pullFromAccount. Doesn't
  /// enforce the premium gate here: the UI (ThemePresetTile) is the only
  /// gate on *choosing* a locked preset, same as it already was before this
  /// existed — reapplying a preset the account already legitimately set
  /// elsewhere isn't a new purchase, it's just this device catching up.
  Future<void> pullFromAccount(String uid) async {
    _uid = uid;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final saved = snap.data()?['themePreset'] as String?;
      if (saved == null || saved == state) return;
      final known = ThemePresets.all.any((p) => p.id == saved);
      if (!known) return;
      await _apply(saved, persistToAccount: false);
    } catch (_) {}
  }

  void detachAccount() => _uid = null;
}

final themePresetProvider =
    StateNotifierProvider<ThemePresetNotifier, String>(
        (ref) => ThemePresetNotifier());

/// Reads the persisted preset id, if any, and immediately applies its
/// colors to [GameColors]. Called once at boot (see main.dart) so the very
/// first frame already renders in the right preset instead of flashing the
/// default colors and then swapping.
Future<String?> loadPersistedThemePreset() async {
  final box = await LocalStoreService.settingsBox();
  final id = box.get(_kThemePresetKey) as String?;
  if (id != null) {
    GameColors.applyPreset(ThemePresets.byId(id));
  }
  return id;
}

// ─── App font (typeface used for every screen) ────────────────────────────

const _kAppFontKey = 'app_font_v1';

class AppFontNotifier extends StateNotifier<AppFont> {
  AppFontNotifier([AppFont initial = AppFont.ibmPlexSansArabic]) : super(initial);

  // See ThemeModeNotifier's identical field for why this is set after
  // construction rather than threaded through the provider.
  String? _uid;

  /// Sets the active font, applies it to [GameTextStyles] so every screen
  /// picks it up on next rebuild, and persists the choice.
  Future<void> set(AppFont font) => _apply(font);

  Future<void> _apply(AppFont font, {bool persistToAccount = true}) async {
    state = font;
    GameTextStyles.applyFont(font);
    final box = await LocalStoreService.settingsBox();
    await box.put(_kAppFontKey, font.name);
    if (persistToAccount && _uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({'appFont': font.name}, SetOptions(merge: true))
          .catchError((_) {});
    }
  }

  /// Called once a signed-in uid is known — pulls this account's saved
  /// font, if any, same idea as ThemeModeNotifier.pullFromAccount.
  Future<void> pullFromAccount(String uid) async {
    _uid = uid;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final saved = snap.data()?['appFont'] as String?;
      if (saved == null) return;
      final matches = AppFont.values.where((f) => f.name == saved);
      if (matches.isEmpty || matches.first == state) return;
      await _apply(matches.first, persistToAccount: false);
    } catch (_) {}
  }

  void detachAccount() => _uid = null;
}

final appFontProvider = StateNotifierProvider<AppFontNotifier, AppFont>(
    (ref) => AppFontNotifier());

/// Reads the persisted font, if any, and immediately applies it to
/// [GameTextStyles]. Called once at boot (see main.dart) so the very first
/// frame already renders in the right font instead of flashing the default
/// and then swapping.
Future<AppFont?> loadPersistedFont() async {
  final box = await LocalStoreService.settingsBox();
  final name = box.get(_kAppFontKey) as String?;
  if (name == null) return null;
  final font = AppFont.values.firstWhere((f) => f.name == name,
      orElse: () => AppFont.ibmPlexSansArabic);
  GameTextStyles.applyFont(font);
  return font;
}
