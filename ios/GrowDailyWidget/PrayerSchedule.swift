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

/// How many minutes each moment stays on the face after it passes,
/// counting up («مضى على الأذان», or «مضى على الشروق» for sunrise), before
/// the face moves on to the next one. Aziz's numbers (2026-09-25), which
/// replaced a flat half hour for the five and none at all for sunrise: with
/// none, the face left sunrise the second the sun was up, where the widget
/// he compared it with still said «مضى على الشروق».
///
/// Also the cap on how late a moment can still be "the one showing": one
/// whose window has closed is simply skipped, which is what makes the face
/// self-correct after the phone has been off for a few hours.
///
/// Must match PrayerWidgetFeed.elapsedMinutes (lib/core/services/
/// prayer_widget_feed.dart), which drops a moment from the list once its
/// window has closed. test/core/prayer_widget_feed_test.dart reads this
/// table and holds the two equal, so keep it a plain literal.
let prayerElapsedMinutes: [String: Int] = [
    "fajr": 25,
    "sunrise": 15,
    "dhuhr": 25,
    "asr": 25,
    "maghrib": 15,
    "isha": 25,
]

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
    /// a prayer: nobody calls it, so the face names the sun where it would
    /// name the adhan, «باقي على الشروق» before it and «مضى على الشروق»
    /// after, because «مضى على الأذان» would be saying something that never
    /// happened.
    var hasAdhan: Bool { k != "sunrise" }

    /// How long this moment stays on the face after it passes: its minutes
    /// in prayerElapsedMinutes, or none for a key the table does not name.
    var elapsedWindow: TimeInterval { TimeInterval((prayerElapsedMinutes[k] ?? 0) * 60) }
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
    /// The stretch of the day this entry falls in: the key of the moment
    /// that last passed. It picks the face's sky (PrayerSky.swift), and it
    /// is deliberately NOT `prayer.k`: the countdown to المغرب at half past
    /// three runs under the afternoon sky, because that is the sky outside
    /// (Aziz's call, 2026-09-24). buildPrayerEntries fills it in; the
    /// default only reaches the gallery placeholder and the empty face.
    var periodKey: String = "dhuhr"
}

/// The six moments in the order a day passes through them, which is also
/// the order the sky moves through.
let prayerDayOrder = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]

/// Which stretch of the day `date` falls in, named by the moment that
/// began it: the latest slot at or before `date`.
///
/// Often that moment is no longer in the list. The Flutter side drops a
/// moment once its window has closed (PrayerWidgetFeed.flatten), so at two
/// in the afternoon the written list starts at العصر and الظهر is gone.
/// The stretch is then the one BEFORE the first slot in the day's order,
/// which is exactly the moment that was dropped (العشاء before الفجر).
/// `slots` must be ascending, as the provider's readSlots returns them.
func prayerPeriodKey(at date: Date, slots: [PrayerSlot]) -> String {
    if let passed = slots.last(where: { $0.date <= date }) { return passed.k }
    guard let first = slots.first,
          let i = prayerDayOrder.firstIndex(of: first.k) else { return "dhuhr" }
    return prayerDayOrder[(i + prayerDayOrder.count - 1) % prayerDayOrder.count]
}

/// Pure, so the entry shape can be reasoned about (and checked) without a
/// widget host, a clock or an App Group.
///
/// For each moment still worth showing, at most two entries:
///   • the countdown, starting when the PREVIOUS moment's elapsed window
///     closes (or now, for the one on screen right now), and
///   • the count-up, starting at the moment itself: the adhan, or the sun
///     coming up.
///
/// A moment already older than its own window (prayerElapsedMinutes) is
/// skipped entirely, which is how a phone switched on at noon lands
/// straight on Dhuhr instead of walking through the morning.
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
        // The count-up face, for every moment with a window after it, which
        // since 2026-09-25 is all six: sunrise too, as «مضى على الشروق». A
        // key the table does not name hands over to the next moment the
        // instant it passes.
        if slot.elapsedWindow > 0 {
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
    // The sky changes at every one of the six moments, and the words
    // nearly always change there too, so nearly every entry already starts
    // on one. The exception is an elapsed window that runs past the next
    // moment, which only two moments closer together than the first one's
    // window produce (الفجر and الشروق at a very high latitude): that entry
    // would carry the old sky past the moment. So a moment falling inside
    // an entry splits it, with the same words and the new sky from then on.
    var timed: [PrayerEntry] = []
    for (i, entry) in entries.enumerated() {
        timed.append(entry)
        guard i + 1 < entries.count else { continue }
        let next = entries[i + 1].date
        for slot in slots where slot.date > entry.date && slot.date < next {
            timed.append(PrayerEntry(date: slot.date, prayer: entry.prayer,
                                     elapsed: entry.elapsed, isAr: entry.isAr))
        }
    }
    return timed.map { entry in
        var e = entry
        e.periodKey = prayerPeriodKey(at: e.date, slots: slots)
        return e
    }
}

