import Flutter
import Foundation
import HealthKit

// Step totals per calendar day, asked of HealthKit the way the Health app
// asks. The Dart half is HealthStepsService.stepsForDays in
// lib/core/services/health_steps_service.dart.
//
// Why not the health plugin's getTotalStepsInInterval, which the app read
// through before: its predicate is .strictStartDate, so a sample that starts
// before midnight and ends after it never reaches the later day, and it cuts
// the sum with Int() instead of rounding it. Each of those can leave a day a
// few steps away from what the Health app shows for it, and a past day's
// count is only worth showing if it is THAT number (Aziz, 2026-09-16: "it
// should match the health app 100%").
//
// So: one HKStatisticsCollectionQuery, .cumulativeSum, anchored at local
// midnight with a one CALENDAR day interval, over an overlap predicate with
// no strict options. The statistics engine merges iPhone and Apple Watch and
// buckets a sample that crosses midnight itself, the same engine the Health
// app's day totals come from; nothing here second-guesses it.
// DateComponents(day: 1) rather than 86,400 seconds, so a daylight-saving
// day is 23 or 25 hours long here exactly as it is there.
//
// The day is passed as year/month/day rather than an instant, so the Dart
// side and this side cannot disagree about which midnight is meant, and the
// answer is a plain array (index 0 is the first day) so no date key is ever
// formatted in a locale that might write it in Arabic-Indic digits.
//
// Read permission comes from the health plugin's authorization request; it
// is the same app and the same HealthKit grant, so this file asks for
// nothing. A denied read answers zeros, exactly as the plugin's did (Apple
// hides read denials by design, see HealthStepsService.hasReadPermission).
enum HealthStepsBridge {
  static let channelName = "com.growdaily.v2/health_steps"

  /// Longest range one call may ask for. The app asks for a week at a time;
  /// this only keeps a bad argument from scanning years of samples.
  private static let maxDays = 400

  private static let store = HKHealthStore()

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "stepsByDay" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let year = args["year"] as? Int,
            let month = args["month"] as? Int,
            let day = args["day"] as? Int,
            let days = args["days"] as? Int,
            days > 0, days <= maxDays
      else {
        result(FlutterError(code: "BAD_ARGS", message: "stepsByDay needs year, month, day and 1...\(maxDays) days", details: nil))
        return
      }
      stepsByDay(year: year, month: month, day: day, days: days, result: result)
    }
  }

  private static func stepsByDay(year: Int, month: Int, day: Int, days: Int,
                                 result: @escaping FlutterResult) {
    guard HKHealthStore.isHealthDataAvailable(),
          let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)
    else {
      result(FlutterError(code: "UNAVAILABLE", message: "HealthKit is not available", details: nil))
      return
    }
    let calendar = Calendar.current
    guard let start = calendar.date(from: DateComponents(year: year, month: month, day: day)),
          let end = calendar.date(byAdding: .day, value: days, to: start)
    else {
      result(FlutterError(code: "BAD_ARGS", message: "not a calendar day", details: nil))
      return
    }
    let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
    let query = HKStatisticsCollectionQuery(
      quantityType: stepType,
      quantitySamplePredicate: predicate,
      options: .cumulativeSum,
      anchorDate: start,
      intervalComponents: DateComponents(day: 1)
    )
    query.initialResultsHandler = { _, collection, error in
      guard let collection = collection else {
        // Most often the phone is locked: HealthKit's store is encrypted
        // then and refuses every query. The Dart side reads this as a
        // failed read, never as a day with no steps.
        let message = error?.localizedDescription ?? "no statistics"
        DispatchQueue.main.async {
          result(FlutterError(code: "HEALTHKIT", message: message, details: nil))
        }
        return
      }
      var totals = [Int]()
      totals.reserveCapacity(days)
      for offset in 0..<days {
        guard let dayStart = calendar.date(byAdding: .day, value: offset, to: start) else {
          totals.append(0)
          continue
        }
        let sum = collection.statistics(for: dayStart)?.sumQuantity()?
          .doubleValue(for: HKUnit.count()) ?? 0
        totals.append(Int(sum.rounded()))
      }
      DispatchQueue.main.async {
        result(totals)
      }
    }
    store.execute(query)
  }
}
