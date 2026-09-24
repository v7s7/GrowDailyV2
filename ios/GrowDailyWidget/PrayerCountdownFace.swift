//
//  PrayerCountdownFace.swift
//  GrowDailyWidget
//
//  The prayer widget's Home Screen face, small and medium: the next
//  prayer and its adhan time, what the counter means, and the live
//  counter, on the sky outside (PrayerSky.swift).
//
//  Redrawn 2026-09-24 from a design canvas Aziz approved ("apply it to the
//  widget"): https://claude.ai/artifact/PLMJAZS3ebkUNPEHg85Goq, one row
//  per prayer with the face before the adhan, after it, and the small size.
//  The first face centred its three lines in SF Arabic, a heavy name over
//  a bold rounded counter, with the mosque peeking out from under them.
//  This one:
//
//   • sets every line in IBM Plex Sans Arabic, the app's own default
//     typeface (GameTextStyles). An extension cannot read Flutter's copy,
//     so the three weights used here ship in this target (Fonts/, listed
//     under UIAppFonts in Info.plist);
//   • stacks the lines on the leading edge (the right, in Arabic) and low
//     on the card, where the warm skies are lightest, so each sky's text
//     can be a shade of the sky rather than near-black, and the sky stays
//     open above;
//   • stands the mosque on the medium card's bottom edge on the side the
//     text runs away from, and puts it in that top corner of the small
//     card as its mark, tinted with the name's colour either way.
//
//  ── Why the gaps below are negative ──────────────────────────────────
//  Plex's line box is 1.5 em tall: 1.085 above the baseline, 0.415 below,
//  no line gap. The canvas set each line in a tighter CSS line-height,
//  but SwiftUI always gives a Text the font's full box, so the gaps that
//  put each BASELINE where the canvas has it come out negative, and the
//  bottom inset small. From the top of the card:
//
//                name/time   label    counter
//      medium    73.8        95.4     137.4
//      small     92.8        111.0    141.4
//
//  Change a size and re-derive the gaps from those baselines; do not nudge
//  them by eye.
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

/// Every size and inset on the face, in points, off the design canvas.
private struct PrayerFaceMetrics {
    let name: CGFloat
    let time: CGFloat
    let label: CGFloat
    let counter: CGFloat
    let counterTracking: CGFloat
    /// Between the prayer's name and its adhan time.
    let nameTimeGap: CGFloat
    /// Above the label and above the counter: see "Why the gaps below are
    /// negative" at the top of this file.
    let labelGap: CGFloat
    let counterGap: CGFloat
    /// From the card's edge, the system's content margins being off for
    /// this widget (GrowDailyPrayerWidget).
    let leadingInset: CGFloat
    let bottomInset: CGFloat

    /// labelGap works out at -1.5 on paper. It is -2.2 because SwiftUI
    /// rounds each line's box up to a whole pixel, which lifted the name
    /// row 0.8 pt above the canvas at -1.5; measured on a 3x render, -2.2
    /// lands it within a third of a point.
    static let medium = PrayerFaceMetrics(
        name: 23, time: 14, label: 12.5, counter: 40, counterTracking: -0.5,
        nameTimeGap: 8, labelGap: -2.2, counterGap: -6.625,
        leadingInset: 20, bottomInset: 4
    )

    static let small = PrayerFaceMetrics(
        name: 20, time: 12, label: 11, counter: 28, counterTracking: -0.4,
        nameTimeGap: 6, labelGap: -2.05, counterGap: -4.55,
        leadingInset: 14, bottomInset: 5
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
            VStack(alignment: .leading, spacing: 0) {
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
                    color: entry.elapsed ? palette.elapsed : palette.ink,
                    isAr: isAr
                )
                .padding(.top, m.counterGap)
            }
            .padding(.leading, m.leadingInset)
            .padding(.bottom, m.bottomInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
/// Screen; this one sets them in the app's typeface, a touch tighter, and
/// on the edge the other lines start from instead of centred.
private struct PrayerFaceTicker: View {
    let target: Date
    let size: CGFloat
    let tracking: CGFloat
    let color: Color
    let isAr: Bool

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
            // the current one inside that box (see PrayerTicker), so the
            // digits are pinned to the box's edge and the box to the card's.
            // The counter lays out left to right in both languages (below),
            // so the right, where Arabic lines start, is .trailing here.
            .multilineTextAlignment(isAr ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: isAr ? .trailing : .leading)
            .environment(\.locale, timerDigitsLocale)
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// The mosque, on the side the text runs away from: the left of the card
/// in Arabic. On the medium card it stands on the bottom edge, its base
/// just under it; on the small one, where the counter spans the bottom,
/// it sits in the top corner as the card's mark.
private struct PrayerFaceMosque: View {
    let sky: PrayerSky
    let compact: Bool

    var body: some View {
        if compact {
            MosqueMark(height: 30, opacity: sky.markOpacity, tint: sky.name)
                .padding(.trailing, 15)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        } else {
            MosqueMark(height: 88, opacity: sky.mosqueOpacity, tint: sky.name)
                .padding(.trailing, 16)
                .offset(y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}
