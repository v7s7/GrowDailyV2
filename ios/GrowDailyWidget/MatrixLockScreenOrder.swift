//
//  MatrixLockScreenOrder.swift
//  GrowDailyWidget
//
//  The order the Lock Screen task widget (GrowDailyMatrixLockScreenWidget in
//  GrowDailyWidget.swift) reads its tasks in. Foundation only, so the rule
//  can be compiled and checked on its own, away from WidgetKit.
//
//  The app sends the board in its own order: Do First, Schedule, Delegate,
//  Eliminate, and the board's own order inside each (main.dart's
//  _matrixWidgetSub). That order alone put a Do First task dated for next
//  week at the top of today's Lock Screen, above something due at 5 today.
//  So the Lock Screen sorts again, by each task's time, and keeps the app's
//  order for whatever the time leaves equal. It sorts here rather than in
//  Dart because which day a time falls on changes at midnight, when the app
//  is usually not running to write anything.
//

import Foundation

/// Which part of the Lock Screen list a task's time puts it in.
///
/// The time is the one the user picked (WidgetMatrixTask.dueAt, from
/// MatrixTask.reminderAnchorAt), not the earliest nudge in its stack: rent
/// due on the 30th with a warning on the 28th is the 30th's task, and the
/// warning is about it.
enum LockScreenBand: Int, Comparable {
    /// Its time falls on the day being drawn, passed or still to come.
    case today
    /// No reminder at all.
    case untimed
    /// Its time is on another day: a day already gone with the task still
    /// open, or a day still to come.
    case otherDay

    static func < (a: LockScreenBand, b: LockScreenBand) -> Bool {
        a.rawValue < b.rawValue
    }
}

/// Gregorian whatever the phone's own calendar, as the app's DateTime is.
/// Made fresh on each read rather than stored once: a calendar takes the
/// phone's time zone when it is made, and the extension can outlive a flight.
var lockScreenCalendar: Calendar { Calendar(identifier: .gregorian) }

extension WidgetMatrixTask {
    func lockScreenBand(on day: Date, calendar: Calendar = lockScreenCalendar) -> LockScreenBand {
        guard let due = dueAt else { return .untimed }
        return calendar.isDate(due, inSameDayAs: day) ? .today : .otherDay
    }

    /// Two tasks the user would both call "5:00" compare as equal, whatever
    /// their seconds, so the app's order decides between them. Same minute
    /// bucket as MatrixTask._sameMinute on the Dart side.
    fileprivate var dueMinute: Int64? {
        dueAtMs.map { Int64(($0 / 60_000).rounded(.down)) }
    }
}

extension Array where Element == WidgetMatrixTask {
    /// This list in the Lock Screen's reading order on [now]'s day:
    ///
    ///  1. Open before done. The app only sends open tasks; a done one here
    ///     was just ticked on the Home Screen widget (MarkTaskDoneIntent)
    ///     and waits at the bottom until the app next writes the list.
    ///  2. A time today, earliest first. One whose time has passed stays in
    ///     its place at the top: it is still today's, and still not done.
    ///  3. No time, in the app's order, so Do First (urgent and important)
    ///     leads.
    ///  4. A time on another day, earliest first, so a day already gone
    ///     comes before one still to come.
    ///
    /// Anything still equal keeps the app's order: a 5:00 in Do First
    /// before a 5:00 in Schedule.
    ///
    /// Starred is not a step here because it is not an order, it is what
    /// gets drawn: MatrixEntry.lockScreenTasks shows only the starred tasks
    /// when there are any, so they are always first, and this orders them
    /// among themselves.
    func inLockScreenOrder(on now: Date, calendar: Calendar = lockScreenCalendar) -> [WidgetMatrixTask] {
        enumerated()
            .map { (at: $0.offset, task: $0.element, band: $0.element.lockScreenBand(on: now, calendar: calendar)) }
            .sorted { a, b in
                if a.task.isDone != b.task.isDone { return !a.task.isDone }
                if a.band != b.band { return a.band < b.band }
                // A band never mixes timed and untimed tasks, so either both
                // sides have a minute here or neither does.
                if let x = a.task.dueMinute, let y = b.task.dueMinute, x != y { return x < y }
                return a.at < b.at
            }
            .map { $0.task }
    }
}
