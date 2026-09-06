//
//  GrowDailyAlarmLiveActivity.swift
//  GrowDailyWidget
//
//  The Live Activity behind a ringing alarm. AlarmKit (iOS 26+) draws every
//  alarm through a Live Activity of the app's own widget extension: the
//  full-screen alert, the Lock Screen banner and the Dynamic Island all hang
//  off this one ActivityConfiguration, and without it SpringBoard refuses to
//  alert at all ("this activity can't be alerted on this device", seen live
//  on 2026-09-06 with an alarm the daemon had fired correctly). The app
//  schedules alarms from ios/Runner/AlarmKitBridge.swift; this file only
//  renders them.
//
//  The metadata struct is a copy of the one in AlarmKitBridge.swift. Live
//  Activities match their attributes by type NAME, so the copy must keep the
//  same name and fields, and both must change together.
//

import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 26.0, *)
struct GrowDailyAlarmMetadata: AlarmMetadata {
    let kind: String
    let targetId: String
    let title: String
    let subtitle: String?
}

@available(iOS 26.0, *)
struct GrowDailyAlarmLiveActivity: Widget {
    /// GameColors.gold, same literal as the Home Screen widgets' gdGold.
    private static let gold = Color(red: 0xE4 / 255.0, green: 0xB4 / 255.0, blue: 0x5F / 255.0)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<GrowDailyAlarmMetadata>.self) { context in
            lockScreen(attributes: context.attributes, state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    title(attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    controls(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            }
            .keylineTint(context.attributes.tintColor)
        }
    }

    /// Lock Screen and Notification Center banner: the habit or task name,
    /// a small alarm mark in the brand gold, and the controls.
    private func lockScreen(
        attributes: AlarmAttributes<GrowDailyAlarmMetadata>,
        state: AlarmPresentationState
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            title(attributes: attributes)
            controls(attributes: attributes, state: state)
        }
        .padding(14)
        // The app's dark card behind the banner, so it reads as Grow Daily
        // beside the system's own notifications.
        .activityBackgroundTint(Color(red: 0x10 / 255.0, green: 0x1B / 255.0, blue: 0x17 / 255.0).opacity(0.92))
        .activitySystemActionForegroundColor(Self.gold)
    }

    /// Stop, and the Done the app configured. Both run intents declared
    /// below; the alarm's own id rides in the activity's alarmID so the
    /// buttons know which alarm to stop.
    @ViewBuilder
    private func controls(
        attributes: AlarmAttributes<GrowDailyAlarmMetadata>,
        state: AlarmPresentationState
    ) -> some View {
        let alarmId = state.alarmID.uuidString
        HStack(spacing: 10) {
            Button(intent: StopGrowDailyAlarmIntent(alarmId: alarmId)) {
                Label {
                    Text(attributes.presentation.alert.stopButton.text)
                } icon: {
                    Image(systemName: "stop.fill")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .tint(.secondary)
            if let done = attributes.presentation.alert.secondaryButton,
               let metadata = attributes.metadata {
                Button(intent: MarkAlarmTargetDoneIntent(
                    kind: metadata.kind, targetId: metadata.targetId, alarmId: alarmId)) {
                    Label {
                        Text(done.text)
                    } icon: {
                        Image(systemName: "checkmark")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .tint(Self.gold)
            }
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
    }

    @ViewBuilder
    private func title(attributes: AlarmAttributes<GrowDailyAlarmMetadata>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "alarm.fill")
                .foregroundStyle(attributes.tintColor)
            Text(attributes.presentation.alert.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - The buttons' intents
//
// Same names, parameters and identifiers as the copies in
// ios/Runner/AlarmKitBridge.swift: a Live Activity intent is resolved by
// its type name, and iOS runs it in whichever process it can, so both copies
// do the same work. Keep them in step.

@available(iOS 26.0, *)
struct StopGrowDailyAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop alarm"
    static var description = IntentDescription("Stops a ringing Grow Daily alarm.")

    @Parameter(title: "Alarm")
    var alarmId: String

    init() { alarmId = "" }
    init(alarmId: String) { self.alarmId = alarmId }

    func perform() async throws -> some IntentResult {
        if let uuid = UUID(uuidString: alarmId) {
            try? AlarmManager.shared.stop(id: uuid)
        }
        return .result()
    }
}

@available(iOS 26.0, *)
struct MarkAlarmTargetDoneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Mark done"
    static var description = IntentDescription("Records the habit or task behind an alarm as done.")

    @Parameter(title: "Kind")
    var kind: String

    @Parameter(title: "Target")
    var targetId: String

    @Parameter(title: "Alarm")
    var alarmId: String

    init() {
        kind = ""
        targetId = ""
        alarmId = ""
    }

    init(kind: String, targetId: String, alarmId: String) {
        self.kind = kind
        self.targetId = targetId
        self.alarmId = alarmId
    }

    func perform() async throws -> some IntentResult {
        if let uuid = UUID(uuidString: alarmId) {
            try? AlarmManager.shared.stop(id: uuid)
        }
        AlarmDoneQueue.record(kind: kind, targetId: targetId)
        return .result()
    }
}

/// Copy of AlarmDoneQueue in ios/Runner/AlarmKitBridge.swift, see the note
/// above the intents. Keys and shapes match lib/core/services/
/// home_widget_service.dart and notification_action_queue.dart.
enum AlarmDoneQueue {
    static let appGroupId = "group.com.growdaily.v2.widget"

    static func record(kind: String, targetId: String) {
        guard !targetId.isEmpty, let defaults = UserDefaults(suiteName: appGroupId) else { return }
        switch kind {
        case "habit":
            appendHabitTap(targetId, to: defaults)
            markHabitDoneInTodayList(targetId, in: defaults)
        case "task":
            appendTaskCompletion(targetId, to: defaults)
        default:
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static func appendHabitTap(_ habitId: String, to defaults: UserDefaults) {
        var queue = readJSONArray("pendingNotificationActions", from: defaults)
        queue.append(["action": "mark_done", "habitId": habitId, "day": todayKey()])
        if queue.count > 200 { queue.removeFirst(queue.count - 200) }
        writeJSON(queue, to: "pendingNotificationActions", in: defaults)
    }

    static func appendTaskCompletion(_ taskId: String, to defaults: UserDefaults) {
        var queue = readJSONArray("pendingWidgetTaskCompletions", from: defaults)
        if queue.compactMap({ $0 as? String }).contains(taskId) { return }
        queue.append(taskId)
        writeJSON(queue, to: "pendingWidgetTaskCompletions", in: defaults)
    }

    static func markHabitDoneInTodayList(_ habitId: String, in defaults: UserDefaults) {
        var list = readJSONArray("todayHabitsJson", from: defaults)
        var changed = false
        for i in list.indices {
            guard var entry = list[i] as? [String: Any], entry["id"] as? String == habitId else { continue }
            entry["done"] = true
            if let perDay = entry["perDay"] as? Int { entry["count"] = perDay }
            list[i] = entry
            changed = true
        }
        if changed { writeJSON(list, to: "todayHabitsJson", in: defaults) }
    }

    static func readJSONArray(_ key: String, from defaults: UserDefaults) -> [Any] {
        guard let raw = defaults.string(forKey: key), let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return [] }
        return parsed
    }

    static func writeJSON(_ value: [Any], to key: String, in defaults: UserDefaults) {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let string = String(data: data, encoding: .utf8)
        else { return }
        defaults.set(string, forKey: key)
    }
}
