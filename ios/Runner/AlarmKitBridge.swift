import Flutter
import Foundation
import UIKit
import WidgetKit
import AlarmKit
import AppIntents
import SwiftUI

// Real alarms for reminders, through Apple's AlarmKit (iOS 26 and newer).
// The Dart half is lib/core/services/alarm_service.dart; this file is the
// other end of its MethodChannel, plus the intents behind the ringing
// screen's buttons. A habit's alarm carries Stop only, a task's also carries
// «خلّصت المهمة»; see schedule().
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
      case "cancel", "syncWindow":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Rides along with the alarm so its Live Activity and the foreground
/// hand-off know what the alarm is about. `kind` is "habit" or "task".
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
            let targetId = args["targetId"] as? String
      else {
        result(false)
        return
      }
      let subtitle = args["subtitle"] as? String
      let doneLabel = args["doneLabel"] as? String
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
        AlarmSlotRecords.forget(slot: id)
        result(nil)
      }
    case "syncWindow":
      guard let args = call.arguments as? [String: Any],
            let low = args["lowId"] as? Int,
            let high = args["highId"] as? Int,
            let raw = args["alarms"] as? [Any]
      else {
        result(nil)
        return
      }
      let items = raw.compactMap { entry in
        (entry as? [String: Any]).flatMap { AlarmWindowItem($0) }
      }
      onLane {
        result(await syncWindow(low: low, high: high, items: items))
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
    kind: String, targetId: String, doneLabel: String? = nil, stopLabel: String,
    signature: String? = nil
  ) async -> Bool {
    let manager = AlarmManager.shared
    guard manager.authorizationState == .authorized else { return false }
    // AlarmKit refuses a moment in the past; a slot that already went by is
    // the notification schedule's business (see the catch-up there), not ours.
    guard fireAt > Date() else { return false }

    // A habit's alarm carries Stop only. It wakes the person, often well
    // before the habit itself, and the habit is recorded in the app (Aziz,
    // 2026-09-11), so nothing is marked done from its ringing screen and the
    // next alarm of the same habit still rings. A task's alarm also carries
    // Done, which the Dart side labels «خلّصت المهمة» so it says what it
    // records, and sends for tasks only. The system draws that button as a
    // circle filled with the tint, so its mark is the dark surface green from
    // the widget palette rather than white, which vanished on gold.
    let done = doneLabel.map { label in
      AlarmButton(
        text: LocalizedStringResource(stringLiteral: label),
        textColor: Color(red: 0x10 / 255.0, green: 0x1B / 255.0, blue: 0x17 / 255.0),
        systemImageName: "checkmark")
    }
    let doneBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior? =
      done == nil ? nil : .custom
    // From iOS 26.1 the stop control is the system's own, localized by iOS;
    // 26.0 still wants one from the app, in the app's language.
    let alert: AlarmPresentation.Alert
    if #available(iOS 26.1, *) {
      alert = AlarmPresentation.Alert(
        title: LocalizedStringResource(stringLiteral: title),
        secondaryButton: done,
        secondaryButtonBehavior: doneBehavior)
    } else {
      alert = AlarmPresentation.Alert(
        title: LocalizedStringResource(stringLiteral: title),
        stopButton: AlarmButton(
          text: LocalizedStringResource(stringLiteral: stopLabel),
          textColor: .white,
          systemImageName: "stop.fill"),
        secondaryButton: done,
        secondaryButtonBehavior: doneBehavior)
    }
    let attributes = AlarmAttributes<GrowDailyAlarmMetadata>(
      presentation: AlarmPresentation(alert: alert),
      metadata: GrowDailyAlarmMetadata(
        kind: kind, targetId: targetId, title: title, subtitle: subtitle),
      tintColor: tint)
    let alarmId = alarmId(for: id)
    // Done runs MarkAlarmTargetDoneIntent below; no Done, no second intent.
    var doneIntent: (any LiveActivityIntent)?
    if done != nil {
      doneIntent = MarkAlarmTargetDoneIntent(
        kind: kind, targetId: targetId, alarmId: alarmId.uuidString)
    }
    let configuration = AlarmManager.AlarmConfiguration<GrowDailyAlarmMetadata>.alarm(
      schedule: .fixed(fireAt),
      attributes: attributes,
      stopIntent: nil,
      secondaryIntent: doneIntent,
      sound: .default)
    // Replace rather than duplicate: the same slot rescheduled (a recompute
    // after any change) must end up with exactly one alarm.
    try? manager.cancel(id: alarmId)
    do {
      _ = try await manager.schedule(id: alarmId, configuration: configuration)
      AlarmSlotRecords.remember(
        slot: id, uuid: alarmId, kind: kind, targetId: targetId,
        fireAt: fireAt, signature: signature)
      return true
    } catch {
      NSLog("[AlarmKitBridge] schedule \(id) failed: \(error)")
      AlarmSlotRecords.forget(slot: id)
      return false
    }
  }

  /// NotificationService._syncAlarmWindow's other end: every alarm in
  /// [low]...[high] ends up exactly what [items] says, in one pass.
  ///
  /// What the range holds and [items] no longer names is cancelled first,
  /// which is how a deleted habit's month of alarms goes away. What [items]
  /// names is scheduled, unless an alarm at the same moment with the same
  /// words is already armed under that id, so a resume that changes nothing
  /// schedules nothing. "Holds" is what AlarmKit lists joined with what this
  /// bridge recorded scheduling, so a failed listing still cancels; "already
  /// armed" needs both: listed at that moment, and recorded with those words.
  static func syncWindow(low: Int, high: Int, items: [AlarmWindowItem]) async -> [String: Int] {
    let manager = AlarmManager.shared
    var listed: [Int: Date] = [:]
    for alarm in (try? manager.alarms) ?? [] {
      guard let slot = slotId(for: alarm.id), slot >= low, slot <= high,
            case .fixed(let date)? = alarm.schedule
      else { continue }
      listed[slot] = date
    }
    let wanted = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var counts = ["scheduled": 0, "kept": 0, "cancelled": 0, "failed": 0]
    for slot in Set(listed.keys).union(AlarmSlotRecords.slots(in: low...high))
    where wanted[slot] == nil {
      try? manager.cancel(id: alarmId(for: slot))
      AlarmSlotRecords.forget(slot: slot)
      counts["cancelled", default: 0] += 1
    }
    for item in wanted.values.sorted(by: { $0.fireAt < $1.fireAt })
    where item.id >= low && item.id <= high {
      if let date = listed[item.id], abs(date.timeIntervalSince(item.fireAt)) < 1,
         AlarmSlotRecords.signature(slot: item.id) == item.signature {
        counts["kept", default: 0] += 1
        continue
      }
      let armed = await schedule(
        id: item.id, fireAt: item.fireAt, title: item.title, subtitle: item.subtitle,
        kind: item.kind, targetId: item.targetId,
        stopLabel: item.stopLabel, signature: item.signature)
      counts[armed ? "scheduled" : "failed", default: 0] += 1
    }
    return counts
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

/// The Done button on a task's ringing alarm, «خلّصت المهمة». Runs in the
/// app's process, with the app possibly not running, so it does the one thing
/// that is safe without the app's state: it stops the alarm and queues the
/// completion in the App Group store the way the Home Screen widget's task
/// checkmark does, and main.dart ticks the task through its normal path at
/// the next open (_processPendingWidgetTaskCompletions, which skips a task
/// already done or deleted).
///
/// A habit is never recorded here. Habit alarms carry Stop only since
/// 2026-09-11 (Aziz's call: the alarm wakes the person, and a tap on it must
/// not mark the habit done), but an alarm armed by an earlier build still
/// names this intent as its second button until the app's next open re-arms
/// it without one, so for a habit it only stops. Copy in
/// GrowDailyAlarmLiveActivity.swift.
@available(iOS 26.0, *)
struct MarkAlarmTargetDoneIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Mark task done"
  static var description = IntentDescription("Stops a ringing Grow Daily alarm and records its task as done.")

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
    if kind == "task" {
      AlarmDoneQueue.recordTask(targetId)
    }
    return .result()
  }
}

/// The App Group write behind a task alarm's Done. The key name and JSON
/// shape must match lib/core/services/home_widget_service.dart exactly; it is
/// the same queue MarkTaskDoneIntent in GrowDailyWidget.swift appends to.
enum AlarmDoneQueue {
  static let appGroupId = "group.com.growdaily.v2.widget"

  static func recordTask(_ taskId: String) {
    guard !taskId.isEmpty, let defaults = UserDefaults(suiteName: appGroupId) else { return }
    var queue = readJSONArray("pendingWidgetTaskCompletions", from: defaults)
    if !queue.compactMap({ $0 as? String }).contains(taskId) {
      queue.append(taskId)
      writeJSON(queue, to: "pendingWidgetTaskCompletions", in: defaults)
    }
    WidgetCenter.shared.reloadAllTimelines()
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

/// One alarm of the extended window, as NotificationService._syncAlarmWindow
/// sends it.
struct AlarmWindowItem: Sendable {
  let id: Int
  let fireAt: Date
  let title: String
  let subtitle: String?
  let kind: String
  let targetId: String
  let stopLabel: String

  init?(_ raw: [String: Any]) {
    guard let id = raw["id"] as? Int,
          let fireAtMs = raw["fireAtMs"] as? Double ?? (raw["fireAtMs"] as? Int).map(Double.init),
          let title = raw["title"] as? String,
          let kind = raw["kind"] as? String,
          let targetId = raw["targetId"] as? String
    else { return nil }
    self.id = id
    self.fireAt = Date(timeIntervalSince1970: fireAtMs / 1000)
    self.title = title
    self.subtitle = raw["subtitle"] as? String
    self.kind = kind
    self.targetId = targetId
    self.stopLabel = raw["stopLabel"] as? String ?? "Stop"
  }

  /// Everything rescheduling would change, so an alarm that matches can be
  /// left armed as it is.
  var signature: String {
    let ms = Int64((fireAt.timeIntervalSince1970 * 1000).rounded())
    return "\(ms)|\(title)|\(subtitle ?? "")|\(stopLabel)"
  }
}

/// What each alarm this app armed is about, one App Group key per slot id,
/// so the window sync can see what it armed even when AlarmKit cannot be
/// listed, and tell an alarm already armed with the same words from one that
/// needs arming again. Keyed by the fixed slot ids, so it never grows with the
/// days that pass: an id rescheduled overwrites its own record.
@available(iOS 26.0, *)
enum AlarmSlotRecords {
  static let prefix = "alarmSlot."
  static let appGroupId = "group.com.growdaily.v2.widget"

  private static var store: UserDefaults? {
    UserDefaults(suiteName: appGroupId)
  }

  static func remember(
    slot: Int, uuid: UUID, kind: String, targetId: String, fireAt: Date, signature: String?
  ) {
    store?.set(
      [
        "uuid": uuid.uuidString,
        "kind": kind,
        "targetId": targetId,
        "at": fireAt.timeIntervalSince1970,
        "sig": signature ?? "",
      ],
      forKey: prefix + String(slot))
  }

  static func forget(slot: Int) {
    store?.removeObject(forKey: prefix + String(slot))
  }

  static func signature(slot: Int) -> String? {
    store?.dictionary(forKey: prefix + String(slot))?["sig"] as? String
  }

  static func slots(in range: ClosedRange<Int>) -> [Int] {
    guard let all = store?.dictionaryRepresentation() else { return [] }
    return all.keys.compactMap { key in
      guard key.hasPrefix(prefix), let slot = Int(key.dropFirst(prefix.count)),
            range.contains(slot)
      else { return nil }
      return slot
    }
  }
}
