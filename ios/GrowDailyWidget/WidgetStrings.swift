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

    var dayStreak: String { pick("يوم متتابع", "day streak") }
    func streakDays(_ n: Int) -> String { pick("\(n) يوم", "\(n)d") }
    func streakLine(_ n: Int) -> String { pick("\(n) يوم متتابع", "\(n) day streak") }
    func level(_ n: Int) -> String { pick("مستوى \(n)", "Lvl \(n)") }
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

    /// The status line whose tone shifts across the day. Same shape as the
    /// English it replaces, and the em dashes the English used are gone:
    /// Aziz asked for that dash never to appear in UI copy.
    func statusLine(completed: Int, total: Int, hour: Int) -> String {
        if total <= 0 { return pick("ما في شي اليوم", "Nothing scheduled today") }
        if completed >= total { return pick("خلّصت اليوم كله", "All done today") }
        let left = total - completed
        if hour >= 20 {
            return left == 1
                ? pick("باقي وحدة، لا تكسر السلسلة", "Last one, don't break the streak")
                : pick("باقي \(left)، خلّصها اليوم", "\(left) left, finish today")
        }
        if hour >= 18 {
            return pick("باقي \(left)، الوقت يمشي", "\(left) left today")
        }
        return pick("باقي \(left) اليوم", "\(left) to go today")
    }

    // MARK: Rooms

    var noActiveRoom: String { pick("ما في غرفة شغالة", "No active room") }
    var joinOrCreate: String { pick("ادخل غرفة أو سوِّ وحدة", "Join or create one in the app") }
    var startingSoon: String { pick("بتبدأ قريب", "Starting soon") }
    func daysLeftShort(_ n: Int) -> String { pick("باقي \(n) يوم", "\(n)d left") }
    func daysLeftLong(_ n: Int) -> String { pick("باقي \(n) يوم", "\(n) days left") }
    func moreRacing(_ n: Int) -> String { pick("معك \(n) غيرهم", "+\(n) more racing") }
    func youSuffix(_ name: String) -> String { pick("\(name) (أنت)", "\(name) (You)") }

    /// The rank as a word, because «#1» is a Western convention sitting on
    /// an Arabic card and the digit alone reads as a score.
    func rankWord(_ rank: Int) -> String {
        if !isAr {
            switch rank {
            case 1: return "1st"
            case 2: return "2nd"
            case 3: return "3rd"
            default: return "\(rank)th"
            }
        }
        switch rank {
        case 1: return "الأول"
        case 2: return "الثاني"
        case 3: return "الثالث"
        case 4: return "الرابع"
        case 5: return "الخامس"
        default: return "المركز \(rank)"
        }
    }

    /// Arabic counts days in three shapes, and a widget that says «٢ يوم»
    /// reads as machine translation. English needs only the plural s.
    func daysWord(_ n: Int) -> String {
        if !isAr { return n == 1 ? "1 day" : "\(n) days" }
        switch n {
        case 1: return "يوم"
        case 2: return "يومين"
        case 3...10: return "\(n) أيام"
        default: return "\(n) يوم"
        }
    }

    /// The one line the Race widget exists for (Aziz, 2026-09-23): not the
    /// whole leaderboard, just where I stand against the person next to me.
    /// Leading is measured against the chaser, because when you are first
    /// there is nobody ahead and the useful number is your cushion.
    func gapLine(days: Int, other: String, iAmAhead: Bool) -> String {
        if days == 0 {
            return pick("متعادل مع \(other)", "Level with \(other)")
        }
        let d = daysWord(days)
        if iAmAhead {
            return pick("متقدم بـ\(d) على \(other)", "\(d) ahead of \(other)")
        }
        return pick("متأخر بـ\(d) عن \(other)", "\(d) behind \(other)")
    }

    var racingSolo: String { pick("تسابق لحالك", "Racing solo") }

    func rankLine(rank: Int, racerCount: Int) -> String {
        if rank == 1 {
            return racerCount > 1
                ? pick("أنت بالمقدمة", "You're leading")
                : pick("تسابق لحالك", "Racing solo")
        }
        if rank == 2 { return pick("قربت، الحق الأول", "So close, catch #1") }
        return pick("واصل", "Keep pushing")
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
