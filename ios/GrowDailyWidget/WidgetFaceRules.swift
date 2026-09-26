//
//  WidgetFaceRules.swift
//  GrowDailyWidget
//
//  The decisions the Habits and Room Race faces make before anything is
//  drawn: which habits come first, which racers a face has room for, what
//  each day of a racer's strip is, and a picked colour made readable on the
//  parchment. Foundation only, like MatrixLockScreenOrder.swift, so every
//  rule here compiles on the Mac and can be checked there (see
//  [[widget-swift-checks]] in the session notes: a swiftc harness, no
//  simulator and no Xcode build).
//
//  Rebuilt 2026-09-24 from Aziz's screenshots of the gallery: the large
//  Habits face listed four finished habits above the one still open, struck
//  through like tasks, and the Race faces answered a question («الأول،
//  متقدم بـ3 أيام») the room screen never asks. His words: "in matrix
//  finish habit should be listed down, show only the un done, and show it
//  as habit, not as tasks", and for the race, "make it same as the one in
//  rooms".
//

import Foundation

// MARK: - Today's habits

/// One of today's habits, as HomeWidgetService.updateWidgetData writes it
/// into `todayHabitsJson`.
///
/// Every field past `done` is Optional, and must stay Optional: a payload
/// written by an older build has no such key, and a non-optional would fail
/// the whole list and blank every habit face until the app next writes.
struct TodayHabit: Codable, Identifiable {
    let id: String
    let name: String
    var done: Bool

    /// Whether today asked for this habit at all. A flexible weekly quota
    /// ("4 times a week, any days") keeps its row on every day of the week,
    /// because any of them will do, but on the days its own week never
    /// needed the row is an invitation, not an outstanding task, and it is
    /// left out of completedToday/totalToday (habitOwesDay / boardHabitsOn on
    /// the app side). nil reads as "due", the way every row read before.
    var notDue: Bool? = nil

    /// How many times it has been done today, and how many the day wants.
    /// A three-a-day habit is not done after one tap, so these two are the
    /// finer truth behind `done`. Until 2026-09-24 this struct did not carry
    /// them, so MarkHabitDoneIntent's re-encode dropped them and every
    /// counted habit read as one-a-day after its first tap from the widget.
    var count: Int? = nil
    var perDay: Int? = nil

    /// HabitCategory.name on the app side ("faith", "quran", "fitness"...),
    /// and the habit's own picked colour as six hex digits when it has one
    /// (IslamicHabitTemplate.iconColorHex). The Grid draws a habit as its
    /// category glyph in that colour; the widget rows do too.
    var category: String? = nil
    var color: String? = nil

    var isDue: Bool { notDue != true }

    /// Completions the day wants, never below one.
    var target: Int { max(1, perDay ?? 1) }

    /// Completions so far, clamped to [target]. A row without the pair (an
    /// old payload) is all or nothing, as it always was.
    var timesDone: Int {
        if let count { return min(max(0, count), target) }
        return done ? target : 0
    }

    /// One more completion, by the rule a lock screen or Watch «تمت» already
    /// follows (NotificationActionRules.markOneDone in
    /// notification_action_queue.dart): count + 1, done once it reaches
    /// perDay; without the pair, one tap means done.
    mutating func recordOneCompletion() {
        if let perDay, let count, perDay > 1 {
            let next = min(count + 1, perDay)
            self.count = next
            done = next >= perDay
        } else {
            if let perDay, count != nil { self.count = perDay }
            done = true
        }
    }
}

/// Today's habits in the order every Habits face lists them: open habits
/// the day asked for first, then open ones it did not (a quota's rest day,
/// still yours to train), then the finished ones at the bottom. The app's
/// own order holds inside each group.
///
/// The app sends the Grid's order, and the large face used to draw it as it
/// came, so a morning's finished habits sat above the ones still waiting and
/// the list was mostly a record of what no longer needed doing. Aziz sent
/// the gallery on 2026-09-24 showing four finished rows above the one open
/// habit, with five more open ones reduced to «باقي 5 بالتطبيق».
func widgetHabitOrder(_ habits: [TodayHabit]) -> [TodayHabit] {
    func group(_ habit: TodayHabit) -> Int {
        habit.done ? 2 : (habit.isDue ? 0 : 1)
    }
    return habits.enumerated()
        .sorted { a, b in
            let (ga, gb) = (group(a.element), group(b.element))
            return ga != gb ? ga < gb : a.offset < b.offset
        }
        .map(\.element)
}

// MARK: - Room Race

/// One ranked member of the Room Race faces, as HomeWidgetService.
/// roomRacePayload writes it. RoomRaceRow in rooms_notifier.dart documents
/// what each field means; only the widget-side reasons are repeated here.
///
/// Everything added after the first release is a genuine Optional: Swift's
/// synthesized decoding only forgives a MISSING key for an Optional, and a
/// widget binary can read a `roomRaceJson` written before the app that
/// carries it relaunched. A failed row decode blanks the whole face.
struct RoomRaceRow: Codable {
    let name: String
    let rank: Int
    let percent: Int
    let isMe: Bool

    /// Keys rows by person rather than by rank slot across two refreshes.
    let uid: String?

    /// The room score's numerator (rounded) and denominator, which the Lock
    /// Screen prints as "5/6".
    let daysDone: Int?
    let daysTotal: Int?

    /// The same numerator unrounded, and already written the way the room
    /// row writes it («24.2»): Dart's toStringAsFixed rounds a half up on
    /// the exact value and no Swift formatter agrees with it on every input,
    /// so the app formats and the widget only prints.
    let score: Double?
    let scoreText: String?

    let partialPlan: Bool?
    let streak: Int?
    let isLeader: Bool?
    let pausedNow: Bool?
    let doneToday: Bool?
    let countsToday: Bool?

    /// One character per day, oldest first, every row ending on the same
    /// day (RoomRaceEntry.stripEndDay). See [RoomDayMark].
    let days: String?

    init(
        name: String,
        rank: Int,
        percent: Int,
        isMe: Bool,
        uid: String? = nil,
        daysDone: Int? = nil,
        daysTotal: Int? = nil,
        score: Double? = nil,
        scoreText: String? = nil,
        partialPlan: Bool? = nil,
        streak: Int? = nil,
        isLeader: Bool? = nil,
        pausedNow: Bool? = nil,
        doneToday: Bool? = nil,
        countsToday: Bool? = nil,
        days: String? = nil
    ) {
        self.name = name
        self.rank = rank
        self.percent = percent
        self.isMe = isMe
        self.uid = uid
        self.daysDone = daysDone
        self.daysTotal = daysTotal
        self.score = score
        self.scoreText = scoreText
        self.partialPlan = partialPlan
        self.streak = streak
        self.isLeader = isLeader
        self.pausedNow = pausedNow
        self.doneToday = doneToday
        self.countsToday = countsToday
        self.days = days
    }

    /// Identity ForEach keys rows by, so a row MOVES to its new place when
    /// the order changes instead of the slot at that place swapping text.
    var stableId: String { uid ?? name }

    /// "5/6" when the day counts are available, falling back to "83%". What
    /// the Lock Screen prints: fewer glyphs than a percentage beside a long
    /// name, and it carries the scale.
    var scoreLabel: String {
        if let done = daysDone, let total = daysTotal, total > 0 {
            return "\(done)/\(total)"
        }
        return "\(percent)%"
    }
}

/// One day of a racer's strip, decoded from the character the app wrote
/// (roomRaceDayCode in rooms_notifier.dart, from roomStripDayOf in
/// room_strip_day.dart, the rule the room screen's own strip paints).
enum RoomDayMark: Equatable {
    /// Before this member's own start: nothing is drawn, so a late joiner's
    /// days still sit under everyone else's.
    case outside
    /// The room was paused or the member's whole plan was stood down.
    case standDown
    /// Today, still open, with nothing recorded on it yet.
    case pending
    /// Every habit marked تخطّي and nothing done.
    case declaredRest
    /// A rest the schedule granted: nothing was asked.
    case rest
    /// Nothing done, and the day can no longer be saved.
    case missed
    /// The credit ramp, 0 (nothing) to 4 (all of it).
    case level(Int)

    init(code: Character) {
        switch code {
        case "p": self = .standDown
        case "o": self = .pending
        case "s": self = .declaredRest
        case "r": self = .rest
        case "x": self = .missed
        case "0", "1", "2", "3", "4": self = .level(Int(String(code)) ?? 0)
        default: self = .outside
        }
    }
}

/// The last [count] days of [codes], oldest first, padded at the front with
/// `.outside` when the string is shorter (an old payload, or none at all).
func roomDayMarks(_ codes: String?, last count: Int) -> [RoomDayMark] {
    let marks = Array(codes ?? "").suffix(count).map(RoomDayMark.init(code:))
    return Array(repeating: .outside, count: max(0, count - marks.count)) + marks
}

/// Every racer's last [count] days, laid out the way the room strip lays out
/// a young room: from the room's first day at the leading edge, with the
/// days still to come left empty at the trailing end, rather than a few
/// squares pushed up against today behind a long empty run.
///
/// The app writes each row ending on today, with '.' for the days before
/// that member's own start. The days before ANY row starts are the days
/// before the room began, so those are moved from the front to the back. A
/// late joiner keeps their own blanks at the front, so a day still sits
/// under the same day on every row.
///
/// Returns the rows' marks and where today's cell lands (nil when the strip
/// does not end today), with [weekStarts] moved the same way.
func roomStripLayout(_ rows: [RoomRaceRow], count: Int, endsToday: Bool,
                     weekStarts: Set<Int> = [])
    -> (marks: [[RoomDayMark]], todayIndex: Int?, weekStarts: Set<Int>) {
    let full = rows.map { roomDayMarks($0.days, last: count) }
    let lead = roomStripCommonLead(rows, count: count)
    // A strip where nobody has a single day (a room still in its lobby)
    // stays as it is: there is nothing to line up.
    guard lead > 0, lead < count else {
        return (full, endsToday ? count - 1 : nil, weekStarts)
    }
    let shifted = full.map { Array($0.dropFirst(lead)) + Array(repeating: RoomDayMark.outside, count: lead) }
    let starts = Set(weekStarts.map { $0 - lead }.filter { $0 > 0 })
    return (shifted, endsToday ? count - 1 - lead : nil, starts)
}

/// How many of the last [count] days no row has anything on: the days
/// before the room began, which no face needs to draw.
func roomStripCommonLead(_ rows: [RoomRaceRow], count: Int) -> Int {
    rows.map { row in
        roomDayMarks(row.days, last: count).firstIndex { $0 != .outside } ?? count
    }.min() ?? count
}

/// One column of a racer's month drawn as the room screen's «كل الأيام»
/// calendar: one Saturday-start week, restricted to ONE month.
///
/// [rows] has seven entries, Saturday first, each an index into the strip's
/// days or -1 where the column draws nothing: the days before the window, or
/// the rows that belong to the neighbouring month's column. [monthKey] is
/// year * 12 + (month - 1), so it sorts and never merges two Decembers.
struct RoomCalendarColumn: Equatable {
    let monthKey: Int
    let rows: [Int]

    /// 1 to 12.
    var month: Int { monthKey % 12 + 1 }
}

/// The calendar columns for the strip days [first]..<[count] of a strip
/// ending on [endDayKey], oldest first.
///
/// A port of roomStripColumns (room_detail_screen_leaderboard_extend.dart),
/// the rule the room screen's own calendar is drawn from, so the widget
/// splits a week the way the room does: a week that straddles two months is
/// two columns, the earlier month's days in its top rows and the later
/// month's under empty ones (Aziz, 2026-09-06). Every day sits on its true
/// weekday row, Saturday at the top.
func roomCalendarColumns(endDayKey: String, count: Int, first: Int = 0,
                         calendar: Calendar = Calendar(identifier: .gregorian)) -> [RoomCalendarColumn] {
    guard count > first, let end = gregorianDay(fromKey: endDayKey, calendar: calendar) else {
        return []
    }
    let days: [Date] = (first..<count).compactMap {
        calendar.date(byAdding: .day, value: $0 - (count - 1), to: end)
    }
    guard let firstDay = days.first else { return [] }
    // Gregorian weekday: Sunday 1 ... Saturday 7, so Saturday lands on row 0.
    let lead = calendar.component(.weekday, from: firstDay) % 7
    let weekCount = (lead + days.count + 6) / 7
    var out: [RoomCalendarColumn] = []
    for week in 0..<weekCount {
        var key = -1
        var rows: [Int] = []
        for row in 0..<7 {
            let i = week * 7 + row - lead
            guard i >= 0, i < days.count else { continue }
            let parts = calendar.dateComponents([.year, .month], from: days[i])
            let k = (parts.year ?? 0) * 12 + (parts.month ?? 1) - 1
            if k != key {
                if key != -1 { out.append(RoomCalendarColumn(monthKey: key, rows: rows)) }
                key = k
                rows = Array(repeating: -1, count: 7)
            }
            rows[row] = i + first
        }
        if key != -1 { out.append(RoomCalendarColumn(monthKey: key, rows: rows)) }
    }
    return out
}

/// The racers a face with room for [limit] rows draws: the board from the
/// top, and my own row kept in the last slot when it would fall below the
/// cut, the way the room screen pins yours under «⋯» (_LeaderboardList).
func roomRaceRowsToShow(_ rows: [RoomRaceRow], limit: Int) -> [RoomRaceRow] {
    guard limit > 0, rows.count > limit else { return rows }
    guard let mine = rows.firstIndex(where: { $0.isMe }), mine >= limit else {
        return Array(rows.prefix(limit))
    }
    return Array(rows.prefix(limit - 1)) + [rows[mine]]
}

/// The small face's two rows: me and whoever is next to me on the board,
/// the one just ahead, or the one just behind when I lead. Kept in board
/// order, so the higher place is always on top. Me alone in a room of one;
/// the top two when I am not on the board at all.
func roomRaceSmallPair(_ rows: [RoomRaceRow]) -> [RoomRaceRow] {
    guard let mine = rows.firstIndex(where: { $0.isMe }) else {
        return Array(rows.prefix(2))
    }
    guard rows.count > 1 else { return [rows[mine]] }
    return mine == 0 ? [rows[0], rows[1]] : [rows[mine - 1], rows[mine]]
}

/// The day a "yyyy-MM-dd" key names, on the Gregorian calendar, parsed by
/// hand: a DateFormatter takes the phone's locale and calendar and misreads
/// the key on an Arabic or Hijri phone (see matrixDayKey).
func gregorianDay(fromKey key: String,
                  calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}

/// Which cells of a [count]-day strip ending on [endDayKey] open a new
/// Saturday week, so the line can leave a slightly wider gap there and a
/// month of squares reads as weeks rather than as one long run. The app's
/// weeks start on Saturday everywhere (startOfDisplayWeek). Cell 0 never
/// counts: there is nothing before it to separate.
func roomStripWeekStarts(endDayKey: String, count: Int,
                         calendar: Calendar = Calendar(identifier: .gregorian)) -> Set<Int> {
    guard count > 1, let end = gregorianDay(fromKey: endDayKey, calendar: calendar) else {
        return []
    }
    var out = Set<Int>()
    for index in 1..<count {
        guard let day = calendar.date(byAdding: .day, value: index - (count - 1), to: end) else {
            continue
        }
        // Gregorian weekday 7 is Saturday, counting Sunday as 1.
        if calendar.component(.weekday, from: day) == 7 { out.insert(index) }
    }
    return out
}

// MARK: - A picked colour, made readable

/// Relative luminance of an sRGB colour, WCAG's formula, the one every
/// number in WidgetParchment.swift was solved with.
func relativeLuminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
    func lin(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

func contrastRatio(_ a: Double, _ b: Double) -> Double {
    (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

/// The worst ground each sheet offers ink (WidgetParchment.swift): the cream
/// runs down to 0.670, the night sheet up to 0.0465.
let parchmentWorstLightGround = 0.670
let parchmentWorstDarkGround = 0.0465

/// [hex] ("1B895D", with or without "#") as 0-1 channels, or nil.
func rgbChannels(fromHex hex: String?) -> (Double, Double, Double)? {
    guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
}

/// A habit's own picked colour, moved just far enough toward black (on the
/// cream sheet) or white (on the night sheet) to read at [target]:1 against
/// that sheet's worst ground. A colour that already reads is returned as it
/// is, so a habit keeps its own colour wherever the sheet allows it.
///
/// The same bisection the Dart side's darkenToContrast does, and the one the
/// parchment tokens were solved with: a picked colour is drawn as ink here,
/// and the app's own gold measures 1.31:1 on the cream sheet.
func parchmentSafeChannels(_ rgb: (Double, Double, Double), dark: Bool,
                           target: Double = 4.5) -> (Double, Double, Double) {
    let ground = dark ? parchmentWorstDarkGround : parchmentWorstLightGround
    let toward: Double = dark ? 1 : 0
    func mix(_ t: Double) -> (Double, Double, Double) {
        (rgb.0 + (toward - rgb.0) * t, rgb.1 + (toward - rgb.1) * t, rgb.2 + (toward - rgb.2) * t)
    }
    func reads(_ c: (Double, Double, Double)) -> Bool {
        contrastRatio(relativeLuminance(c.0, c.1, c.2), ground) >= target
    }
    if reads(rgb) { return rgb }
    var lo = 0.0, hi = 1.0
    for _ in 0..<24 {
        let mid = (lo + hi) / 2
        if reads(mix(mid)) { hi = mid } else { lo = mid }
    }
    return mix(hi)
}

// ── The app's colour theme (2026-09-25) ──────────────────────────────────
//
// Aziz: the Home Screen faces follow the app's theme, for everyone. Free
// accounts have two themes and everything else is Premium already, so this
// needs no lock of its own. HomeWidgetService.pushTheme writes one string,
// "presetId|#accent|#done"; the Habits, Tasks and Room Race faces wear its
// two colours where they wore the brand gold and green (themeGold,
// themeGreen and themeGreenFill in WidgetParchment.swift), made readable on
// the sheet by the same rule a habit's own colour gets.

/// The two colours a face wears, as six hex digits with or without "#".
struct WidgetThemeColors: Equatable {
    let accentHex: String
    let doneHex: String
}

/// The default theme's id (ThemePresets.defaultId on the Dart side).
let widgetDefaultThemeId = "emerald_gold"

/// The app's theme from the string pushTheme wrote, or nil. nil for the
/// default theme, for nothing written yet, and for anything malformed: the
/// faces then keep the hand-solved parchment tokens exactly, so an account
/// on the default theme sees no change at all, and a phone updated before
/// the app has run once looks as it always did.
func parseWidgetTheme(_ raw: String?) -> WidgetThemeColors? {
    guard let parts = raw?.split(separator: "|", omittingEmptySubsequences: false),
          parts.count == 3 else { return nil }
    let id = String(parts[0])
    let accent = String(parts[1])
    let done = String(parts[2])
    guard !id.isEmpty, id != widgetDefaultThemeId,
          rgbChannels(fromHex: accent) != nil,
          rgbChannels(fromHex: done) != nil else { return nil }
    return WidgetThemeColors(accentHex: accent, doneHex: done)
}
