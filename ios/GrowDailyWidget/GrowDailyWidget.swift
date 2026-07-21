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
/// just deferring it. Instead this only ever touches shared UserDefaults:
///
///  1. Flips this habit's `done` flag in the cached today-list, so the one
///     reload iOS guarantees right after `perform()` returns shows it
///     checked immediately.
///  2. Appends the habit id to a small pending-completions queue.
///
/// The Flutter app drains that queue (HomeWidgetService.
/// takePendingCompletions, called from main.dart whenever the app comes to
/// the foreground) and runs it through the exact same completeHabit path a
/// normal in-app tap uses. That's the one real reward — this button's own
/// visual "done" state is provisional until then.
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

        if var habits = readJSON("todayHabitsJson", from: defaults, as: [TodayHabit].self) {
            for i in habits.indices where habits[i].id == habitId {
                habits[i].done = true
            }
            writeJSON(habits, to: "todayHabitsJson", in: defaults)
        }

        var pending = readJSON("pendingWidgetCompletions", from: defaults, as: [String].self) ?? []
        if !pending.contains(habitId) {
            pending.append(habitId)
        }
        writeJSON(pending, to: "pendingWidgetCompletions", in: defaults)

        return .result()
    }
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
    private var ringColor: Color { isUrgent ? .gdWarning : .gdEmerald }

    var body: some View {
        ZStack {
            Circle().stroke(Color.gdBorder, lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
            Text("\(completed)/\(total)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.default, value: completed)
        }
    }
}

/// A short status line whose tone shifts across the day — encouraging
/// early, more direct once it's evening and something's still open. This
/// is the copy-only half of "make the widget feel alive": Duolingo's owl
/// does the same escalating-urgency trick by swapping between a handful
/// of pre-made expression images (see the design discussion this is from)
/// — same idea, just words instead of art, so it needs no new asset work
/// at all.
func statusLine(completed: Int, total: Int) -> String {
    if total <= 0 { return "Nothing scheduled today" }
    if completed >= total { return "All done today" }
    let remaining = total - completed
    let hour = Calendar.current.component(.hour, from: Date())
    if hour >= 20 {
        return remaining == 1 ? "Last one — don't break the streak" : "\(remaining) left — finish today"
    } else if hour >= 18 {
        return "\(remaining) left today"
    }
    return "\(remaining) to go today"
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
struct HeatmapGrid: View {
    let days: [HeatmapDay]
    var cellSize: CGFloat = 9
    var spacing: CGFloat = 2.5

    private var rows: [[HeatmapDay]] {
        guard !days.isEmpty else { return [] }
        return stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }
    }

    private func color(for count: Int) -> Color {
        switch count {
        case 0: return Color.gdBorder.opacity(0.55)
        case 1: return Color.gdEmerald.opacity(0.30)
        case 2, 3: return Color.gdEmerald.opacity(0.60)
        default: return Color.gdEmerald
        }
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.date) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(for: day.count))
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }
}

// MARK: - Home Screen widget views

struct GrowDailySmallView: View {
    var entry: GrowDailyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                FlameIcon(size: 17)
                Text("\(entry.streak)")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                    .animation(.default, value: entry.streak)
            }
            Text("day streak")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            HStack {
                ProgressRing(completed: entry.completedToday, total: entry.totalToday)
                    .frame(width: 26, height: 26)
                Spacer()
                Label("\(entry.gold)", systemImage: "circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gdGold)
                    .contentTransition(.numericText())
                    .animation(.default, value: entry.gold)
            }
        }
        .padding()
        .containerBackground(for: .widget) { Color.gdBg }
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
                Text(statusLine(completed: entry.completedToday, total: entry.totalToday))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
                    .animation(.default, value: entry.completedToday)
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        FlameIcon(size: 12)
                        Text("\(entry.streak)d")
                            .contentTransition(.numericText())
                            .animation(.default, value: entry.streak)
                    }
                    .foregroundColor(.gdStreak)
                    Label("Lvl \(entry.level)", systemImage: "star.fill")
                        .foregroundColor(.gdXpBlue)
                        .contentTransition(.numericText())
                        .animation(.default, value: entry.level)
                    Label("\(entry.gold)", systemImage: "circle.fill")
                        .foregroundColor(.gdGold)
                        .contentTransition(.numericText())
                        .animation(.default, value: entry.gold)
                }
                .font(.system(size: 11, weight: .semibold))
            }
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(for: .widget) { Color.gdBg }
    }
}

/// The "pro" size — mini heatmap plus today's actual habits, each with a
/// real checkmark button (see MarkHabitDoneIntent above). Shows at most 5
/// rows; a widget can't scroll, so anything past that is a count, not a
/// list.
struct GrowDailyLargeView: View {
    var entry: GrowDailyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    FlameIcon(size: 15)
                    Text("\(entry.streak)")
                        .foregroundColor(.gdStreak)
                        .font(.system(size: 15, weight: .heavy))
                        .contentTransition(.numericText())
                        .animation(.default, value: entry.streak)
                }
                Spacer()
                // Same day-aware line as the medium widget, in place of the
                // old flat "X/Y today" — see statusLine's doc comment.
                Text(statusLine(completed: entry.completedToday, total: entry.totalToday))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.default, value: entry.completedToday)
            }

            // No .frame(height:) here on purpose — HeatmapGrid now sizes
            // itself deterministically from fixed cells (see its own doc
            // comment), so forcing an outer height back on is exactly the
            // mismatch that caused the overlap bug in the first place.
            HeatmapGrid(days: entry.heatmap)

            Divider().background(Color.gdBorder)

            VStack(alignment: .leading, spacing: 7) {
                if entry.habits.isEmpty {
                    Text("No habits scheduled today")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                } else {
                    ForEach(Array(entry.habits.prefix(5))) { habit in
                        HStack(spacing: 8) {
                            Button(intent: MarkHabitDoneIntent(habitId: habit.id)) {
                                Image(systemName: habit.done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(habit.done ? .gdEmerald : .white.opacity(0.35))
                            }
                            .buttonStyle(.plain)
                            Text(habit.name)
                                .font(.system(size: 12, weight: .medium))
                                .strikethrough(habit.done)
                                .foregroundColor(habit.done ? .white.opacity(0.5) : .white)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    if entry.habits.count > 5 {
                        Text("+\(entry.habits.count - 5) more in app")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding()
        .background(cornerMotif(), alignment: .topTrailing)
        .containerBackground(for: .widget) { Color.gdBg }
    }
}

struct GrowDailyWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: GrowDailyEntry

    var body: some View {
        switch family {
        case .systemMedium:
            GrowDailyMediumView(entry: entry)
        case .systemLarge:
            GrowDailyLargeView(entry: entry)
        default:
            GrowDailySmallView(entry: entry)
        }
    }
}

struct GrowDailyWidget: Widget {
    let kind: String = "GrowDailyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GrowDailyProvider()) { entry in
            GrowDailyWidgetView(entry: entry)
        }
        .configurationDisplayName("GrowDaily")
        .description("Today's progress, streak, and a tappable habit list at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Lock Screen widgets
//
// Display-only on purpose — Lock Screen widgets are rendered in the
// system's own tint on a locked device, not really where you want someone
// trying to tap fiddly buttons.

struct GrowDailyCircularView: View {
    var entry: GrowDailyEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                Text("\(entry.streak)")
                    .font(.system(size: 14, weight: .bold))
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
                Text("\(entry.streak) day streak")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(entry.completedToday)/\(entry.totalToday) done today")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct GrowDailyLockScreenView: View {
    @Environment(\.widgetFamily) var family
    var entry: GrowDailyEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            GrowDailyRectangularView(entry: entry)
        default:
            GrowDailyCircularView(entry: entry)
        }
    }
}

struct GrowDailyLockScreenWidget: Widget {
    let kind: String = "GrowDailyLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GrowDailyProvider()) { entry in
            GrowDailyLockScreenView(entry: entry)
        }
        .configurationDisplayName("GrowDaily Streak")
        .description("Your streak and today's progress on the Lock Screen.")
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
}

struct RoomRaceEntry: TimelineEntry {
    let date: Date
    let hasRoom: Bool
    let roomName: String
    let isLive: Bool
    let daysRemaining: Int
    let rows: [RoomRaceRow]
}

struct RoomRaceProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoomRaceEntry {
        RoomRaceEntry(date: Date(), hasRoom: true, roomName: "Ramadan Push", isLive: true, daysRemaining: 12,
                      rows: [RoomRaceRow(name: "You", rank: 1, percent: 86, isMe: true),
                             RoomRaceRow(name: "Sara", rank: 2, percent: 74, isMe: false),
                             RoomRaceRow(name: "Omar", rank: 3, percent: 61, isMe: false)])
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
            return RoomRaceEntry(date: Date(), hasRoom: false, roomName: "", isLive: false, daysRemaining: 0, rows: [])
        }
        return RoomRaceEntry(date: Date(), hasRoom: raw.hasRoom, roomName: raw.roomName,
                              isLive: raw.isLive, daysRemaining: raw.daysRemaining, rows: raw.rows)
    }
}

/// Medal-toned circle + first initial — rank 1/2/3 get gold/silver/bronze
/// so the top of the pack reads at a glance without needing real avatars.
struct RoomAvatarCircle: View {
    let name: String
    let rank: Int
    var size: CGFloat = 26

    private var ringColor: Color {
        switch rank {
        case 1: return .gdGold
        case 2: return Color(white: 0.75)
        case 3: return rgb(0xCD, 0x7F, 0x32) // bronze
        default: return .gdBorder
        }
    }

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle().fill(Color.gdSurface)
            Circle().stroke(ringColor, lineWidth: rank <= 3 ? 2 : 1)
            Text(initial.isEmpty ? "?" : initial)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Same "shifting tone, no new art" idea as [statusLine] above, for the
/// Room Race face — leading feels different from mid-pack, worth saying
/// out loud rather than just showing a number and leaving the reaction to
/// the person looking at it.
func rankLine(rank: Int, racerCount: Int) -> String {
    if rank == 1 { return racerCount > 1 ? "You're leading" : "Racing solo" }
    if rank == 2 { return "So close — catch #1" }
    return "Keep pushing"
}

/// One leaderboard row: avatar, name, rank, percent — highlighted with a
/// soft emerald wash when [row.isMe] so someone can find themselves in the
/// pack without reading every name.
struct RoomRaceRowView: View {
    let row: RoomRaceRow
    var avatarSize: CGFloat = 26

    var body: some View {
        HStack(spacing: 8) {
            Text("#\(row.rank)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 18, alignment: .leading)
                .contentTransition(.numericText())
                .animation(.default, value: row.rank)
            RoomAvatarCircle(name: row.name, rank: row.rank, size: avatarSize)
            Text(row.isMe ? "\(row.name) (You)" : row.name)
                .font(.system(size: 12, weight: row.isMe ? .bold : .medium))
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(row.percent)%")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.gdEmerald)
                .contentTransition(.numericText())
                .animation(.default, value: row.percent)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(row.isMe ? Color.gdEmerald.opacity(0.14) : Color.clear)
        )
    }
}

/// Shown in every size when nobody's in an active room yet — a plain
/// "nothing to show" state reads as broken on a widget in a way it doesn't
/// in the full app, so this always explains what to do next instead of
/// just going blank.
struct RoomRaceEmptyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.4))
            Text("No active room")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
            Text("Join or create one in the app")
                .font(.system(size: 10.5))
                .foregroundColor(.white.opacity(0.55))
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
                RoomRaceEmptyView()
            } else if let mine {
                VStack(alignment: .leading, spacing: 6) {
                    Label(entry.roomName, systemImage: "flag.checkered")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                    Spacer()
                    Text("#\(mine.rank)")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(.gdGold)
                        .contentTransition(.numericText())
                        .animation(.default, value: mine.rank)
                    Text(rankLine(rank: mine.rank, racerCount: entry.rows.count))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                        .contentTransition(.opacity)
                        .animation(.default, value: mine.rank)
                    if entry.daysRemaining > 0 {
                        Text("\(entry.daysRemaining)d left")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .containerBackground(for: .widget) { Color.gdBg }
    }
}

struct RoomRaceMediumView: View {
    var entry: RoomRaceEntry

    var body: some View {
        Group {
            if !entry.hasRoom || entry.rows.isEmpty {
                RoomRaceEmptyView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(entry.roomName, systemImage: "flag.checkered")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        if entry.daysRemaining > 0 {
                            Text("\(entry.daysRemaining)d left")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    ForEach(Array(entry.rows.prefix(4)), id: \.rank) { row in
                        RoomRaceRowView(row: row, avatarSize: 22)
                    }
                }
            }
        }
        .padding()
        .containerBackground(for: .widget) { Color.gdBg }
    }
}

struct RoomRaceLargeView: View {
    var entry: RoomRaceEntry

    var body: some View {
        Group {
            if !entry.hasRoom || entry.rows.isEmpty {
                RoomRaceEmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(entry.roomName, systemImage: "flag.checkered")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        if entry.daysRemaining > 0 {
                            Text("\(entry.daysRemaining) days left")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.55))
                        } else if !entry.isLive {
                            Text("Starting soon")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.gdWarning)
                        }
                    }
                    Divider().background(Color.gdBorder)
                    ForEach(Array(entry.rows.prefix(6)), id: \.rank) { row in
                        RoomRaceRowView(row: row, avatarSize: 26)
                    }
                    if entry.rows.count > 6 {
                        Text("+\(entry.rows.count - 6) more racing")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding()
        .background(cornerMotif(), alignment: .topTrailing)
        .containerBackground(for: .widget) { Color.gdBg }
    }
}

struct RoomRaceWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: RoomRaceEntry

    var body: some View {
        switch family {
        case .systemMedium:
            RoomRaceMediumView(entry: entry)
        case .systemLarge:
            RoomRaceLargeView(entry: entry)
        default:
            RoomRaceSmallView(entry: entry)
        }
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
        .configurationDisplayName("Room Race")
        .description("See your rank and your friends' progress in your active room.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Bundle

@main
struct GrowDailyWidgetBundle: WidgetBundle {
    var body: some Widget {
        GrowDailyWidget()
        GrowDailyLockScreenWidget()
        GrowDailyRoomRaceWidget()
    }
}
