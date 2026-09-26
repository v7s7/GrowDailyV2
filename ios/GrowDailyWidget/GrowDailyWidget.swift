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
//
// TodayHabit and RoomRaceRow live in WidgetFaceRules.swift, beside the rules
// that order and pick them, so all of it compiles on the Mac without
// WidgetKit.

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
    let completedToday: Int
    let totalToday: Int
    let habits: [TodayHabit]
}

struct GrowDailyProvider: TimelineProvider {
    func placeholder(in context: Context) -> GrowDailyEntry {
        GrowDailyEntry(date: Date(), streak: 3, completedToday: 1, totalToday: 3,
                       habits: [TodayHabit(id: "1", name: "Fajr Dhikr", done: true),
                                TodayHabit(id: "2", name: "Read Quran", done: false)])
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
            completedToday: defaults?.integer(forKey: "completedToday") ?? 0,
            totalToday: defaults?.integer(forKey: "totalToday") ?? 0,
            habits: readJSON("todayHabitsJson", from: defaults, as: [TodayHabit].self) ?? []
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
///  1. Records one completion in the cached today-list
///     (TodayHabit.recordOneCompletion, the rule a lock-screen «تمت»
///     follows), so the one reload iOS guarantees right after `perform()`
///     returns shows it: checked for a once-a-day habit, one step further
///     along for a counted one.
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
        // Decided before the list is rewritten, from the counts as they
        // stood before this tap.
        let finishes = habitTapFinishesDay(habitId, in: defaults)
        // One clock reading for the whole tap: the day it is queued under and
        // the day whose reminders it takes down have to be the same day, even
        // if midnight falls between the two lines.
        let day = appDayKey(Date())

        if var habits = readJSON("todayHabitsJson", from: defaults, as: [TodayHabit].self) {
            for i in habits.indices where habits[i].id == habitId {
                habits[i].recordOneCompletion()
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
/// missing, which is how a list re-encoded by a build before 2026-09-24
/// reads (TodayHabit keeps the pair since then).
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

/// completedToday/totalToday as a small ring. Hand-rolled with
/// Circle().trim rather than ProgressView(value:) so it renders identically
/// across OS versions. Turns amber instead of emerald in the evening if
/// there's still something left today. The sweep animates on refresh (see
/// Apple's "Animating data updates in widgets and Live Activities") rather
/// than snapping straight to the new value — this is used at two different
/// sizes (34pt on Small, 56pt on Medium; see call sites), so nothing here
/// is a fixed-point size: an earlier version added a small dot riding the
/// progress head at a hardcoded offset, which would have landed at roughly
/// the right radius on one of those two sizes and visibly floating in the
/// wrong place on the other — cut rather than fixed with a GeometryReader
/// this file has no way to check on-device before shipping.
struct ProgressRing: View {
    let completed: Int
    let total: Int
    /// The count at the centre. 11pt suits the small face's 34pt ring; the
    /// medium's 54pt ring reads better with a larger figure.
    var fontSize: CGFloat = 11
    var lineWidth: CGFloat = 4
    var progress: Double { total <= 0 ? 0 : min(1, Double(completed) / Double(total)) }
    private var isUrgent: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 18 && total > 0 && completed < total
    }
    private var ringColor: Color { isUrgent ? .parchmentWarn : .themeGreen }

    var body: some View {
        ZStack {
            // The unfilled track, which on cream must stay behind the arc
            // rather than compete with it.
            Circle().stroke(Color.parchmentBorder.opacity(0.28), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            Text(verbatim: "\(completed)/\(total)")
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(.parchmentInk)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.default, value: completed)
        }
    }
}


// MARK: - Habit rows
//
// Aziz, 2026-09-24, on the large face: "show it as habit, not as tasks". The
// rows used to be a checklist, a round tick and a name struck through once
// done, which is exactly how the Tasks widget draws a task. A habit in this
// app is drawn the Grid's way: its category glyph in a tinted tile beside
// its name, and a square for today. So the rows below are a Grid row with
// one column: the tile, the name, and today's square, which is also the
// button. Done is a filled square with a tick, never a struck-through name.

/// The Grid's glyph for a habit's category (CategoryIcon in the app): the
/// app's own drawn art for five categories, the Material icon it falls back
/// to for the rest. Copied into this target's asset catalog as template
/// images, because a widget extension cannot read Flutter's assets/.
struct HabitGlyph: View {
    let category: String?

    /// HabitCategory.iconAsset first, then HabitCategory.icon, exactly the
    /// choice CategoryIcon makes.
    static func assetName(for category: String?) -> String {
        switch category {
        case "quran", "athkar": return "HabitGlyphQuran"
        case "fitness": return "HabitGlyphFitness"
        case "focus": return "HabitGlyphFocus"
        case "sadaqah", "money": return "HabitGlyphCharity"
        case "sleep": return "HabitGlyphSleep"
        case "faith": return "HabitGlyphMosque"
        case "fasting": return "HabitGlyphNoFood"
        case "health": return "HabitGlyphHeart"
        case "learning": return "HabitGlyphSchool"
        case "mind": return "HabitGlyphMind"
        case "social": return "HabitGlyphGroups"
        default: return "HabitGlyphStar"
        }
    }

    var body: some View {
        Image(Self.assetName(for: category))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
    }
}

/// The colour a habit's glyph is drawn in: its own picked colour when it has
/// one, as on the Grid (`habit.customColor ?? categoryColor`), and the
/// category's otherwise (categoryVisual in grid_screen.dart). Every one of
/// them as parchment ink, since the brand colours do not read on cream.
func habitInk(_ habit: TodayHabit) -> Color {
    if let own = Color.parchmentInk(hex: habit.color) { return own }
    switch habit.category {
    case "health", "fitness": return .parchmentStreak
    case "learning", "focus": return .parchmentXp
    case "money": return .parchmentWarn
    case "mind": return .parchmentPurple
    case "sleep": return .parchmentSleep
    case "social", "custom", nil: return .themeGold
    default: return .themeGreen // faith, fasting, quran, athkar, sadaqah
    }
}

/// The Grid's habit tile: the glyph on a 14% wash of its own colour, in a
/// rounded square (22pt with a 13pt glyph and a 7pt corner on the Grid; the
/// same proportions at whatever size a face asks for).
struct HabitIconTile: View {
    let habit: TodayHabit
    var size: CGFloat = 20

    var body: some View {
        let ink = habitInk(habit)
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(ink.opacity(0.14))
            .frame(width: size, height: size)
            .overlay(
                HabitGlyph(category: habit.category)
                    .foregroundColor(ink)
                    .frame(width: size * 0.6, height: size * 0.6)
            )
    }
}

/// Today's square for a habit, in the Grid's own vocabulary: an open square
/// ringed in gold (the Grid's today column), filled green with a tick once
/// done, part-filled with its count ("1/3") for a counted habit on its way,
/// and the soft emerald of a covered day for a row the day did not ask for
/// (see [[covered-day-state]]: "nothing was owed" must not look like "not
/// done").
struct HabitDaySquare: View {
    let habit: TodayHabit
    var size: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        let partial = !habit.done && habit.timesDone > 0
        let resting = !habit.done && !habit.isDue
        ZStack {
            if habit.done {
                shape.fill(Color.themeGreenFill)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .heavy))
                    .foregroundColor(.white)
            } else if partial {
                shape.fill(Color.themeGreenFill.opacity(0.32))
                shape.stroke(Color.themeGreenFill, lineWidth: 1.2)
                Text(verbatim: "\(habit.timesDone)/\(habit.target)")
                    .font(.system(size: size * 0.36, weight: .heavy))
                    .foregroundColor(.parchmentInk)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 1)
            } else if resting {
                shape.fill(Color.themeGreenFill.opacity(0.18))
            } else {
                shape.fill(Color.parchmentSurface.opacity(0.55))
                shape.stroke(Color.themeGold, lineWidth: 1.3)
            }
        }
        .frame(width: size, height: size)
        .contentTransition(.opacity)
        .animation(.default, value: habit.timesDone)
    }
}

/// One habit, drawn as a Grid row with a single day: tile, name, square.
///
/// Only the square is a button, as only the square is on the Grid, and only
/// while there is something left to do: a finished habit has nothing a tap
/// could add, and a second completion queued by accident would be paid.
/// A tap anywhere else on the face opens the app.
struct HabitWidgetRow: View {
    let habit: TodayHabit
    let copy: WidgetCopy
    var tile: CGFloat = 20
    var square: CGFloat = 20
    var fontSize: CGFloat = 12.5
    /// Two lets a long name wrap rather than lose its end.
    var nameLines: Int = 1
    /// Between the tile, the name and the square. The small face tightens
    /// it: its row is about 128pt, and at 8 the gaps alone took a fifth.
    var spacing: CGFloat = 8
    /// How far a name may shrink before it is cut. The small face allows a
    /// little, so «قراءة القرآن» fits whole instead of «قراءة الق…».
    var nameMinScale: CGFloat = 1

    var body: some View {
        let resting = !habit.isDue && !habit.done
        HStack(spacing: spacing) {
            HabitIconTile(habit: habit, size: tile)
            Text(habit.name)
                .font(.system(size: fontSize, weight: habit.done ? .medium : .semibold))
                .foregroundColor(habit.done || resting ? .parchmentSecondary : .parchmentInk)
                .lineLimit(nameLines)
                .minimumScaleFactor(nameMinScale)
                // First claim on the row's width. Without it an HStack splits
                // the free space between the name and the Spacer beside it,
                // and the small face cut «قراءة القرآن» to «قراءة الق…» with
                // half the row still empty (seen in the gallery 2026-09-24).
                .layoutPriority(1)
            if resting {
                // A day you may train on but do not owe: said in words as
                // well as by the square, so an empty square here is never
                // read as a habit left undone.
                Text(copy.notDue)
                    .font(.system(size: max(8.5, fontSize - 3.5), weight: .semibold))
                    .foregroundColor(.themeGreen)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            if habit.done {
                HabitDaySquare(habit: habit, size: square)
            } else {
                Button(intent: MarkHabitDoneIntent(habitId: habit.id)) {
                    HabitDaySquare(habit: habit, size: square)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The streak as the room row and the Grid show it: the flame and a number,
/// with the days spelt out beside it when there is room. «4 أيام», not
/// «4 يوم»: Arabic counts days in three shapes (WidgetCopy.daysWord).
struct StreakBadge: View {
    let streak: Int
    let copy: WidgetCopy
    var size: CGFloat = 12
    var showWord: Bool = true

    var body: some View {
        HStack(spacing: 3) {
            FlameIcon(size: size)
            Text(verbatim: showWord ? copy.daysWord(streak) : "\(streak)")
                .font(.system(size: size, weight: .bold))
                .foregroundColor(.parchmentStreak)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.default, value: streak)
        }
        .fixedSize()
    }
}

// MARK: - Habit faces
//
// Rebuilt 2026-09-24. Aziz on the medium face: "what is 4005, xp? no one
// cares, please add useful things that people love". The 4,005 was his gold
// balance and «مستوى 17» his level: two numbers about the game, on the one
// surface that should be about today. Both are gone from every Habits face.
// What took their place is the thing a habit widget is for: today's open
// habits, each one tap from done, without opening the app.

/// Today's share of what the day asked for, as one thin bar: the ring's
/// fraction without the ring's space. Green, and amber in the evening while
/// something is still open, the same rule ProgressRing follows.
struct DayProgressBar: View {
    let completed: Int
    let total: Int
    var height: CGFloat = 6

    private var progress: Double { total <= 0 ? 0 : min(1, Double(completed) / Double(total)) }
    private var isUrgent: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 18 && total > 0 && completed < total
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.parchmentSurface)
                Capsule()
                    .fill(isUrgent ? Color.parchmentWarn : Color.themeGreenFill)
                    .frame(width: geo.size.width * progress)
                    .animation(.easeOut(duration: 0.6), value: progress)
            }
        }
        .frame(height: height)
    }
}

/// The one line both compact faces open with: today's count on the leading
/// side («4 من 9», green once it is full), the streak's flame and number on
/// the other. Nothing more: Aziz asked for the count alone on 2026-09-24.
struct HabitStatusLine: View {
    let entry: GrowDailyEntry
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.totalToday > 0
                 ? entry.copy.todayCount(entry.completedToday, entry.totalToday)
                 : entry.copy.noHabitsToday)
                .font(.system(size: size, weight: .heavy))
                .foregroundColor(entry.totalToday <= 0 ? .parchmentSecondary
                                 : entry.completedToday >= entry.totalToday
                                 ? .themeGreen : .parchmentInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
                .contentTransition(.opacity)
                .animation(.default, value: entry.completedToday)
            Spacer(minLength: 4)
            StreakBadge(streak: entry.streak, copy: entry.copy, size: size - 1, showWord: false)
        }
    }
}

/// Small: today's count («4 من 9») and the streak on one line, then the
/// next three open habits, each one tap from done.
///
/// Rebuilt twice on 2026-09-24. The first pass put the streak and a ring on
/// the top half and a single habit under them; Aziz: "the upper part still
/// not useful ... widget should be for quick and useful flow". The ring
/// repeated what the line above the list already says in words, so it went,
/// and its half of the card now holds two more habits.
struct GrowDailySmallView: View {
    var entry: GrowDailyEntry

    static let habitRows = 3

    private var open: [TodayHabit] {
        widgetHabitOrder(entry.habits).filter { !$0.done && $0.isDue }
    }

    var body: some View {
        let open = open
        VStack(alignment: .leading, spacing: 8) {
            HabitStatusLine(entry: entry, size: 12)
            if open.isEmpty {
                Spacer(minLength: 0)
                // Nothing left: the line above already says so in words;
                // this is the one mark that says it at a glance.
                Image(systemName: entry.totalToday > 0 ? "checkmark.seal.fill" : "leaf")
                    .font(.system(size: 34))
                    .foregroundColor(entry.totalToday > 0 ? .themeGreen : .parchmentSecondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                // Rows sized to the card: three of them fill what the
                // status line leaves, and a 25pt square with a 9pt gap is a
                // target a thumb can hit without landing on its neighbour.
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(open.prefix(Self.habitRows))) { habit in
                        HabitWidgetRow(habit: habit, copy: entry.copy,
                                       tile: 20, square: 24, fontSize: 12,
                                       spacing: 6, nameMinScale: 0.85)
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: open.map(\.id))
                Spacer(minLength: 0)
            }
        }
        // The family's content margin is the inset; see RoomRaceSmallView.
        .padding(2)
        .containerBackground(for: .widget) { WidgetParchmentBackground() }
    }
}

/// Medium: today's ring and streak on one side, and on the other the habits
/// still open, each with its square to tap. Only open ones: a medium card
/// has room for three rows, and a row spent on a finished habit is a row
/// that cannot be used. When nothing is left, the side says the day is done.
struct GrowDailyMediumView: View {
    var entry: GrowDailyEntry

    static let habitRows = 3

    private var open: [TodayHabit] {
        widgetHabitOrder(entry.habits).filter { !$0.done && $0.isDue }
    }

    var body: some View {
        let open = open
        HStack(spacing: 14) {
            VStack(spacing: 8) {
                ProgressRing(completed: entry.completedToday, total: entry.totalToday,
                             fontSize: 15, lineWidth: 5)
                    .frame(width: 56, height: 56)
                StreakBadge(streak: entry.streak, copy: entry.copy, size: 11)
            }
            .frame(width: 76)

            VStack(alignment: .leading, spacing: 8) {
                if open.isEmpty {
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        if entry.totalToday > 0 {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.themeGreen)
                        }
                        Text(entry.totalToday > 0
                             ? entry.copy.allDoneToday
                             : entry.copy.noHabitsToday)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.parchmentInk)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(open.prefix(Self.habitRows))) { habit in
                        HabitWidgetRow(habit: habit, copy: entry.copy)
                    }
                    if open.count > Self.habitRows {
                        Text(entry.copy.moreInApp(open.count - Self.habitRows))
                            .font(.system(size: 10))
                            .foregroundColor(.parchmentSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.35), value: open.map(\.id))
        }
        .padding(.horizontal, 2)
        .containerBackground(for: .widget) { WidgetParchmentBackground() }
    }
}

/// Large: today's count and a thin bar for how much of it is done, then the
/// whole day's habits, open first and finished at the bottom
/// (widgetHabitOrder), each one tap from done.
///
/// The month grid that used to fill the top half is gone (Aziz, 2026-09-24:
/// "if user wants to see his month work, he can check in app, widget should
/// be for quick and useful flow"). Its space went to rows: nine fit, which
/// is a whole ordinary day, so the face usually shows everything today holds
/// and the open ones are always the ones that win a row.
struct GrowDailyLargeView: View {
    var entry: GrowDailyEntry

    /// How many habits fit under the line and the bar: nine rows of 22pt at
    /// a 7pt gap is about 254pt of a large card's ~334, with room left for
    /// the «باقي N بالتطبيق» line under them.
    static let habitRows = 9

    var body: some View {
        let ordered = widgetHabitOrder(entry.habits)
        let shown = Array(ordered.prefix(Self.habitRows))
        // Owed and still open. A row the day did not ask for is not
        // «باقي», and neither is a finished one.
        let hiddenOpen = ordered.dropFirst(Self.habitRows).filter { !$0.done && $0.isDue }.count
        // Where the finished habits begin, for the hairline between the two
        // groups: the list reads "still to do", then "done".
        let firstDone = shown.firstIndex { $0.done }
        VStack(alignment: .leading, spacing: 10) {
            HabitStatusLine(entry: entry, size: 13.5)
            DayProgressBar(completed: entry.completedToday, total: entry.totalToday)

            if entry.habits.isEmpty {
                Text(entry.copy.noHabitsToday)
                    .font(.system(size: 12))
                    .foregroundColor(.parchmentSecondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, habit in
                        if index == firstDone, index > 0 {
                            Rectangle()
                                .fill(Color.parchmentBorder.opacity(0.35))
                                .frame(height: 0.5)
                        }
                        HabitWidgetRow(habit: habit, copy: entry.copy,
                                       tile: 20, square: 22, fontSize: 13)
                    }
                }
                .animation(.easeInOut(duration: 0.35),
                           value: shown.map { "\($0.id)|\($0.timesDone)" })
                if hiddenOpen > 0 {
                    Text(entry.copy.moreInApp(hiddenOpen))
                        .font(.system(size: 10.5))
                        .foregroundColor(.parchmentSecondary)
                }
            }
        }
        // From the top: a list starts where it is read from.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 2)
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
        // A tap anywhere but a habit's square opens the habit board, as the
        // Lock Screen streak face does. The squares are buttons and keep
        // their own taps.
        .widgetURL(lockScreenOpenURL(tab: "grid"))
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
// deliberately add it from the widget gallery. Shows one room: the one
// rooms_notifier.dart's myRoomRaceSnapshotProvider picks (a starred room
// first), already ranked and already graded on the Dart side, which is where
// every number here is computed. This file only draws the finished result
// HomeWidgetService.updateRoomRaceData wrote.
//
// ── What it draws, since 2026-09-24 ──────────────────────────────────
// The room screen's own list. Aziz, on the faces built the day before:
// "make it same as the one in rooms. the small one shows the last 7 days,
// and the points of total, same as rooms, and the big ones shows same as
// the list in the room, show a month". So:
//
//   small   me and the racer next to me, each with the room row's compact
//           seven days and its «24.2 من 42»
//   medium  the ranked list, three rows, a month of days on each
//   large   the room's «اليوم» count on top, then, for up to three racers,
//           each one's month as the room's «كل الأيام» calendar beside
//           their place, percentage, count, flame and bar; for more, the
//           medium's rows with that line under each, five of them
//
// Every day is drawn from the room strip's own states (RoomDayMark, decoded
// from roomRaceDayCode): a miss is crossed, a rest is soft green, a تخطّي is
// grey, a paused day is a dash, today still open is faint, and today wears
// the gold border, all as on the room screen. The days run the way the room
// row's run: oldest at the leading edge, today at the trailing end, so in
// Arabic today is on the left, as it is in the room.
//
// Avatars are not drawn: the character art is a set of PNGs in the Runner
// target only, and a widget extension has its own asset catalog. The place,
// the name and the tags carry the row, as they do beside the avatar in the
// app.

struct RoomRaceEntry: TimelineEntry {
    let date: Date
    var copy: WidgetCopy = WidgetCopy(isAr: false)
    let hasRoom: Bool
    let roomName: String
    let isLive: Bool
    let daysRemaining: Int
    /// A team room ranks nobody on its own screen, so no places here either.
    var isTeam: Bool = false
    /// The day every strip ends on (RoomRaceSnapshot.stripEndDay).
    var stripEndDay: String = ""
    let rows: [RoomRaceRow]

    /// Whether the strips' last cell is today on this entry's own clock. A
    /// strip written yesterday and not refreshed since keeps its cells but
    /// loses the gold border: yesterday must not be drawn as today. The
    /// provider adds a midnight entry for exactly this.
    var stripEndsToday: Bool { !stripEndDay.isEmpty && stripEndDay == appDayKey(date) }

    /// The room's «اليوم» card: who was asked something today, and how many
    /// of them finished it (RoomTodayCard, over the same unblocked roster).
    var todayCounted: Int { rows.filter { $0.countsToday == true }.count }
    var todayFinished: Int { rows.filter { $0.countsToday == true && $0.doneToday == true }.count }
}

struct RoomRaceProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoomRaceEntry {
        // Varied strips, not all-full, so the gallery preview shows what a
        // miss, a rest and a paused day look like before anyone has a room.
        RoomRaceEntry(date: Date(), hasRoom: true, roomName: "Ramadan Push", isLive: true,
                      daysRemaining: 12, stripEndDay: appDayKey(Date()),
                      rows: [RoomRaceRow(name: "You", rank: 1, percent: 86, isMe: true,
                                         daysDone: 12, daysTotal: 14, score: 12, scoreText: "12",
                                         streak: 5, doneToday: true, countsToday: true,
                                         days: "................4434r4443x4444"),
                             RoomRaceRow(name: "Omar", rank: 2, percent: 74, isMe: false,
                                         daysDone: 10, daysTotal: 14, score: 10.5, scoreText: "10.5",
                                         streak: 2, isLeader: true, countsToday: true,
                                         days: "................42x4pp4424x44o")])
    }

    func getSnapshot(in context: Context, completion: @escaping (RoomRaceEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoomRaceEntry>) -> Void) {
        let now = Date()
        // Same fallback-only cadence as GrowDailyProvider — the real
        // refresh trigger is HomeWidgetService.updateRoomRaceData firing
        // from main.dart's _roomRaceSub whenever Firestore's room/
        // participant data actually changes, or the day turns.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: now)!
        // Plus an entry at midnight, drawn whether or not iOS grants the
        // hourly reload: that is when the strips' last cell stops being
        // today (RoomRaceEntry.stripEndsToday).
        let calendar = Calendar(identifier: .gregorian)
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        completion(Timeline(entries: [loadEntry(at: now), loadEntry(at: midnight)], policy: .after(next)))
    }

    private func loadEntry(at date: Date = Date()) -> RoomRaceEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        struct RawRaceData: Codable {
            let hasRoom: Bool
            let roomName: String
            let isLive: Bool
            let daysRemaining: Int
            let isTeam: Bool?
            let stripEndDay: String?
            let rows: [RoomRaceRow]
        }
        guard let raw = readJSON("roomRaceJson", from: defaults, as: RawRaceData.self) else {
            return RoomRaceEntry(date: date, copy: WidgetCopy.fromDefaults(), hasRoom: false,
                                 roomName: "", isLive: false, daysRemaining: 0, rows: [])
        }
        return RoomRaceEntry(date: date, copy: WidgetCopy.fromDefaults(),
                             hasRoom: raw.hasRoom, roomName: raw.roomName,
                             isLive: raw.isLive, daysRemaining: raw.daysRemaining,
                             isTeam: raw.isTeam ?? false, stripEndDay: raw.stripEndDay ?? "",
                             rows: raw.rows)
    }
}

/// A place, or a dash when there isn't one yet. The Lock Screen faces'
/// badge, where a cup does not fit a 58pt circle.
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

/// The mark on a paused day: one short bar, the room strip's
/// _StandDownBarPainter.
private struct DayDashShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.28, y: rect.midY))
        return p
    }
}

/// The cross on a missed day, inset so it never touches the cell's own
/// edge: the room strip's _MissCrossPainter.
private struct DayCrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: rect.width * 0.27, dy: rect.height * 0.27)
        var p = Path()
        p.move(to: CGPoint(x: inset.minX, y: inset.minY))
        p.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY))
        p.move(to: CGPoint(x: inset.maxX, y: inset.minY))
        p.addLine(to: CGPoint(x: inset.minX, y: inset.maxY))
        return p
    }
}

/// One day of a racer's strip, painted the way roomStripCellFill paints the
/// same state in the room (room_detail_screen_leaderboard_extend.dart), in
/// the parchment's colours.
struct RoomDayCell: View {
    let mark: RoomDayMark
    var isToday: Bool = false
    var corner: CGFloat = 2

    /// The credit ramp. Empty is a whisper on both sheets and every filled
    /// step climbs above it. On the dark card a LOW opacity read as faint;
    /// on cream the same numbers made the emptiest days the loudest thing in
    /// a strip, which is why the ramp was rebuilt for the parchment.
    private func levelColor(_ level: Int) -> Color {
        switch level {
        case 1: return Color.themeGreenFill.opacity(0.38)
        case 2: return Color.themeGreenFill.opacity(0.58)
        case 3: return Color.themeGreenFill.opacity(0.78)
        case 4: return Color.themeGreenFill
        default: return Color.parchmentSurface
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack {
            switch mark {
            case .outside:
                Color.clear
            case .standDown:
                shape.fill(Color.parchmentSurface)
                DayDashShape()
                    .stroke(Color.parchmentSecondary.opacity(0.7),
                            style: StrokeStyle(lineWidth: 1, lineCap: .round))
            case .pending:
                // Half the stand-down wash: "not yet", never an outcome.
                shape.fill(Color.parchmentSurface.opacity(0.5))
            case .declaredRest:
                // Neutral, like the Grid's تخطّي square: nothing earned,
                // nothing lost.
                shape.fill(Color.parchmentSecondary.opacity(0.3))
            case .rest:
                // A granted rest: soft, under the ramp's lowest step.
                shape.fill(Color.themeGreenFill.opacity(0.22))
            case .missed:
                shape.fill(Color.parchmentSurface)
                shape.stroke(Color.parchmentMiss.opacity(0.45), lineWidth: 0.8)
                DayCrossShape()
                    .stroke(Color.parchmentMiss, style: StrokeStyle(lineWidth: 1, lineCap: .round))
            case .level(let level):
                shape.fill(levelColor(level))
            }
            if isToday && mark != .outside {
                // Gold means "today" everywhere in this app.
                shape.stroke(Color.themeGold, lineWidth: 1.3)
            }
        }
    }
}

/// A racer's days as one line of squares, sized to whatever width it is
/// given. Follows the face's direction, as the room row's does: the oldest
/// day at the leading edge and today at the trailing end, which is the left
/// in Arabic. A slightly wider gap opens before each Saturday, so a month
/// reads as its weeks.
struct RoomDayStrip: View {
    let marks: [RoomDayMark]
    var todayIndex: Int? = nil
    var weekStarts: Set<Int> = []
    var gap: CGFloat = 1.5
    var weekGap: CGFloat = 4
    var corner: CGFloat = 2

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(marks.enumerated()), id: \.offset) { index, mark in
                if index > 0 {
                    Color.clear.frame(width: weekStarts.contains(index) ? weekGap : gap, height: 1)
                }
                RoomDayCell(mark: mark, isToday: index == todayIndex, corner: corner)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// A racer's month as the room screen's «كل الأيام» calendar: Saturday-start
/// week columns under their month's name, a week that straddles two months
/// split into two columns with the wider month gap between them, every day on
/// its weekday row, Saturday at the top (roomCalendarColumns, the port of the
/// room's roomStripColumns). Columns follow the face's direction as the
/// room's do, so in Arabic the oldest week is on the right.
struct RoomMonthCalendar: View {
    /// The whole strip, indexed as [columns] index it.
    let marks: [RoomDayMark]
    let columns: [RoomCalendarColumn]
    let todayIndex: Int?
    let copy: WidgetCopy
    var cell: CGFloat = 12
    var gap: CGFloat = 2.5
    var monthGap: CGFloat = 7

    /// Consecutive columns of one month, for the name over them.
    private var segments: [(month: Int, span: Int)] {
        var out: [(key: Int, month: Int, span: Int)] = []
        for column in columns {
            if let last = out.last, last.key == column.monthKey {
                out[out.count - 1].span += 1
            } else {
                out.append((column.monthKey, column.month, 1))
            }
        }
        return out.map { ($0.month, $0.span) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Color.clear.frame(width: monthGap, height: 1)
                    }
                    // Allowed to spill past a one-week month into the gap
                    // beside it, as RoomStripMonthLabel does: a cut name
                    // («سب…») names nothing.
                    Text(copy.monthShort(segment.month))
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.parchmentSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: CGFloat(segment.span) * cell
                               + CGFloat(max(0, segment.span - 1)) * gap)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    if index > 0 {
                        Color.clear.frame(
                            width: column.monthKey != columns[index - 1].monthKey ? monthGap : gap,
                            height: 1)
                    }
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { row in
                            let day = column.rows[row]
                            if day >= 0 && day < marks.count {
                                RoomDayCell(mark: marks[day], isToday: day == todayIndex,
                                            corner: max(2, cell * 0.2))
                                    .frame(width: cell, height: cell)
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
        }
        .fixedSize()
    }
}

/// The start of a row: the cup for first place, second and third in their
/// medal colours, any other place as its number, and a dash for no place
/// yet (RoomPlaceBadge on the board). Nothing in a team room.
struct RoomPlaceMark: View {
    let rank: Int
    var isTeam: Bool = false
    var size: CGFloat = 12

    var body: some View {
        Group {
            if isTeam {
                Color.clear
            } else if rank < 1 {
                Text(verbatim: "–").foregroundColor(.parchmentSecondary)
            } else if rank == 1 {
                Image(systemName: "trophy.fill").foregroundColor(.themeGold)
            } else {
                Text(verbatim: "\(rank)")
                    .foregroundColor(rank == 2 ? .parchmentSilver
                                     : rank == 3 ? .parchmentBronze : .parchmentSecondary)
            }
        }
        .font(.system(size: size, weight: .heavy))
    }
}

/// «أنت», «القائد», «موقوف»: the board's small tags beside a name.
struct RoomRaceTag: View {
    let text: String
    let color: Color
    var size: CGFloat = 8.5

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundColor(color)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.14)))
            .fixedSize()
    }
}

/// The room name and how long is left, the room card's own header line.
struct RoomRaceTitle: View {
    let entry: RoomRaceEntry
    var size: CGFloat = 12
    var showDaysLeft: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flag.checkered")
                .font(.system(size: size - 1, weight: .semibold))
                .foregroundColor(.parchmentSecondary)
            Text(entry.roomName)
                .font(.system(size: size, weight: .heavy))
                .foregroundColor(.parchmentInk)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 6)
            if showDaysLeft {
                if entry.daysRemaining > 0 {
                    Text(entry.copy.daysLeftShort(entry.daysRemaining))
                        .font(.system(size: size - 2, weight: .semibold))
                        .foregroundColor(.parchmentSecondary)
                        .fixedSize()
                } else if !entry.isLive {
                    Text(entry.copy.startingSoon)
                        .font(.system(size: size - 2, weight: .semibold))
                        .foregroundColor(.parchmentWarn)
                        .fixedSize()
                }
            }
        }
    }
}

extension RoomRaceRow {
    /// «24.2 من 42», the room row's count, or nil where the row prints none:
    /// a member carrying only part of the plan, whose count no strip can
    /// reconcile (see RoomRaceRow.partialPlan), or a payload without the
    /// pair.
    func dayCount(_ copy: WidgetCopy) -> String? {
        guard partialPlan != true, let total = daysTotal, total > 0 else { return nil }
        return copy.roomDayCount(scoreText ?? "\(daysDone ?? 0)", total)
    }

    /// The board's bar colour for this place: the medal colours, gold for
    /// everyone else (LinearProgressIndicator in _LeaderboardRow).
    var barColor: Color {
        switch rank {
        case 2: return .parchmentSilver
        case 3: return .parchmentBronze
        default: return .themeGold
        }
    }
}

/// Place, name and tags at the leading edge; the score at the trailing one.
struct RoomRaceNameLine: View {
    let row: RoomRaceRow
    let entry: RoomRaceEntry
    var nameSize: CGFloat = 12
    var showTags: Bool = true
    /// The day count beside the percentage (medium), or in place of it
    /// (small, where "the points of total" is the number asked for).
    var showCount: Bool = true
    var showPercent: Bool = true

    static func badgeWidth(_ nameSize: CGFloat) -> CGFloat { nameSize + 5 }

    var body: some View {
        HStack(spacing: 5) {
            RoomPlaceMark(rank: row.rank, isTeam: entry.isTeam, size: nameSize - 0.5)
                .frame(width: Self.badgeWidth(nameSize))
            Text(row.name)
                .font(.system(size: nameSize, weight: .heavy))
                .foregroundColor(.parchmentInk)
                .lineLimit(1)
                .layoutPriority(1)
            if showTags {
                if row.isMe { RoomRaceTag(text: entry.copy.youTag, color: .themeGold) }
                if row.isLeader == true {
                    RoomRaceTag(text: entry.copy.leaderTag, color: .parchmentSecondary)
                }
                if row.pausedNow == true {
                    RoomRaceTag(text: entry.copy.pausedTag, color: .parchmentSecondary)
                }
            }
            Spacer(minLength: 4)
            let count = showCount ? row.dayCount(entry.copy) : nil
            if let count {
                Text(count)
                    .font(.system(size: nameSize - 1.5, weight: .semibold))
                    .foregroundColor(.parchmentSecondary)
                    .fixedSize()
                    .contentTransition(.numericText())
            }
            if showPercent || count == nil {
                Text(entry.copy.percent(row.percent))
                    .font(.system(size: nameSize, weight: .heavy))
                    .foregroundColor(.parchmentInk)
                    .fixedSize()
                    .contentTransition(.numericText())
            }
        }
    }
}

extension View {
    /// The board draws your own row on a gold-tinted card with a gold edge;
    /// every row takes the same inset so the columns still line up.
    func roomRaceRowCard(isMine: Bool, corner: CGFloat = 8) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return self
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(shape.fill(isMine ? Color.themeGold.opacity(0.08) : Color.clear))
            .overlay(shape.stroke(isMine ? Color.themeGold.opacity(0.4) : Color.clear, lineWidth: 1))
    }
}

/// Small: the room row's compact form ("آخر 7 أيام") for me and the racer
/// beside me, each with the count the room prints under its row.
struct RoomRaceSmallView: View {
    var entry: RoomRaceEntry

    var body: some View {
        Group {
            if !entry.hasRoom || entry.rows.isEmpty {
                RoomRaceEmptyView(copy: entry.copy)
            } else {
                let pair = roomRaceSmallPair(entry.rows)
                let strips = roomStripLayout(pair, count: 7, endsToday: entry.stripEndsToday)
                VStack(alignment: .leading, spacing: 0) {
                    RoomRaceTitle(entry: entry, size: 10.5, showDaysLeft: false)
                    Spacer(minLength: 4)
                    ForEach(Array(pair.enumerated()), id: \.element.stableId) { index, row in
                        VStack(alignment: .leading, spacing: 4) {
                            RoomRaceNameLine(row: row, entry: entry, nameSize: 11,
                                             showTags: false, showPercent: false)
                            RoomDayStrip(marks: strips.marks[index],
                                         todayIndex: strips.todayIndex,
                                         gap: 3, corner: 3)
                        }
                        .roomRaceRowCard(isMine: row.isMe && pair.count > 1)
                        Spacer(minLength: 3)
                    }
                }
            }
        }
        // No padding of its own. WidgetKit already insets every face by the
        // family's content margin (about 16pt on this phone), and the 10pt
        // this added on top left the small card about 110pt inside: the
        // names shrank to «A:» and «…» beside «24.2 من 42». Seen in the
        // gallery on 2026-09-24.
        .containerBackground(for: .widget) { WidgetParchmentBackground() }
    }
}

/// Medium and large: the room's ranked list, a month of days on each row.
struct RoomRaceListView: View {
    var entry: RoomRaceEntry
    var large: Bool

    static let stripDays = 30

    /// Three on the medium card. Five on the large, or four and the
    /// «معك N غيرهم» line when there are more: at about 51pt a row, five and
    /// that line together would run past the ~338pt the large card leaves.
    private var rowLimit: Int {
        guard large else { return 3 }
        return entry.rows.count <= 5 ? 5 : 4
    }

    var body: some View {
        Group {
            if !entry.hasRoom || entry.rows.isEmpty {
                RoomRaceEmptyView(copy: entry.copy)
            } else {
                let rows = roomRaceRowsToShow(entry.rows, limit: rowLimit)
                let strips = roomStripLayout(
                    rows, count: Self.stripDays, endsToday: entry.stripEndsToday,
                    weekStarts: roomStripWeekStarts(endDayKey: entry.stripEndDay,
                                                    count: Self.stripDays))
                VStack(alignment: .leading, spacing: large ? 8 : 0) {
                    RoomRaceTitle(entry: entry, size: large ? 14 : 12)
                    if large && entry.todayCounted > 0 {
                        todayLine
                    }
                    if !large { Spacer(minLength: 4) }
                    if large && rows.count <= Self.calendarRacers {
                        calendarBlocks(rows)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.stableId) { index, row in
                            listRow(row, marks: strips.marks[index], weekStarts: strips.weekStarts,
                                    todayIndex: strips.todayIndex,
                                    highlight: row.isMe && rows.count > 1)
                            if !large { Spacer(minLength: 2) }
                        }
                    }
                    if large {
                        if entry.rows.count > rows.count {
                            Text(entry.copy.moreRacing(entry.rows.count - rows.count))
                                .font(.system(size: 10))
                                .foregroundColor(.parchmentSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        // The system's own content margin already insets the face; see the
        // note on RoomRaceSmallView.
        .padding(large ? 2 : 0)
        .containerBackground(for: .widget) { WidgetParchmentBackground() }
    }

    /// Up to this many racers, the large card draws each month as the room's
    /// «كل الأيام» calendar, the view the room screen offers beside «آخر 7
    /// أيام». More than this and the calendars would shrink past reading, so
    /// the card falls back to the medium's one line per racer. With two
    /// racers the one-line form left the lower half of the card empty, which
    /// is what sank the face built the day before.
    static let calendarRacers = 3

    /// Each racer as a card: who, where and how much at the leading side,
    /// their month as the room's calendar at the trailing side. The cards
    /// share the height the card has left, and the calendar's squares are
    /// sized from each card's own height, so two racers get big squares and
    /// three still fit.
    @ViewBuilder
    private func calendarBlocks(_ rows: [RoomRaceRow]) -> some View {
        let lead = roomStripCommonLead(rows, count: Self.stripDays)
        let columns = roomCalendarColumns(endDayKey: entry.stripEndDay,
                                          count: Self.stripDays, first: lead)
        let todayIndex = entry.stripEndsToday ? Self.stripDays - 1 : nil
        ForEach(Array(rows.enumerated()), id: \.element.stableId) { _, row in
            GeometryReader { geo in
                // The card's own inset (roomRaceRowCard: 4 above and below),
                // the month names (~11) and their 3pt gap, then seven rows
                // and six gaps of 2.5pt.
                let cell = max(6, min(13, (geo.size.height - 8 - 14 - 6 * 2.5) / 7))
                HStack(alignment: .center, spacing: 10) {
                    calendarInfo(row)
                    Spacer(minLength: 4)
                    RoomMonthCalendar(marks: roomDayMarks(row.days, last: Self.stripDays),
                                      columns: columns, todayIndex: todayIndex,
                                      copy: entry.copy, cell: cell)
                }
                .frame(maxHeight: .infinity)
                .roomRaceRowCard(isMine: row.isMe && rows.count > 1)
            }
        }
    }

    /// The leading side of a calendar card: the row's place, name and tags,
    /// its percentage, then the line under a room row, its count and flame,
    /// and the bar.
    private func calendarInfo(_ row: RoomRaceRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                RoomPlaceMark(rank: row.rank, isTeam: entry.isTeam, size: 13)
                Text(row.name)
                    .font(.system(size: 13.5, weight: .heavy))
                    .foregroundColor(.parchmentInk)
                    .lineLimit(1)
                    .layoutPriority(1)
                if row.isMe { RoomRaceTag(text: entry.copy.youTag, color: .themeGold) }
                if row.isLeader == true {
                    RoomRaceTag(text: entry.copy.leaderTag, color: .parchmentSecondary)
                }
                if row.pausedNow == true {
                    RoomRaceTag(text: entry.copy.pausedTag, color: .parchmentSecondary)
                }
            }
            Text(entry.copy.percent(row.percent))
                .font(.system(size: 20, weight: .heavy))
                .foregroundColor(.parchmentInk)
                .contentTransition(.numericText())
            HStack(spacing: 8) {
                if let count = row.dayCount(entry.copy) {
                    Text(count)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.parchmentSecondary)
                        .fixedSize()
                }
                if let streak = row.streak, streak >= 1 {
                    StreakBadge(streak: streak, copy: entry.copy, size: 10.5, showWord: false)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.parchmentSurface)
                    Capsule().fill(row.barColor)
                        .frame(width: geo.size.width * CGFloat(min(100, max(0, row.percent))) / 100)
                }
            }
            .frame(width: 96, height: 5)
        }
    }

    /// The room's «اليوم» card in one line: how many of the members asked
    /// something today have finished it.
    private var todayLine: some View {
        let finished = entry.todayFinished
        let counted = entry.todayCounted
        return HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.parchmentSecondary)
            Text(entry.copy.todayTitle)
                .font(.system(size: 11.5, weight: .heavy))
                .foregroundColor(.parchmentInk)
            Spacer(minLength: 4)
            Text(entry.copy.todayFinished(finished, counted))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(finished == counted ? .themeGreen : .parchmentSecondary)
                .contentTransition(.numericText())
        }
    }

    @ViewBuilder
    private func listRow(_ row: RoomRaceRow, marks: [RoomDayMark], weekStarts: Set<Int>,
                         todayIndex: Int?, highlight: Bool) -> some View {
        let nameSize: CGFloat = large ? 12.5 : 11.5
        let indent = RoomRaceNameLine.badgeWidth(nameSize) + 5
        VStack(alignment: .leading, spacing: large ? 4 : 3) {
            RoomRaceNameLine(row: row, entry: entry, nameSize: nameSize,
                             showCount: !large)
            RoomDayStrip(marks: marks, todayIndex: todayIndex, weekStarts: weekStarts)
                .padding(.leading, indent)
            if large {
                // The line under a room row: its bar, its flame and its count.
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.parchmentSurface)
                            Capsule().fill(row.barColor)
                                .frame(width: geo.size.width * CGFloat(min(100, max(0, row.percent))) / 100)
                        }
                    }
                    .frame(height: 5)
                    if let streak = row.streak, streak >= 1 {
                        StreakBadge(streak: streak, copy: entry.copy, size: 10, showWord: false)
                    }
                    if let count = row.dayCount(entry.copy) {
                        Text(count)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.parchmentSecondary)
                            .fixedSize()
                    }
                }
                .padding(.leading, indent)
            }
        }
        .roomRaceRowCard(isMine: highlight)
    }
}

struct RoomRaceWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: RoomRaceEntry

    var body: some View {
        Group {
        switch family {
        case .systemMedium:
            RoomRaceListView(entry: entry, large: false)
        case .systemLarge:
            RoomRaceListView(entry: entry, large: true)
        default:
            RoomRaceSmallView(entry: entry)
        }
        }
        // A tap anywhere opens the rooms page, as the Lock Screen face does.
        .widgetURL(lockScreenOpenURL(tab: "rooms"))
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
// Deliberately no explicit .foregroundColor(.themeGold/.themeGreen/etc.) here,
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
                        // Was the English "You" on every phone, an Arabic one
                        // included; the board's own «أنت» since 2026-09-24.
                        name: entry.copy.youTag,
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
/// .dart): red, blue, orange and grey, as the parchment's own inks.
///
/// These were the dark card's raw colours until 2026-09-24, and the card has
/// been cream in light mode since the day before: the blue and orange dots
/// read at about 1.6:1 there, and Eliminate's white at 40% vanished outright
/// (seen in the gallery beside «اقرا شوي من الكتاب النفسي»). Each token
/// below clears 3:1 on both sheets, the bar for a drawn shape.
///
/// A user's own custom quadrant color (MatrixState.colorFor) isn't threaded
/// through to the widget: same "simplified but on-brand, not full parity"
/// call already made for Room Race's avatars.
private func quadrantColor(_ quadrant: String) -> Color {
    switch quadrant {
    case "doFirst": return .parchmentRed
    case "schedule": return .parchmentXp
    case "delegate": return .parchmentStreak
    default: return .parchmentSecondary // eliminate, or anything unrecognized
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
                    .foregroundColor(task.isDone ? .themeGreen : .parchmentSecondary)
            }
            .buttonStyle(.plain)
            Text(task.title)
                .font(.system(size: 12, weight: .medium))
                .strikethrough(task.isDone)
                .foregroundColor(task.isDone ? .parchmentSecondary : .parchmentInk)
                .lineLimit(1)
                // First claim on the row, before the Spacer: see HabitWidgetRow.
                .layoutPriority(1)
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
            .foregroundColor(.parchmentRed)
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
                .foregroundColor(.themeGreen.opacity(0.8))
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
                    .foregroundColor(.themeGold)
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
                // From the top, as a list reads. See MatrixLargeView.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(.easeInOut(duration: 0.35),
                           value: entry.tasks.map { "\($0.id)|\($0.isDone)" })
            }
        }
        // The family's content margin is the inset (see RoomRaceSmallView).
        .padding(.horizontal, 2)
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
                // Pinned to the top. The stack used to take only its own
                // height, and a widget centres whatever it is given, so a
                // board of three tasks floated in the middle of the large
                // card with empty space above the title as well as below the
                // list (Aziz asked for it fixed on 2026-09-24). A list starts
                // where it is read from; what it does not fill stays below.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        // No second padding inside the family's content margin, and no
        // corner star: on an Arabic face the trailing corner is the left
        // one, where the «+» sits, and the star was drawn across it.
        .padding(.horizontal, 2)
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
                            .foregroundColor(.themeGold)
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
        .padding(2)
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
        // A tap anywhere but a row's circle or the «+» opens the Tasks page,
        // as the Lock Screen task face does; those two keep their own taps.
        .widgetURL(lockScreenOpenURL(tab: "matrix"))
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
