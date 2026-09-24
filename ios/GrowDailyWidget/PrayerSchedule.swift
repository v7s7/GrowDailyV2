//
//  PrayerSchedule.swift
//  GrowDailyWidget
//
//  The prayer-countdown widget's MODEL, with no face attached: what a
//  moment is, how long it stays on screen after it passes, and the exact
//  list of entries a day of them produces.
//
//  Split out of PrayerCountdownWidget.swift so it can be compiled and
//  exercised on its own. The faces in that file use Lock Screen accessory
//  families, which exist only on iOS, so a file holding both cannot be
//  built for the Mac — and building it for the Mac is what lets
//  buildPrayerEntries be checked against real assertions without a device,
//  a simulator or an App Group. Keep this file free of anything iOS-only.
//

import Foundation
import WidgetKit

/// How long «مضى على الأذان» stays up after the adhan before the face moves
/// on to the next prayer. Aziz's number (2026-09-23).
///
/// Also the cap on how late a prayer can still be "the one showing": a
/// prayer whose window has closed is simply skipped, which is what makes
/// the face self-correct after the phone has been off for a few hours.
///
/// Sunrise gets none of it — see PrayerSlot.hasAdhan.
let prayerElapsedWindow: TimeInterval = 30 * 60

// MARK: - Shared data

/// One prayer as the Flutter side wrote it — a canonical key and an
/// absolute instant. Deliberately not a wall-clock time: a stored
/// "05:14" would need this process to re-derive a time zone (and get
/// daylight saving right in the countries that have it), and an epoch
/// already answers that.
struct PrayerSlot: Codable {
    /// 'fajr' | 'sunrise' | 'dhuhr' | 'asr' | 'maghrib' | 'isha' —
    /// PrayerDayTimes' own field names (lib/core/services/
    /// prayer_times_service.dart), so the two sides share one vocabulary.
    let k: String
    /// Milliseconds since epoch, matching every other instant this app hands
    /// the widget (see matrixTasksJson's `dueAtMs`).
    let ms: Double

    var date: Date { Date(timeIntervalSince1970: ms / 1000) }

    /// The displayed name. Hand-written both ways rather than localized
    /// through a strings file: a widget extension has no access to the
    /// Flutter app's S class, and these five names are not going to drift.
    func name(isAr: Bool) -> String {
        switch k {
        case "fajr": return isAr ? "الفجر" : "Fajr"
        case "sunrise": return isAr ? "الشروق" : "Sunrise"
        case "dhuhr": return isAr ? "الظهر" : "Dhuhr"
        case "asr": return isAr ? "العصر" : "Asr"
        case "maghrib": return isAr ? "المغرب" : "Maghrib"
        case "isha": return isAr ? "العشاء" : "Isha"
        default: return k
        }
    }

    /// Whether an adhan is called for this moment. Sunrise is in the list
    /// because the gap between Fajr and Dhuhr is otherwise five hours with
    /// nothing to count to (Aziz asked for it on 2026-09-23), but it is not
    /// a prayer: nobody calls it, so the face says «باقي على الشروق» rather
    /// than «باقي على الأذان», and it gets NO elapsed window — the moment
    /// the sun is up the face moves on to Dhuhr, because «مضى على الأذان»
    /// would be saying something that never happened.
    var hasAdhan: Bool { k != "sunrise" }

    /// How long this moment stays on the face after it passes.
    var elapsedWindow: TimeInterval { hasAdhan ? prayerElapsedWindow : 0 }
}


// MARK: - Timeline entries

struct PrayerEntry: TimelineEntry {
    let date: Date
    /// The prayer this face is about — nil only when there is no schedule
    /// to show at all (no saved location yet, or the written week has run
    /// out because the app has not been opened in over a week).
    let prayer: PrayerSlot?
    /// false → counting down to the adhan, true → counting up since it.
    let elapsed: Bool
    let isAr: Bool
}

/// Pure, so the entry shape can be reasoned about (and checked) without a
/// widget host, a clock or an App Group.
///
/// For each prayer still worth showing, at most two entries:
///   • the countdown, starting when the PREVIOUS prayer's elapsed window
///     closes (or now, for the one on screen right now), and
///   • the count-up, starting at the adhan itself.
///
/// A prayer already more than [prayerElapsedWindow] old is skipped
/// entirely, which is how a phone switched on at noon lands straight on
/// Dhuhr instead of walking through the morning.
func buildPrayerEntries(slots: [PrayerSlot], now: Date, isAr: Bool, limit: Int = 15) -> [PrayerEntry] {
    let live = slots
        .filter { $0.date.addingTimeInterval($0.elapsedWindow) > now }
        .prefix(limit)
    guard !live.isEmpty else { return [] }

    var entries: [PrayerEntry] = []
    var openedAt = now
    for slot in live {
        let adhan = slot.date
        // The countdown face. Skipped when this moment has already passed
        // (we are inside its elapsed window) or when the previous prayer's
        // window runs right up to it — two prayers closer together than the
        // window would otherwise produce an entry that starts after the one
        // following it.
        if openedAt < adhan {
            entries.append(PrayerEntry(date: openedAt, prayer: slot, elapsed: false, isAr: isAr))
        }
        // The count-up face, for the moments that have an adhan to have
        // passed. Sunrise has none, so it simply hands over to Dhuhr the
        // instant the sun is up.
        if slot.hasAdhan {
            // `max(openedAt, adhan)` because entry dates have to keep
            // climbing.
            let elapsedStart = max(openedAt, adhan)
            entries.append(PrayerEntry(date: elapsedStart, prayer: slot, elapsed: true, isAr: isAr))
            openedAt = max(elapsedStart, adhan.addingTimeInterval(slot.elapsedWindow))
        } else {
            openedAt = max(openedAt, adhan)
        }
    }
    // WidgetKit wants the first entry at or before now, and the list is
    // built from `now` forward, so this only ever trims the leading entry
    // when a prayer sat exactly on the boundary.
    if let first = entries.first, first.date > now {
        entries[0] = PrayerEntry(date: now, prayer: first.prayer, elapsed: first.elapsed, isAr: first.isAr)
    }
    return entries
}

