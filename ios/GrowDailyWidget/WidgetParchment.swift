//
//  WidgetParchment.swift
//  GrowDailyWidget
//
//  The two grounds every Home Screen face is painted on, and the only
//  palette allowed on top of them.
//
//  ── Two sheets, one family ───────────────────────────────────────────
//  Aziz supplied a cream parchment sheet and, later the same day, a night
//  version of it. They are the same composition and the same size, so the
//  asset catalog serves them by appearance (PrayerBackdrop.imageset holds
//  both) and a widget follows the phone's light/dark setting with no code
//  in any face. Every token below therefore carries TWO values.
//
//  ── Why the palette had to be re-derived twice ───────────────────────
//  The widgets used to be dark: GrowDaily's near-black card with the brand
//  gold on it. On cream, not one brand colour survives. Measured against
//  the cream sheet's darkest corner:
//
//      gold     1.31:1      emerald  1.38:1
//      streak   1.60:1      xp blue  1.66:1      warning  1.07:1
//
//  All unreadable. On the NIGHT sheet the same colours come back almost
//  untouched, which is the clearest sign that sheet is the right one:
//
//      gold     5.70:1      emerald  5.41:1      streak   4.66:1
//      warning  6.94:1      white   10.88:1
//
//  Only three needed work in dark: the secondary grey (white at the 55-60%
//  the old faces used lands at 3.45-4.06, under the bar), the XP blue
//  (4.48, a hair under), and the border (the old #2D4037 measures 1.02 on
//  this warmer sheet and simply disappears).
//
//  ── How the numbers were arrived at ──────────────────────────────────
//  Not by eye. Each sheet was sampled for its WORST ground: the cream runs
//  0.952 down to 0.670 luminance, so 0.670 is the hardest thing light-mode
//  ink can land on; the night sheet runs 0.0156 up to 0.0465, so 0.0465 is
//  the hardest thing dark-mode ink can land on. Every token was then solved
//  against its own worst case by the same bisection the Dart side's
//  darkenToContrast does: 4.5:1 for text and meaningful icons, 3:1 for
//  borders and filled shapes, which is the bar those are held to.
//
//      light   ink 12.50  gold 5.51  secondary 5.67  green 4.85
//              streak 4.49  xp 4.50  warn 4.48  border 2.99  fill 3.01
//      dark    ink 10.88  gold 5.70  secondary 4.52  green 5.41
//              streak 4.66  xp 5.42  warn 6.94  border 3.56  fill 5.41
//
//  IF EITHER IMAGE IS REGENERATED these numbers stop being true, because
//  they are all relative to that one image's worst corner. Re-sample and
//  re-solve before trusting any of them.
//

import SwiftUI
import UIKit

/// One token, two grounds. `UIColor`'s dynamic provider is what makes this
/// work without touching a single face: every `.parchmentInk` in the whole
/// target resolves itself per appearance, so switching the phone to dark
/// mode repaints all nine Home Screen faces and no view code knows.
private func parchmentDual(light: (Int, Int, Int), dark: (Int, Int, Int)) -> Color {
    Color(uiColor: UIColor { traits in
        let c = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255,
                       blue: CGFloat(c.2) / 255, alpha: 1)
    })
}

extension Color {
    /// The sheet's own mid-tone, painted under the image so a face that
    /// fails to load the asset still reads as the same card.
    static let parchmentGround = parchmentDual(light: (0xEF, 0xE4, 0xD9), dark: (0x2A, 0x26, 0x21))
    /// A step from the ground, for inset rows and dividers.
    static let parchmentSurface = parchmentDual(light: (0xE3, 0xD4, 0xC0), dark: (0x3A, 0x35, 0x30))

    /// The strongest ink: counters, names, primary numbers.
    static let parchmentInk = parchmentDual(light: (0x1A, 0x14, 0x10), dark: (0xFF, 0xFF, 0xFF))
    /// Supporting text: labels, times, captions.
    static let parchmentSecondary = parchmentDual(light: (0x5A, 0x4C, 0x3E), dark: (0xAD, 0xA6, 0x9F))

    /// The brand gold as ink.
    static let parchmentGold = parchmentDual(light: (0x6B, 0x4A, 0x12), dark: (0xE4, 0xB4, 0x5F))
    /// The brand emerald as ink (done, complete, elapsed).
    static let parchmentGreen = parchmentDual(light: (0x16, 0x65, 0x3F), dark: (0x2E, 0xCF, 0x8F))
    /// The streak flame as ink.
    static let parchmentStreak = parchmentDual(light: (0x8F, 0x4B, 0x27), dark: (0xFF, 0x8A, 0x4C))
    /// The level/XP blue as ink.
    static let parchmentXp = parchmentDual(light: (0x32, 0x61, 0x87), dark: (0x7C, 0xBE, 0xEE))
    /// The warning amber as ink.
    static let parchmentWarn = parchmentDual(light: (0x71, 0x5B, 0x1C), dark: (0xF7, 0xC9, 0x48))

    /// Rules, hairlines and focus rings. Held to 3:1, not 4.5:1.
    static let parchmentBorder = parchmentDual(light: (0x94, 0x74, 0x3B), dark: (0x9C, 0x92, 0x87))
    /// A FILLED shape rather than ink: a heatmap square, a progress arc.
    static let parchmentGreenFill = parchmentDual(light: (0x1B, 0x89, 0x5D), dark: (0x2E, 0xCF, 0x8F))

    // Added 2026-09-24 for the Room Race list and the habit rows, solved the
    // same way against the same two worst grounds:
    //
    //     light   miss 4.50  silver 4.91  bronze 4.94  purple 4.88  sleep 5.12
    //     dark    miss 3.54  silver 5.39  bronze 4.85  purple 4.91  sleep 4.80
    //
    // The miss is a drawn cross, a graphic, so it is held to 3:1; the rest
    // are ink and held to 4.5:1. The red is the miss's colour; it is also
    // the Tasks faces' Do First dot and late mark, both graphics too.

    /// The app's error red, darkened for the cream sheet: a Do First task's
    /// dot, a late task's mark.
    static let parchmentRed = parchmentDual(light: (0xB0, 0x2A, 0x22), dark: (0xFF, 0x5A, 0x52))
    /// The red cross on a day that can no longer be saved.
    static let parchmentMiss = parchmentRed
    /// Second and third place, the room board's silver and bronze
    /// (roomPlaceMedalColor) as ink.
    static let parchmentSilver = parchmentDual(light: (0x52, 0x58, 0x62), dark: (0xB0, 0xB7, 0xC3))
    static let parchmentBronze = parchmentDual(light: (0x80, 0x4A, 0x1A), dark: (0xE0, 0xA0, 0x60))
    /// The Mind category's purple (GameColors.rarityEpic) and the Sleep
    /// category's indigo (GameColors.iconSleep) as ink, for a habit's icon.
    static let parchmentPurple = parchmentDual(light: (0x6A, 0x3F, 0xB0), dark: (0xC6, 0x9A, 0xFF))
    static let parchmentSleep = parchmentDual(light: (0x3F, 0x4C, 0xA8), dark: (0x9C, 0xA8, 0xF0))

    /// A habit's own picked colour as ink: unchanged where it already reads
    /// on the sheet, moved just far enough toward black (cream) or white
    /// (night) where it does not. See parchmentSafeChannels. nil for a
    /// value that is not six hex digits, so the caller falls back to the
    /// category's colour, as the Grid does.
    static func parchmentInk(hex: String?) -> Color? {
        parchmentSafe(hex: hex, target: 4.5)
    }

    /// The same, held to the 3:1 a FILLED shape is held to (a square, an
    /// arc) rather than ink's 4.5:1, as parchmentGreenFill is.
    static func parchmentFill(hex: String?) -> Color? {
        parchmentSafe(hex: hex, target: 3)
    }

    private static func parchmentSafe(hex: String?, target: Double) -> Color? {
        guard let rgb = rgbChannels(fromHex: hex) else { return nil }
        let light = parchmentSafeChannels(rgb, dark: false, target: target)
        let dark = parchmentSafeChannels(rgb, dark: true, target: target)
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(c.0), green: CGFloat(c.1), blue: CGFloat(c.2), alpha: 1)
        })
    }

    // ── The app's colour theme on the faces (2026-09-25) ─────────────────
    // What the Habits, Tasks and Room Race faces paint where they painted
    // the brand gold and green: the theme's accent and done colours, made
    // readable on the sheet the way a habit's own colour is, or the tokens
    // above exactly when the app is on its default theme (parseWidgetTheme
    // in WidgetFaceRules.swift). The prayer face keeps its skies, and the
    // Lock Screen faces are tinted by the system, so neither reads these.

    /// The accent as ink: a ring, a tag, a highlighted row, a medal.
    static var themeGold: Color {
        widgetTheme.flatMap { parchmentInk(hex: $0.accentHex) } ?? .parchmentGold
    }

    /// The done colour as ink: counts of what is finished.
    static var themeGreen: Color {
        widgetTheme.flatMap { parchmentInk(hex: $0.doneHex) } ?? .parchmentGreen
    }

    /// The done colour as a filled shape: a finished square, a progress arc.
    static var themeGreenFill: Color {
        widgetTheme.flatMap { parchmentFill(hex: $0.doneHex) } ?? .parchmentGreenFill
    }
}

/// The theme the app last pushed (HomeWidgetService.pushTheme), read fresh
/// on every use rather than cached: a widget process can outlive a theme
/// change, and a stale copy would keep painting the old colours.
var widgetTheme: WidgetThemeColors? {
    parseWidgetTheme(UserDefaults(suiteName: appGroupId)?.string(forKey: "themeColors"))
}

/// The sheet, as every Home Screen face's ground. Which of the two is
/// drawn is the asset catalog's business, not this view's: the imageset
/// carries a dark appearance, so `Image("PrayerBackdrop")` already resolves
/// to the night sheet on a phone in dark mode.
///
/// `scaledToFill` and not `.fill`: the source is 1.91:1 and the small
/// widget is square, so filling by height keeps the whole top-to-bottom
/// gradient and crops the sides, which is the half of the image that
/// carries the pattern.
struct WidgetParchmentBackground: View {
    var body: some View {
        ZStack {
            Color.parchmentGround
            Image("PrayerBackdrop")
                .resizable()
                .scaledToFill()
        }
    }
}

/// Aziz's mosque, tinted rather than painted: the asset is a black
/// silhouette marked as a template, so this one file serves every face and
/// would serve any other ground the same way. The prayer widget passes its
/// sky's name colour as `tint`, since its skies do not follow the phone's
/// mode. The asset is cropped to the silhouette itself (2026-09-24; it
/// used to carry a fifth of its size in empty margin), so `height` is the
/// height of the mosque from its base to the crescent on the minaret.
struct MosqueMark: View {
    var height: CGFloat
    var opacity: Double = 0.10
    var tint: Color = .parchmentInk

    var body: some View {
        Image("MosqueMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .foregroundColor(tint)
            .opacity(opacity)
    }
}
