//
//  PrayerCountdownFace.swift
//  GrowDailyWidget
//
//  The prayer widget's Home Screen face, small and medium: the next
//  prayer and its adhan time, what the counter means, and the live
//  counter, on the sky outside (PrayerSky.swift).
//
//  Redrawn 2026-09-24 from a design canvas Aziz approved:
//  https://claude.ai/artifact/PLMJAZS3ebkUNPEHg85Goq. The same evening he
//  asked for the lines to be centred again, "same as the pre design", at
//  clear sizes. So the face keeps the first design's shape, three centred
//  lines (the name and its adhan time, what the counter means, the
//  counter) at close to its sizes, and takes the rest from the canvas:
//
//   • every line in IBM Plex Sans Arabic, the app's own default typeface
//     (GameTextStyles). An extension cannot read Flutter's copy, so the
//     three weights used here ship in this target (Fonts/, listed under
//     UIAppFonts in Info.plist);
//   • colours that are shades of each sky rather than one set for all;
//   • the mosque standing on the medium card's bottom edge on the side the
//     text runs away from, and as the small card's mark in that top
//     corner, tinted with the name's colour either way.
//
//  Centred lines sit higher than the canvas's low ones, on darker orange,
//  which is why the warm skies' second colour is darker than the canvas
//  shows. PrayerSky.swift has the measurements.
//
//  ── Where the lines go, and why the gaps look odd ────────────────────
//  Plex's line box is 1.5 em tall: 1.085 above the baseline, 0.415 below,
//  no line gap, and SwiftUI gives every Text that whole box. So the lines
//  are placed by their BASELINES, in points from the top of a 158 pt card
//  (the stack is centred, so on a taller card each moves down by half the
//  difference):
//
//                name/time   label    counter
//      medium    53.1        79.1     124.1
//      small     62.0        82.0     115.0
//
//  On the medium card that centres the ink, from the top of the name's
//  alef (0.74 em above its baseline) to the counter's baseline. On the
//  small one it centres the ink a little low, clear of the mark. The gaps
//  below were derived from those baselines and then checked on a 3x
//  render, where SwiftUI rounds each line's box up to a whole pixel.
//  Change a size and derive them again rather than nudging by eye.
//

import SwiftUI
import WidgetKit

/// IBM Plex Sans Arabic by PostScript name, as bundled in this target.
private enum PrayerFaceFont {
    static func regular(_ size: CGFloat) -> Font { plex("IBMPlexSansArabic-Regular", size) }
    static func medium(_ size: CGFloat) -> Font { plex("IBMPlexSansArabic-Medium", size) }
    static func semiBold(_ size: CGFloat) -> Font { plex("IBMPlexSansArabic-SemiBold", size) }

    /// `fixedSize`, not `size`: a custom font given `size:` grows with
    /// Dynamic Type, which the system fonts this face used before did not,
    /// and a widget card has no room to grow into.
    private static func plex(_ postScriptName: String, _ size: CGFloat) -> Font {
        .custom(postScriptName, fixedSize: size)
    }
}

/// Every size and inset on the face, in points.
private struct PrayerFaceMetrics {
    let name: CGFloat
    let time: CGFloat
    let label: CGFloat
    let counter: CGFloat
    let counterTracking: CGFloat
    /// Between the prayer's name and its adhan time.
    let nameTimeGap: CGFloat
    /// Above the label and above the counter: see "Where the lines go" at
    /// the top of this file.
    let labelGap: CGFloat
    let counterGap: CGFloat
    /// Added above the stack before it is centred on the card. The stack's
    /// boxes overhang its ink unevenly (0.345 em of the name's box above
    /// the alef, 0.415 em of the counter's below the digits), so centring
    /// the boxes alone would lift the ink 5 pt. This puts it back: centred
    /// on the medium card, 2 pt low on the small one, clear of the mark.
    /// Centring rather than a fixed top inset because the card is not one
    /// size: 158 pt tall on most iPhones, 163 on this one, 170 on the
    /// largest.
    let centreBias: CGFloat
    /// Kept clear on both sides, so a long English line shrinks before it
    /// reaches the edge.
    let sideInset: CGFloat

    static let medium = PrayerFaceMetrics(
        name: 26, time: 16, label: 14, counter: 46, counterTracking: -0.5,
        nameTimeGap: 8, labelGap: 0, counterGap: -10.7,
        centreBias: 10.1, sideInset: 16
    )

    static let small = PrayerFaceMetrics(
        name: 20, time: 13, label: 12, counter: 30, counterTracking: -0.4,
        nameTimeGap: 6, labelGap: -1.3, counterGap: -5.1,
        centreBias: 9.8, sideInset: 10
    )
}

struct PrayerCountdownFace: View {
    @Environment(\.widgetFamily) var family
    /// False where the system strips the card's background: StandBy, and
    /// the tinted and clear Home Screens. The warm skies' colours are dark
    /// and would vanish on the black the face is then drawn over, so the
    /// face falls back to the night sky's, which are made for a dark ground.
    @Environment(\.showsWidgetContainerBackground) var showsBackground
    var entry: PrayerEntry

    var body: some View {
        let compact = family == .systemSmall
        guard let prayer = entry.prayer else {
            return AnyView(PrayerEmptyFace(isAr: entry.isAr, compact: compact))
        }
        let isAr = entry.isAr
        let m = compact ? PrayerFaceMetrics.small : .medium
        // The sky outside at this entry's moment, and the only colours
        // solved to read on it (PrayerSky.swift).
        let sky = PrayerSky.forPeriod(entry.periodKey)
        let palette = showsBackground ? sky : .night
        let direction: LayoutDirection = isAr ? .rightToLeft : .leftToRight

        return AnyView(
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: m.nameTimeGap) {
                    Text(prayer.name(isAr: isAr))
                        .font(PrayerFaceFont.semiBold(m.name))
                        .foregroundColor(palette.name)
                    Text(prayerClockFormatter(isAr: isAr).string(from: prayer.date))
                        .font(PrayerFaceFont.medium(m.time))
                        .foregroundColor(palette.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Text(prayerPhaseLabel(elapsed: entry.elapsed, prayer: prayer, isAr: isAr))
                    .font(PrayerFaceFont.regular(m.label))
                    .foregroundColor(palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, m.labelGap)

                // Green once the adhan has gone, so the change of phase
                // reads at a glance and not only from the words.
                PrayerFaceTicker(
                    target: prayer.date,
                    size: m.counter,
                    tracking: m.counterTracking,
                    color: entry.elapsed ? palette.elapsed : palette.ink
                )
                .padding(.top, m.counterGap)
            }
            .padding(.top, m.centreBias)
            .padding(.horizontal, m.sideInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.layoutDirection, direction)
            // The mosque belongs to the scene, not the text, so it lives in
            // the background and leaves with it wherever the system strips
            // the background. The direction is set again here because the
            // background does not inherit the content's environment, and
            // the app's language (isAr) can differ from the phone's.
            .containerBackground(for: .widget) {
                ZStack {
                    PrayerSkyBackground(sky: sky)
                    PrayerFaceMosque(sky: sky, compact: compact)
                }
                .environment(\.layoutDirection, direction)
            }
        )
    }
}

/// The live digits on the sky faces. PrayerTicker draws them on the Lock
/// Screen; this one sets them in the app's typeface and a touch tighter.
private struct PrayerFaceTicker: View {
    let target: Date
    let size: CGFloat
    let tracking: CGFloat
    let color: Color

    var body: some View {
        // Plex's digits are tabular already (every figure 0.6 em), so the
        // line cannot jitter as the seconds change.
        Text(target, style: .timer)
            .font(PrayerFaceFont.medium(size))
            .tracking(tracking)
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            // Timer text reserves the width of its LONGEST value and draws
            // the current one inside that box (see PrayerTicker). Centred
            // in it, so a short value like «18:19» sits under the lines
            // above instead of off to one side.
            .multilineTextAlignment(.center)
            .environment(\.locale, timerDigitsLocale)
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// The mosque, on the side the text runs away from: the left of the card
/// in Arabic. On the medium card it stands on the bottom edge, its base
/// just under it, 14 pt clear of the centred counter at its widest
/// («0:00:00»). On the small one, where the counter spans the middle, it
/// sits in the top corner as the card's mark.
private struct PrayerFaceMosque: View {
    let sky: PrayerSky
    let compact: Bool

    var body: some View {
        if compact {
            // 26, not the canvas's 30: with the lines centred, a 30 pt
            // mark came within 3 pt of the first line's left end.
            MosqueMark(height: 26, opacity: sky.markOpacity, tint: sky.name)
                .padding(.trailing, 15)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        } else {
            MosqueMark(height: 70, opacity: sky.mosqueOpacity, tint: sky.name)
                .padding(.trailing, 16)
                .offset(y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}
