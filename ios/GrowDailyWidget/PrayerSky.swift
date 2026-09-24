//
//  PrayerSky.swift
//  GrowDailyWidget
//
//  The prayer widget's four skies, one for each stretch of the day, and
//  the only colours allowed on each.
//
//  ── Where they came from ─────────────────────────────────────────────
//  Aziz generated them on 2026-09-23 from the brief this widget was
//  designed with: the same pattern every time, only the light changing.
//  They then sat unused in the app's assets/ folder, which a widget cannot
//  read anyway, until 2026-09-24. Originals in design/prayer-widget/.
//
//  ── Which sky, when ──────────────────────────────────────────────────
//  The sky OUTSIDE, not the prayer on the face (Aziz, 2026-09-24): the
//  countdown to المغرب at half past three sits under the afternoon sky.
//  PrayerEntry.periodKey says which stretch that is. الفجر has no image of
//  its own and shares the night sky with المغرب and العشاء, also his call.
//
//  ── The colours, redrawn with the face (2026-09-24) ──────────────────
//  The skies ignore light and dark mode (his call again: the evening and
//  night skies are dark already), so every colour here is FIXED, one set
//  per sky, where the parchment tokens flip with the phone.
//
//  The first set held every line to 4.5:1 near the top of the card, where
//  the two warm skies are at their darkest and most saturated, and nothing
//  but near-black cleared that: the name came out all but black on
//  orange. The face was then redrawn from a design canvas Aziz approved,
//  and each colour is now a shade of its own sky: brick and burnt sienna
//  on the warm two, bronze on the cream, the brand gold on the night, and
//  a warm sand for the second line where there used to be grey. The
//  canvas set the lines low on the card; Aziz then asked for them centred
//  again, like the first face, which puts the adhan time back on darker
//  orange. So on the warm skies the second colour is darker than the
//  canvas's, and the sunrise name a shade darker too.
//
//  Every colour is measured against the worst pixel under the row it sits
//  on, small face or medium, whichever is worse, and everything but the
//  name holds 4.5:1. The name is 26 pt SemiBold (20 on the small face).
//  WCAG lowers the bar to 3:1 for large text, 14 pt and up when bold,
//  without saying which weights count as bold; this face counts SemiBold,
//  so the name's bar is 3:1. On the two warm skies it is the one line that
//  needs it: 3.3 to 3.4 at the lightest pixel of its row (a line of the
//  pattern), 4.7 to 5.1 against the sky's mean. The counter is large too,
//  but it is what the widget is for, so it is held to 4.5:1 anyway.
//  Luminance under the rows of the centred face:
//
//                 name row       time row       label row      counter row
//      night      0.016-0.026    0.017-0.024    0.014-0.019    0.012-0.029
//      midday     0.867-0.929    0.876-0.921    0.895-0.943    0.866-0.967
//      afternoon  0.281-0.414    0.309-0.394    0.405-0.468    0.454-0.615
//      sunrise    0.212-0.357    0.232-0.311    0.318-0.424    0.376-0.632
//
//  and the worst contrast each colour reaches there (the adhan time is in
//  the secondary colour, the green is the counter after the adhan):
//
//                 name   time   label   counter   green
//      night      7.19   6.27   6.68    11.29     7.39
//      midday     5.12   5.64   5.75    13.86     5.31
//      afternoon  3.36   4.66   5.91    8.21      5.24
//      sunrise    3.27   4.67   6.10    7.08      4.99
//
//  Every colour also clears its bar on its sky's `ground`, the flat fill
//  under the image, which is what a face shows if the image fails to load.
//  That is what deepened the two warm greens: at the canvas's shades they
//  read 4.4 on it.
//
//  The mosque takes the name's colour: faint on the medium card, where it
//  stands on the bottom edge with only sky behind it, and strong on the
//  small one, where it is the card's only mark.
//
//  The sunrise sky shows «مضى على الأذان» only where الفجر's half hour
//  runs past sunrise, which takes a very high latitude (buildPrayerEntries
//  splits that entry at sunrise). Everywhere else its stretch runs from
//  sunrise, which has no adhan, to الظهر, whose count-up belongs to the
//  midday sky. Its green is solved for that one case.
//
//  IF AN IMAGE IS REGENERATED, OR THE FACE'S LINES MOVE, these numbers stop
//  being true. Re-measure the rows and re-solve before trusting any of them.
//

import SwiftUI

struct PrayerSky {
    /// The imageset in this target's asset catalog.
    let imageName: String
    /// The mean colour of the image across the text rows, painted under
    /// it: a face whose image fails to load keeps the same card and still
    /// reads.
    let ground: Color
    /// The counter before the adhan.
    let ink: Color
    /// The adhan time beside the name, and the line under it.
    let secondary: Color
    /// The prayer's name, and the mosque.
    let name: Color
    /// The counter after the adhan: green, so the change of phase reads at
    /// a glance and not only from the words.
    let elapsed: Color
    /// The medium card's mosque, standing on its bottom edge.
    let mosqueOpacity: Double
    /// The small card's mosque, the mark in its top corner.
    let markOpacity: Double

    /// The sky for the stretch of the day `periodKey` names.
    static func forPeriod(_ periodKey: String) -> PrayerSky {
        switch periodKey {
        case "sunrise": return .sunrise
        case "dhuhr": return .midday
        case "asr": return .afternoon
        default: return .night // fajr, maghrib, isha
        }
    }

    /// Soft cream, from الظهر to العصر.
    static let midday = PrayerSky(
        imageName: "PrayerSkyMidday",
        ground: skyRGB(0xFC, 0xF3, 0xE7),
        ink: skyRGB(0x2B, 0x20, 0x17),
        secondary: skyRGB(0x6E, 0x5C, 0x47),
        name: skyRGB(0x8C, 0x5A, 0x10),
        elapsed: skyRGB(0x17, 0x70, 0x4A),
        mosqueOpacity: 0.13,
        markOpacity: 0.7
    )

    /// Sand and orange, from العصر to المغرب.
    static let afternoon = PrayerSky(
        imageName: "PrayerSkyAfternoon",
        ground: skyRGB(0xDD, 0xA0, 0x65),
        ink: skyRGB(0x2E, 0x15, 0x0A),
        secondary: skyRGB(0x4A, 0x23, 0x11),
        name: skyRGB(0x6E, 0x28, 0x10),
        elapsed: skyRGB(0x0D, 0x46, 0x29),
        mosqueOpacity: 0.22,
        markOpacity: 0.75
    )

    /// Amber rising from the bottom, from الشروق to الظهر.
    static let sunrise = PrayerSky(
        imageName: "PrayerSkySunrise",
        ground: skyRGB(0xD2, 0x94, 0x51),
        ink: skyRGB(0x2A, 0x14, 0x07),
        secondary: skyRGB(0x2B, 0x14, 0x07),
        name: skyRGB(0x53, 0x22, 0x08),
        elapsed: skyRGB(0x0B, 0x3D, 0x22),
        mosqueOpacity: 0.22,
        markOpacity: 0.75
    )

    /// Deep teal, from المغرب through العشاء and الفجر to الشروق.
    static let night = PrayerSky(
        imageName: "PrayerSkyNight",
        ground: skyRGB(0x10, 0x26, 0x2C),
        ink: skyRGB(0xF4, 0xEC, 0xDF),
        secondary: skyRGB(0xB8, 0xAA, 0x96),
        name: skyRGB(0xE4, 0xB4, 0x5F),
        elapsed: skyRGB(0x66, 0xD6, 0xA6),
        mosqueOpacity: 0.16,
        markOpacity: 0.8
    )
}

private func skyRGB(_ r: Int, _ g: Int, _ b: Int) -> Color {
    Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
}

/// A sky as a face's ground, filled the way WidgetParchmentBackground is:
/// the source is 1.91:1, so the square small widget keeps the whole
/// top-to-bottom gradient and loses the sides, and the medium one loses
/// about ten points top and bottom. Those two crops are the ones the text
/// rows above were measured on.
struct PrayerSkyBackground: View {
    let sky: PrayerSky

    var body: some View {
        ZStack {
            sky.ground
            Image(sky.imageName)
                .resizable()
                .scaledToFill()
                // Reports the card's size, not the filled image's. A stack
                // sizes itself to its widest child, and the filled image is
                // 302 pt wide on the small card and 177 pt tall on the
                // medium one, so the mosque layered over this sky
                // (PrayerCountdownFace.swift) was placed against those
                // overflowing edges: off the small card entirely, and nine
                // points low on the medium one. The zero minimums are the
                // point: a frame with only maximums never reports less than
                // its child.
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
    }
}
