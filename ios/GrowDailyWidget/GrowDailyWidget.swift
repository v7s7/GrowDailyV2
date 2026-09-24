//
//  GrowDailyWidget.swift
//  GrowDailyWidget
//
//  Home Screen (small/medium/large) + Lock Screen widgets for GrowDaily,
//  plus the opt-in Room Race widget (separate kind — someone only sees it
//  if they explicitly add it from the widget gallery, per its own
//  .configurationDisplayName). See ios/WIDGET_SETUP.md for the original
//  target setup notes. This file owns the @main entry point
//  (GrowDailyWidgetBundle at the bottom) - the separate
//  GrowDailyWidgetBundle.swift Xcode generated is intentionally left empty
//  to avoid a duplicate @main.
//

import WidgetKit
import SwiftUI
import AppIntents
import UserNotifications
// iOS 26 and newer only, and every use is behind #available: the extension
// targets iOS 17, so the framework is weak-linked and absent below 26.
import AlarmKit

// Must match HomeWidgetService's _appGroupId exactly (lib/core/services/
// home_widget_service.dart) — this is how the widget reads what the Flutter
// app last saved, and how MarkHabitDoneIntent below writes back to it.
let appGroupId = "group.com.growdaily.v2.widget"

// MARK: - Brand colors
//
// Literal copies of lib/core/theme/theme_preset.dart's default preset (gold,
// streak/xp icon tints, dark surfaces) — a widget extension is a separate
// native target and can't import the Flutter app's Dart theme code, so
// these are hand-copied rather than shared. If the in-app default theme
// preset's hex values ever change, these fall out of sync until someone
// re-copies them here; there's no automatic link between the two. Picked
// over the plain SwiftUI semantic colors (.orange/.yellow/.green/
// systemBackground) the widget used before so it actually reads as
// GrowDaily's own dark/gold identity instead of a generic system widget.
/// Plain 0-255 → 0-1 conversion, spelled out with explicit Double(...)
/// rather than leaning on integer-literal-in-a-Double-context inference —
/// that inference is standard, correct Swift, but this file has no
/// compiler in the loop to confirm it against, and a silently-wrong
/// (Int-divided-to-zero) brand palette would be a much more annoying bug
/// to spot on-device than one extra helper function is to write.
private func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
    Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
}

extension Color {
    /// GameColors.background — default theme preset's darkBg.
    static let gdBg = rgb(0x07, 0x10, 0x0D)
    /// GameColors.surface — default theme preset's darkSurface. Used for
    /// inset rows/dividers so they read as a step up from the card bg.
    static let gdSurface = rgb(0x10, 0x1B, 0x17)
    /// GameColors.border — default theme preset's darkBorder.
    static let gdBorder = rgb(0x2D, 0x40, 0x37)
    /// GameColors.gold — default theme preset. Level/gold-coin accent.
    static let gdGold = rgb(0xE4, 0xB4, 0x5F)
    /// GameColors.iconStreak (theme-invariant const) — the flame.
    static let gdStreak = rgb(0xFF, 0x8A, 0x4C)
    /// GameColors.emerald — default theme preset. "Done"/complete green,
    /// matches the in-app Grid's own complete-square color exactly.
    static let gdEmerald = rgb(0x2E, 0xCF, 0x8F)
    /// GameColors.iconXp (theme-invariant const) — level/rank blue accent.
    static let gdXpBlue = rgb(0x5D, 0xAD, 0xEC)
    /// GameColors.warning (const) — partial/urgent amber.
    static let gdWarning = rgb(0xF7, 0xC9, 0x48)
    /// GameColors.error (const) — reserved for a future "falling behind"
    /// treatment; not used yet, kept alongside the rest of the palette so
    /// anyone adding one later reaches for this instead of a raw .red.
    static let gdError = rgb(0xFF, 0x5A, 0x52)
}


// MARK: - Shared data models

struct TodayHabit: Codable, Identifiable {
    let id: String
    let name: String
    var done: Bool

    /// Whether today asked for this habit at all. A flexible weekly quota
    /// ("4 times a week, any days") keeps its row on every day of the week,
    /// because any of them will do — but on the days its own week never
    /// needed, the row is an invitation, not an outstanding task, and it is
    /// left out of completedToday/totalToday (habitOwesDay /
    /// boardHabitsOn on the app side).
    ///
    /// Optional, and it must stay optional: a payload written before this
    /// existed has no such key, and a non-optional Bool would fail to decode
    /// the whole list and blank the widget. nil reads as "due", the way every
    /// row read before.
    var notDue: Bool? = nil

    /// Unlike `count`/`perDay`, which this struct does not carry and which
    /// MarkHabitDoneIntent's re-encode therefore drops, this survives that
    /// round trip — so a rest-day row tapped from the home screen does not
    /// come back as an outstanding one.
    var isDue: Bool { notDue != true }
}

struct HeatmapDay: Codable {
    let date: String
    let count: Int
}

private func readJSON<T: Decodable>(_ key: String, from defaults: UserDefaults?, as type: T.Type) -> T? {
    guard let raw = defaults?.string(forKey: key),
          let data = raw.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

private func writeJSON<T: Encodable>(_ value: T, to key: String, in defaults: UserDefaults?) {
    guard let data = try? JSONEncoder().encode(value),
          let string = String(data: data, encoding: .utf8) else { return }
    defaults?.set(string, forKey: key)
}

// MARK: - Timeline (daily progress)

struct GrowDailyEntry: TimelineEntry {
    let date: Date
    /// The language this face draws in, resolved once per entry — see
    /// WidgetStrings.swift for why it is carried rather than read per view.
    var copy: WidgetCopy = WidgetCopy(isAr: false)
    let streak: Int
    let level: Int
    let gold: Int
    let completedToday: Int
    let totalToday: Int
    let habits: [TodayHabit]
    let heatmap: [HeatmapDay]
}

struct GrowDailyProvider: TimelineProvider {
    func placeholder(in context: Context) -> GrowDailyEntry {
        GrowDailyEntry(date: Date(), streak: 3, level: 2, gold: 40, completedToday: 1, totalToday: 3,
                       habits: [TodayHabit(id: "1", name: "Fajr Dhikr", done: true),
                                TodayHabit(id: "2", name: "Read Quran", done: false)],
                       heatmap: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (GrowDailyEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GrowDailyEntry>) -> Void) {
        let entry = loadEntry()
        // Widgets don't get live pushes — this just tells iOS "check back
        // in an hour." The real refresh trigger is HomeWidgetService calling
        // updateWidget() from Flutter every time these numbers change, plus
        // the one guaranteed reload iOS gives a widget right after its own
        // AppIntent button finishes — this timeline is only the fallback
        // for while the app isn't open and nothing's been tapped.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> GrowDailyEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        return GrowDailyEntry(
            date: Date(),
            copy: WidgetCopy.fromDefaults(),
            streak: defaults?.integer(forKey: "streak") ?? 0,
            level: defaults?.integer(forKey: "level") ?? 1,
            gold: defaults?.integer(forKey: "gold") ?? 0,
            completedToday: defaults?.integer(forKey: "completedToday") ?? 0,
            totalToday: defaults?.integer(forKey: "totalToday") ?? 0,
            habits: readJSON("todayHabitsJson", from: defaults, as: [TodayHabit].self) ?? [],
            heatmap: readJSON("heatmapJson", from: defaults, as: [HeatmapDay].self) ?? []
        )
    }
}

// MARK: - Mark Done button

/// Backs the checkmark button on each habit row in the large widget.
/// Deliberately does *not* try to reach into the Flutter app or replicate
/// completeHabit's XP/streak/gold logic here — a widget's AppIntent runs in
/// its own process with none of that state, and getting a reward
/// calculation silently wrong in Swift no one can unit-test is worse than
/// just deferring it. Instead this only ever touches shared UserDefaults,
/// and what the app has pending about the habit:
///
///  1. Flips this habit's `done` flag in the cached today-list, so the one
///     reload iOS guarantees right after `perform()` returns shows it
///     checked immediately.
///  2. Appends the tap, with the DAY it was made on, to the queue a lock
///     screen «تمت» already writes (queueWithMarkDone).
///  3. When the tap finishes the habit for the day, removes the habit's own
///     reminders and alarms still to come today (standDownTodaysReminders),
///     so it does not ring for a habit already done, and the pending notes
///     that count finished habits (standDownNotesWithStaleCounts).
///
/// The Flutter app drains that queue (main.dart's
/// _processPendingNotificationActions, whenever the app comes to the
/// foreground) and runs it through the exact same completeHabit path a normal
/// in-app tap uses, on the day the tap names: a day still open is paid in
/// full, a day that has closed gets its square and no reward. That's the one
/// real reward — this button's own visual "done" state is provisional until
/// then.
struct MarkHabitDoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Habit Done"

    @Parameter(title: "Habit ID")
    var habitId: String

    init() {
        self.habitId = ""
    }

    init(habitId: String) {
        self.habitId = habitId
    }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroupId)
        // Decided before the list is rewritten: TodayHabit has no count
        // keys, so the rewrite below drops the ones this reads.
        let finishes = habitTapFinishesDay(habitId, in: defaults)
        // One clock reading for the whole tap: the day it is queued under and
        // the day whose reminders it takes down have to be the same day, even
        // if midnight falls between the two lines.
        let day = appDayKey(Date())

        if var habits = readJSON("todayHabitsJson", from: defaults, as: [TodayHabit].self) {
            for i in habits.indices where habits[i].id == habitId {
                habits[i].done = true
            }
            writeJSON(habits, to: "todayHabitsJson", in: defaults)
        }

        // The tap, with its day, in the queue the app drains day-aware. The
        // id-only queue below is what this wrote before that and is still
        // drained, so an encode that somehow failed would cost the tap its
        // day rather than the tap itself.
        if let queued = queueWithMarkDone(
            defaults?.string(forKey: "pendingNotificationActions"),
            habitId: habitId,
            day: day
        ) {
            defaults?.set(queued, forKey: "pendingNotificationActions")
        } else {
            var pending = readJSON("pendingWidgetCompletions", from: defaults, as: [String].self) ?? []
            if !pending.contains(habitId) {
                pending.append(habitId)
            }
            writeJSON(pending, to: "pendingWidgetCompletions", in: defaults)
        }

        if finishes {
            await standDownTodaysReminders(of: habitId, on: day, in: defaults)
            standDownNotesWithStaleCounts(includingFridayNote: true)
        }
        return .result()
    }
}

/// Takes down what the app armed to remind about [habitId] today, now that a
/// tap here has finished it: its own reminders still to come today, a pending
/// snooze, a bundle once every habit it names is done, and today's alarms.
/// The app would drop them itself at its next open; until then they rang for
/// a habit already ticked. The later days stay armed.
///
/// The ids come from the record the app's last reminder pass wrote beside the
/// today-list (habitReminderStandDown in HabitReminderStandDown.swift). With
/// no record, from a build before it, the habit's reminders are left to the
/// app, as they always were.
///
/// Pending requests only, the rule standDownNotesWithStaleCounts below
/// explains: a reminder already delivered was right when it came.
private func standDownTodaysReminders(
    of habitId: String, on day: String, in defaults: UserDefaults?
) async {
    guard let plan = habitReminderStandDown(
        recordJSON: defaults?.string(forKey: "armedHabitRemindersJson"),
        habitId: habitId,
        day: day,
        doneOnDay: habitsDoneOn(
            day: day,
            todayListJSON: defaults?.string(forKey: "todayHabitsJson"),
            listDay: defaults?.string(forKey: "todayHabitsDay")))
    else {
        NSLog("[GrowDailyWidget] %@ done, no reminder record: its reminders wait for the app", habitId)
        return
    }
    await applyStandDown(plan, subject: "\(habitId) done for \(day)")
}

/// Takes down what the app armed to remind about [taskId], now that a tap
/// here has finished it: every slot its reminders can be sitting under, as an
/// alarm or as a notification. A task is done once and for all, so unlike a
/// habit's there is no later copy to spare and no day to pick.
///
/// The ids come from the record the app wrote beside the widget's task rows
/// (taskReminderStandDown in TaskReminderStandDown.swift). With no record,
/// from a build before it, the task's reminders are left to the app, as they
/// always were: the tick is queued either way, and the next open cancels them
/// as part of completing the task.
///
/// Not private: the alarm's «خلّصت المهمة» calls this too, from
/// GrowDailyAlarmLiveActivity.swift.
func standDownTaskReminders(of taskId: String, in defaults: UserDefaults?) async {
    guard let plan = taskReminderStandDown(
        recordJSON: defaults?.string(forKey: "armedTaskRemindersJson"),
        taskId: taskId)
    else {
        NSLog("[GrowDailyWidget] task %@ done, no reminder record: its reminders wait for the app", taskId)
        return
    }
    await applyStandDown(plan, subject: "task \(taskId) done")
}

/// Removes [plan]'s pending notification requests and cancels its alarms, and
/// says in the log what it found. [subject] names what was finished, for that
/// log alone.
///
/// Pending requests only, the rule standDownNotesWithStaleCounts below
/// explains: a reminder already delivered was right when it came.
private func applyStandDown(_ plan: ReminderStandDown, subject: String) async {
    let center = UNUserNotificationCenter.current()
    // Read first only so the log below can say what the removal found.
    let wasPending = await center.pendingNotificationRequests()
        .filter { plan.notificationIds.contains($0.identifier) }.count
    if !plan.notificationIds.isEmpty {
        center.removePendingNotificationRequests(withIdentifiers: plan.notificationIds)
    }
    // An alarm that has already rung is gone from AlarmKit, and cancelling
    // it throws; that is the only reason one of these fails.
    var alarmsCancelled = 0
    if #available(iOS 26.0, *) {
        for slot in plan.alarmSlots {
            guard let id = growDailyAlarmID(slot: slot) else { continue }
            if (try? AlarmManager.shared.cancel(id: id)) != nil {
                alarmsCancelled += 1
            }
        }
    }
    // Read back over the same connection, so the removal has reached the
    // system before this process can be suspended, and so the log can say
    // what is left of it.
    let pending = await center.pendingNotificationRequests()
    let stillPending = pending.filter { plan.notificationIds.contains($0.identifier) }.count
    NSLog("[GrowDailyWidget] %@: %ld of %ld reminder id(s) were pending, %ld still are, of %ld the app holds; %ld of %ld alarm(s) cancelled",
          subject, wasPending, plan.notificationIds.count, stillPending, pending.count,
          alarmsCancelled, plan.alarmSlots.count)
}

/// The count keys the app writes on each entry of the cached today-list
/// (home_widget_service.dart). TodayHabit does not carry them, so they are
/// read on their own.
private struct TodayHabitCount: Decodable {
    let id: String
    let count: Int?
    let perDay: Int?
}

/// Whether one more completion of [habitId] finishes it for the day, by the
/// rule a lock-screen or Watch tap uses (NotificationActionRules.finishesDay
/// in notification_action_queue.dart): count + 1 reaches perDay. True when
/// that cannot be known, as there: no list, the habit absent, or its counts
/// missing, which is how a list this intent already re-encoded reads.
private func habitTapFinishesDay(_ habitId: String, in defaults: UserDefaults?) -> Bool {
    guard let list = readJSON("todayHabitsJson", from: defaults, as: [TodayHabitCount].self),
          let entry = list.first(where: { $0.id == habitId }),
          let count = entry.count,
          let perDay = entry.perDay else { return true }
    return count + 1 >= perDay
}

/// Removes the app's pending notes whose numbers a tap here has just made
/// false. Silence over a stale count, the rule a lock-screen or Watch tap
/// follows (notification_action_background.dart); the next app open arms
/// each again with true numbers.
///
/// flutter_local_notifications names each request by its Dart id as a
/// string (getIdentifier in its FlutterLocalNotificationsPlugin.m), so:
///   - "1010" is tonight's evening note, which counts today's finished
///     habits, the streak it is asking for, the quit habits still
///     unanswered and open Do First tasks. It was "8000", the streak note,
///     while that was a second banner of its own; the two merged into this
///     one id (NotificationService.scheduleEveningNote);
///   - "9001" is the week's numbered note, which counts the week's green
///     days. Only on a Friday on this device's clock, the window the app
///     arms it in (NotificationService.weeklyNumberedNoteAhead); it goes
///     out on the Saturday morning after, once the week has sealed.
///
/// Pending requests only: a note already delivered was true when it came and
/// stays in the notification list. That is the single rule on every path, and
/// the app's own two paths have to work for it: the plugin's cancel removes a
/// delivered notification beside a pending one on iOS, so the lock screen and
/// Watch path reads the pending list first before cancelling anything (see
/// NotificationService._cancelIfPending). Here it is free, because
/// removePendingNotificationRequests is already pending-only.
///
/// Apple documents UNUserNotificationCenter for app extensions as well as
/// apps, and on the simulator (2026-09-22) this extension read the app's own
/// pending requests, 42 of them, and its removal took: the ticked habit's
/// reminder for that day went, SpringBoard rescheduled its timer without it,
/// and nothing rang at the minute it had been due. Not yet on a device.
private func standDownNotesWithStaleCounts(includingFridayNote: Bool) {
    var identifiers = ["1010"]
    if includingFridayNote {
        // Gregorian whatever the device's own calendar, as the app's
        // DateTime is: weekday 6 is Friday, counting Sunday as 1. The whole
        // Friday, with no hour bound: the note does not fire until Saturday
        // morning, so a habit finished at 22:00 still changes what it says.
        let calendar = Calendar(identifier: .gregorian)
        if calendar.component(.weekday, from: Date()) == 6 {
            identifiers.append("9001")
        }
    }
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
}

// MARK: - Shared pieces

/// A hand-drawn flame silhouette (two cubic curves mirrored around a
/// center spine) instead of SF Symbol "flame.fill" — used on the Home
/// Screen faces only, see [FlameIcon]'s doc comment for why. Deliberately
/// simple geometry (one spine, two symmetric curves) rather than a more
/// elaborate multi-lobed flame: every point here is defined as a fraction
/// of [rect], so the same four curve calls stay a recognizable flame at a
/// 12pt lock-screen size or a 32pt small-widget size without needing
/// separate tuning per size — the risk of an elaborate hand-tuned path
/// looking right at one size and wrong at another isn't worth it when
/// there's no on-device preview to check against while writing this.
struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addCurve(
            to: CGPoint(x: w * 0.86, y: h * 0.62),
            control1: CGPoint(x: w * 0.86, y: h * 0.18),
            control2: CGPoint(x: w * 0.98, y: h * 0.42)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control1: CGPoint(x: w * 0.86, y: h * 0.86),
            control2: CGPoint(x: w * 0.68, y: h)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.14, y: h * 0.62),
            control1: CGPoint(x: w * 0.32, y: h),
            control2: CGPoint(x: w * 0.14, y: h * 0.86)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control1: CGPoint(x: w * 0.02, y: h * 0.38),
            control2: CGPoint(x: w * 0.5, y: h * 0.3)
        )
        path.closeSubpath()
        return path
    }
}

/// Two-tone [FlameShape] (outer streak-orange, smaller inner gold core) —
/// the vector alternative to a flame photo/illustration: no image asset,
/// no extra Xcode step, still reads as more "GrowDaily" than a stock SF
/// Symbol. Home Screen widgets only (Small/Medium/Large) — Lock Screen
/// accessory widgets keep the plain SF Symbol flame instead, since iOS
/// renders *those* in its own system tint/vibrancy mode and automatically
/// recolors SF Symbols to match; a custom Shape with a hardcoded fill
/// wouldn't get that same treatment and could clash with whatever tint the
/// system picks for a given wallpaper.
struct FlameIcon: View {
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            FlameShape()
                .fill(Color.gdStreak)
            FlameShape()
                .fill(Color.gdGold)
                .frame(width: size * 0.46, height: size * 0.58)
                .offset(y: size * 0.14)
        }
        .frame(width: size, height: size * 1.15)
    }
}

/// A subtle 8-point star (rub el hizb-style geometric motif) as a thin
/// stroked outline — pure decoration, meant to sit low-opacity in a
/// corner behind real content, never on top of it. Built from alternating
/// outer/inner radius points around a circle (standard N-point star
/// construction), not a traced/imported shape, so it's exact at any size
/// with no separate art asset.
struct EightPointStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.55
        let points = 8
        var path = Path()
        for i in 0..<(points * 2) {
            let angle = (Double(i) * .pi / Double(points)) - .pi / 2
            let radius = i.isMultiple(of: 2) ? outerRadius : innerRadius
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

/// Applied as `.background(cornerMotif(), alignment: .topTrailing)` on a
/// Large widget's outer VStack — low-opacity enough to read as texture,
/// not a competing shape, and offset to bleed off the corner rather than
/// sit fully inside the card.
private func cornerMotif() -> some View {
    EightPointStarShape()
        .stroke(Color.gdBorder.opacity(0.4), lineWidth: 1)
        .frame(width: 84, height: 84)
        .rotationEffect(.degrees(8))
        .offset(x: 46, y: -34)
}

/// completedToday/totalToday as a small ring. Hand-rolled with
/// Circle().trim rather than ProgressView(value:) so it renders identically
/// across OS versions. Turns amber instead of emerald in the evening if
/// there's still something left today. The sweep animates on refresh (see
/// Apple's "Animating data updates in widgets and Live Activities") rather
/// than snapping straight to the new value — this is used at two different
/// sizes (26pt on Small, 48pt on Medium; see call sites), so nothing here
/// is a fixed-point size: an earlier version added a small dot riding the
/// progress head at a hardcoded offset, which would have landed at roughly
/// the right radius on one of those two sizes and visibly floating in the
/// wrong place on the other — cut rather than fixed with a GeometryReader
/// this file has no way to check on-device before shipping.
struct ProgressRing: View {
    let completed: Int
    let total: Int
    var progress: Double { total <= 0 ? 0 : min(1, Double(completed) / Double(total)) }
    private var isUrgent: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 18 && total > 0 && completed < total
    }
    private var ringColor: Color { isUrgent ? .parchmentWarn : .parchmentGreen }

    var body: some View {
        ZStack {
            // The unfilled track, which on cream must stay behind the arc
            // rather than compete with it.
            Circle().stroke(Color.parchmentBorder.opacity(0.28), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            Text(verbatim: "\(completed)/\(total)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.parchmentInk)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.default, value: completed)
        }
    }
}


/// 4-week mini heatmap — same dailyGreenCounts rollup the in-app Monthly
/// Heatmap screen reads, just windowed to the last 28 days.
///
/// Fixed-size cells laid out in explicit rows of 7, rather than the
/// LazyVGrid(columns:) + .aspectRatio(1, contentMode: .fit) version this
/// used to be: that combination asked each cell to be exactly as tall as it
/// was wide (driven by the *available width*, ~45pt in a systemLarge
/// widget), while the grid's own containing frame only budgeted 64pt of
/// *height* for all 4 rows combined (~14.5pt/row after the fixed .frame
/// (height: 64) below was ever added). SwiftUI doesn't shrink an
/// aspectRatio(contentMode: .fit) view to respect a height budget shorter
/// than its width-driven natural size, and WidgetKit's rendering doesn't
/// clip a VStack's overflowing children by default — so the grid quietly
/// rendered ~3x taller than its allotted box and the habit checklist
/// beneath it in GrowDailyLargeView got drawn right on top of it, not
/// after it. That's what showed up as habit names overlapping the last
/// heatmap row on-device. Explicit fixed-size cells have no width-vs-height
/// tension to lose: the grid's total size is just rows × (cellSize +
/// spacing), always, regardless of how much width the parent happens to
/// hand it.
/// The last four weeks as a real month grid: seven weekday columns,
/// Saturday on the left, days running left to right.
///
/// ── What this replaces, and why ──────────────────────────────────────
/// The old grid chunked the day array into rows of seven and drew them at
/// a hard-coded 9pt. Two things were wrong with that. It was 78pt wide on
/// a 329pt card, so it sat in a quarter of the width with dead space
/// beside it. And its columns were not weekdays at all: it LOOKED like a
/// calendar while its column positions meant nothing, so a Tuesday could
/// appear under a Friday. Aziz called it on 2026-09-23.
///
/// Now each day is placed in its own weekday column, the first week is
/// padded so it starts in the right one, and the cells size themselves
/// from whatever width they are given (`aspectRatio(1, .fit)` on a cell
/// with `maxWidth: .infinity`) so the grid always spans the card. No outer
/// height is set, which is what the previous version's own comment warned
/// about: a fixed height plus a fitted aspect ratio is the combination
/// that made cells overlap.
///
/// Saturday on the left is the app's own rule, decided 2026-09-21 for
/// every calendar it draws, and it holds IN ARABIC TOO. That is why this
/// view pins its own layout direction rather than inheriting the face's.
struct HeatmapGrid: View {
    let days: [HeatmapDay]
    var spacing: CGFloat = 4
    /// The weekday initials above the columns. They are what turns a block
    /// of squares into a calendar someone can read a position off.
    var showWeekdays: Bool = true
    var copy: WidgetCopy = WidgetCopy(isAr: false)

    /// Sunday is 1 in Gregorian, so Saturday (7) maps to column 0 and the
    /// rest follow: Sunday 1, Monday 2 ... Friday 6.
    private static func column(of date: Date, calendar: Calendar) -> Int {
        calendar.component(.weekday, from: date) % 7
    }

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The grid as rows of optional days: nil is a cell before the window
    /// started, drawn as nothing at all so the first week lines up.
    private var weeks: [[HeatmapDay?]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let parsed: [(day: HeatmapDay, col: Int)] = days.compactMap { d in
            guard let date = Self.parser.date(from: d.date) else { return nil }
            return (d, Self.column(of: date, calendar: calendar))
        }
        guard let first = parsed.first else { return [] }
        var out: [[HeatmapDay?]] = []
        var row: [HeatmapDay?] = Array(repeating: nil, count: first.col)
        for entry in parsed {
            if row.count == 7 { out.append(row); row = [] }
            row.append(entry.day)
        }
        if !row.isEmpty {
            row.append(contentsOf: Array(repeating: nil, count: 7 - row.count))
            out.append(row)
        }
        return out
    }

    /// The ramp had to be rebuilt when the card stopped being near-black.
    /// On a dark ground a LOW opacity reads as faint, so an empty day at
    /// 0.55 sat quietly under a filled one; on cream the same numbers
    /// inverted the hierarchy and made the emptiest days the loudest thing
    /// in the grid. Empty is now a whisper on both sheets and every filled
    /// step climbs above it.
    private func color(for count: Int) -> Color {
        switch count {
        case 0: return Color.parchmentSurface
        case 1: return Color.parchmentGreenFill.opacity(0.38)
        case 2, 3: return Color.parchmentGreenFill.opacity(0.68)
        default: return Color.parchmentGreenFill
        }
    }

    var body: some View {
        VStack(spacing: spacing) {
            if showWeekdays {
                HStack(spacing: spacing) {
                    ForEach(Array(copy.weekdayInitials.enumerated()), id: \.offset) { _, letter in
                        Text(letter)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.parchmentSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: spacing) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(day == nil ? Color.clear : color(for: day!.count))
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        // A calendar reads left to right in this app whatever the language
        // (2026-09-21). Inheriting the face's direction mirrored the weeks.
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct GrowDailySmallView: View {
    var entry: GrowDailyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                FlameIcon(size: 17)
                Text(verbatim: "\(entry.streak)")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(.parchmentInk)
                    .contentTransition(.numericText())
                    .animation(.default, value: entry.streak)
            }
            Text(entry.copy.dayStreak)
                .font(.system(size: 11))
                .foregroundColor(.parchmentSecondary)
            Spacer()
            HStack {
                ProgressRing(completed: entry.completedToday, total: entry.totalToday)
                    .frame(width: 26, height: 26)
                Spacer()
                Label("\(entry.gold)", systemImage: "circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.parchmentGold)
                    .contentTransition(.numericText())
                    .animation(.default, value: entry.gold)
            }
        }
        .padding()
        .containerBackground(for: .widget) { WidgetParchmentBackground() }
    }
}

struct GrowDailyMediumView: View {
    var entry: GrowDailyEntry

    var body: some View {
        HStack(spacing: 16) {
            ProgressRing(completed: entry.completedToday, total: entry.totalToday)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                // Was a flat "X of Y done today" — the ring already shows
                // that exact fraction at its center, so this slot is
                // better spent on statusLine's day-aware nudge instead of
                // repeating the same two numbers a second time.
                Text(entry.copy.statusLine(completed: entry.completedToday, total: entry.totalToday,
                                           hour: Calendar.current.component(.hour, from: entry.date)))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.parchmentInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
                    .animation(.default, value: entry.completedToday)
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        FlameIcon(size: 12)
                        Text(entry.copy.streakDays(entry.streak))
                            .contentTransition(.numericText())
                            .animation(.default, value: entry.streak)
                    }
                    .foregroundColor(.parchmentStreak)
                    Label(entry.copy.level(entry.level), systemImage: "star.fill")
                        .foregroundColor(.parchmentXp)
                        .contentTransition(.numericText())
                        .animation(.default, value: entry.level)
                    Label("\(entry.gold)", systemImage: "circle.fill")
                        .foregroundColor(.parchmentGold)
                        .contentTransition(.numericText())
                        .animation(.default, value: entry.gold)
                }
                .font(.system(size: 11, weight: .semibold))
            }
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(for: .widget) { WidgetParchmentBackground() }
    }
}

/// The "pro" size — mini heatmap plus today's actual habits, each with a
/// real checkmark button (see MarkHabitDoneIntent above). Shows at most 5
/// rows; a widget can't scroll, so anything past that is a count, not a
/// list.
struct GrowDailyLargeView: View {
    var entry: GrowDailyEntry

    /// How many habits fit under the month grid.
    ///
    /// Measured off screenshots of the built widget, not estimated.
    ///
    /// The arithmetic said the full-width month grid would cost the list
    /// two rows: about 210pt of grid on a 313pt card. It did not. The grid
    /// lands narrower than the raw width because of the card's own inset,
    /// so at three rows and again at four there was visible slack at the
    /// bottom, and five still fits with room over. The list keeps the count
    /// it always had, and the trade-off this comment used to describe was
    /// an estimate that a screenshot disproved.
    static let habitRows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    FlameIcon(size: 15)
                    Text(verbatim: "\(entry.streak)")
                        .foregroundColor(.parchmentStreak)
                        .font(.system(size: 15, weight: .heavy))
                        .contentTransition(.numericText())
                        .animation(.default, value: entry.streak)
                }
                Spacer()
                // Same day-aware line as the medium widget, in place of the
                // old flat "X/Y today" — see statusLine's doc comment.
                Text(entry.copy.statusLine(completed: entry.completedToday, total: entry.totalToday,
                                           hour: Calendar.current.component(.hour, from: entry.date)))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.parchmentSecondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.default, value: entry.completedToday)
            }

            // No .frame(height:) here on purpose — HeatmapGrid now sizes
            // itself deterministically from fixed cells (see its own doc
            // comment), so forcing an outer height back on is exactly the
            // mismatch that caused the overlap bug in the first place.
            HeatmapGrid(days: entry.heatmap, copy: entry.copy)

            Divider().background(Color.parchmentBorder)

            VStack(alignment: .leading, spacing: 7) {
                if entry.habits.isEmpty {
                    Text(entry.copy.noHabitsToday)
                        .font(.system(size: 12))
                        .foregroundColor(.parchmentSecondary)
                } else {
                    ForEach(Array(entry.habits.prefix(Self.habitRows))) { habit in
                        // A row the day did not ask for stays here and stays
                        // tappable — you may always train on a rest day — but
                        // it is drawn as an invitation, not as something
                        // outstanding: the app's own soft emerald for a
                        // covered square, and a label saying so. Without it
                        // the list showed a plain empty circle beside a count
                        // that had already left it out, which is the same
                        // "two answers on one screen" the counts were fixed
                        // to end.
                        let resting = !habit.isDue && !habit.done
                        HStack(spacing: 8) {
                            Button(intent: MarkHabitDoneIntent(habitId: habit.id)) {
                                Image(systemName: habit.done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(habit.done
                                                     ? .parchmentGreen
                                                     : (resting
                                                        ? .parchmentGreen.opacity(0.45)
                                                        : .parchmentSecondary))
                            }
                            .buttonStyle(.plain)
                            Text(habit.name)
                                .font(.system(size: 12, weight: .medium))
                                .strikethrough(habit.done)
                                .foregroundColor(habit.done || resting
                                                 ? .parchmentSecondary
                                                 : .parchmentInk)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if resting {
                                Text(entry.copy.notDue)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.parchmentGreen.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                    }
                    if entry.habits.count > Self.habitRows {
                        Text(entry.copy.moreInApp(entry.habits.count - Self.habitRows))
                            .font(.system(size: 10))
                            .foregroundColor(.parchmentSecondary)
                    }
                }
            }
        }
        .padding()
        .background(cornerMotif(), alignment: .topTrailing)
        .containerBackground(for: .widget) { WidgetParchmentBackground() }
    }
}

struct GrowDailyWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: GrowDailyEntry

    var body: some View {
        Group {
        switch family {
        case .systemMedium:
            GrowDailyMediumView(entry: entry)
        case .systemLarge:
            GrowDailyLargeView(entry: entry)
        default:
            GrowDailySmallView(entry: entry)
        }
        }
        // Arabic reads right to left, and these faces are built from
        // leading-aligned stacks, so without this every row stayed pinned
        // to the left with its Arabic text ragged against it. Set once
        // here rather than per face: the switch above is the single root
        // all three sizes pass through.
        .environment(\.layoutDirection, entry.copy.isAr ? .rightToLeft : .leftToRight)
    }
}

struct GrowDailyWidget: Widget {
    let kind: String = "GrowDailyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GrowDailyProvider()) { entry in
            GrowDailyWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Grow Daily"))
        .description(Text("Today's progress, streak, and a tappable habit list at a glance."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Lock Screen widgets
//
// Display-only on purpose — Lock Screen widgets are rendered in the
// system's own tint on a locked device, not really where you want someone
// trying to tap fiddly buttons.

/// Where a tap on a Lock Screen widget lands: the page that widget is about.
/// Each of the three Lock Screen widgets (streak, Room Race, tasks) is one
/// tap target as a whole and used to carry no link, so a tap opened the app
/// wherever it had last been left; Aziz asked on 2026-09-21 for each to
/// open its own page. Same link shape as the Lock Screen controls
/// (deep_links.dart's parseOpenTabLink), resolved by main.dart's
/// _handleDeepLink, which also closes anything left open on top first. The
/// tab ids are NavTab's, which test/core/open_tab_link_test.dart pins.
///
/// growdaily:// is right here: iOS hands a widget's own link straight to its
/// app, with no universal link or web association involved.
func lockScreenOpenURL(tab: String) -> URL {
    URL(string: "growdaily://open?tab=\(tab)")!
}

struct GrowDailyCircularView: View {
    var entry: GrowDailyEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                Text(verbatim: "\(entry.streak)")
                    .font(.system(size: 14, weight: .bold))
                    .contentTransition(.numericText())
                    .animation(.default, value: entry.streak)
            }
        }
    }
}

struct GrowDailyRectangularView: View {
    var entry: GrowDailyEntry

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.copy.streakLine(entry.streak))
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.numericText())
                    .animation(.default, value: entry.streak)
                Text(entry.copy.doneToday(entry.completedToday, entry.totalToday))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .contentTransition(.numericText())
                    .animation(.default, value: entry.completedToday)
            }
        }
    }
}

struct GrowDailyLockScreenView: View {
    @Environment(\.widgetFamily) var family
    var entry: GrowDailyEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                GrowDailyRectangularView(entry: entry)
            default:
                GrowDailyCircularView(entry: entry)
            }
        }
        .widgetURL(lockScreenOpenURL(tab: "grid"))
        // Arabic on the Lock Screen too. Only the three Home Screen
        // families got this in the first pass, so an Arabic user's Lock
        // Screen kept laying its rows out left to right while the Home
        // Screen above it read correctly. Found by reading rather than by
        // looking: the simulator's Lock Screen editor would not render.
        .environment(\.layoutDirection, entry.copy.isAr ? .rightToLeft : .leftToRight)
    }
}

struct GrowDailyLockScreenWidget: Widget {
    let kind: String = "GrowDailyLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GrowDailyProvider()) { entry in
            GrowDailyLockScreenView(entry: entry)
        }
        .configurationDisplayName(Text("Grow Daily Streak"))
        .description(Text("Your streak and today's progress on the Lock Screen."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Room Race widget (opt-in)
//
// A second, separate widget kind — someone only ever sees this if they
// deliberately add it from the widget gallery (long-press home screen → +
// → search "GrowDaily" → pick "Room Race" specifically), same as picking
// any widget size for the main GrowDailyWidget above. Shows one room's
// ranked leaderboard; see rooms_notifier.dart's myRoomRaceSnapshotProvider
// for how "which room" and the ranking itself get computed on the Dart
// side — this only ever reads the already-finished result HomeWidgetService
// .updateRoomRaceData wrote, same division of labor as the daily widget.
//
// Avatars are a colored initial circle, not the in-app character art:
// character art is a set of real PNG assets that only exist in the main
// Runner target's asset catalog today, and a widget extension has its own,
// separate asset catalog — showing the real art here would mean manually
// adding a copy of every character/accessory PNG to this target in Xcode
// too (and keeping that in sync any time the closet grows). Initials avoid
// that whole extra setup step and still make each row easy to tell apart at
// a glance.

struct RoomRaceRow: Codable {
    let name: String
    let rank: Int
    let percent: Int
    let isMe: Bool

    // This participant's real uid, carried only so ForEach can key rows by
    // "the same person" across two timeline refreshes instead of by their
    // rank slot - see stableId below. Optional for the same reason heatmap
    // is: a non-optional with a default value still throws on a missing
    // key when decoding, only a genuine Optional degrades gracefully for
    // old cached data from just before this field existed.
    let uid: String?

    // Last roomRaceHeatmapDays (rooms_notifier.dart) days, oldest first, as
    // heatmapLevelFor levels (0-4) - see RoomRaceHeatmapStrip below for how
    // these render. Genuinely Optional (not a non-optional with a default)
    // on purpose: Swift's synthesized Decodable conformance only treats a
    // missing JSON key as "fall back" for an Optional-typed property - a
    // non-optional with a default value still throws on a missing key.
    // Being Optional here means a brief window right after an app update -
    // old cached roomRaceJson from before this field existed, read by the
    // new widget binary before the app itself has relaunched and repushed
    // fresh data - degrades to "no strip for this row" instead of failing
    // this row's whole decode (which would otherwise blank the entire Room
    // Race face, name/rank/percent included, until the next push).
    let heatmap: [Int]?

    // Explicit memberwise init, written by hand instead of relying on the
    // compiler-synthesized one: giving uid/heatmap a `= nil` default
    // directly on the stored property (as this struct used to do) silently
    // drops them from Swift's *synthesized* memberwise initializer
    // entirely - it does not make them optional-to-pass, it removes them
    // as parameters outright. That's what broke the placeholder() calls
    // below ("Extra argument 'heatmap' in call": the synthesized init
    // genuinely had no heatmap parameter to pass one to). Defaulting them
    // here, in a hand-written init, is the correct way to keep both
    // "pass heatmap explicitly" and "omit it" call sites compiling, and
    // has no effect on Decodable - init(from:) is synthesized separately
    // and is untouched by adding this.
    // Days credited / days the room has run — what the Lock Screen shows
    // instead of a percentage ("5 / 6" reads faster and says how much is
    // actually at stake, which "83%" hides). Optional for the same
    // forward/backward-compatibility reason as `heatmap` above: a widget
    // binary that updated before the app relaunched and repushed still
    // decodes, and just falls back to the percentage.
    let daysDone: Int?
    let daysTotal: Int?

    init(
        name: String,
        rank: Int,
        percent: Int,
        isMe: Bool,
        uid: String? = nil,
        daysDone: Int? = nil,
        daysTotal: Int? = nil,
        heatmap: [Int]? = nil
    ) {
        self.name = name
        self.rank = rank
        self.percent = percent
        self.isMe = isMe
        self.uid = uid
        self.daysDone = daysDone
        self.daysTotal = daysTotal
        self.heatmap = heatmap
    }

    /// Identity ForEach should key rows by so a row *moves* to its new rank
    /// position when it changes instead of the slot at that rank just
    /// swapping its text - falls back to name only in that same brief
    /// stale-cache window described above, when two same-named participants
    /// would still be no worse off than this widget's previous rank-keyed
    /// behavior.
    var stableId: String { uid ?? name }

    /// "5/6" when the day counts are available, falling back to "83%".
    ///
    /// A fraction beats a percentage on an accessory widget for two
    /// reasons: it's usually fewer glyphs (so it survives beside a long
    /// name), and it carries the scale — "5/6" says there are six days in
    /// play, where "83%" could be six days or sixty. The percentage
    /// fallback covers a widget binary running against app data pushed
    /// before these fields existed.
    var scoreLabel: String {
        if let done = daysDone, let total = daysTotal, total > 0 {
            return "\(done)/\(total)"
        }
        return "\(percent)%"
    }
}

struct RoomRaceEntry: TimelineEntry {
    let date: Date
    var copy: WidgetCopy = WidgetCopy(isAr: false)
    let hasRoom: Bool
    let roomName: String
    let isLive: Bool
    let daysRemaining: Int
    let rows: [RoomRaceRow]
}

struct RoomRaceProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoomRaceEntry {
        // Varied, non-trivial sample levels (not all-4s/all-0s) so the
        // Xcode widget gallery preview actually shows what the heatmap
        // strip's shading range looks like, not a flat block of one color.
        let strongWeek = [2, 3, 4, 4, 3, 4, 4, 2, 4, 3, 4, 4, 4, 4]
        let mixedWeek = [1, 2, 0, 3, 2, 4, 3, 1, 2, 3, 0, 2, 3, 4]
        return RoomRaceEntry(date: Date(), hasRoom: true, roomName: "Ramadan Push", isLive: true, daysRemaining: 12,
                      rows: [RoomRaceRow(name: "You", rank: 1, percent: 86, isMe: true, daysDone: 12, daysTotal: 14, heatmap: strongWeek),
                             // A deliberately long name in the preview — this
                             // row is what proves the score still renders
                             // beside one instead of being truncated away.
                             RoomRaceRow(name: "mohdabood2003", rank: 2, percent: 74, isMe: false, daysDone: 10, daysTotal: 14, heatmap: mixedWeek),
                             RoomRaceRow(name: "Omar", rank: 3, percent: 61, isMe: false, daysDone: 9, daysTotal: 14)])
    }

    func getSnapshot(in context: Context, completion: @escaping (RoomRaceEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoomRaceEntry>) -> Void) {
        let entry = loadEntry()
        // Same fallback-only cadence as GrowDailyProvider — the real
        // refresh trigger is HomeWidgetService.updateRoomRaceData firing
        // from main.dart's _roomRaceSub whenever Firestore's room/
        // participant data actually changes.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> RoomRaceEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        struct RawRaceData: Codable {
            let hasRoom: Bool
            let roomName: String
            let isLive: Bool
            let daysRemaining: Int
            let rows: [RoomRaceRow]
        }
        guard let raw = readJSON("roomRaceJson", from: defaults, as: RawRaceData.self) else {
            return RoomRaceEntry(date: Date(), copy: WidgetCopy.fromDefaults(), hasRoom: false,
                                 roomName: "", isLive: false, daysRemaining: 0, rows: [])
        }
        return RoomRaceEntry(date: Date(), copy: WidgetCopy.fromDefaults(),
                             hasRoom: raw.hasRoom, roomName: raw.roomName,
                              isLive: raw.isLive, daysRemaining: raw.daysRemaining, rows: raw.rows)
    }
}




/// A place, or a dash when there isn't one yet.
///
/// The Dart side leaves a member unranked (rank 0) until their own
/// percentage reads above 0%, so a room on day one has no positions to
/// show rather than a leader who has done nothing. See
/// RoomLeaderboard.standings. Every "#" in this file goes through here so
/// none of them can print "#0".
func rankLabel(_ rank: Int) -> String {
    rank > 0 ? "#\(rank)" : "#-"
}



/// Shown in every size when nobody's in an active room yet — a plain
/// "nothing to show" state reads as broken on a widget in a way it doesn't
/// in the full app, so this always explains what to do next instead of
/// just going blank.
struct RoomRaceEmptyView: View {
    /// Taken as a parameter rather than read here: this view has no entry,
    /// and a second read of the flag is a second chance to disagree with
    /// the face around it.
    let copy: WidgetCopy

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 20))
                .foregroundColor(.parchmentSecondary)
            Text(copy.noActiveRoom)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.parchmentInk)
            Text(copy.joinOrCreate)
                .font(.system(size: 10.5))
                .foregroundColor(.parchmentSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct RoomRaceSmallView: View {
    var entry: RoomRaceEntry

    private var mine: RoomRaceRow? { entry.rows.first(where: { $0.isMe }) }

    var body: some View {
        Group {
            if !entry.hasRoom || mine == nil {
                RoomRaceEmptyView(copy: entry.copy)
            } else if let mine {
                VStack(alignment: .leading, spacing: 6) {
                    Label(entry.roomName, systemImage: "flag.checkered")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.parchmentSecondary)
                        .lineLimit(1)
                    Spacer()
                    // The word, not «#1»: a Western rank badge on an
                    // Arabic card, and a bare digit reads as a score. The
                    // Lock Screen faces keep the badge, where a word does
                    // not fit in a 58pt circle.
                    Text(entry.copy.rankWord(mine.rank))
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(.parchmentGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(.default, value: mine.rank)
                    Text(entry.copy.rankLine(rank: mine.rank, racerCount: entry.rows.count))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.parchmentSecondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .animation(.default, value: mine.rank)
                    if entry.daysRemaining > 0 {
                        Text(entry.copy.daysLeftShort(entry.daysRemaining))
                            .font(.system(size: 10))
                            .foregroundColor(.parchmentSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .containerBackground(for: .widget) { WidgetParchmentBackground() }
    }
}

/// My own 28 days as one wide line, sized to whatever width it is given.
///
/// The old strip drew 6pt cells at a fixed size, which left it ending
/// two thirds of the way across a card and lining up with nothing. This
/// one fills the row, and like the month grid it pins its direction: a
/// run of days reads left to right in this app whatever the language.
struct RoomRaceWideStrip: View {
    let levels: [Int]
    var spacing: CGFloat = 2

    private func color(for level: Int) -> Color {
        switch level {
        case 1: return Color.parchmentGreenFill.opacity(0.38)
        case 2: return Color.parchmentGreenFill.opacity(0.58)
        case 3: return Color.parchmentGreenFill.opacity(0.78)
        case 4: return Color.parchmentGreenFill
        default: return Color.parchmentSurface
        }
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: level))
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(
                        index == levels.count - 1
                            ? RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.parchmentGold, lineWidth: 1.2)
                            : nil
                    )
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// The Race face, rebuilt 2026-09-23.
///
/// ── What it used to be, and why that failed ──────────────────────────
/// A miniature leaderboard: every racer as a row with a rank, an avatar, a
/// name and an unlabelled «23/41». Aziz called it unclear and he was
/// right. Three separate problems. With two racers the rows filled about
/// half the card and the rest was dead space. The biggest, greenest thing
/// on each row was a fraction that could have been days, points or
/// percent, and both racers' fractions were the same colour, so the
/// leader was not distinguished by the one element the eye goes to. And
/// the rank sat OUTSIDE the highlight on the row that was mine.
///
/// ── What it is now ───────────────────────────────────────────────────
/// One question, answered: where do I stand against the person next to
/// me. My place as a word, the gap in days to whoever is immediately
/// ahead (or, when I am first, my cushion over the chaser), and my own
/// month as one wide line. The whole card is spent on my own position
/// rather than on a table nobody reads at a glance.
struct RoomRaceStandingView: View {
    var entry: RoomRaceEntry
    var compact: Bool

    /// Me, and whoever I am measured against: the racer one place ahead,
    /// or the one behind when I am already first.
    private var pair: (me: RoomRaceRow, rival: RoomRaceRow?)? {
        guard let me = entry.rows.first(where: { $0.isMe }) ?? entry.rows.first
        else { return nil }
        let rival = entry.rows.first { $0.rank == me.rank - 1 }
            ?? entry.rows.first { $0.rank == me.rank + 1 }
        return (me, rival)
    }

    private func gapText(_ me: RoomRaceRow, _ rival: RoomRaceRow) -> String {
        let mine = me.daysDone ?? 0
        let theirs = rival.daysDone ?? 0
        return entry.copy.gapLine(days: abs(mine - theirs),
                                  other: rival.name,
                                  iAmAhead: mine >= theirs)
    }

    var body: some View {
        Group {
            if !entry.hasRoom || entry.rows.isEmpty {
                RoomRaceEmptyView(copy: entry.copy)
            } else if let pair = pair {
                VStack(alignment: .leading, spacing: compact ? 4 : 8) {
                    HStack {
                        Label(entry.roomName, systemImage: "flag.checkered")
                            .font(.system(size: compact ? 12 : 14, weight: .bold))
                            .foregroundColor(.parchmentInk)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        if entry.daysRemaining > 0 {
                            Text(entry.copy.daysLeftShort(entry.daysRemaining))
                                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                                .foregroundColor(.parchmentSecondary)
                                .fixedSize()
                        } else if !entry.isLive {
                            Text(entry.copy.startingSoon)
                                .font(.system(size: compact ? 10 : 12, weight: .semibold))
                                .foregroundColor(.parchmentWarn)
                                .fixedSize()
                        }
                    }

                    // Spacers above and below, so two racers and six fill
                    // the same card instead of clinging to the top edge.
                    Spacer(minLength: 0)

                    Text(entry.copy.rankWord(pair.me.rank))
                        .font(.system(size: compact ? 30 : 42, weight: .heavy))
                        .foregroundColor(.parchmentGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(pair.rival.map { gapText(pair.me, $0) } ?? entry.copy.racingSolo)
                        .font(.system(size: compact ? 12 : 15, weight: .semibold))
                        .foregroundColor(.parchmentSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    if let heatmap = pair.me.heatmap, !heatmap.isEmpty {
                        RoomRaceWideStrip(levels: heatmap)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(compact ? 12 : 16)
                .background(MosqueMark(height: compact ? 58 : 84), alignment: .bottomTrailing)
            }
        }
        .containerBackground(for: .widget) { WidgetParchmentBackground() }
    }
}

struct RoomRaceWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: RoomRaceEntry

    var body: some View {
        Group {
        switch family {
        case .systemMedium:
            RoomRaceStandingView(entry: entry, compact: true)
        case .systemLarge:
            RoomRaceStandingView(entry: entry, compact: false)
        default:
            RoomRaceSmallView(entry: entry)
        }
        }
        // Arabic reads right to left, and these faces are built from
        // leading-aligned stacks, so without this every row stayed pinned
        // to the left with its Arabic text ragged against it. Set once
        // here rather than per face: the switch above is the single root
        // all three sizes pass through.
        .environment(\.layoutDirection, entry.copy.isAr ? .rightToLeft : .leftToRight)
    }
}

struct GrowDailyRoomRaceWidget: Widget {
    // Must exactly match HomeWidgetService's _iOSRoomRaceWidgetName
    // (lib/core/services/home_widget_service.dart), same convention as
    // GrowDailyWidget's own kind string above.
    let kind: String = "GrowDailyRoomRaceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RoomRaceProvider()) { entry in
            RoomRaceWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Room Race"))
        .description(Text("See your rank and your friends' progress in your active room."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Room Race Lock Screen widgets
//
// Same "display-only, own compact views, shares the Home Screen widget's
// provider" shape as GrowDailyLockScreenWidget above - see that struct's
// doc comment for why Lock Screen widgets stay tap-free here (system tint,
// no room for fiddly buttons). Reuses RoomRaceProvider/RoomRaceEntry as-is -
// same roomRaceJson data, just laid out for a tiny accessory slot instead
// of a Home Screen size.
//
// Deliberately no explicit .foregroundColor(.parchmentGold/.parchmentGreen/etc.) here,
// unlike the Home Screen Room Race views above - accessory-family Lock
// Screen widgets are rendered by the system in its own monochrome tint
// (the always-on-display/lock-screen accent), which overrides custom
// colors anyway. Only `.secondary` is used for de-emphasis, since iOS does
// still respect that much - same convention GrowDailyRectangularView above
// already follows for the streak widget.
//
// Which room shows here is decided once, on the Dart side, by
// myRoomRaceSnapshotProvider - a starred room (RoomsController.
// toggleStarRoom) wins first, live or not, so starring a room in the app
// is what actually controls what appears here.

struct RoomRaceCircularView: View {
    var entry: RoomRaceEntry
    private var mine: RoomRaceRow? { entry.rows.first(where: { $0.isMe }) }

    var body: some View {
        if let mine {
            // Same capacity-ring idiom as the Matrix star circle - the
            // ring fills to this room's percent complete, with the actual
            // rank as the number that matters most staying front and
            // center.
            Gauge(value: Double(mine.percent), in: 0...100) {
                Image(systemName: "flag.checkered")
            } currentValueLabel: {
                Text(rankLabel(mine.rank))
                    .font(.system(size: 14, weight: .bold))
                    .contentTransition(.numericText())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .animation(.default, value: mine.percent)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "flag.checkered")
                    .font(.system(size: 16))
            }
        }
    }
}

struct RoomRaceRectangularView: View {
    var entry: RoomRaceEntry
    private var mine: RoomRaceRow? { entry.rows.first(where: { $0.isMe }) }

    // The one racer worth showing next to yourself, so this reads as a
    // head-to-head instead of just a solo scoreboard: whoever's at the top
    // if that isn't you (the gap you're closing), or whoever's directly
    // behind you if it is (the gap someone else is closing on you). Never
    // both at once, there's only room for one rival line here.
    //
    // Picked by POSITION, not by rank number. Ranks are shared on the Dart
    // side now (RoomLeaderboard.standings): two members who are level are
    // both rank 1 and no row carries rank 2 at all, so the old
    // `first(where: { $0.rank == 2 })` found nobody and told a member who
    // was tied for the lead that they were racing alone. rows already
    // arrive in rank order, so "the first row that isn't me" is the same
    // racer in every case that used to work, and the right one in the case
    // that didn't.
    private var rival: RoomRaceRow? {
        guard mine != nil else { return nil }
        return entry.rows.first(where: { !$0.isMe })
    }

    // One racer's line: "#2 mohdabo…            4/6".
    //
    // Name and score are separate Texts in an HStack, NOT one interpolated
    // string. As a single string with lineLimit(1) the truncation lands at
    // the *end* — so a long display name ate the score, which is the only
    // part of the row actually worth glancing at. Splitting them lets the
    // name absorb all the truncation while the score keeps its intrinsic
    // width and always renders in full.
    @ViewBuilder
    private func racerLine(
        rank: Int,
        name: String,
        score: String,
        isMine: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Text(rankLabel(rank))
                .fontWeight(.bold)
                .layoutPriority(2)
            Text(name)
                .lineLimit(1)
                .truncationMode(.tail)
                // Lowest priority: this is the one part that may shrink.
                .layoutPriority(0)
            Spacer(minLength: 4)
            Text(score)
                // fixedSize + top priority: never compressed, never
                // truncated, no matter how long the name beside it is.
                .fixedSize()
                .layoutPriority(2)
                .contentTransition(.numericText())
        }
        .font(.system(size: isMine ? 12 : 11,
                      weight: isMine ? .bold : .regular))
        .foregroundColor(isMine ? .primary : .secondary)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flag.checkered")
                .layoutPriority(2)
            if let mine {
                VStack(alignment: .leading, spacing: 1) {
                    racerLine(
                        rank: mine.rank,
                        name: "You",
                        score: mine.scoreLabel,
                        isMine: true
                    )
                    .animation(.default, value: mine.daysDone)
                    if let rival {
                        racerLine(
                            rank: rival.rank,
                            name: rival.name,
                            score: rival.scoreLabel,
                            isMine: false
                        )
                        .animation(.default, value: rival.daysDone)
                    } else {
                        // Solo room, nobody else at rank 1/2 to compare
                        // against — fall back to the room name rather than
                        // show nothing on the second line.
                        Text(entry.roomName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(entry.copy.noActiveRoom)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }
}

struct RoomRaceLockScreenView: View {
    @Environment(\.widgetFamily) var family
    var entry: RoomRaceEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                RoomRaceRectangularView(entry: entry)
            default:
                RoomRaceCircularView(entry: entry)
            }
        }
        // The rooms page, not the one room: the entry does not carry the
        // room's code. With no room at all this is where joining starts.
        .widgetURL(lockScreenOpenURL(tab: "rooms"))
        // Arabic on the Lock Screen too. Only the three Home Screen
        // families got this in the first pass, so an Arabic user's Lock
        // Screen kept laying its rows out left to right while the Home
        // Screen above it read correctly. Found by reading rather than by
        // looking: the simulator's Lock Screen editor would not render.
        .environment(\.layoutDirection, entry.copy.isAr ? .rightToLeft : .leftToRight)
    }
}

struct GrowDailyRoomRaceLockScreenWidget: Widget {
    // Must exactly match HomeWidgetService's
    // _iOSRoomRaceLockScreenWidgetName (lib/core/services/
    // home_widget_service.dart).
    let kind: String = "GrowDailyRoomRaceLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RoomRaceProvider()) { entry in
            RoomRaceLockScreenView(entry: entry)
        }
        .configurationDisplayName(Text("Room Race"))
        .description(Text("Your rank in your starred room, on the Lock Screen."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Matrix widget
//
// A third, separate widget kind — same opt-in-from-the-gallery model as
// Room Race above. Shows open tasks across all four quadrants, ranked Do
// First → Schedule → Delegate → Eliminate (see main.dart's
// _matrixQuadrantRank, which does the actual sorting before this ever sees
// the list — this file only ever draws an already-ordered array). Real
// checkmarks and a real "+" button, same interaction model as the daily
// widget's habit rows: MarkTaskDoneIntent below only ever touches shared
// UserDefaults, never the live Flutter app state — see its own doc comment,
// identical reasoning to MarkHabitDoneIntent's.

struct WidgetMatrixTask: Codable, Identifiable {
    let id: String
    let title: String
    /// One of MatrixQuadrant's own `.name` values ("doFirst", "schedule",
    /// "delegate", "eliminate") — sent as the plain enum name rather than a
    /// separate hex string so there's exactly one place (quadrantColor
    /// below) that maps a quadrant to a color, matching MatrixQuadrant
    /// .color's role on the Dart side.
    let quadrant: String
    var isDone: Bool
    /// Mirrors MatrixTask.isFav (matrix_task.dart) — the gold star toggle
    /// on the Tasks screen. Ignored by the Home Screen Matrix widget's own
    /// views below (no star shown there); exists so the Lock Screen
    /// starred-task widget further down has something to pick out from
    /// this same shared list without a second write path from Flutter.
    var isFav: Bool
    /// True when the task has a reminder that's already passed and it's
    /// still open — same "overdue" definition MatrixNotifier already uses
    /// on the Dart side (see main.dart's _matrixWidgetSub, computed there
    /// since that's the one place this list already touches
    /// DateTime.now()). Drives a small red marker next to the quadrant dot
    /// below — a flag only, it never changes row order.
    var isLate: Bool
    /// The moment the user picked for this task (MatrixTask.reminderAnchorAt),
    /// in milliseconds since 1970, or nil when it has no reminder. The Lock
    /// Screen orders by it, see MatrixLockScreenOrder.swift.
    ///
    /// Stored as the raw number rather than a Date so it survives
    /// MarkTaskDoneIntent's write-back unchanged: the synthesized encoder
    /// writes a Date as seconds since 2001 under its own key, and the next
    /// read would have found no `dueAtMs` and lost the time.
    var dueAtMs: Double?

    var dueAt: Date? { dueAtMs.map { Date(timeIntervalSince1970: $0 / 1000) } }

    init(id: String, title: String, quadrant: String, isDone: Bool, isFav: Bool, isLate: Bool, dueAtMs: Double? = nil) {
        self.id = id
        self.title = title
        self.quadrant = quadrant
        self.isDone = isDone
        self.isFav = isFav
        self.isLate = isLate
        self.dueAtMs = dueAtMs
    }

    // Custom decode so a `matrixTasksJson` blob written by an older app
    // build (before isLate or dueAtMs existed) still decodes instead of
    // failing the whole array — same "just missing the new bit" tolerance
    // worth having for any field added after this widget already shipped.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        quadrant = try c.decode(String.self, forKey: .quadrant)
        isDone = try c.decode(Bool.self, forKey: .isDone)
        isFav = try c.decode(Bool.self, forKey: .isFav)
        isLate = try c.decodeIfPresent(Bool.self, forKey: .isLate) ?? false
        dueAtMs = try c.decodeIfPresent(Double.self, forKey: .dueAtMs)
    }
}

/// Mirrors MatrixQuadrant.color's built-in fallback palette (matrix_task
/// .dart) — doFirst/schedule/delegate map onto colors this file already
/// has (gdError/gdXpBlue/gdStreak); eliminate has no direct equivalent
/// here, so it falls back to a plain muted white matching every other
/// "least important" treatment already used throughout this file (e.g.
/// GrowDailyRoomAvatarCircle's default ring color). A user's own custom
/// quadrant color (MatrixState.colorFor) isn't threaded through to the
/// widget — same "simplified but on-brand, not full parity" call already
/// made for Room Race's avatars (see that section's own doc comment).
private func quadrantColor(_ quadrant: String) -> Color {
    switch quadrant {
    case "doFirst": return .gdError
    case "schedule": return .gdXpBlue
    case "delegate": return .gdStreak
    default: return .white.opacity(0.4) // eliminate, or anything unrecognized
    }
}

/// Tapping this opens the app straight into Matrix with the Add Task sheet
/// already open (see main.dart's isMatrixQuickAddLink + MatrixScreen's own
/// ref.listen(requestedMatrixQuickAddProvider, ...)) — the app already
/// listens for growdaily:// links for room invites, so this reuses that
/// same scheme/plumbing with a different path rather than needing any new
/// Info.plist entry.
private let matrixQuickAddURL = URL(string: "growdaily://matrix/add")!

struct MatrixEntry: TimelineEntry {
    let date: Date
    var copy: WidgetCopy = WidgetCopy(isAr: false)
    let tasks: [WidgetMatrixTask]
    // Tasks completed IN-APP today. The app deliberately writes only OPEN
    // tasks into matrixTasksJson (every list face assumes open-only), so
    // without this the lock-screen ring computed done/total over a list
    // where isDone is false by construction and rendered 0% forever —
    // completing 9 of 10 tasks showed an empty ring. Defaulted so older
    // snapshots and placeholders keep working.
    var doneToday: Int = 0
}

struct MatrixProvider: TimelineProvider {
    func placeholder(in context: Context) -> MatrixEntry {
        MatrixEntry(date: Date(), tasks: [
            WidgetMatrixTask(id: "1", title: "Reply to client email", quadrant: "doFirst", isDone: false, isFav: true, isLate: true),
            WidgetMatrixTask(id: "2", title: "Plan next week", quadrant: "schedule", isDone: false, isFav: false, isLate: false),
            WidgetMatrixTask(id: "3", title: "Forward invoice to Sara", quadrant: "delegate", isDone: false, isFav: false, isLate: false),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (MatrixEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MatrixEntry>) -> Void) {
        let now = Date()
        // Same fallback-only cadence as GrowDailyProvider/RoomRaceProvider —
        // the real refresh trigger is HomeWidgetService.updateMatrixWidgetData
        // firing from main.dart's _matrixWidgetSub whenever the board changes.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: now)!
        // Plus a second entry at midnight. The Lock Screen's order depends on
        // the day (MatrixLockScreenOrder.swift): at 00:00 yesterday's timed
        // tasks drop down and tomorrow's become today's, while the board
        // itself has not changed, so the app has nothing to write. The hourly
        // reload above is a request iOS rations, and a phone left on the
        // nightstand can go hours without one; an entry is drawn at its own
        // date regardless.
        let calendar = lockScreenCalendar
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        completion(Timeline(entries: [loadEntry(at: now), loadEntry(at: midnight)], policy: .after(next)))
    }

    private func loadEntry(at date: Date = Date()) -> MatrixEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let tasks = readJSON("matrixTasksJson", from: defaults, as: [WidgetMatrixTask].self) ?? []
        // The count is only meaningful on the day it was written: after
        // midnight a stale count would sit in today's denominator until the
        // app next foregrounds. Judged on the entry's own date, so the
        // midnight entry starts the new day at zero.
        let stamp = defaults?.string(forKey: "matrixDoneTodayDate")
        let doneToday = stamp == matrixDayKey(date)
            ? (defaults?.integer(forKey: "matrixDoneTodayCount") ?? 0)
            : 0
        return MatrixEntry(date: date, copy: WidgetCopy.fromDefaults(),
                           tasks: tasks, doneToday: doneToday)
    }
}

/// [date]'s day as the app writes `matrixDoneTodayDate`
/// (LocalStoreService.dateKey): Gregorian, Latin digits, "2026-09-21".
///
/// Built by hand rather than by a DateFormatter, because a formatter takes
/// the phone's locale and calendar. On an Arabic iPhone it wrote
/// «٢٠٢٦-٠٩-٢١», and on one set to the Hijri calendar a 1448 date, and
/// neither ever matched the app's key: every task finished in the app was
/// read as another day's, and the Lock Screen ring never filled.
private func matrixDayKey(_ date: Date) -> String {
    let day = lockScreenCalendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04ld-%02ld-%02ld", day.year ?? 0, day.month ?? 0, day.day ?? 0)
}

/// Backs the checkmark on each task row. Exact same division of labor as
/// MarkHabitDoneIntent above — flips this task's cached `isDone` so the one
/// reload iOS guarantees right after `perform()` returns shows it checked
/// immediately, and queues the id for the real Flutter-side completion
/// (XP bonus included) the next time the app is open — see main.dart's
/// _processPendingWidgetTaskCompletions, which guards against re-toggling a
/// task the user already finished in-app in the meantime. It also takes the
/// task's own reminders down (standDownTaskReminders), so a task ticked here
/// stops asking for itself before the app is next opened.
struct MarkTaskDoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Task Done"

    @Parameter(title: "Task ID")
    var taskId: String

    init() {
        self.taskId = ""
    }

    init(taskId: String) {
        self.taskId = taskId
    }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroupId)
        var closesDoFirstTask = false

        if var tasks = readJSON("matrixTasksJson", from: defaults, as: [WidgetMatrixTask].self) {
            // Decided before the flip: tonight's evening streak note counts
            // open Do First tasks («وعندك مهمة عاجلة وحدة.»), so ticking one
            // off here makes that count false.
            closesDoFirstTask = tasks.contains { $0.id == taskId && $0.quadrant == "doFirst" && !$0.isDone }
            for i in tasks.indices where tasks[i].id == taskId {
                tasks[i].isDone = true
            }
            // Sink the just-finished task below every still-open one so the
            // Medium/Large rows' `.prefix(N)` naturally reveals whatever was
            // hiding behind it, instead of leaving a checked row parked in
            // its old spot until the next real Dart-side refresh. `sort(by:)`
            // is stable in Swift, so this only ever moves done tasks past
            // not-done ones - it never disturbs the quadrant-priority order
            // the Dart side already sorted open tasks into, or the relative
            // order of multiple already-done tasks among themselves.
            tasks.sort { !$0.isDone && $1.isDone }
            writeJSON(tasks, to: "matrixTasksJson", in: defaults)
        }

        var pending = readJSON("pendingWidgetTaskCompletions", from: defaults, as: [String].self) ?? []
        if !pending.contains(taskId) {
            pending.append(taskId)
        }
        writeJSON(pending, to: "pendingWidgetTaskCompletions", in: defaults)

        // A finished task has nothing left to remind about, whatever hour it
        // is: its reminders are moments picked for this one task. Until this,
        // they went on ringing until the app was next opened.
        await standDownTaskReminders(of: taskId, in: defaults)
        if closesDoFirstTask {
            standDownNotesWithStaleCounts(includingFridayNote: false)
        }
        return .result()
    }
}

/// Small colored circle standing in for a quadrant label — Do First's red
/// reads as "urgent" at a glance without spending row width on text like
/// "DO FIRST" the way the in-app QuadrantCard headers can afford to.
struct QuadrantDot: View {
    let quadrant: String
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(quadrantColor(quadrant))
            .frame(width: size, height: size)
    }
}

/// One task row: quadrant dot, checkmark, title. Identical structure to the
/// daily widget's habit rows (see GrowDailyLargeView), just with a quadrant
/// dot standing in for that row's habit-streak context.
struct MatrixTaskRow: View {
    let task: WidgetMatrixTask

    var body: some View {
        HStack(spacing: 8) {
            QuadrantDot(quadrant: task.quadrant)
            Button(intent: MarkTaskDoneIntent(taskId: task.id)) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(task.isDone ? .parchmentGreen : .parchmentSecondary)
            }
            .buttonStyle(.plain)
            Text(task.title)
                .font(.system(size: 12, weight: .medium))
                .strikethrough(task.isDone)
                .foregroundColor(task.isDone ? .parchmentSecondary : .parchmentInk)
                .lineLimit(1)
            if task.isLate && !task.isDone {
                LateMarker()
            }
            Spacer(minLength: 0)
        }
    }
}

/// The one visual signal a task is overdue — a small red exclamation next
/// to its title, same "colored dot at a glance" language QuadrantDot
/// already uses, just unmistakably a different color/shape so it never
/// reads as a fifth quadrant. Deliberately flag-only: per Aziz's call, a
/// late task stays exactly where its quadrant/order already placed it
/// rather than jumping to the top, so Do First still always leads.
struct LateMarker: View {
    var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .font(.system(size: 10))
            .foregroundColor(.gdError)
    }
}

/// Shown whenever there's nothing open to show — a positive, not empty-
/// feeling, message rather than a blank card, same "never just go blank"
/// rule RoomRaceEmptyView follows for its own no-room state.
struct MatrixEmptyView: View {
    let copy: WidgetCopy

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 20))
                .foregroundColor(.parchmentGreen.opacity(0.8))
            Text(copy.nothingUrgent)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.parchmentInk)
            Text(copy.boardIsClear)
                .font(.system(size: 10.5))
                .foregroundColor(.parchmentSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// The header row shared by Medium/Large: title, open count, "+" quick-add.
/// The Link opens `matrixQuickAddURL` — a real, separate tap target from
/// each row's own checkmark Button, both live in the same widget at once
/// the same way MarkHabitDoneIntent's checkmarks and this app's other free-
/// tap-opens-app behavior already coexist.
struct MatrixHeaderRow: View {
    let openCount: Int
    let copy: WidgetCopy

    var body: some View {
        HStack {
            Text(copy.tasksTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.parchmentInk)
            if openCount > 0 {
                Text(verbatim: "\(openCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.parchmentSecondary)
                    .contentTransition(.numericText())
                    .animation(.default, value: openCount)
            }
            Spacer()
            Link(destination: matrixQuickAddURL) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.parchmentGold)
            }
        }
    }
}

struct MatrixMediumView: View {
    var entry: MatrixEntry

    var body: some View {
        Group {
            if entry.tasks.isEmpty {
                MatrixEmptyView(copy: entry.copy)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    MatrixHeaderRow(openCount: entry.tasks.count, copy: entry.copy)
                    ForEach(Array(entry.tasks.prefix(3))) { task in
                        MatrixTaskRow(task: task)
                    }
                }
                .animation(.easeInOut(duration: 0.35),
                           value: entry.tasks.map { "\($0.id)|\($0.isDone)" })
            }
        }
        .padding()
        .containerBackground(for: .widget) { WidgetParchmentBackground() }
    }
}

/// Mirrors GrowDailyLargeView's habit-list structure closely on purpose —
/// same header-then-rows-then-overflow shape, so the two widgets read as
/// one family despite showing different data.
struct MatrixLargeView: View {
    var entry: MatrixEntry

    var body: some View {
        Group {
            if entry.tasks.isEmpty {
                MatrixEmptyView(copy: entry.copy)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    MatrixHeaderRow(openCount: entry.tasks.count, copy: entry.copy)
                    Divider().background(Color.parchmentBorder)
                    // Was capped at 5 regardless of size, which left a
                    // systemLarge card with obvious empty space below the
                    // list on any board with 6-8 open tasks — 8 comfortably
                    // fits systemLarge's real height on every device size
                    // this ships on; boards past that still fall back to
                    // "+N more in app" rather than risk overflowing a small
                    // physical widget.
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(entry.tasks.prefix(8))) { task in
                            MatrixTaskRow(task: task)
                        }
                    }
                    .animation(.easeInOut(duration: 0.35),
                               value: entry.tasks.map { "\($0.id)|\($0.isDone)" })
                    if entry.tasks.count > 8 {
                        Text(entry.copy.moreInApp(entry.tasks.count - 8))
                            .font(.system(size: 10))
                            .foregroundColor(.parchmentSecondary)
                    }
                }
            }
        }
        .padding()
        .background(cornerMotif(), alignment: .topTrailing)
        .containerBackground(for: .widget) { WidgetParchmentBackground() }
    }
}

/// Small has no room for a header row, a "+" button, and a task list all
/// at once, so it keeps to the same terse "one big number" idiom as
/// GrowDailySmallView/RoomRaceSmallView — the open count, plus the single
/// most urgent task's title underneath if there's room to read it. No
/// interactivity here (no Link, no Button) — same free "tap opens app"
/// fallback the other widgets' Small size already relies on.
struct MatrixSmallView: View {
    var entry: MatrixEntry

    var body: some View {
        Group {
            if entry.tasks.isEmpty {
                MatrixEmptyView(copy: entry.copy)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .foregroundColor(.parchmentGold)
                            .font(.system(size: 14))
                        Text(verbatim: "\(entry.tasks.count)")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundColor(.parchmentInk)
                            .contentTransition(.numericText())
                            .animation(.default, value: entry.tasks.count)
                    }
                    Text(entry.copy.tasksOpen(entry.tasks.count))
                        .font(.system(size: 11))
                        .foregroundColor(.parchmentSecondary)
                    Spacer(minLength: 0)
                    if let top = entry.tasks.first {
                        HStack(spacing: 5) {
                            QuadrantDot(quadrant: top.quadrant, size: 6)
                            Text(top.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(.parchmentInk.opacity(0.8))
                                .lineLimit(1)
                            if top.isLate && !top.isDone {
                                LateMarker()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .containerBackground(for: .widget) { WidgetParchmentBackground() }
    }
}

struct MatrixWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: MatrixEntry

    var body: some View {
        Group {
        switch family {
        case .systemMedium:
            MatrixMediumView(entry: entry)
        case .systemLarge:
            MatrixLargeView(entry: entry)
        default:
            MatrixSmallView(entry: entry)
        }
        }
        // Arabic reads right to left, and these faces are built from
        // leading-aligned stacks, so without this every row stayed pinned
        // to the left with its Arabic text ragged against it. Set once
        // here rather than per face: the switch above is the single root
        // all three sizes pass through.
        .environment(\.layoutDirection, entry.copy.isAr ? .rightToLeft : .leftToRight)
    }
}

struct GrowDailyMatrixWidget: Widget {
    // Must exactly match HomeWidgetService's _iOSMatrixWidgetName
    // (lib/core/services/home_widget_service.dart), same convention as the
    // other two widgets' kind strings above.
    let kind: String = "GrowDailyMatrixWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MatrixProvider()) { entry in
            MatrixWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Matrix"))
        .description(Text("Your most urgent tasks — check them off or add a new one without opening the app."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Matrix Lock Screen widget (starred task)
//
// A fifth widget kind, opt-in from the gallery like Room Race and the
// Matrix Home Screen widget above it — reuses that exact same
// MatrixProvider/MatrixEntry (matrixTasksJson already carries every open
// task, sorted by quadrant priority — see main.dart's _matrixWidgetSub),
// just a different face on the same data: the *starred*
// (WidgetMatrixTask.isFav, mirrors MatrixTask.isFav's gold star toggle on
// the Tasks screen) tasks, falling back to the full list when nothing is
// starred — see MatrixEntry.lockScreenTasks below for why. Unlike the Home
// Screen face it re-sorts that list by each task's time first, see
// MatrixLockScreenOrder.swift.
// Display-only, same reasoning as GrowDailyLockScreenWidget's own
// doc comment above (Lock Screen isn't where you want someone tapping
// fiddly buttons) — unlike the Home Screen Matrix widget's real
// checkmarks, there's deliberately no MarkTaskDoneIntent button here.
//
// A separate widget kind from the existing streak Lock Screen widget
// rather than a replacement for it — someone can place either, both, or
// neither on their Lock Screen from the gallery, same as Room Race's own
// opt-in model.

// Shared "what should this widget actually show?" rule for both faces
// below. Starring is an opt-in most people never discover, and a widget
// that just says "No starred task" to everyone who hasn't found that
// toggle is dead space on their Lock Screen. So: star something and this
// respects it exactly as before (starred-only, that's the whole point of
// starring); star nothing and it quietly falls back to every open task
// on the board, so it's useful out of the box either way.
//
// entry.tasks is open-only from the Dart side (see main.dart's
// _matrixWidgetSub); the only done tasks that can appear are ones
// MarkTaskDoneIntent just marked locally, and inLockScreenOrder keeps
// those at the bottom.
extension MatrixEntry {
    /// Starred tasks when there are any, otherwise every open task, in the
    /// Lock Screen's order (MatrixLockScreenOrder.swift). Judged on the
    /// entry's own date, not the clock at drawing time: iOS draws entries
    /// ahead of time, and the midnight entry has to sort as the new day.
    var lockScreenTasks: [WidgetMatrixTask] {
        let starred = tasks.filter { $0.isFav }
        return (starred.isEmpty ? tasks : starred).inLockScreenOrder(on: date)
    }

    /// True when [lockScreenTasks] is the fallback list rather than a real
    /// starred selection — drives the icon swap so the two states are
    /// always distinguishable at a glance.
    var lockScreenIsFallback: Bool { !tasks.contains { $0.isFav } }

    var lockScreenIcon: String { lockScreenIsFallback ? "checklist" : "star.fill" }

    // Both faces below count against the WHOLE board, never against
    // `lockScreenTasks`.
    //
    // Starring picks what to *show*; it must not change what gets *counted*.
    // Counting the starred subset meant that starring one task out of nine
    // made the widget report a board of one: the ring's centre label read
    // "1" with eight tasks still open, and the rectangular face showed the
    // starred title with no overflow line, so the other eight were invisible
    // and unmentioned. A glanceable surface that under-reports how much is
    // left is worse than no surface — it's the one number someone acts on
    // without opening the app.
    // App-completed tasks (doneToday) never appear in the open-only list;
    // widget-checkmark completions (MarkTaskDoneIntent) flip isDone in
    // place and stay in the list until the app next rewrites it. Both are
    // progress; count both. The denominator grows by doneToday for the
    // same reason: those tasks left the list but not the day.
    var lockScreenDone: Int { tasks.filter { $0.isDone }.count + doneToday }
    var lockScreenTotal: Int { tasks.count + doneToday }
    var lockScreenRemaining: Int { lockScreenTotal - lockScreenDone }
}

struct MatrixLockScreenCircularView: View {
    var entry: MatrixEntry
    // The whole board, not entry.lockScreenTasks — see lockScreenRemaining.
    // The star icon still says "you have starred tasks"; the number says how
    // much is actually left, which is a different question.
    private var total: Int { entry.lockScreenTotal }
    private var doneCount: Int { entry.lockScreenDone }
    private var remaining: Int { entry.lockScreenRemaining }

    var body: some View {
        if entry.tasks.isEmpty && entry.doneToday == 0 {
            // Only when there's genuinely nothing on the board at all —
            // "nothing starred" alone no longer lands here, it falls back
            // to the full list above. An empty list WITH doneToday > 0 is
            // the opposite of nothing: it's a finished day, and it falls
            // through to the ring below, full, with the checkmark — a
            // state that used to be unreachable because completing the
            // last task emptied the list.
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "checklist")
                    .font(.system(size: 16))
            }
        } else {
            // A capacity ring (same idiom as RoomRaceCircularView's percent
            // ring below) showing today's task progress at a glance, not
            // just a flat total — the center label is the still-open count
            // so there's still an immediate "how many are left" answer, or
            // a checkmark once there's nothing left open.
            Gauge(value: Double(doneCount), in: 0...Double(total)) {
                Image(systemName: entry.lockScreenIcon)
            } currentValueLabel: {
                if remaining == 0 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                } else {
                    Text(verbatim: "\(remaining)")
                        .font(.system(size: 14, weight: .bold))
                        .contentTransition(.numericText())
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .animation(.default, value: doneCount)
        }
    }
}

struct MatrixLockScreenRectangularView: View {
    var entry: MatrixEntry

    /// This accessory family has room for about three lines of text. That's
    /// a budget to *spend*, not a per-task cap — the previous version put
    /// `lineLimit(1)` on every title regardless, so a single task with a
    /// long title got cut to "اسوي الاشعارات واتاكد ان..." while two
    /// perfectly good empty lines sat underneath it.
    private static let lineBudget = 3

    private var shown: [WidgetMatrixTask] { entry.lockScreenTasks }

    /// The tasks that actually get drawn, and how many are left over.
    ///
    /// The overflow counts against the WHOLE board, not against the starred
    /// subset being drawn. Counting inside the subset meant one starred task
    /// out of nine produced `shown.count == 1`, which is under the line
    /// budget, so no overflow line was drawn at all — the widget showed one
    /// title and silently omitted that eight other tasks were open. "+8 more"
    /// is the entire point of starring one thing: it stays the focus, and the
    /// rest is still accounted for.
    ///
    /// So a line is spent on the summary whenever anything is being left out,
    /// whether that's because the starred selection is narrower than the
    /// board or because the board is simply longer than three lines.
    private var visible: (tasks: [WidgetMatrixTask], overflow: Int) {
        let boardCount = entry.tasks.count
        let needsSummary = shown.count > Self.lineBudget || boardCount > shown.count
        guard needsSummary else { return (shown, 0) }
        let head = Array(shown.prefix(Self.lineBudget - 1))
        return (head, boardCount - head.count)
    }

    /// Splits the line budget across however many titles are being shown,
    /// front-loading the remainder onto the highest-priority task.
    ///
    ///  - 1 task  → 3 lines (it gets the whole budget, wraps fully)
    ///  - 2 tasks → 2 lines for the first, 1 for the second
    ///  - 3 tasks → 1 line each
    ///  - 4+       → 1 line each for two titles, 1 for "+N more"
    ///
    /// So a short title never leaves dead space, and a long one is only
    /// clipped when something else genuinely needs the room.
    private func lines(for index: Int, count: Int, hasOverflow: Bool) -> Int {
        guard count > 0 else { return 1 }
        let usable = Self.lineBudget - (hasOverflow ? 1 : 0)
        let base = usable / count
        let remainder = usable % count
        return max(1, base + (index < remainder ? 1 : 0))
    }

    var body: some View {
        let (tasks, overflow) = visible
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: entry.lockScreenIcon)
                .font(.system(size: 11))
            if tasks.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.copy.noTasks)
                        .font(.system(size: 12, weight: .semibold))
                    Text(entry.copy.addOneInMatrix)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        Text(task.title)
                            .font(.system(size: 11.5,
                                          weight: index == 0 ? .semibold : .regular))
                            .lineLimit(lines(for: index,
                                             count: tasks.count,
                                             hasOverflow: overflow > 0))
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if overflow > 0 {
                        // One wording for both states. It used to say
                        // "+N more starred" in the starred case, which is
                        // now actively wrong: the overflow is the rest of
                        // the *board*, which is mostly unstarred. "+N more"
                        // means the same thing either way — more open tasks
                        // you aren't seeing.
                        Text(entry.copy.moreTasks(overflow))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct MatrixLockScreenView: View {
    @Environment(\.widgetFamily) var family
    var entry: MatrixEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                MatrixLockScreenRectangularView(entry: entry)
            default:
                MatrixLockScreenCircularView(entry: entry)
            }
        }
        .widgetURL(lockScreenOpenURL(tab: "matrix"))
        // Arabic on the Lock Screen too. Only the three Home Screen
        // families got this in the first pass, so an Arabic user's Lock
        // Screen kept laying its rows out left to right while the Home
        // Screen above it read correctly. Found by reading rather than by
        // looking: the simulator's Lock Screen editor would not render.
        .environment(\.layoutDirection, entry.copy.isAr ? .rightToLeft : .leftToRight)
    }
}

struct GrowDailyMatrixLockScreenWidget: Widget {
    // Must exactly match HomeWidgetService's _iOSMatrixLockScreenWidgetName
    // (lib/core/services/home_widget_service.dart), same convention as
    // every other widget kind string in this file.
    let kind: String = "GrowDailyMatrixLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MatrixProvider()) { entry in
            MatrixLockScreenView(entry: entry)
        }
        .configurationDisplayName(Text("Starred Tasks"))
        .description(Text("Your starred tasks on the Lock Screen — or your top tasks if you haven't starred any."))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Bundle

/// The gallery walks this list in order, so the order IS the arrangement:
/// the first thing someone sees when they go looking for a widget. Aziz
/// asked on 2026-09-23 for the useful ones to come first, so it runs by how
/// often a face changes and how much it is worth glancing at, Home Screen
/// before Lock Screen within each:
///
///   1. Prayer     changes every second, useful every day, needs no setup
///   2. Habits     the app's own subject, and the only tappable face
///   3. Tasks      useful to whoever lives on the Tasks page
///   4. Rooms      only says anything while a room is actually running
///
/// Nothing is removed. Four kinds, 20 faces; the cost of a kind is the
/// gallery pages it adds, and the cost of REMOVING one is that it
/// disappears from the Home Screen of anyone who already placed it, which
/// is not something to do to shipped users for tidiness.
@main
struct GrowDailyWidgetBundle: WidgetBundle {
    var body: some Widget {
        GrowDailyPrayerWidget()
        GrowDailyPrayerLockScreenWidget()
        GrowDailyWidget()
        GrowDailyLockScreenWidget()
        GrowDailyMatrixWidget()
        GrowDailyMatrixLockScreenWidget()
        GrowDailyRoomRaceWidget()
        GrowDailyRoomRaceLockScreenWidget()
        // The ringing screen of an alarm-mode reminder, see
        // GrowDailyAlarmLiveActivity.swift. iOS 26 only; older systems have
        // no AlarmKit and never start this activity.
        if #available(iOS 26.0, *) {
            GrowDailyAlarmLiveActivity()
        }
        // The Lock Screen's bottom slots, Control Center and the Action
        // Button, see GrowDailyControls.swift. iOS 18 only; before that
        // there are no controls to put anywhere.
        if #available(iOS 18.0, *) {
            GrowDailyHabitsControl()
            GrowDailyTasksControl()
            GrowDailyAddTaskControl()
        }
    }
}
