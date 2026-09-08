import 'dart:ui' show BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme_preset.dart';

// ─── Gamification Colors ──────────────────────────────────────────────────
//
// Most colors below are preset-driven and mutable — call
// `GameColors.applyPreset(...)` to swap the whole app's look: background,
// surfaces, borders, body text, gold, xp blue, streak orange, and the grid
// green, in both light mode and dark mode. `error`/`warning` and the
// `icon*` set stay fixed across every preset instead — see the `icon*`
// doc comment below for why.

abstract final class GameColors {
  static Color gold = ThemePresets.byId(ThemePresets.defaultId).gold;
  static Color goldDim = ThemePresets.byId(ThemePresets.defaultId).goldDim;
  static Color emerald = ThemePresets.byId(ThemePresets.defaultId).emerald;
  static Color emeraldDim =
      ThemePresets.byId(ThemePresets.defaultId).emeraldDim;
  static Color xpBlue = ThemePresets.byId(ThemePresets.defaultId).xpBlue;
  static Color xpBlueDim = ThemePresets.byId(ThemePresets.defaultId).xpBlueDim;
  static Color streakOrange =
      ThemePresets.byId(ThemePresets.defaultId).streakOrange;
  static Color streakOrangeDim =
      ThemePresets.byId(ThemePresets.defaultId).streakOrangeDim;
  static Color get success => emerald;

  /// The accent and the grid colour moved far enough to be READ on each
  /// mode's own surfaces: darkened on light, lightened on dark. See
  /// ThemePreset's note for the measurements and for why no existing token
  /// could do this job. Where a preset already clears the bar these are the
  /// raw colour, untouched. Reach for them through `context.gp.goldInk` /
  /// `.goldEdge` / `.emeraldInk` / `.emeraldEdge`, which pick the right one
  /// for the current brightness, rather than off this class.
  static Color goldInkLight =
      ThemePresets.byId(ThemePresets.defaultId).goldInkLight;
  static Color goldInkDark =
      ThemePresets.byId(ThemePresets.defaultId).goldInkDark;
  static Color goldEdgeLight =
      ThemePresets.byId(ThemePresets.defaultId).goldEdgeLight;
  static Color goldEdgeDark =
      ThemePresets.byId(ThemePresets.defaultId).goldEdgeDark;
  static Color emeraldInkLight =
      ThemePresets.byId(ThemePresets.defaultId).emeraldInkLight;
  static Color emeraldInkDark =
      ThemePresets.byId(ThemePresets.defaultId).emeraldInkDark;
  static Color emeraldEdgeLight =
      ThemePresets.byId(ThemePresets.defaultId).emeraldEdgeLight;
  static Color emeraldEdgeDark =
      ThemePresets.byId(ThemePresets.defaultId).emeraldEdgeDark;

  /// Black or white, whichever reads better on top of a *solid* emerald
  /// fill (e.g. a quit habit's kept-day mark) — not needed for
  /// emerald used as a translucent tint, text color, or icon color on the
  /// app's own surface, only where emerald itself is the background a
  /// fixed-color glyph/label sits on. Every original green emerald was
  /// bright enough for black to always win here, so this used to just be
  /// `Colors.black` outright; the signature-color presets (see
  /// ThemePreset's doc comment) include some genuinely dark, moody hues —
  /// Rose & Ink, Nour Violet, and Navy all fall low enough on luminance
  /// that black text on them would be hard to read, so this now actually
  /// picks per preset instead of assuming. 0.1791 is the luminance where
  /// black and white give exactly equal WCAG contrast — above it black
  /// wins, below it white does.
  static Color get onEmerald =>
      emerald.computeLuminance() > 0.1791 ? Colors.black : Colors.white;

  /// Same reasoning and crossover point as [onEmerald], for a solid gold
  /// fill instead — e.g. Grid's Add Habit FAB, once it switched from a
  /// neutral surface fill with a gold icon to a solid gold fill needing its
  /// own icon contrast. Gold swings even wider across presets than emerald
  /// does (a warm amber default vs. Ocean's teal vs. Rose & Ink's rose), so
  /// this can't be assumed constant either.
  static Color get onGold =>
      gold.computeLuminance() > 0.1791 ? Colors.black : Colors.white;

  /// The same choice `context.gp.*` makes, for code that has no
  /// BuildContext to make it with — the colour getters on enums and model
  /// classes (a mood's face, a milestone's accent, a square's state), which
  /// are called from a build method that DOES know the brightness and can
  /// pass it down. Prefer `context.gp.*` wherever a context is in reach.
  /// Any colour, moved just far enough to be READ in [dark] mode: darkened
  /// on light, lightened on dark, hue and saturation kept.
  ///
  /// The general form of the named `*Ink` tokens, for colours this file
  /// cannot enumerate — a prestige tier's metal, a Matrix quadrant's accent,
  /// anything a user or a data model supplies. Use it at the point a colour
  /// becomes TEXT or a glyph; a fill keeps the true colour, because the
  /// label on top is what has to be readable, not the fill.
  static Color inkFor(Color c, bool dark) => _solveInk(c, dark, 4.5);

  /// Same, for something held only to the 3:1 non-text bar (a border, a
  /// rule, a dot) — closer to the true colour than [inkFor] is.
  static Color edgeFor(Color c, bool dark) => _solveInk(c, dark, 3.0);

  /// Memoised because the solvers bisect 24 times, and these are called from
  /// BUILD methods — the Matrix cards and the animated task stack among them,
  /// which rebuild every frame while a card is moving. Solving a fixed set of
  /// quadrant colours sixty times a second is exactly the kind of quiet
  /// per-frame cost that shows up as jank rather than as a bug.
  ///
  /// The key set is small and stable in practice (a handful of quadrant,
  /// tier and habit colours), so the cap is a safety net for a pathological
  /// case rather than an expected path; clearing wholesale is fine because
  /// every entry is cheap to recompute.
  static final Map<int, Color> _inkCache = {};

  static Color _solveInk(Color c, bool dark, double target) {
    final key = Object.hash(c.toARGB32(), dark, target);
    final hit = _inkCache[key];
    if (hit != null) return hit;
    final solved = dark
        ? lightenToContrast(c, kDarkSurfaceCeil, target)
        : darkenToContrast(c, kLightSurfaceFloor, target);
    if (_inkCache.length >= 512) _inkCache.clear();
    return _inkCache[key] = solved;
  }

  static Color goldInkFor(bool dark) => dark ? goldInkDark : goldInkLight;
  static Color emeraldInkFor(bool dark) =>
      dark ? emeraldInkDark : emeraldInkLight;
  static Color iconGoldFor(bool dark) => dark ? iconGold : iconGoldInkLight;
  static Color iconStreakFor(bool dark) =>
      dark ? iconStreak : iconStreakInkLight;
  static Color iconXpFor(bool dark) => dark ? iconXp : iconXpInkLight;
  static Color iconSuccessFor(bool dark) =>
      dark ? iconSuccess : iconSuccessInkLight;

  static const Color error = Color(0xFFFF5A52);
  static const Color warning = Color(0xFFF7C948);

  /// "Something is wrong" and "careful" as INK, per mode.
  ///
  /// The pair above is chosen to alarm, not to read: on light surfaces they
  /// measure **1.98:1** and **1.01:1** — warning is very nearly invisible on
  /// cream — and error only reaches 4.34:1 even on dark. Same fixed-constant
  /// treatment as the `icon*` set, for the same reason: a warning has to
  /// look like a warning under every preset, so its ink cannot be
  /// preset-derived either. Read through `context.gp.errorInk` /
  /// `.warningInk`. The raw pair stays for FILLS (a destructive button's
  /// background, an error banner's tint), where the label on top carries the
  /// contrast instead.
  static final Color errorInkLight =
      darkenToContrast(error, kLightSurfaceFloor, 4.5);
  static final Color errorInkDark =
      lightenToContrast(error, kDarkSurfaceCeil, 4.5);
  static final Color warningInkLight =
      darkenToContrast(warning, kLightSurfaceFloor, 4.5);
  static final Color warningInkDark =
      lightenToContrast(warning, kDarkSurfaceCeil, 4.5);
  static Color errorInkFor(bool dark) => dark ? errorInkDark : errorInkLight;
  static Color warningInkFor(bool dark) =>
      dark ? warningInkDark : warningInkLight;

  // Fixed semantic icon colors — never swapped by a preset, unlike
  // gold/xpBlue/streakOrange above (which are now just tint/shade touches
  // of one accent hue, so a preset like Nour Violet renders all three as
  // near-identical purple). A "Gold" stat, a streak flame, an XP bolt, and
  // a done/correct checkmark each carry a real-world color meaning that a
  // theme swap shouldn't erase — gold should always look gold, a checkmark
  // should always look green, no matter which preset is active. Use these
  // for small dashboard icons that name a specific stat; keep using
  // gold/xpBlue/streakOrange/emerald for actual theme chrome (buttons,
  // highlights, tab indicators) that's meant to track the preset.
  static const Color iconGold = Color(0xFFE4B45F);
  static const Color iconGoldDim = Color(0xFF9C7436);
  static const Color iconStreak = Color(0xFFFF8A4C);
  static const Color iconStreakDim = Color(0xFFC95B22);
  static const Color iconXp = Color(0xFF5DADEC);
  static const Color iconXpDim = Color(0xFF236EA8);
  static const Color iconSuccess = Color(0xFF2ECF8F);
  static const Color iconSuccessDim = Color(0xFF188A61);
  // Grid's categoryVisual() used to point the Sleep category at
  // rarityEpic below to get a quick purple - but that color is the item-
  // rarity tier system's "epic" tier, already spoken for by the Mind
  // category, so the two sat identically colored in the habit list with
  // nothing but icon shape (brain vs. crescent) telling them apart. A
  // dedicated fixed color, same fixed-not-preset-driven treatment as the
  // icon* set above, so Sleep reads as its own category at a glance.
  static const Color iconSleep = Color(0xFF6C7BDB);

  // The same five colours, deep enough to be READ on a light surface.
  //
  // The set above is tuned for the dark theme's near-black, where it
  // measures 5.5..7.0 and is fine. On light it measures **1.71..2.46**,
  // failing even the 3:1 an icon is held to, and nine of the call sites
  // put these in a TextStyle, where the bar is 4.5.
  //
  // Note what did NOT work, because the palette looks like it already has
  // the answer: the `*Dim` variants above clear 3:1 on the PALE presets but
  // bottom out at 2.70..3.50 on Nour Violet's tinted surfaces, so they fix
  // the default look and quietly fail the moody ones. (They stay as they
  // are; `iconXpDim` is a gradient tone in the XP bar, not an ink.)
  //
  // These are single fixed constants rather than per-preset derivations,
  // which is the point: the doc comment above promises a Gold stat looks
  // gold under every preset, so the light variant has to be equally fixed.
  // Each is its own hue darkened until it clears 4.5:1 against luminance
  // 0.613 — the darkest light surface ANY preset can produce, including a
  // custom accent's re-hued neutrals — so one constant is legible
  // everywhere. Measured worst case on a real preset surface: 4.59..4.63.
  // Read them through `context.gp.iconGold` and friends, never directly.
  ///
  /// Computed rather than written out as hexes, so they cannot drift if one
  /// of the source colours above is ever retuned.
  static final Color iconGoldInkLight =
      darkenToContrast(iconGold, kLightSurfaceFloor, 4.5);
  static final Color iconStreakInkLight =
      darkenToContrast(iconStreak, kLightSurfaceFloor, 4.5);
  static final Color iconXpInkLight =
      darkenToContrast(iconXp, kLightSurfaceFloor, 4.5);
  static final Color iconSuccessInkLight =
      darkenToContrast(iconSuccess, kLightSurfaceFloor, 4.5);
  static final Color iconSleepInkLight =
      darkenToContrast(iconSleep, kLightSurfaceFloor, 4.5);

  static const Color rarityCommon = Color(0xFF8C9A92);
  static Color get rarityUncommon => emerald;
  // Pinned to the fixed [iconXp] rather than the preset's `xpBlue` accent,
  // for exactly the reason the medal tiers were pinned (see tierGold's
  // comment): "xpBlue" is an accent *role*, not a hue promise. On the
  // default Emerald & Gold preset it resolves to #E49F25 while
  // rarityLegendary resolves to #E4B45F — two near-identical ambers, so
  // the rarity ladder stopped communicating the one thing it exists to
  // communicate. A fixed blue keeps rare distinguishable from legendary
  // under every preset.
  static const Color rarityRare = iconXp;
  static const Color rarityEpic = Color(0xFFB982FF);
  static Color get rarityLegendary => gold;

  // ── Achievement medal tiers ──────────────────────────────────
  //
  // All four are fixed, not preset-driven: bronze/silver/gold/platinum are
  // real metals with a real-world color, the same way iconGold/iconStreak
  // above stay put rather than tracking the active theme.
  //
  // `tierGold` used to be the one exception — an alias for the preset's
  // [gold] accent, on the reasoning that a Gold medal should match the
  // app's own gold. That only holds for the two warm presets. "Gold" is
  // the *accent role* name in ThemePreset, not a hue promise: it resolves
  // to teal on Ocean and Teal & Slate, rose on Rose & Ink, violet on Nour
  // Violet, sky blue on Sky. So on 9 of the 11 presets the Gold tier
  // rendered in a color that isn't gold, under a label reading
  // "ذهبية"/"Gold", with a hardcoded warm-cream `tierGoldShine` highlight
  // sitting on top of it. Worse, Ocean's accent (#7CBADE) lands close
  // enough to `tierPlatinum` that the top two rungs of every ladder became
  // near-indistinguishable — the ordering the whole tier system exists to
  // communicate. Pinned to [iconGold], the same fixed gold the coin/XP
  // stats already use, so the metal ladder survives a theme swap.
  //
  // Each tier carries three shades: `Shine` (the light catch), the base,
  // and `Deep` (the shadowed edge) — a real three-stop metallic gradient
  // rather than the two-stop shine→base it had, which left a silver medal
  // as a pale disc with a near-white rim, effectively invisible against a
  // light-mode card. `Ink` is the separate on-surface variant used for
  // labels, rings and progress bars, split out because the fill color and
  // the text color of a metal genuinely can't be the same value: silver's
  // #B8C0C8 is right as a fill and only reaches 1.6:1 against a white
  // card as text.
  static const Color tierBronze = Color(0xFFCD7F32);
  static const Color tierBronzeShine = Color(0xFFEFAD6D);
  static const Color tierBronzeDeep = Color(0xFF8C5522);
  static const Color tierSilver = Color(0xFFB8C0C8);
  static const Color tierSilverShine = Color(0xFFF2F5F7);
  static const Color tierSilverDeep = Color(0xFF7F8B96);
  static const Color tierGold = iconGold;
  static const Color tierGoldShine = Color(0xFFFFE9A8);
  static const Color tierGoldDeep = Color(0xFFA97C20);
  static const Color tierPlatinum = Color(0xFF6E8CA0);
  static const Color tierPlatinumShine = Color(0xFFDCEEF9);
  static const Color tierPlatinumDeep = Color(0xFF44606F);

  // On-surface ink per tier, per mode — see the `Ink` note above. The dark
  // values are the metals lightened enough to clear 7:1 on a dark card; the
  // light values are darkened enough to clear 4.5:1 on a white one. Read
  // these through `context.gp.tierInk(tier)`, never directly.
  static const Color tierBronzeInkDark = Color(0xFFD9944F);
  static const Color tierBronzeInkLight = Color(0xFFA5622A);
  static const Color tierSilverInkDark = Color(0xFFC6CED6);
  static const Color tierSilverInkLight = Color(0xFF66707A);
  static const Color tierGoldInkDark = Color(0xFFE9C47D);
  static const Color tierGoldInkLight = Color(0xFF8A6614);
  static const Color tierPlatinumInkDark = Color(0xFF9DBACE);
  static const Color tierPlatinumInkLight = Color(0xFF43616F);

  // Dark-mode structural — preset-driven, mutable.
  static Color background = ThemePresets.byId(ThemePresets.defaultId).darkBg;
  static Color surface = ThemePresets.byId(ThemePresets.defaultId).darkSurface;
  static Color surfaceElevated =
      ThemePresets.byId(ThemePresets.defaultId).darkSurfaceElevated;
  static Color surfaceHighlight =
      ThemePresets.byId(ThemePresets.defaultId).darkSurfaceHighlight;
  static Color textPrimary =
      ThemePresets.byId(ThemePresets.defaultId).darkTextPrimary;
  static Color textSecondary =
      ThemePresets.byId(ThemePresets.defaultId).darkTextSecondary;
  static Color textTertiary =
      ThemePresets.byId(ThemePresets.defaultId).darkTextTertiary;
  static Color border = ThemePresets.byId(ThemePresets.defaultId).darkBorder;
  static Color divider =
      ThemePresets.byId(ThemePresets.defaultId).darkDivider;

  // Light-mode structural — preset-driven, mutable.
  static Color lightBg = ThemePresets.byId(ThemePresets.defaultId).lightBg;
  static Color lightSurface =
      ThemePresets.byId(ThemePresets.defaultId).lightSurface;
  static Color lightSurfaceHigh =
      ThemePresets.byId(ThemePresets.defaultId).lightSurfaceHigh;
  static Color lightSurfaceHL =
      ThemePresets.byId(ThemePresets.defaultId).lightSurfaceHL;
  static Color lightBorder =
      ThemePresets.byId(ThemePresets.defaultId).lightBorder;
  static Color lightDivider =
      ThemePresets.byId(ThemePresets.defaultId).lightDivider;
  static Color lightTextPrimary =
      ThemePresets.byId(ThemePresets.defaultId).lightTextPrimary;
  static Color lightTextSecondary =
      ThemePresets.byId(ThemePresets.defaultId).lightTextSecondary;
  static Color lightTextTertiary =
      ThemePresets.byId(ThemePresets.defaultId).lightTextTertiary;

  /// Swaps every preset-driven color in place. Callers must rebuild
  /// (`setState`/provider notify) after calling this — it doesn't trigger
  /// any rebuild itself.
  static void applyPreset(ThemePreset preset) {
    gold = preset.gold;
    goldDim = preset.goldDim;
    goldInkLight = preset.goldInkLight;
    goldInkDark = preset.goldInkDark;
    goldEdgeLight = preset.goldEdgeLight;
    goldEdgeDark = preset.goldEdgeDark;
    emerald = preset.emerald;
    emeraldDim = preset.emeraldDim;
    emeraldInkLight = preset.emeraldInkLight;
    emeraldInkDark = preset.emeraldInkDark;
    emeraldEdgeLight = preset.emeraldEdgeLight;
    emeraldEdgeDark = preset.emeraldEdgeDark;
    xpBlue = preset.xpBlue;
    xpBlueDim = preset.xpBlueDim;
    streakOrange = preset.streakOrange;
    streakOrangeDim = preset.streakOrangeDim;
    background = preset.darkBg;
    surface = preset.darkSurface;
    surfaceElevated = preset.darkSurfaceElevated;
    surfaceHighlight = preset.darkSurfaceHighlight;
    textPrimary = preset.darkTextPrimary;
    textSecondary = preset.darkTextSecondary;
    textTertiary = preset.darkTextTertiary;
    border = preset.darkBorder;
    divider = preset.darkDivider;
    lightBg = preset.lightBg;
    lightSurface = preset.lightSurface;
    lightSurfaceHigh = preset.lightSurfaceHigh;
    lightSurfaceHL = preset.lightSurfaceHL;
    lightBorder = preset.lightBorder;
    lightDivider = preset.lightDivider;
    lightTextPrimary = preset.lightTextPrimary;
    lightTextSecondary = preset.lightTextSecondary;
    lightTextTertiary = preset.lightTextTertiary;
  }
}

// ─── Adaptive Palette — widgets call context.gp.* ────────────────────────────

class _GamePalette {
  final bool dark;
  const _GamePalette(this.dark);

  Color get bg => dark ? GameColors.background : GameColors.lightBg;
  Color get surface => dark ? GameColors.surface : GameColors.lightSurface;
  Color get surfaceHigh =>
      dark ? GameColors.surfaceElevated : GameColors.lightSurfaceHigh;
  Color get surfaceHL =>
      dark ? GameColors.surfaceHighlight : GameColors.lightSurfaceHL;
  Color get textPrimary =>
      dark ? GameColors.textPrimary : GameColors.lightTextPrimary;
  Color get textSec =>
      dark ? GameColors.textSecondary : GameColors.lightTextSecondary;
  Color get textTert =>
      dark ? GameColors.textTertiary : GameColors.lightTextTertiary;
  Color get border => dark ? GameColors.border : GameColors.lightBorder;
  Color get divider => dark ? GameColors.divider : GameColors.lightDivider;

  /// The accent as a LABEL or icon (AA 4.5:1 on this mode's surfaces).
  Color get goldInk =>
      dark ? GameColors.goldInkDark : GameColors.goldInkLight;

  /// The accent as a BORDER, rule or focus ring (AA 3:1). Closer to the raw
  /// accent than [goldInk] is, because a border is held to the lower bar.
  Color get goldEdge =>
      dark ? GameColors.goldEdgeDark : GameColors.goldEdgeLight;

  /// [GameColors.inkFor] / [GameColors.edgeFor] against the current mode —
  /// for a colour that arrives from data rather than the palette.
  Color ink(Color c) => GameColors.inkFor(c, dark);
  Color edge(Color c) => GameColors.edgeFor(c, dark);

  /// "Something is wrong" and "careful" as a label or icon. The raw
  /// [GameColors.error] / [GameColors.warning] stay for fills.
  Color get errorInk => GameColors.errorInkFor(dark);
  Color get warningInk => GameColors.warningInkFor(dark);

  /// The grid colour as a label or icon, same rule as [goldInk].
  Color get emeraldInk =>
      dark ? GameColors.emeraldInkDark : GameColors.emeraldInkLight;

  /// The grid colour as a border, same rule as [goldEdge].
  Color get emeraldEdge =>
      dark ? GameColors.emeraldEdgeDark : GameColors.emeraldEdgeLight;

  /// The fixed semantic stat colours, legible in the current mode: the
  /// vivid original in dark, its darkened ink in light. See the
  /// `icon*InkLight` block in [GameColors] for why the `*Dim` values could
  /// not do this job.
  Color get iconGold => dark ? GameColors.iconGold : GameColors.iconGoldInkLight;
  Color get iconStreak =>
      dark ? GameColors.iconStreak : GameColors.iconStreakInkLight;
  Color get iconXp => dark ? GameColors.iconXp : GameColors.iconXpInkLight;
  Color get iconSuccess =>
      dark ? GameColors.iconSuccess : GameColors.iconSuccessInkLight;
  Color get iconSleep =>
      dark ? GameColors.iconSleep : GameColors.iconSleepInkLight;
}

extension BuildContextGameTheme on BuildContext {
  _GamePalette get gp =>
      _GamePalette(Theme.of(this).brightness == Brightness.dark);
}

// ─── Typography ──────────────────────────────────────────────────────────────

/// The set of user-selectable app-wide typefaces — see [GameTextStyles].
/// Both are free Google Fonts with real, matched Arabic + Latin cuts (not
/// just a Latin face with a generic Arabic fallback bolted on), so neither
/// choice degrades the other script the way most "Arabic-friendly" Latin
/// fonts do.
enum AppFont {
  /// IBM's UI-first family — the most neutral, highest-legibility option,
  /// closer to a system font than a stylized one. The app-wide default.
  ibmPlexSansArabic,

  /// Same friendly, geometric feel as the app's original Cairo, but with
  /// more open counters/joins — the clearer of the two at small sizes.
  tajawal;

  /// The exact family name Google Fonts (and [GoogleFonts.getFont]) expects
  /// — not the Dart method name.
  String get googleFontsFamily => switch (this) {
        AppFont.ibmPlexSansArabic => 'IBM Plex Sans Arabic',
        AppFont.tajawal => 'Tajawal',
      };

  /// Font names are proper nouns/brand names — shown the same in both
  /// languages rather than transliterated.
  String get label => switch (this) {
        AppFont.ibmPlexSansArabic => 'IBM Plex Sans Arabic',
        AppFont.tajawal => 'Tajawal',
      };
}

abstract final class GameTextStyles {
  /// The active typeface — defaults to IBM Plex Sans Arabic. Every getter
  /// below reads this, so changing it (via [applyFont]) and triggering a
  /// rebuild (see `appFontProvider` in theme_provider.dart) re-skins every
  /// screen in one shot, the same way [GameColors.applyPreset] re-skins
  /// colors.
  static AppFont _active = AppFont.ibmPlexSansArabic;

  static AppFont get activeFont => _active;

  /// Swaps the active typeface in place. Callers must rebuild
  /// (`setState`/provider notify) after calling this — it doesn't trigger
  /// any rebuild itself. See [GameColors.applyPreset] for the same pattern.
  static void applyFont(AppFont font) {
    _active = font;
  }

  /// Covers both Arabic and Latin script in the *same* typeface, so
  /// switching the app's language never also changes the *feel* of the
  /// type the way pairing two unrelated fonts would. Replaces relying on
  /// the OS's own system font: a `.SF Pro Text` + generic-name fallback
  /// stack only actually renders as intended on iOS — Android has no
  /// bundled high-quality Arabic typeface to fall back to, so Arabic text
  /// there was at the mercy of whatever the device happened to ship.
  static String get fontFamily =>
      GoogleFonts.getFont(_active.googleFontsFamily).fontFamily!;

  /// Last-resort names for the rare case the active font hasn't finished
  /// loading yet (first launch, no network) — still legible on every
  /// platform.
  static const List<String> fontFallback = <String>[
    'Noto Sans Arabic',
    'Segoe UI',
    'Roboto',
    'Arial',
    'sans-serif',
  ];

  /// Pinned on every text field in the app (add it to any new one).
  ///
  /// Flutter 3.41 (flutter/flutter#167762) changed [EditableText]'s
  /// default to [BoxWidthStyle.max], and the engine gets that style wrong
  /// on wrapped RTL lines: a word in the middle of a line comes back with a
  /// second box that runs from the word to the paragraph edge, so a
  /// double-tapped Arabic word painted as the whole line while the actual
  /// selection (and so delete) was correct. Single-line and Latin text were
  /// unaffected. `tight` is the pre-3.41 default and paints only the glyphs.
  /// Guarded by test/text_selection_width_style_test.dart.
  static const BoxWidthStyle selectionWidthStyle = BoxWidthStyle.tight;

  static TextStyle get displayLarge => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 34, fontWeight: FontWeight.w800, color: GameColors.textPrimary, letterSpacing: -0.5, height: 1.12).copyWith(fontFamilyFallback: fontFallback);
  static TextStyle get displayMedium => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 28, fontWeight: FontWeight.w800, color: GameColors.textPrimary, letterSpacing: -0.3, height: 1.15).copyWith(fontFamilyFallback: fontFallback);
  static TextStyle get headlineLarge => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 22, fontWeight: FontWeight.w700, color: GameColors.textPrimary, letterSpacing: -0.2, height: 1.22).copyWith(fontFamilyFallback: fontFallback);
  static TextStyle get headlineMedium => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 18, fontWeight: FontWeight.w700, color: GameColors.textPrimary, height: 1.25).copyWith(fontFamilyFallback: fontFallback);
  static TextStyle get titleLarge => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 17, fontWeight: FontWeight.w700, color: GameColors.textPrimary, height: 1.25).copyWith(fontFamilyFallback: fontFallback);
  static TextStyle get titleMedium => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 15, fontWeight: FontWeight.w700, color: GameColors.textPrimary, height: 1.28).copyWith(fontFamilyFallback: fontFallback);
  static TextStyle get bodyLarge => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 17, fontWeight: FontWeight.w400, color: GameColors.textPrimary, height: 1.45).copyWith(fontFamilyFallback: fontFallback);
  static TextStyle get bodyMedium => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 15, fontWeight: FontWeight.w400, color: GameColors.textPrimary, height: 1.45).copyWith(fontFamilyFallback: fontFallback);
  static TextStyle get bodySmall => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 13, fontWeight: FontWeight.w400, color: GameColors.textSecondary, height: 1.42).copyWith(fontFamilyFallback: fontFallback);
  static TextStyle get labelLarge => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 15, fontWeight: FontWeight.w700, color: GameColors.textPrimary, letterSpacing: 0.1, height: 1.25).copyWith(fontFamilyFallback: fontFallback);
  static TextStyle get labelSmall => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 11, fontWeight: FontWeight.w600, color: GameColors.textSecondary, letterSpacing: 0.5, height: 1.25).copyWith(fontFamilyFallback: fontFallback);

  static TextStyle get xpLabel => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 13, fontWeight: FontWeight.w800, color: GameColors.xpBlue, letterSpacing: 0.5, height: 1.2).copyWith(fontFamilyFallback: fontFallback);
  static TextStyle get streakDisplay => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 32, fontWeight: FontWeight.w800, color: GameColors.streakOrange, letterSpacing: -0.8, height: 1.05).copyWith(fontFamilyFallback: fontFallback);

  static TextStyle get arabicTitle => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 24, fontWeight: FontWeight.w700, color: GameColors.textPrimary, height: 1.55).copyWith(fontFamilyFallback: fontFallback);
  static TextStyle get arabicBody => GoogleFonts.getFont(_active.googleFontsFamily, fontSize: 16, fontWeight: FontWeight.w400, color: GameColors.textPrimary, height: 1.65).copyWith(fontFamilyFallback: fontFallback);
}
// ─── Spacing & Radii ─────────────────────────────────────────────────────────

abstract final class GameSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double cardRadius = 16;
  static const double buttonRadius = 12;
  static const double chipRadius = 8;
  static const double pillRadius = 100;
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
}

// ─── Motion ────────────────────────────────────────────────────────────────

/// Shared `duration:` timings for entrance/exit/transition animations —
/// reach for one of these instead of a fresh literal millisecond count, the
/// same reasoning as [GameSpacing] for radii/padding. Picked from this
/// app's own most common existing values (not invented numbers), so
/// adopting one of these into a call site already on that value is a
/// no-op, and an imperceptible ~20ms nudge at most for its closest
/// neighbors — never a jump across a genuinely different pacing tier (a
/// tap's feedback and a celebratory reveal were never going to share a
/// number anyway).
///
/// Deliberately says nothing about `delay:`/stagger timings - those encode
/// a sequence's own relative order (item 2 starts 80ms after item 1, and
/// so on), not a shared duration, and folding them in here would flatten a
/// deliberate cascade into everything moving at once. Leave delays as
/// their own explicit literals.
abstract final class GameMotion {
  /// Snappy micro-interactions - a toggle flipping, a chip selecting, a
  /// small AnimatedContainer's color/border changing.
  static const Duration quick = Duration(milliseconds: 160);

  /// The default fade/slide entrance most `.animate()` calls reach for -
  /// this app's single most common timing.
  static const Duration standard = Duration(milliseconds: 220);

  /// A little more visual weight to carry - a card settling into place, a
  /// tab page turning.
  static const Duration relaxed = Duration(milliseconds: 260);

  /// A slower, more deliberate reveal - a sheet opening, a heavier
  /// transition.
  static const Duration slow = Duration(milliseconds: 300);
}

// ─── Shared input theme helper ────────────────────────────────────────────────

InputDecorationTheme _inputTheme(bool dark) {
  final fill = dark ? GameColors.surface : GameColors.lightSurface;
  final bd = dark ? GameColors.border : GameColors.lightBorder;
  final hint = dark ? GameColors.textTertiary : GameColors.lightTextTertiary;
  final label = dark ? GameColors.textSecondary : GameColors.lightTextSecondary;
  // The focus ring is a border (3:1) and the floating label is text (4.5:1),
  // so in light mode they take the accent's edge and ink rather than the
  // accent itself, which is 1.86:1 there. Dark mode keeps the raw accent.
  final focus = dark ? GameColors.goldEdgeDark : GameColors.goldEdgeLight;
  final focusLabel = dark ? GameColors.goldInkDark : GameColors.goldInkLight;
  return InputDecorationTheme(
    filled: true,
    fillColor: fill,
    contentPadding: const EdgeInsets.symmetric(horizontal: GameSpacing.lg, vertical: GameSpacing.md),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: BorderSide(color: bd, width: 0.5)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: BorderSide(color: bd, width: 0.5)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: BorderSide(color: focus)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: const BorderSide(color: GameColors.error)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius), borderSide: const BorderSide(color: GameColors.error)),
    hintStyle: TextStyle(
      fontSize: 15,
      color: hint,
      fontFamily: GameTextStyles.fontFamily,
      fontFamilyFallback: GameTextStyles.fontFallback,
    ),
    labelStyle: TextStyle(
      fontSize: 15,
      color: label,
      fontFamily: GameTextStyles.fontFamily,
      fontFamilyFallback: GameTextStyles.fontFallback,
    ),
    floatingLabelStyle: TextStyle(
      fontSize: 12,
      color: focusLabel,
      fontFamily: GameTextStyles.fontFamily,
      fontFamilyFallback: GameTextStyles.fontFallback,
    ),
  );
}

// ─── ThemeData Assembly ──────────────────────────────────────────────────────

abstract final class GameTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: GameTextStyles.fontFamily,
      fontFamilyFallback: GameTextStyles.fontFallback,
      scaffoldBackgroundColor: GameColors.background,
      colorScheme: ColorScheme.dark(
        primary: GameColors.gold,
        onPrimary: GameColors.background,
        secondary: GameColors.xpBlue,
        onSecondary: GameColors.textPrimary,
        tertiary: GameColors.streakOrange,
        onTertiary: GameColors.textPrimary,
        surface: GameColors.surface,
        onSurface: GameColors.textPrimary,
        surfaceContainerHighest: GameColors.surfaceElevated,
        onSurfaceVariant: GameColors.textSecondary,
        outline: GameColors.border,
        error: GameColors.error,
        onError: GameColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: GameColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        titleTextStyle: GameTextStyles.titleLarge,
        iconTheme: IconThemeData(color: GameColors.textPrimary),
        actionsIconTheme: IconThemeData(color: GameColors.goldEdgeDark),
      ),
      cardTheme: CardThemeData(
        color: GameColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          side: BorderSide(color: GameColors.border, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: GameColors.gold,
          foregroundColor: GameColors.background,
          disabledBackgroundColor: GameColors.surfaceHighlight,
          disabledForegroundColor: GameColors.textTertiary,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius)),
          textStyle: GameTextStyles.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          // Dark needed this after all: the accent is 7.00:1 on the
          // default preset's surfaces, but only 3.16:1 on Navy's and
          // 3.99 on Rose & Ink's. For every preset that already cleared
          // the bar these hand back the raw accent untouched.
          foregroundColor: GameColors.goldInkDark,
          side: BorderSide(color: GameColors.goldEdgeDark),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius)),
          textStyle: GameTextStyles.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: GameColors.goldInkDark,
          textStyle: GameTextStyles.labelLarge,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: GameColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: GameColors.gold.withAlpha(46),
        iconTheme: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? IconThemeData(color: GameColors.goldInkDark, size: 24)
            : IconThemeData(color: GameColors.textTertiary, size: 24)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: GameColors.goldInkDark, fontFamily: GameTextStyles.fontFamily, fontFamilyFallback: GameTextStyles.fontFallback)
            : TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: GameColors.textTertiary, fontFamily: GameTextStyles.fontFamily, fontFamilyFallback: GameTextStyles.fontFallback)),
        elevation: 0,
        height: 72,
      ),
      dividerTheme: DividerThemeData(color: GameColors.divider, space: 1, thickness: 0.5),
      dialogTheme: DialogThemeData(
        backgroundColor: GameColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GameSpacing.cardRadius)),
        titleTextStyle: GameTextStyles.headlineMedium,
        contentTextStyle: TextStyle(fontSize: 15, color: GameColors.textSecondary, fontFamily: GameTextStyles.fontFamily, fontFamilyFallback: GameTextStyles.fontFallback),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: GameColors.surfaceElevated,
        contentTextStyle: GameTextStyles.bodyMedium,
        actionTextColor: GameColors.goldInkDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GameSpacing.chipRadius)),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: GameColors.xpBlue,
        circularTrackColor: GameColors.surfaceElevated,
        linearTrackColor: GameColors.surfaceElevated,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? GameColors.background : GameColors.textTertiary),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? GameColors.gold : GameColors.surfaceElevated),
      ),
      inputDecorationTheme: _inputTheme(true),
      textTheme: TextTheme(
          displayLarge: GameTextStyles.displayLarge,
          displayMedium: GameTextStyles.displayMedium,
          headlineLarge: GameTextStyles.headlineLarge,
          headlineMedium: GameTextStyles.headlineMedium,
          titleLarge: GameTextStyles.titleLarge,
          titleMedium: GameTextStyles.titleMedium,
          bodyLarge: GameTextStyles.bodyLarge,
          bodyMedium: GameTextStyles.bodyMedium,
          bodySmall: GameTextStyles.bodySmall,
          labelLarge: GameTextStyles.labelLarge,
          labelSmall: GameTextStyles.labelSmall,
        ),
    );
  }

  static ThemeData get light {
    final Color lBg = GameColors.lightBg;
    final Color lCard = GameColors.lightSurface;
    final Color lHigh = GameColors.lightSurfaceHigh;
    final Color lHL = GameColors.lightSurfaceHL;
    final Color lTp = GameColors.lightTextPrimary;
    final Color lTs = GameColors.lightTextSecondary;
    final Color lTt = GameColors.lightTextTertiary;
    final Color lBd = GameColors.lightBorder;
    final Color lDv = GameColors.lightDivider;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: GameTextStyles.fontFamily,
      fontFamilyFallback: GameTextStyles.fontFallback,
      scaffoldBackgroundColor: lBg,
      colorScheme: ColorScheme.light(
        primary: GameColors.gold,
        // Same reason as filledButtonTheme's: whatever Material paints on
        // top of `primary` (a picker's selected chip, say) needs an ink
        // chosen by the accent's luminance, not the body ink, which is
        // only 3.75:1 on Navy's accent.
        onPrimary: GameColors.onGold,
        secondary: GameColors.xpBlue,
        onSecondary: Colors.white,
        tertiary: GameColors.streakOrange,
        onTertiary: Colors.white,
        surface: lCard,
        onSurface: lTp,
        surfaceContainerHighest: lHigh,
        onSurfaceVariant: lTs,
        outline: lBd,
        error: GameColors.error,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: lBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: lTp, fontFamily: GameTextStyles.fontFamily, fontFamilyFallback: GameTextStyles.fontFallback),
        iconTheme: IconThemeData(color: lTp),
        actionsIconTheme: IconThemeData(color: GameColors.goldEdgeLight),
      ),
      cardTheme: CardThemeData(
        color: lCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.cardRadius),
          side: BorderSide(color: lBd, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: GameColors.gold,
          // `onGold` rather than `lTp`: black-or-white by the accent's own
          // luminance. The near-black body ink only measured 3.75:1 on
          // Navy's comparatively dark accent, and clears 4.97:1 this way.
          foregroundColor: GameColors.onGold,
          disabledBackgroundColor: lHL,
          disabledForegroundColor: lTt,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius)),
          textStyle: GameTextStyles.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          // Not `gold` for either of these, and the gap is not small: the
          // accent is 1.86:1 on this background, so an outlined button used
          // to render its label, its icon AND its border below the 3:1 that
          // is the LOWER of the two bars it has to clear. Dark mode keeps
          // the raw accent, where the same pair measures 10.09:1.
          foregroundColor: GameColors.goldInkLight,
          side: BorderSide(color: GameColors.goldEdgeLight),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GameSpacing.buttonRadius)),
          textStyle: GameTextStyles.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          // A text button is nothing but its label, so the accent's 1.86:1
          // is the whole widget. Ink keeps the hue and clears AA; going
          // neutral here instead would have cost the affordance too.
          foregroundColor: GameColors.goldInkLight,
          textStyle: GameTextStyles.labelLarge,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lBg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: GameColors.gold.withAlpha(46),
        iconTheme: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? IconThemeData(color: GameColors.goldInkLight, size: 24)
            : IconThemeData(color: lTt, size: 24)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: GameColors.goldInkLight, fontFamily: GameTextStyles.fontFamily, fontFamilyFallback: GameTextStyles.fontFallback)
            : TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: lTt, fontFamily: GameTextStyles.fontFamily, fontFamilyFallback: GameTextStyles.fontFallback)),
        elevation: 0,
        shadowColor: Colors.black12,
        height: 72,
      ),
      dividerTheme: DividerThemeData(color: lDv, space: 1, thickness: 0.5),
      dialogTheme: DialogThemeData(
        backgroundColor: lBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(GameSpacing.cardRadius)),
        ),
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: lTp, fontFamily: GameTextStyles.fontFamily, fontFamilyFallback: GameTextStyles.fontFallback),
        contentTextStyle: TextStyle(fontSize: 15, color: lTs, fontFamily: GameTextStyles.fontFamily, fontFamilyFallback: GameTextStyles.fontFallback),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: lBg,
        contentTextStyle: TextStyle(fontSize: 15, color: lTp, fontFamily: GameTextStyles.fontFamily, fontFamilyFallback: GameTextStyles.fontFallback),
        actionTextColor: GameColors.goldInkLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.chipRadius),
          side: BorderSide(color: lBd, width: 0.5),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: GameColors.xpBlue,
        circularTrackColor: lCard,
        linearTrackColor: lCard,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? lBg : lTt),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? GameColors.gold : lHL),
      ),
      inputDecorationTheme: _inputTheme(false),
      // The active AppFont everywhere: one Google Font that covers Arabic
      // and Latin script natively, so the two languages read as one
      // consistent typeface instead of an OS-dependent system-font/
      // fallback guess.
      textTheme: TextTheme(
          displayLarge: GameTextStyles.displayLarge,
          displayMedium: GameTextStyles.displayMedium,
          headlineLarge: GameTextStyles.headlineLarge,
          headlineMedium: GameTextStyles.headlineMedium,
          titleLarge: GameTextStyles.titleLarge,
          titleMedium: GameTextStyles.titleMedium,
          bodyLarge: GameTextStyles.bodyLarge,
          bodyMedium: GameTextStyles.bodyMedium,
          bodySmall: GameTextStyles.bodySmall,
          labelLarge: GameTextStyles.labelLarge,
          labelSmall: GameTextStyles.labelSmall,
        ).apply(
          bodyColor: lTp,
          displayColor: lTp,
        ),
    );
  }
}
