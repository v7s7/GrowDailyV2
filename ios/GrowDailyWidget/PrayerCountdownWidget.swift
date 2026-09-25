//
//  PrayerCountdownWidget.swift
//  GrowDailyWidget
//
//  The next prayer and a live countdown to its adhan, then «مضى على الأذان»
//  counting up for a while (25 minutes, 15 after المغرب: see
//  prayerElapsedMinutes) before the face moves on to the prayer after it.
//  Sunrise takes a turn between الفجر and الظهر, in its own words. Asked
//  for 2026-09-23.
//
//  Two things make this work without burning WidgetKit's refresh budget:
//
//   1. The SECONDS tick on their own. `Text(date, style: .timer)` is one of
//      the handful of views WidgetKit keeps live on its own, with no
//      timeline reload behind it — and it already does both directions:
//      remaining before `date`, elapsed after it. So the digits are never
//      what a timeline entry is for.
//
//   2. The WORDS are all a timeline entry is for. Each prayer needs exactly
//      two: one at the moment the previous prayer's elapsed window closes
//      («باقي على الأذان» + this prayer's name) and one at the adhan itself
//      («مضى على الأذان»). That is 12 entries a day, all pre-rendered in a
//      single getTimeline call, which is one refresh — not one per minute.
//
//  The data is whatever PrayerWidgetFeed (lib/core/services/
//  prayer_widget_feed.dart) last wrote into the shared App Group: a week of
//  absolute instants, so this file never calculates a prayer time, never
//  reads a latitude, and never has to know about Bahrain's official table,
//  Aladhan, madhab or a time zone. It only picks the next instant out of a
//  sorted list.
//

import WidgetKit
import SwiftUI

/// Latin digits under Arabic text, which is what the rest of the app
/// settled on (see the 2026-09-18 digits pass) and what the countdown in
/// the screenshot this was modelled on shows. `@numbers=latn` keeps the
/// Arabic locale's own ص/م and its 12-hour convention while forcing 0-9.
func prayerClockFormatter(isAr: Bool, padHour: Bool = false) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: isAr ? "ar_BH@numbers=latn" : "en_US")
    // Template, not a literal "h:mm a": this is the one piece of the face
    // that should follow the device's own 12/24-hour setting.
    f.setLocalizedDateFormatFromTemplate("jmm")
    if padHour {
        // «05:32 م», not «5:32 م»: the Lock Screen face was modelled on a
        // widget that pads the hour (2026-09-24). Doubling the hour field of
        // whatever the template produced keeps the order and hour cycle it
        // chose, where a literal "hh:mm a" would force both. Quoted literal
        // text is left alone, so a pattern carrying a quoted 'h' cannot
        // turn into a printed "hh".
        f.dateFormat = f.dateFormat
            .components(separatedBy: "'")
            .enumerated()
            .map { i, part in
                i.isMultiple(of: 2)
                    ? part.replacingOccurrences(
                        of: "(?<![hHkK])([hHkK])(?![hHkK])", with: "$1$1",
                        options: .regularExpression)
                    : part
            }
            .joined(separator: "'")
    }
    return f
}

/// The locale the live timer digits are rendered in. `Text(style: .timer)`
/// takes its digits from the environment, and an Arabic environment would
/// print ٤:٠٥:١٠ — the same Arabic-Indic trap the Dart side has its own
/// note about. Fixed to en_US_POSIX so the countdown is always 4:05:10.
let timerDigitsLocale = Locale(identifier: "en_US_POSIX")

// MARK: - Timeline

struct PrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PrayerEntry {
        PrayerEntry(
            date: Date(),
            prayer: PrayerSlot(k: "dhuhr", ms: Date().addingTimeInterval(4 * 3600).timeIntervalSince1970 * 1000),
            elapsed: false,
            isAr: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PrayerEntry) -> Void) {
        completion(entries().first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PrayerEntry>) -> Void) {
        let built = entries()
        guard let last = built.last else {
            // Nothing to show. Ask again in an hour rather than never: the
            // app writing a schedule reloads this widget explicitly, but an
            // hourly retry is the same cheap safety net every other provider
            // in this target keeps.
            let empty = PrayerEntry(date: Date(), prayer: nil, elapsed: false, isAr: readIsAr())
            completion(Timeline(entries: [empty], policy: .after(Date().addingTimeInterval(3600))))
            return
        }
        // .atEnd, not a fixed hour: every word on this face is already
        // scheduled up to `last`, so there is nothing to ask about until
        // then. The entry list is capped below at a few days, so this still
        // comes back regularly enough to pick up a freshly written week
        // even if the app itself never gets opened to push one.
        _ = last
        completion(Timeline(entries: built, policy: .atEnd))
    }

    private func readIsAr() -> Bool {
        UserDefaults(suiteName: appGroupId)?.bool(forKey: "localeIsAr") ?? false
    }

    private func readSlots() -> [PrayerSlot] {
        let defaults = UserDefaults(suiteName: appGroupId)
        guard let raw = defaults?.string(forKey: "prayerTimesJson"),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([PrayerSlot].self, from: data)
        else { return [] }
        // Sorted here rather than trusted: the writer sorts too, but a face
        // built from an out-of-order list would produce a timeline whose
        // entries go backwards, which WidgetKit simply drops.
        return decoded.sorted { $0.ms < $1.ms }
    }

    /// The whole schedule, expressed as the moments the WORDS change.
    ///
    /// Exposed as its own function (rather than inlined into getTimeline)
    /// so getSnapshot renders the identical first face instead of a second,
    /// slightly different guess at "now".
    private func entries() -> [PrayerEntry] {
        buildPrayerEntries(slots: readSlots(), now: Date(), isAr: readIsAr())
    }
}

// MARK: - Face

/// The live digits. The one view here that redraws itself.
private struct PrayerTicker: View {
    let target: Date
    let size: CGFloat
    let color: Color
    var weight: Font.Weight = .bold
    var design: Font.Design = .rounded
    /// Tabular digits stop the line shifting as the seconds change. The
    /// Lock Screen faces turn them off to match the widget they were
    /// modelled on, whose counter is set in proportional digits: its glyph
    /// positions only fit that way, and a fixed-width «1» stands visibly
    /// apart from its neighbours.
    var tabularDigits: Bool = true
    /// Drawn in front of the digits, for a face with no room to say «باقي»
    /// or «مضى» in words beside them: the Lock Screen circle passes «−»
    /// until the adhan and «+» after it. nil draws the bare digits.
    var sign: String? = nil

    private var font: Font {
        let base = Font.system(size: size, weight: weight, design: design)
        return tabularDigits ? base.monospacedDigit() : base
    }

    private var digits: Text {
        // `.timer` and not `Text(timerInterval:)`: this one style covers
        // both phases (remaining before `target`, elapsed after it), so the
        // countdown and the count-up are the same view and cannot disagree
        // about the instant they are measuring from.
        let timer = Text(target, style: .timer)
        guard let sign else { return timer }
        // Joined into ONE Text, not set beside it in an HStack: the timer
        // reserves the width of its longest value, so a separate sign would
        // sit outside that box, a gap away from a short value like «5:12».
        // The LRM starts the run left to right, so on an Arabic face the
        // sign stays on the left of the digits instead of trailing them.
        // Interpolated rather than `Text + Text`, which the iOS 26 SDK
        // deprecates; the timer inside keeps ticking either way.
        let mark = Text(verbatim: "\u{200E}" + sign)
        return Text("\(mark)\(timer)")
    }

    var body: some View {
        digits
            .font(font)
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            // Timer text reserves the width of its LONGEST value ("0:00:00")
            // and draws the current one leading inside that box, so an
            // otherwise centred card showed "20:11" pushed to the left as
            // soon as the last hour began. Centring inside the reserved box
            // is the fix; shrinking the box is not possible, since the width
            // it reserves is the point — it is what stops the whole line
            // jittering as the digits change.
            .multilineTextAlignment(.center)
            // Timer digits ignore the surrounding text direction but not
            // the surrounding locale — see timerDigitsLocale.
            .environment(\.locale, timerDigitsLocale)
            // A ticking counter in an RTL container would otherwise have
            // its own components mirrored on some systems; the clock reads
            // left to right in Arabic too.
            .environment(\.layoutDirection, .leftToRight)
    }
}

/// Shown when there is no schedule at all — no saved location yet, or a
/// written week that has run out. Says which, and opens the page that
/// fixes it.
struct PrayerEmptyFace: View {
    let isAr: Bool
    let compact: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "location.slash")
                .font(.system(size: compact ? 18 : 22))
                .foregroundColor(.parchmentGold)
            Text(isAr ? "حدّد موقعك" : "Set your location")
                .font(.system(size: compact ? 13 : 15, weight: .bold))
                .foregroundColor(.parchmentInk)
            Text(isAr ? "عشان تطلع أوقات الصلاة" : "to see prayer times")
                .font(.system(size: compact ? 10 : 12))
                .foregroundColor(.parchmentSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .containerBackground(for: .widget) { WidgetParchmentBackground() }
        .widgetURL(lockScreenOpenURL(tab: "settings"))
    }
}

// The Home Screen face itself, on its sky, is PrayerCountdownFace.swift.

// MARK: - Lock Screen
//
// Everything above this line is painted on a sky (PrayerSky.swift), or on
// parchment when there is no schedule. None of it applies here and that
// is not a shortcut: the system renders an accessory widget
// in ITS own tint on a locked device, flattening every colour and dropping
// the container background entirely. A backdrop image would not survive the
// trip, and the gold/green phase cue would come out the same shade of
// white. So these faces carry the phase in the words, which do survive
// (the inline one, too short for them, in a symbol).
//
// The seconds still tick: Text(style: .timer) is live on the Lock Screen
// too, so this costs no extra refresh either.

/// The symbol that says which phase this is, for the inline face: one line
/// beside the clock, with no room for the words.
private func prayerPhaseSymbol(elapsed: Bool, hasAdhan: Bool) -> String {
    // No bell after sunrise: the bell is the adhan, and none was called.
    if !hasAdhan { return elapsed ? "sun.max" : "sunrise" }
    return elapsed ? "bell.fill" : "hourglass"
}

/// What the counter means: «باقي على الأذان» before the adhan and «مضى على
/// الأذان» after it. Sunrise is never called (see PrayerSlot.hasAdhan), so
/// its pair names the sun instead: «باقي على الشروق», then «مضى على
/// الشروق», the words of the widget Aziz compared this one with
/// (2026-09-25).
func prayerPhaseLabel(elapsed: Bool, prayer: PrayerSlot, isAr: Bool) -> String {
    if prayer.hasAdhan {
        if elapsed { return isAr ? "مضى على الأذان" : "since the adhan" }
        return isAr ? "باقي على الأذان" : "until the adhan"
    }
    if elapsed { return isAr ? "مضى على الشروق" : "since sunrise" }
    return isAr ? "باقي على الشروق" : "until sunrise"
}

/// Rebuilt 2026-09-24 to match a screenshot Aziz sent of another app's
/// Lock Screen widget beside this one ("ALL IN LEFT WIDGET IS WHAT I
/// WANT"): three centred lines and no symbol. The prayer and its time,
/// what the counter means, then the counter.
///
/// Every size, weight and gap below was MEASURED off that screenshot, not
/// picked by eye. It is a native 3x capture; rendering our old face with
/// the same fonts reproduced its pixels to within 2 px, which is what made
/// fitting the other face's glyph positions trustworthy. The fits: the
/// countdown's digit advances land on 20 pt medium in proportional digits,
/// the label's on 14 pt regular, the top line's on 15.5 pt semibold.
struct PrayerRectangularView: View {
    var entry: PrayerEntry

    var body: some View {
        guard let prayer = entry.prayer else {
            return AnyView(
                Text(entry.isAr ? "حدّد موقعك" : "Set your location")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .widgetURL(lockScreenOpenURL(tab: "settings"))
            )
        }
        let isAr = entry.isAr
        let clock = prayerClockFormatter(isAr: isAr, padHour: true).string(from: prayer.date)
        return AnyView(
            // Uneven gaps, measured: the label sits 1 pt nearer the counter
            // than the name, so one VStack spacing cannot place all three.
            VStack(spacing: 0) {
                // One Text, not an HStack of two, so the bidi algorithm lays
                // «المغرب 05:32 م» out as a single phrase; its measured gap
                // between the name and the digits is exactly one space.
                // `verbatim` so nothing in it is ever looked up as a key.
                Text(verbatim: "\(prayer.name(isAr: isAr)) \(clock)")
                    .font(.system(size: 15.5, weight: .semibold))
                Text(prayerPhaseLabel(elapsed: entry.elapsed, prayer: prayer, isAr: isAr))
                    .font(.system(size: 14))
                    // The label measured 0.89 of the white lines' brightness
                    // (the old 0.8 read visibly darker beside it); the Lock
                    // Screen maps opacity to brightness close to linearly.
                    .opacity(0.88)
                    .padding(.top, 2.5)
                PrayerTicker(target: prayer.date, size: 20, color: .primary,
                             weight: .medium, design: .default, tabularDigits: false)
                    .padding(.top, 0.5)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // The slot is shorter than it looks: about 57 pt of content on
            // an iPhone 17 Pro, where these three lines' boxes add up to 63,
            // so SwiftUI squeezed the counter to 80% of its size to make up
            // the difference (measured on the simulator 2026-09-24, and
            // reproduced exactly by squeezing the same view to 57 pt). All
            // of the difference is empty space the fonts keep above the
            // first line's ascenders (2.7 pt) and below the digits' baseline
            // (4.7 pt), the same for all six names. Trimming it leaves the
            // ink, 55.7 pt, at the measured size and spacing, and a smaller
            // phone's slot still squeezes gracefully instead of clipping.
            .padding(.top, -2.5)
            .padding(.bottom, -4.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.layoutDirection, isAr ? .rightToLeft : .leftToRight)
        )
    }
}

/// The small round slot, rebuilt 2026-09-24. It used to be a ring that
/// drained from the moment the face opened to the adhan, with only the
/// prayer's name inside: Aziz could not tell what the ring meant, and
/// nothing in it said when the prayer was or how long was left. What people
/// ask of a prayer widget on the Lock Screen is the next prayer, its time
/// and a live countdown, so the circle is now the rectangle in miniature:
/// the name, the counter where the circle is widest, and the adhan time
/// under it. After the adhan the time has already passed, so that line
/// says «مضى على الأذان» instead («مضى على الشروق» after sunrise), which is
/// what a counter going UP needs.
struct PrayerCircularView: View {
    var entry: PrayerEntry

    var body: some View {
        guard let prayer = entry.prayer else {
            return AnyView(
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "location.slash").font(.system(size: 14))
                }
            )
        }
        let isAr = entry.isAr
        let footer: String
        if !entry.elapsed {
            footer = prayerClockFormatter(isAr: isAr, padHour: true).string(from: prayer.date)
        } else if isAr {
            footer = prayerPhaseLabel(elapsed: true, prayer: prayer, isAr: true)
        } else {
            // "since the adhan" needs more than the bottom line's width even
            // at the smallest scale and came out as "since the adh…".
            footer = prayer.hasAdhan ? "since adhan" : "since sunrise"
        }
        return AnyView(
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(prayer.name(isAr: isAr))
                        .font(.system(size: 12, weight: .semibold))
                    // The sign says which way the counter runs, so «باقي» and
                    // «مضى» read from the digits alone (Aziz, 2026-09-24):
                    // «−1:01:27» until the adhan, «+5:12» after it. U+2212,
                    // the true minus, is the width of the plus beside it.
                    PrayerTicker(target: prayer.date, size: 15, color: .primary,
                                 weight: .medium, design: .default, tabularDigits: false,
                                 sign: entry.elapsed ? "+" : "\u{2212}")
                    Text(verbatim: footer)
                        .font(.system(size: 10))
                        .opacity(0.88)
                        // The bottom line sits where the circle has already
                        // narrowed, and «مضى على الأذان» is as wide as it.
                        .padding(.horizontal, 2)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // The circle measured 58 pt across on an iPhone 17 Pro. A
                // live timer reserves room for its longest value, not the one
                // showing, so the counter is fitted to the width it gets: at
                // 52 pt, «−8:35:03» draws its digits at about 12 pt, as big
                // as the name above it (measured on the simulator 2026-09-24).
                .padding(.horizontal, 3)
            }
            .environment(\.layoutDirection, isAr ? .rightToLeft : .leftToRight)
        )
    }
}

struct PrayerInlineView: View {
    var entry: PrayerEntry

    var body: some View {
        guard let prayer = entry.prayer else {
            return AnyView(Text(entry.isAr ? "حدّد موقعك" : "Set your location"))
        }
        // One line beside the clock, so it gets the name and the counter and
        // nothing else; the symbol carries what the words have no room for.
        return AnyView(
            Label {
                HStack(spacing: 4) {
                    Text(prayer.name(isAr: entry.isAr))
                    PrayerTicker(target: prayer.date, size: 14, color: .primary)
                }
            } icon: {
                Image(systemName: prayerPhaseSymbol(
                    elapsed: entry.elapsed, hasAdhan: prayer.hasAdhan))
            }
        )
    }
}

struct PrayerLockScreenView: View {
    @Environment(\.widgetFamily) var family
    var entry: PrayerEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                PrayerRectangularView(entry: entry)
            case .accessoryInline:
                PrayerInlineView(entry: entry)
            default:
                PrayerCircularView(entry: entry)
            }
        }
        // Same "each Lock Screen widget opens its own page" rule the other
        // three follow. Settings is where the location that feeds this lives.
        .widgetURL(lockScreenOpenURL(tab: "settings"))
        // Same omission as the other three Lock Screen faces, same fix.
        .environment(\.layoutDirection, entry.isAr ? .rightToLeft : .leftToRight)
    }
}

struct GrowDailyPrayerLockScreenWidget: Widget {
    /// Must exactly match HomeWidgetService's _iOSPrayerLockScreenWidgetName.
    /// Shares PrayerProvider with the Home Screen widget — same list, same
    /// entries, just drawn for a slot that has no colour.
    let kind: String = "GrowDailyPrayerLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerProvider()) { entry in
            PrayerLockScreenView(entry: entry)
        }
        .configurationDisplayName(Text("Prayer Countdown"))
        .description(Text("The next prayer and how long is left, on the Lock Screen."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        // Every point of height counts in the rectangle (see the trim in
        // PrayerRectangularView): the default margins cost about 1 pt there,
        // and there is no background on these faces for a margin to keep
        // anything off.
        .contentMarginsDisabled()
    }
}

struct GrowDailyPrayerWidget: Widget {
    /// Must exactly match HomeWidgetService's _iOSPrayerWidgetName
    /// (lib/core/services/home_widget_service.dart), same convention as
    /// every other widget kind string in this target.
    let kind: String = "GrowDailyPrayerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PrayerProvider()) { entry in
            PrayerCountdownFace(entry: entry)
        }
        .configurationDisplayName(Text("Prayer Countdown"))
        .description(Text("The next prayer and how long is left until the adhan."))
        .supportedFamilies([.systemSmall, .systemMedium])
        // The face places every line to the point from the card's own edge
        // (PrayerCountdownFace.swift); the default margins would add about
        // 16 more on every side.
        .contentMarginsDisabled()
    }
}
