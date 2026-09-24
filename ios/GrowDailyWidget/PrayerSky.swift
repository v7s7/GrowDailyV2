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
//  The first set was solved for a face centred on the card, which put the
//  prayer's name near the top, where the two warm skies are at their
//  darkest and most saturated. Nothing but near-black cleared 4.5:1 there,
//  so the name came out all but black on orange. The face has since been
//  redrawn from a design canvas Aziz approved (PrayerCountdownFace.swift),
//  with its lines low on the card, where those skies are lightest. Each
//  colour is now a shade of its own sky: brick and burnt sienna on the
//  warm two, bronze on the cream, the brand gold on the night, and a warm
//  sand for the second line where there used to be grey.
//
//  Every one is still measured against the worst pixel under the row it
//  sits on, small face or medium, whichever is worse, and everything but
//  the name holds 4.5:1. The name is 23 pt SemiBold (20 on the small
//  face). WCAG lowers the bar to 3:1 for large text, 14 pt and up when
//  bold, without saying which weights count as bold; this face counts
//  SemiBold, so the name's bar is 3:1. On the two warm skies it is the one
//  line that needs it: 3.7 to 3.9 at the lightest pixel of its row (a line
//  of the pattern), above 5 against the sky's mean. The counter is large
//  too, but it is what the widget is for, so it is held to 4.5:1 anyway.
//  Luminance under the rows:
//
//                 name row       label row      counter row
//      night      0.013-0.021    0.012-0.025    0.010-0.041
//      midday     0.874-0.951    0.874-0.958    0.863-0.967
//      afternoon  0.338-0.525    0.444-0.594    0.478-0.704
//      sunrise    0.268-0.472    0.386-0.571    0.439-0.818
//
//  and the worst contrast each colour reaches there (the adhan time sits
//  on the name row, in the secondary colour):
//
//                 name   time   label   counter   green
//      night      7.74   6.50   6.14    9.81      6.43
//      midday     5.16   5.63   5.63    13.81     5.29
//      afternoon  3.93   4.86   6.19    8.60      4.98
//      sunrise    3.74   4.71   6.46    8.14      5.36
//
//  Every colour also clears its bar on its sky's `ground`, the flat fill
//  under the image, which is what a face shows if the image fails to load.
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
        ground: skyRGB(0xFC, 0xF4, 0xEA),
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
        ground: skyRGB(0xE1, 0xAB, 0x6F),
        ink: skyRGB(0x2E, 0x15, 0x0A),
        secondary: skyRGB(0x4E, 0x25, 0x12),
        name: skyRGB(0x6E, 0x28, 0x10),
        elapsed: skyRGB(0x0F, 0x4D, 0x2E),
        mosqueOpacity: 0.22,
        markOpacity: 0.75
    )

    /// Amber rising from the bottom, from الشروق to الظهر.
    static let sunrise = PrayerSky(
        imageName: "PrayerSkySunrise",
        ground: skyRGB(0xDF, 0xA4, 0x5B),
        ink: skyRGB(0x2A, 0x14, 0x07),
        secondary: skyRGB(0x3A, 0x1C, 0x0A),
        name: skyRGB(0x5A, 0x25, 0x09),
        elapsed: skyRGB(0x0D, 0x42, 0x26),
        mosqueOpacity: 0.22,
        markOpacity: 0.75
    )

    /// Deep teal, from المغرب through العشاء and الفجر to الشروق.
    static let night = PrayerSky(
        imageName: "PrayerSkyNight",
        ground: skyRGB(0x15, 0x23, 0x26),
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
