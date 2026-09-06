import Flutter
import Foundation
import UIKit
import WidgetKit
import AlarmKit
import AppIntents
import SwiftUI

// Real alarms for reminders, through Apple's AlarmKit (iOS 26 and newer).
// The Dart half is lib/core/services/alarm_service.dart; this file is the
// other end of its MethodChannel, plus the App Intent behind the Done button
// on the ringing screen.
//
// Alarm ids: the Dart side passes the integer id it uses for the same slot's
// notification, and the bridge folds it into a fixed-prefix UUID. Being
// deterministic is the point: a later schedule or cancel for the same slot
// needs no stored mapping, and switching a reminder between alarm and
// notification can always find the alarm to remove.
//
// Registered on the implicit engine from AppDelegate. Below iOS 26 every
// call answers "unsupported" so the Dart side falls back to notifications
// without ever touching an AlarmKit symbol.

enum AlarmKitBridge {
  static let channelName = "com.growdaily.v2/alarm"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    if #available(iOS 26.0, *) {
      AlarmKitBridgeImpl.observeAlarms(reportingTo: channel)
    }
    channel.setMethodCallHandler { call, result in
      if #available(iOS 26.0, *) {
        AlarmKitBridgeImpl.handle(call, result: result)
        return
      }
      switch call.method {
      case "isSupported", "requestAuthorization", "schedule":
        result(false)
      case "authorizationState":
        result("unsupported")
      case "cancel":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Rides along with the alarm so the Done intent and any future Live
/// Activity know what the alarm is about. `kind` is "habit" or "task".
@available(iOS 26.0, *)
struct GrowDailyAlarmMetadata: AlarmMetadata {
  let kind: String
  let targetId: String
  /// The ringing screen's words, kept here as well so the foreground
  /// hand-off below can show the same reminder without a lookup.
  let title: String
  let subtitle: String?
}

@available(iOS 26.0, *)
enum AlarmKitBridgeImpl {
  /// Same gold as the widget extension's brand palette, so the ringing
  /// screen's stop control reads as this app.
  static let tint = Color(red: 0xE4 / 255.0, green: 0xB4 / 255.0, blue: 0x5F / 255.0)

  /// Every schedule and cancel runs after the one before it, in call
  /// order. The app recomputes its reminders several times in a row on a
  /// resume, and each pass replaces a slot with cancel-then-schedule.
  /// Interleaved, the pairs collided inside mobiletimerd ("Not scheduling
  /// an alarm with a duplicate ID", seen live 2026-09-06 15:26) and the
  /// refused pass then cancelled the alarm the other had just made. Dart
  /// serialises its passes too; this keeps each pair whole regardless.
  /// Only ever touched from the platform thread, where the channel calls.
  private static var lane: Task<Void, Never> = Task {}

  private static func onLane(_ work: @escaping @Sendable () async -> Void) {
    let previous = lane
    lane = Task {
      await previous.value
      await work()
    }
  }

  static func handle(_ call: FlutterMethodCall, result rawResult: @escaping FlutterResult) {
    // Async work below resumes off the main thread; Flutter wants replies on it.
    let result: FlutterResult = { value in
      if Thread.isMainThread { rawResult(value) } else { DispatchQueue.main.async { rawResult(value) } }
    }
    switch call.method {
    case "isSupported":
      result(true)
    case "authorizationState":
      result(name(of: AlarmManager.shared.authorizationState))
    case "requestAuthorization":
      Task {
        do {
          let state = try await AlarmManager.shared.requestAuthorization()
          result(state == .authorized)
        } catch {
          NSLog("[AlarmKitBridge] authorization request failed: \(error)")
          result(false)
        }
      }
    case "schedule":
      guard let args = call.arguments as? [String: Any],
            let id = args["id"] as? Int,
            let fireAtMs = args["fireAtMs"] as? Double ?? (args["fireAtMs"] as? Int).map(Double.init),
            let title = args["title"] as? String,
            let kind = args["kind"] as? String,
            let targetId = args["targetId"] as? String,
            let doneLabel = args["doneLabel"] as? String
      else {
        result(false)
        return
      }
      let subtitle = args["subtitle"] as? String
      let stopLabel = args["stopLabel"] as? String ?? "Stop"
      onLane {
        result(await schedule(
          id: id,
          fireAt: Date(timeIntervalSince1970: fireAtMs / 1000),
          title: title,
          subtitle: subtitle,
          kind: kind,
          targetId: targetId,
          doneLabel: doneLabel,
          stopLabel: stopLabel))
      }
    case "cancel":
      guard let args = call.arguments as? [String: Any], let id = args["id"] as? Int else {
        result(nil)
        return
      }
      onLane {
        try? AlarmManager.shared.cancel(id: alarmId(for: id))
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// iOS shows no alarm while the app that owns it is in front ("can
  /// present alert: NO, isHostApplicationForeground: YES" in SpringBoard's
  /// log, seen live on 2026-09-06 when a test alarm fired with the app
  /// open). The alarm just sits alerting, silently. So the app watches its
  /// own alarms and, when one starts alerting while the app is active,
  /// stops it and hands the moment to Dart, which shows the same reminder
  /// as a notification banner with the same buttons. In the background
  /// nothing is done here: the system's ringing screen is the right thing
  /// and this must not cut it short.
  static func observeAlarms(reportingTo channel: FlutterMethodChannel) {
    Task {
      var reported = Set<UUID>()
      for await alarms in AlarmManager.shared.alarmUpdates {
        let alerting = alarms.filter { $0.state == .alerting }
        reported = reported.intersection(alerting.map(\.id))
        for alarm in alerting where !reported.contains(alarm.id) {
          let active = await MainActor.run { UIApplication.shared.applicationState == .active }
          guard active else { continue }
          reported.insert(alarm.id)
          try? AlarmManager.shared.stop(id: alarm.id)
          let slot = slotId(for: alarm.id)
          await MainActor.run {
            channel.invokeMethod("alarmAlertingInForeground", arguments: [
              "id": slot as Any,
              "alarmId": alarm.id.uuidString,
            ])
          }
        }
      }
    }
  }

  /// The inverse of [alarmId(for:)]: the slot id folded into the UUID, or
  /// nil for an alarm this app did not make.
  static func slotId(for uuid: UUID) -> Int? {
    let text = uuid.uuidString
    guard text.hasPrefix("47524F57-4441-494C-5900-"),
          let low = UInt64(text.suffix(12), radix: 16)
    else { return nil }
    return Int(low)
  }

  static func name(of state: AlarmManager.AuthorizationState) -> String {
    switch state {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unknown"
    }
  }

  /// The slot's integer id as a UUID with a fixed prefix, see the file
  /// comment. 48 bits of id is far more than any slot band uses.
  static func alarmId(for id: Int) -> UUID {
    let low = UInt64(bitPattern: Int64(id)) & 0xFFFF_FFFF_FFFF
    return UUID(uuidString: String(format: "47524F57-4441-494C-5900-%012llX", low))!
  }

  static func schedule(
    id: Int, fireAt: Date, title: String, subtitle: String?,
    kind: String, targetId: String, doneLabel: String, stopLabel: String
  ) async -> Bool {
    let manager = AlarmManager.shared
    guard manager.authorizationState == .authorized else { return false }
    // AlarmKit refuses a moment in the past; a slot that already went by is
    // the notification schedule's business (see the catch-up there), not ours.
    guard fireAt > Date() else { return false }

    // The system draws this button as a circle filled with the tint, so
    // the mark on it is the dark surface green from the widget palette
    // rather than white, which vanished on gold.
    let done = AlarmButton(
      text: LocalizedStringResource(stringLiteral: doneLabel),
      textColor: Color(red: 0x10 / 255.0, green: 0x1B / 255.0, blue: 0x17 / 255.0),
      systemImageName: "checkmark")
    // Only the second button is really ours: Done, which records the habit
    // or task through MarkAlarmTargetDoneIntent below. From iOS 26.1 the
    // stop control is the system's own, localized by iOS; 26.0 still wants
    // one from the app, in the app's language.
    let alert: AlarmPresentation.Alert
    if #available(iOS 26.1, *) {
      alert = AlarmPresentation.Alert(
        title: LocalizedStringResource(stringLiteral: title),
        secondaryButton: done,
        secondaryButtonBehavior: .custom)
    } else {
      alert = AlarmPresentation.Alert(
        title: LocalizedStringResource(stringLiteral: title),
        stopButton: AlarmButton(
          text: LocalizedStringResource(stringLiteral: stopLabel),
          textColor: .white,
          systemImageName: "stop.fill"),
        secondaryButton: done,
        secondaryButtonBehavior: .custom)
    }
    let attributes = AlarmAttributes<GrowDailyAlarmMetadata>(
      presentation: AlarmPresentation(alert: alert),
      metadata: GrowDailyAlarmMetadata(
        kind: kind, targetId: targetId, title: title, subtitle: subtitle),
      tintColor: tint)
    let alarmId = alarmId(for: id)
    let configuration = AlarmManager.AlarmConfiguration<GrowDailyAlarmMetadata>.alarm(
      schedule: .fixed(fireAt),
      attributes: attributes,
      stopIntent: nil,
      secondaryIntent: MarkAlarmTargetDoneIntent(
        kind: kind, targetId: targetId, alarmId: alarmId.uuidString),
      sound: .default)
    // Replace rather than duplicate: the same slot rescheduled (a recompute
    // after any change) must end up with exactly one alarm.
    try? manager.cancel(id: alarmId)
    do {
      _ = try await manager.schedule(id: alarmId, configuration: configuration)
      return true
    } catch {
      NSLog("[AlarmKitBridge] schedule \(id) failed: \(error)")
      return false
    }
  }
}

/// The Stop button of the alarm's Live Activity banner (the full-screen
/// alert has the system's own). Copy in GrowDailyAlarmLiveActivity.swift.
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

/// The Done button on a ringing alarm. Runs in the app's process, with the
/// app possibly not running, so it does the one thing that is safe without
/// the app's state: it queues the completion in the App Group store the way
/// the home screen widget's Mark Done and a background notification tap do,
/// and the app pays the reward through its normal path at the next open.
/// Habits go into the day-stamped notification-action queue
/// (pendingNotificationActions, drained by main.dart), tasks into the
/// widget's task queue (pendingWidgetTaskCompletions).
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

/// The App Group writes behind the Done button. Key names and JSON shapes
/// must match lib/core/services/home_widget_service.dart and
/// notification_action_queue.dart exactly, and the today-list flip mirrors
/// MarkHabitDoneIntent in GrowDailyWidget.swift.
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

  /// Today's date key the way the Dart side writes it: the local calendar
  /// day in Western digits. The app's effective day rolls at midnight, so
  /// the calendar day at the tap is the day the tap belongs to.
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
    // Same ceiling as NotificationActionRules.maxQueued, oldest first out.
    if queue.count > 200 { queue.removeFirst(queue.count - 200) }
    writeJSON(queue, to: "pendingNotificationActions", in: defaults)
  }

  static func appendTaskCompletion(_ taskId: String, to defaults: UserDefaults) {
    var queue = readJSONArray("pendingWidgetTaskCompletions", from: defaults)
    let ids = queue.compactMap { $0 as? String }
    if ids.contains(taskId) { return }
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
