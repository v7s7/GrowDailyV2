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
// The custom preset's two colours, stored as ARGB ints beside the id. Kept
// separate from the id so switching to a built-in and back does not lose
// what the user built.
const _kCustomAccentKey = 'theme_custom_accent_v1';
const _kCustomGridKey = 'theme_custom_grid_v1';

class ThemePresetNotifier extends StateNotifier<String> {
  ThemePresetNotifier([String initial = ThemePresets.defaultId])
      : super(initial);

  // See ThemeModeNotifier's identical field for why this is set after
  // construction rather than threaded through the provider.
  String? _uid;

  /// Notify on every set, even when the id is unchanged.
  ///
  /// This notifier's state is only the preset ID, but the ACTUAL theme lives
  /// in [GameColors] and [ThemePresets.customAccent]/[customGrid], which
  /// [_apply] mutates. For the eleven built-in presets those two always move
  /// together, so the default "did the value change" check was right. The
  /// custom preset breaks that: editing either colour while already on
  /// `custom` leaves the id at `custom`, the default check sees no change,
  /// nothing rebuilds, and the app keeps painting the previous colours while
  /// the stored ones have already moved.
  @override
  bool updateShouldNotify(String old, String current) => true;

  /// Sets the active preset, applies its colors to [GameColors] so every
  /// screen picks them up on next rebuild, and persists the choice.
  Future<void> set(String presetId) => _apply(presetId);

  /// Sets the user's own two colours and switches to the custom preset.
  ///
  /// Writes the statics BEFORE applying, because [ThemePresets.custom] is a
  /// getter built from them — applying first would paint the previous pair.
  ///
  /// Both colours go through the readability guard here, and this is the
  /// point where that matters most. The picker already fits what it shows,
  /// so for a tap on a swatch this is a no-op; the reason it is repeated at
  /// the STORAGE boundary is everything that is not a tap. A hex typed into
  /// the field, a colour restored from Hive that an older build wrote before
  /// the guard existed, a pair pulled off another device by
  /// [pullFromAccount] — each of those reaches the stored colours without
  /// passing the picker, and only one of them has to carry 0xFF000000 for
  /// every filled button in the app to lose its label. Fitting twice costs a
  /// luminance comparison. Fitting once, in the UI, costs the guarantee.
  Future<void> setCustom({required Color accent, required Color grid}) async {
    ThemePresets.customAccent = fitAccentColour(accent);
    ThemePresets.customGrid = fitGridColour(grid);
    await _apply(ThemePresets.customId);
  }

  /// Same as [setCustom], minus the writing down.
  ///
  /// Exists for the one caller that changes the colours CONTINUOUSLY: a
  /// finger dragging across the custom theme sheet's saturation field
  /// produces a new pair on every frame, and [setCustom] would answer each
  /// one with a Hive write and a Firestore write. At sixty frames a second
  /// that is not a slow path, it is a bill and a rate limit, for values the
  /// user is still in the middle of choosing and most of which they will
  /// never see again.
  ///
  /// The split is between what has to be INSTANT and what has to be
  /// DURABLE. Repainting the app in the new colours is instant, costs
  /// nothing and is the entire point of dragging; persisting is durable and
  /// only has to be true once the finger lifts. So the picker calls this on
  /// every frame and [setCustom] once, on release.
  void previewCustom({required Color accent, required Color grid}) {
    ThemePresets.customAccent = fitAccentColour(accent);
    ThemePresets.customGrid = fitGridColour(grid);
    GameColors.applyPreset(ThemePresets.custom);
    // updateShouldNotify is unconditionally true on this notifier (see its
    // override), which is what makes re-setting the same id repaint the app
    // rather than being swallowed as a no-op change.
    state = ThemePresets.customId;
  }

  Future<void> _apply(String presetId, {bool persistToAccount = true}) async {
    state = presetId;
    GameColors.applyPreset(ThemePresets.byId(presetId));
    final box = await LocalStoreService.settingsBox();
    await box.put(_kThemePresetKey, presetId);
    // Always written, not only while custom is active, so a round trip
    // through a built-in preset and back returns the same two colours.
    await box.put(_kCustomAccentKey, ThemePresets.customAccent.value);
    await box.put(_kCustomGridKey, ThemePresets.customGrid.value);
    if (persistToAccount && _uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({
            'themePreset': presetId,
            'themeCustomAccent': ThemePresets.customAccent.value,
            'themeCustomGrid': ThemePresets.customGrid.value,
          }, SetOptions(merge: true))
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
      final data = snap.data();
      final saved = data?['themePreset'] as String?;
      if (saved == null) return;
      if (!ThemePresets.isKnown(saved)) return;
      // The two colours have to land before the apply, and they are pulled
      // even when the id is unchanged: the other device may have edited the
      // custom pair without switching preset.
      final accent = data?['themeCustomAccent'] as int?;
      final grid = data?['themeCustomGrid'] as int?;
      // Fitted on the way in for the same reason the local path fits: an
      // older build of this app, on the user's other device, could have
      // written a pair from before the guard existed.
      if (accent != null) {
        ThemePresets.customAccent = fitAccentColour(Color(accent));
      }
      if (grid != null) ThemePresets.customGrid = fitGridColour(Color(grid));
      if (saved == state && saved != ThemePresets.customId) return;
      await _apply(saved, persistToAccount: false);
    } catch (_) {}
  }

  /// Called on sign-out. Drops a PAID look back to the free default.
  ///
  /// It used to only clear the uid, which left the preset state and this
  /// device's three Hive keys untouched. So a premium account's theme — a
  /// premium preset, or the custom colours they built — survived sign-out and
  /// was handed to whoever signed in next on the same device, showing them a
  /// look they had never paid for and, in the custom case, somebody else's
  /// two chosen colours. The entitlement cache already guards against exactly
  /// this (see PremiumNotifier.bindAccount's stale-cache drop); the theme did
  /// not.
  ///
  /// Free presets are left alone on purpose. They are legitimately
  /// device-local, in the same way the light/dark mode and the font are, and
  /// resetting them would be a change nobody asked for.
  Future<void> detachAccount() async {
    _uid = null;
    if (!ThemePresets.byId(state).isPremium) return;
    await _apply(ThemePresets.defaultId, persistToAccount: false);
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
  // Restored before the apply below, since ThemePresets.custom reads them.
  final accent = box.get(_kCustomAccentKey) as int?;
  final grid = box.get(_kCustomGridKey) as int?;
  // Fitted on restore, so a pair written by a build older than the guard is
  // corrected on the next cold start rather than persisting forever.
  if (accent != null) ThemePresets.customAccent = fitAccentColour(Color(accent));
  if (grid != null) ThemePresets.customGrid = fitGridColour(Color(grid));
  if (id != null) {
    GameColors.applyPreset(ThemePresets.byId(id));
  }
  return id;
}

// ─── Saved colours (the user's own shortlist) ─────────────────────────────

const _kSavedColoursKey = 'theme_saved_colours_v1';

/// How many colours the shortlist holds.
///
/// Ten, because the row is horizontal and a shortlist that scrolls is not a
/// shortlist. The oldest drops off the end rather than the save being
/// refused: a full list is not an error state a user should have to
/// understand, and the colour they just saved is by definition the one they
/// care about right now.
const int kMaxSavedColours = 10;

/// The colours a user has kept, newest first.
///
/// Deliberately NOT synced to the account, unlike the preset and the two
/// custom colours beside it. Those describe what the app LOOKS like, which
/// should follow the person to their other device. This is a scratchpad for
/// building that look, and merging two devices' scratchpads has no answer
/// that is obviously right: newest-wins silently discards, union grows past
/// the cap and reorders. Device-local has one behaviour and it is the one it
/// appears to have.
class SavedThemeColoursNotifier extends StateNotifier<List<Color>> {
  SavedThemeColoursNotifier([List<Color> initial = const []]) : super(initial);

  /// Saves [c] to the front of the list.
  ///
  /// Fitted first, so the shortlist can only ever hold colours that are
  /// actually usable. Saving raw and fitting on recall would mean the swatch
  /// in the row and the colour it applies are different, which is the same
  /// bug as a built-in swatch lying about itself.
  Future<void> add(Color c, {required bool asAccent}) async {
    final fitted = asAccent ? fitAccentColour(c) : fitGridColour(c);
    // Re-saving a colour already held is a no-op rather than a reorder. The
    // + button is not disabled when the current colour is already saved (it
    // would flicker as the user moves through the palette), so this is the
    // press that has to do nothing gracefully.
    if (state.any((x) => x.value == fitted.value)) return;
    state = [fitted, ...state].take(kMaxSavedColours).toList();
    await _persist();
  }

  Future<void> remove(Color c) async {
    state = state.where((x) => x.value != c.value).toList();
    await _persist();
  }

  /// Cleared on sign-out, for the reason [ThemePresetNotifier.detachAccount]
  /// spells out: the custom theme is premium, so a shortlist built with it is
  /// both a paid artifact and, more to the point, somebody else's colours
  /// sitting on a shared device in front of whoever signs in next.
  Future<void> detachAccount() async {
    if (state.isEmpty) return;
    state = const [];
    await _persist();
  }

  Future<void> _persist() async {
    final box = await LocalStoreService.settingsBox();
    await box.put(_kSavedColoursKey, [for (final c in state) c.value]);
  }
}

final savedThemeColoursProvider =
    StateNotifierProvider<SavedThemeColoursNotifier, List<Color>>(
        (ref) => SavedThemeColoursNotifier());

/// Reads the shortlist at boot. Unlike the preset this paints nothing, so it
/// is not on the first-frame critical path and is only seeded into the
/// provider's initial value for consistency with its neighbours.
Future<List<Color>> loadPersistedSavedColours() async {
  final box = await LocalStoreService.settingsBox();
  final raw = box.get(_kSavedColoursKey);
  if (raw is! List) return const [];
  return [
    // Fitted on read, same as the custom pair above: a list written by a
    // build older than the guard must not be able to hand back a colour the
    // guard would reject.
    for (final v in raw)
      if (v is int) fitAccentColour(Color(v)),
  ].take(kMaxSavedColours).toList();
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
