import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/local_store_service.dart';
import '../theme/game_theme.dart';
import '../theme/theme_preset.dart';

// ─── Theme mode (light / dark / system) ────────────────────────────────────

const _kThemeModeKey = 'theme_mode_v1';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier([ThemeMode initial = ThemeMode.system]) : super(initial);

  void toggle() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _persist();
  }

  void set(ThemeMode mode) {
    state = mode;
    _persist();
  }

  Future<void> _persist() async {
    final box = await LocalStoreService.settingsBox();
    await box.put(_kThemeModeKey, state.name);
  }
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
      orElse: () => ThemeMode.system);
}

// ─── Theme preset (app-wide color template, e.g. Ocean, Rose & Ink) ───────

const _kThemePresetKey = 'theme_preset_v1';

class ThemePresetNotifier extends StateNotifier<String> {
  ThemePresetNotifier([String initial = ThemePresets.defaultId])
      : super(initial);

  /// Sets the active preset, applies its colors to [GameColors] so every
  /// screen picks them up on next rebuild, and persists the choice.
  Future<void> set(String presetId) async {
    state = presetId;
    GameColors.applyPreset(ThemePresets.byId(presetId));
    final box = await LocalStoreService.settingsBox();
    await box.put(_kThemePresetKey, presetId);
  }
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
