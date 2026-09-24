//
//  HabitReminderStandDown.swift
//  GrowDailyWidget
//
//  Which of the app's reminders a habit ticked on the Home Screen widget
//  takes down with it. Foundation only, so the rule can be compiled and
//  checked on its own, away from WidgetKit; MarkHabitDoneIntent in
//  GrowDailyWidget.swift applies it.
//
//  The app writes the record after every reminder pass
//  (lib/core/services/armed_reminder_record.dart): for each habit, the ids of
//  every reminder it armed, filed under the day each one fires on. The ids are
//  Dart hashes this side cannot compute, and which id holds a given day's copy
//  depends on when the pass ran (today's copy is the next occurrence of its
//  slot when the pass ran this morning, the one after when it ran yesterday
//  before yesterday's reminder), so the widget reads them rather than
//  guessing. The rule must stay the one ArmedReminderRecord.standDownFor
//  applies on the Dart side for a lock screen or Watch «تمت».
//

import Foundation

/// The JSON the app writes under `armedHabitRemindersJson`.
struct ArmedReminderRecord: Decodable {
    struct Day: Decodable {
        var notifications: [Int]?
        var alarms: [Int]?
        var bundles: [Int]?
    }

    struct Habit: Decodable {
        /// The id a snooze of this habit sits under, pending or not.
        var snooze: Int?
        /// Day key ("2026-09-22") to what the pass armed for that day.
        var days: [String: Day]?
    }

    /// ArmedReminderRecord.version on the Dart side. A record of any other
    /// version reads as no record at all.
    static let version = 1

    var v: Int
    var habits: [String: Habit]?
    /// A bundle's id, as a string, to the habits it names.
    var bundles: [String: [String]]?
}

/// What one tap that finishes a habit, or a task, takes down. Shared with
/// TaskReminderStandDown.swift, and the shape of ReminderStandDown on the
/// Dart side (armed_reminder_record.dart).
struct ReminderStandDown: Equatable {
    /// Pending request identifiers. flutter_local_notifications names each
    /// request by its Dart id as a string (getIdentifier in its
    /// FlutterLocalNotificationsPlugin.m).
    var notificationIds: [String]
    /// The integer ids of alarms, turned into AlarmKit's by
    /// growDailyAlarmID(slot:).
    var alarmSlots: [Int]
}

/// What a tap that finishes [habitId] on [day] takes down, read from
/// [recordJSON]; nil when there is no record to read (no pass has written one
/// yet, it does not decode, or it is another version), in which case nothing
/// of the habit's is touched and the app's next open stands it down.
///
///  - The habit's own copies filed under [day], and only those: the copies for
///    later days are its next reminders, and a phone left closed after the
///    tap still has them.
///  - The habit's snooze, which was asked for about a habit now finished.
///  - A bundle filed under [day], only once every OTHER habit it names is in
///    [doneOnDay]: it is one notification for all of them, and taking it down
///    for one finished habit would silence another that is still owed.
func habitReminderStandDown(
    recordJSON: String?, habitId: String, day: String, doneOnDay: Set<String>
) -> ReminderStandDown? {
    guard let data = recordJSON?.data(using: .utf8),
          let record = try? JSONDecoder().decode(ArmedReminderRecord.self, from: data),
          record.v == ArmedReminderRecord.version
    else { return nil }
    let habit = record.habits?[habitId]
    let today = habit?.days?[day]
    var ids = Set(today?.notifications ?? [])
    if let snooze = habit?.snooze { ids.insert(snooze) }
    for bundle in today?.bundles ?? [] {
        guard let members = record.bundles?[String(bundle)] else { continue }
        if members.allSatisfy({ $0 == habitId || doneOnDay.contains($0) }) {
            ids.insert(bundle)
        }
    }
    return ReminderStandDown(
        notificationIds: ids.sorted().map(String.init),
        alarmSlots: Set(today?.alarms ?? []).sorted())
}

/// The habits the cached today-list shows done, when it is [day]'s list
/// (NotificationActionRules.doneOn on the Dart side). The list holds no date;
/// the app writes the day it was built for beside it as `todayHabitsDay`, and
/// a list from another day (the app last opened yesterday) carries that day's
/// checkmarks, so it answers empty rather than wrong.
func habitsDoneOn(day: String, todayListJSON: String?, listDay: String?) -> Set<String> {
    struct Row: Decodable {
        let id: String
        let done: Bool?
    }
    guard listDay == day,
          let data = todayListJSON?.data(using: .utf8),
          let rows = try? JSONDecoder().decode([Row].self, from: data)
    else { return [] }
    return Set(rows.filter { $0.done == true }.map(\.id))
}

/// [date]'s day the way the app keys its days (toDateKey on an effective day,
/// which rolls at midnight): Gregorian, Latin digits, "2026-09-22", whatever
/// the phone's own calendar and numerals. Built from components, never from a
/// DateFormatter, which takes the phone's locale and calendar and writes
/// «٢٠٢٦-٠٩-٢٢» or a Hijri year on an Arabic iPhone (see matrixDayKey).
func appDayKey(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
    let day = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04ld-%02ld-%02ld", day.year ?? 0, day.month ?? 0, day.day ?? 0)
}

/// The queue of taps waiting for the app's next open, with one more appended:
/// the action, the habit, and the DAY the tap was made on.
///
/// The shape is NotificationActionRules' (lib/core/services/
/// notification_action_queue.dart), the queue a lock screen or Watch «تمت»
/// already writes, so a tick here is drained by the same day-aware path: a day
/// still open is paid in full, a day that has closed gets its square and no
/// reward. The widget used to write a bare habit id to a queue of its own,
/// which the app could only credit to the day it drained on, so a tick at
/// 23:50 drained after 10:00 the next morning landed on the wrong day and left
/// the right one blank.
///
/// Trimmed from the front at [limit], NotificationActionRules.maxQueued, as
/// the Dart side trims. Entries the Dart side would drop are dropped here too,
/// so the count both sides trim by is the same. Nil only if the result cannot
/// be encoded, which leaves the caller its old queue to fall back on rather
/// than losing the tap.
func queueWithMarkDone(
    _ queueJSON: String?, habitId: String, day: String, limit: Int = 200
) -> String? {
    var queue: [[String: String]] = []
    if let data = queueJSON?.data(using: .utf8),
       let decoded = try? JSONSerialization.jsonObject(with: data) as? [Any] {
        for entry in decoded {
            guard let row = entry as? [String: Any],
                  let action = row["action"] as? String, !action.isEmpty,
                  let habit = row["habitId"] as? String, !habit.isEmpty,
                  let stamp = row["day"] as? String, !stamp.isEmpty
            else { continue }
            queue.append(["action": action, "habitId": habit, "day": stamp])
        }
    }
    queue.append(["action": "mark_done", "habitId": habitId, "day": day])
    if queue.count > limit {
        queue.removeFirst(queue.count - limit)
    }
    guard let data = try? JSONSerialization.data(withJSONObject: queue),
          let text = String(data: data, encoding: .utf8)
    else { return nil }
    return text
}

/// The AlarmKit id of the alarm the app armed under [slot]: a fixed prefix,
/// then the slot in the last 48 bits. A copy of AlarmKitBridgeImpl.alarmId(for:)
/// in ios/Runner/AlarmKitBridge.swift, which the app schedules and cancels by;
/// the two must stay the same, or the widget cancels ids nothing holds.
func growDailyAlarmID(slot: Int) -> UUID? {
    let low = UInt64(bitPattern: Int64(slot)) & 0xFFFF_FFFF_FFFF
    return UUID(uuidString: String(format: "47524F57-4441-494C-5900-%012llX", low))
}
