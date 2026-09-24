//
//  TaskReminderStandDown.swift
//  GrowDailyWidget
//
//  Which reminders a task finished from outside the app takes down with it:
//  the Matrix widget's checkmark (MarkTaskDoneIntent in GrowDailyWidget
//  .swift) and «خلّصت المهمة» on a ringing task alarm
//  (MarkAlarmTargetDoneIntent in GrowDailyAlarmLiveActivity.swift, copied in
//  ios/Runner/AlarmKitBridge.swift for the app's own process). Foundation
//  only, like HabitReminderStandDown.swift beside it, so the rule can be
//  compiled and checked against the Dart encoder on a Mac.
//
//  The app writes the record beside the widget's task rows
//  (lib/core/services/armed_task_record.dart): for each task with a reminder
//  set, every id its reminders can be sitting under. The ids are folds of
//  Dart's String.hashCode, which this side cannot reproduce, so it reads them
//  rather than guessing.
//
//  Simpler than the habit rule next door, and deliberately so. A task's
//  reminders are one-shot moments picked for that one task, so there is no
//  day to file them under, nothing to keep for tomorrow and nothing shared
//  with another task: finishing it takes down everything it holds, which is
//  what NotificationService.cancelTaskReminder does from inside the app.
//

import Foundation

/// The JSON the app writes under `armedTaskRemindersJson`.
struct ArmedTaskRecord: Decodable {
    struct Task: Decodable {
        var notifications: [Int]?
        /// Present only for a task the person asked to ring as an alarm, and
        /// then holding the same ids as `notifications`: AlarmKit takes the
        /// slot when it can, and the app falls back to a plain notification
        /// under the same id when it cannot (below iOS 26, or permission
        /// refused), which is not knowable from the record.
        var alarms: [Int]?
    }

    /// ArmedTaskRecord.version on the Dart side. A record of any other
    /// version reads as no record at all.
    static let version = 1

    var v: Int
    var tasks: [String: Task]?
}

/// What a tap that finishes [taskId] takes down, read from [recordJSON]; nil
/// when there is no record to read (no push has written one yet, it does not
/// decode, or it is another version), in which case nothing of the task's is
/// touched and the app's next open stands it down, as it always did.
///
/// A task the record does not name stands down nothing, which is an answer
/// rather than a failure: the record names every task with a reminder set, so
/// one it leaves out has nothing armed to take down.
func taskReminderStandDown(recordJSON: String?, taskId: String) -> ReminderStandDown? {
    guard let data = recordJSON?.data(using: .utf8),
          let record = try? JSONDecoder().decode(ArmedTaskRecord.self, from: data),
          record.v == ArmedTaskRecord.version
    else { return nil }
    let task = record.tasks?[taskId]
    return ReminderStandDown(
        notificationIds: Set(task?.notifications ?? []).sorted().map(String.init),
        alarmSlots: Set(task?.alarms ?? []).sorted())
}
