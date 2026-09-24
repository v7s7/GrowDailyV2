//
//  WidgetStrings.swift
//  GrowDailyWidget
//
//  Every word any widget face shows, in both languages, in one file.
//
//  ── Why this exists ──────────────────────────────────────────────────
//  Until 2026-09-23 the widgets were English only, in an Arabic-first app:
//  a user reading «العادات» everywhere in the app got "day streak", "No
//  active room" and "Add one in Matrix" on their Home Screen. The flag was
//  already there — HomeWidgetService.saveLocale writes `localeIsAr` into
//  the App Group on every boot and every switch — and nothing read it.
//
//  ── Why a struct and not a .strings file ─────────────────────────────
//  A .strings file is resolved from the DEVICE language. This app has its
//  own in-app language toggle (see locale_precedence.dart), and the two
//  can disagree: an Arabic user on an English phone must still get Arabic
//  widgets. So the copy is picked from the app's own flag, at render time,
//  which only a plain Swift value can do.
//
//  The one exception is each widget's gallery title and description
//  (.configurationDisplayName / .description). Those are read by the system
//  before any of our code runs, so they follow the DEVICE language and are
//  localized through Localizable.strings instead. That split is not a
//  choice, it is where the system draws the line.
//
//  ── The wording is Aziz's ────────────────────────────────────────────
//  House style is easy spoken Arabic, not MSA and not full Gulf. What is
//  below is a first pass to replace the English, not a final answer; every
//  line here is his to change, and changing one is a one-line edit in this
//  file with no other file to touch.
//

import Foundation

/// Picks each string for the language the app is currently running in.
///
/// Built from the App Group flag once per entry and carried on the entry
/// itself, rather than read per-view: a face must not be able to render
/// half in one language because a read landed differently mid-draw.
struct WidgetCopy {
    let isAr: Bool

    init(isAr: Bool) { self.isAr = isAr }

    /// The flag exactly as HomeWidgetService.saveLocale last wrote it.
    /// English when nothing was ever written, matching readLocaleIsAr.
    static func fromDefaults() -> WidgetCopy {
        WidgetCopy(isAr: UserDefaults(suiteName: appGroupId)?
            .bool(forKey: "localeIsAr") ?? false)
    }

    private func pick(_ ar: String, _ en: String) -> String { isAr ? ar : en }

    // MARK: Habits

    func streakLine(_ n: Int) -> String { pick("\(n) يوم متتابع", "\(n) day streak") }
    func doneToday(_ done: Int, _ total: Int) -> String {
        pick("\(done) من \(total) اليوم", "\(done)/\(total) done today")
    }
    /// The seven weekday initials for the month grid, Saturday first,
    /// because that is the column order every calendar in this app uses.
    var weekdayInitials: [String] {
        isAr ? ["س", "ح", "ن", "ث", "ر", "خ", "ج"]
             : ["S", "S", "M", "T", "W", "T", "F"]
    }

    var noHabitsToday: String { pick("ما في عادات اليوم", "No habits scheduled today") }
    var notDue: String { pick("مو مطلوبة", "not due") }
    /// NOT "+\(n) ..." in Arabic. A leading "+" is a bidi-neutral character,
    /// so at the start of a right-to-left line the system moves it to the
    /// other end and the widget rendered «5+ بالتطبيق». Seen on the large
    /// habits face on 2026-09-23. The Arabic forms below lead with a word
    /// instead, which sidesteps the reordering entirely; English keeps its
    /// plus, because a left-to-right line has nothing to reorder.
    func moreInApp(_ n: Int) -> String { pick("باقي \(n) بالتطبيق", "+\(n) more in app") }

    /// Today as a count, «4 من 9»: how many of the habits the day asked for
    /// are done, and nothing else. This replaced a line whose words changed
    /// through the day («باقي 5، الوقت يمشي» after six, «خلّصها اليوم» after
    /// eight); Aziz, 2026-09-24: "no need for the time is running sentence,
    /// make it 4 of 5 ... make it clean".
    func todayCount(_ done: Int, _ total: Int) -> String {
        pick("\(done) من \(total)", "\(done)/\(total)")
    }
    /// The medium face's words once nothing is left.
    var allDoneToday: String { pick("خلّصت اليوم كله", "All done today") }

    // MARK: Rooms

    var noActiveRoom: String { pick("ما في غرفة شغالة", "No active room") }
    var joinOrCreate: String { pick("ادخل غرفة أو سوِّ وحدة", "Join or create one in the app") }
    var startingSoon: String { pick("بتبدأ قريب", "Starting soon") }
    func daysLeftShort(_ n: Int) -> String { pick("باقي \(n) يوم", "\(n)d left") }
    func moreRacing(_ n: Int) -> String { pick("معك \(n) غيرهم", "+\(n) more racing") }

    /// Arabic counts days in three shapes, and a widget that says «٢ يوم»
    /// reads as machine translation. English needs only the plural s. The
    /// Habits faces' streak reads through this: «4 أيام», where the medium
    /// face used to print «4 يوم».
    func daysWord(_ n: Int) -> String {
        if !isAr { return n == 1 ? "1 day" : "\(n) days" }
        switch n {
        case 1: return "يوم"
        case 2: return "يومين"
        case 3...10: return "\(n) أيام"
        default: return "\(n) يوم"
        }
    }

    // The Race faces since 2026-09-24 draw the room's own list («make it
    // same as the one in rooms»), so their words are the room screen's own,
    // copied from app_strings.dart rather than written fresh: a label on the
    // Home Screen and the same label in the room must not read differently.

    /// The room row's day count, S.roomDayCount: «24.2 من 42». [scoreText]
    /// is the number exactly as the app wrote it (RoomRaceRow.scoreText),
    /// fraction and all. No unit word, as on the row.
    func roomDayCount(_ scoreText: String, _ total: Int) -> String {
        pick("\(scoreText) من \(total)", "\(scoreText)/\(total)")
    }
    /// The row's percentage, with the ASCII sign the row uses.
    func percent(_ n: Int) -> String { "\(n)%" }
    /// S.roomYouLabel, S.roomLeaderLabel, S.roomPausedTag.
    var youTag: String { pick("أنت", "You") }
    var leaderTag: String { pick("القائد", "Leader") }
    var pausedTag: String { pick("موقوف", "Paused") }
    /// A month's short name over its weeks in the room calendar, as the
    /// room screen prints it (DateFormat('MMM') for 'ar' and 'en'). [month]
    /// is 1 to 12.
    func monthShort(_ month: Int) -> String {
        let ar = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
                  "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]
        let en = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let i = min(max(month, 1), 12) - 1
        return isAr ? ar[i] : en[i]
    }
    /// The room's «اليوم» card: S.navToday and S.roomTodayFinished.
    var todayTitle: String { pick("اليوم", "Today") }
    func todayFinished(_ done: Int, _ total: Int) -> String {
        pick("\(done) من \(total) خلّصوا", "\(done) of \(total) finished")
    }

    // MARK: Tasks

    var tasksTitle: String { pick("المهام", "Matrix") }
    var nothingUrgent: String { pick("ما في شي مستعجل", "Nothing urgent") }
    var boardIsClear: String { pick("لوحتك فاضية", "Your board is clear") }
    var noTasks: String { pick("ما في مهام", "No tasks") }
    /// Missed by the first sweep because it was written as a ternary
    /// (`count == 1 ? "task open" : "tasks open"`) rather than a plain
    /// literal, so a grep for `Text("...")` never saw it. Arabic needs no
    /// singular/plural split here.
    func tasksOpen(_ n: Int) -> String {
        pick("مهام مفتوحة", n == 1 ? "task open" : "tasks open")
    }
    var addOneInMatrix: String { pick("أضف مهمة", "Add one in Matrix") }
    func moreTasks(_ n: Int) -> String { pick("باقي \(n) غيرها", "+\(n) more") }
}
