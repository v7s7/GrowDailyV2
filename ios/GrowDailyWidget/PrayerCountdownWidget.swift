//
//  PrayerCountdownWidget.swift
//  GrowDailyWidget
//
//  The next prayer and a live countdown to its adhan, then «مضى على الأذان»
//  counting up for half an hour before the face moves on to the prayer
//  after it. Asked for 2026-09-23.
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
//      («مضى على الأذان»). That is ~10 entries a day, all pre-rendered in a
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
private func prayerClockFormatter(isAr: Bool) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: isAr ? "ar_BH@numbers=latn" : "en_US")
    // Template, not a literal "h:mm a": this is the one piece of the face
    // that should follow the device's own 12/24-hour setting.
    f.setLocalizedDateFormatFromTemplate("jmm")
    return f
}

/// The locale the live timer digits are rendered in. `Text(style: .timer)`
/// takes its digits from the environment, and an Arabic environment would
/// print ٤:٠٥:١٠ — the same Arabic-Indic trap the Dart side has its own
/// note about. Fixed to en_US_POSIX so the countdown is always 4:05:10.
private let timerDigitsLocale = Locale(identifier: "en_US_POSIX")

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

    var body: some View {
        // `.timer` and not `Text(timerInterval:)`: this one style covers
        // both phases (remaining before `target`, elapsed after it), so the
        // countdown and the count-up are the same view and cannot disagree
        // about the instant they are measuring from.
        Text(target, style: .timer)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
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
private struct PrayerEmptyFace: View {
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

struct PrayerCountdownFace: View {
    @Environment(\.widgetFamily) var family
    var entry: PrayerEntry

    private var compact: Bool { family == .systemSmall }

    var body: some View {
        guard let prayer = entry.prayer else {
            return AnyView(PrayerEmptyFace(isAr: entry.isAr, compact: compact))
        }
        let isAr = entry.isAr
        // Sunrise is not called, so it never claims an adhan — see
        // PrayerSlot.hasAdhan.
        let label: String
        if entry.elapsed {
            label = isAr ? "مضى على الأذان" : "since the adhan"
        } else if prayer.hasAdhan {
            label = isAr ? "باقي على الأذان" : "until the adhan"
        } else {
            label = isAr ? "باقي على الشروق" : "until sunrise"
        }
        // Green once the adhan has gone, so the change of phase reads at a
        // glance and not only from the words. Both are the parchment
        // palette's, not the app's raw accents — see its own note above for
        // why the bright ones cannot be used here.
        let tickerColor: Color = entry.elapsed ? .parchmentGreen : .parchmentInk

        return AnyView(
            VStack(spacing: compact ? 2 : 6) {
                HStack(spacing: 8) {
                    Text(prayer.name(isAr: isAr))
                        .font(.system(size: compact ? 19 : 26, weight: .heavy))
                        .foregroundColor(.parchmentGold)
                    Text(prayerClockFormatter(isAr: isAr).string(from: prayer.date))
                        .font(.system(size: compact ? 13 : 17, weight: .semibold))
                        .foregroundColor(.parchmentSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Text(label)
                    .font(.system(size: compact ? 11 : 14, weight: .medium))
                    .foregroundColor(.parchmentSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                PrayerTicker(
                    target: prayer.date,
                    size: compact ? 30 : 46,
                    color: tickerColor
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(compact ? 8 : 14)
            // The mosque sits in the corner the text runs AWAY from, so it
            // never lands under the countdown: trailing in Arabic is the
            // left of the card. Behind the content, not over it.
            .background(alignment: compact ? .bottomTrailing : .bottomTrailing) {
                MosqueMark(height: compact ? 54 : 74)
                    .padding(.trailing, compact ? -6 : -4)
                    .padding(.bottom, compact ? -8 : -6)
            }
            .environment(\.layoutDirection, isAr ? .rightToLeft : .leftToRight)
            .containerBackground(for: .widget) { WidgetParchmentBackground() }
        )
    }
}

// MARK: - Lock Screen
//
// Everything above this line is painted on parchment. None of it applies
// here and that is not a shortcut: the system renders an accessory widget
// in ITS own tint on a locked device, flattening every colour and dropping
// the container background entirely. A backdrop image would not survive the
// trip, and the gold/green phase cue would come out the same shade of
// white. So these faces carry the phase in a SYMBOL and in the words, which
// do survive.
//
// The seconds still tick: Text(style: .timer) is live on the Lock Screen
// too, so this costs no extra refresh either.

/// The symbol that says which phase this is, for the faces that have no
/// colour to say it with.
private func prayerPhaseSymbol(elapsed: Bool, hasAdhan: Bool) -> String {
    if elapsed { return "bell.fill" }
    return hasAdhan ? "hourglass" : "sunrise"
}

struct PrayerRectangularView: View {
    var entry: PrayerEntry

    var body: some View {
        guard let prayer = entry.prayer else {
            return AnyView(
                Text(entry.isAr ? "حدّد موقعك" : "Set your location")
                    .font(.system(size: 13))
                    .widgetURL(lockScreenOpenURL(tab: "settings"))
            )
        }
        let isAr = entry.isAr
        let label: String
        if entry.elapsed {
            label = isAr ? "مضى على الأذان" : "since the adhan"
        } else if prayer.hasAdhan {
            label = isAr ? "باقي على الأذان" : "until the adhan"
        } else {
            label = isAr ? "باقي على الشروق" : "until sunrise"
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: prayerPhaseSymbol(
                        elapsed: entry.elapsed, hasAdhan: prayer.hasAdhan))
                        .font(.system(size: 11))
                    Text(prayer.name(isAr: isAr))
                        .font(.system(size: 13, weight: .bold))
                    Text(prayerClockFormatter(isAr: isAr).string(from: prayer.date))
                        .font(.system(size: 11))
                        .opacity(0.8)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // The label and the counter share a line because the
                // rectangular slot is two lines tall, not three, and losing
                // the label would leave «3:20:45» meaning nothing.
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 11))
                        .opacity(0.8)
                    PrayerTicker(target: prayer.date, size: 15, color: .primary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, isAr ? .rightToLeft : .leftToRight)
        )
    }
}

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
        // A ring that drains toward the adhan, which is the one thing this
        // slot is big enough to say clearly. ProgressView(timerInterval:)
        // is live the same way the counter is — the ring moves without a
        // reload — and it prints the remaining time inside itself.
        //
        // The range is this face's own span, so the ring is full when the
        // face opens and empty at the adhan. Both ends are guaranteed valid:
        // a countdown entry is only ever emitted while its moment is still
        // ahead, and an elapsed one only for a slot that HAS a window.
        let span: ClosedRange<Date> = entry.elapsed
            ? prayer.date...prayer.date.addingTimeInterval(prayer.elapsedWindow)
            : entry.date...prayer.date
        return AnyView(
            ZStack {
                AccessoryWidgetBackground()
                ProgressView(timerInterval: span, countsDown: !entry.elapsed) {
                    Text(prayer.name(isAr: entry.isAr))
                } currentValueLabel: {
                    Text(prayer.name(isAr: entry.isAr))
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .progressViewStyle(.circular)
            }
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
    }
}
