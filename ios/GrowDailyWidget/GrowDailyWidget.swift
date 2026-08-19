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

/// Every widget face's background - a subtle vertical gradient standing in
/// for what used to be a flat Color.gdBg fill everywhere. Runs gdSurface
/// (already this palette's "one step up from bg" tone, used elsewhere for
/// inset rows/dividers) into gdBg itself, so it reads as gentle depth
/// rather than a new color. Deliberately understated - a widget sits on
/// top of the user's own wallpaper, and a strong gradient would fight that
/// far more than the old flat fill ever did.
struct WidgetGradientBackground: View {
    var body: some View {
        LinearGradient(colors: [.gdSurface, .gdBg], startPoint: .top, endPoint: .bottom)
    }
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
        .containerBackground(for: .widget) { WidgetGradientBackground() }
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
        .containerBackground(for: .widget) { WidgetGradientBackground() }
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
        .containerBackground(for: .widget) { WidgetGradientBackground() }
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
        .configurationDisplayName("Grow Daily")
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
                Text("\(entry.streak) day streak")
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.numericText())
                    .animation(.default, value: entry.streak)
                Text("\(entry.completedToday)/\(entry.totalToday) done today")
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
        .configurationDisplayName("Grow Daily Streak")
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

/// Compact horizontal contribution strip for one participant — the widget's
/// own copy of the in-app _MiniHeatmapStrip (room_detail_screen.dart).
/// Renders whatever levels (0-4) Dart already computed via heatmapLevelFor
/// (rooms_notifier.dart) rather than raw credit, so this view only ever
/// does a color lookup, never math. Same emerald-opacity tiers as heatColor
/// (monthly_heatmap_screen.dart); .gdBorder stands in for that function's
/// "empty" fill since this widget has one fixed dark palette, not a light/
/// dark-adaptive one. Each cell fades to its new shade on refresh instead
/// of popping (same "Animating data updates in widgets" treatment
/// ProgressRing's sweep already uses above), and the last cell always gets
/// today's gold ring — safe to assume it's today without checking a date,
/// since myRoomRaceSnapshotProvider only ever picks a room that hasn't
/// ended, so this strip's final day is never anything but today.
struct RoomRaceHeatmapStrip: View {
    let levels: [Int]

    private static let cell: CGFloat = 6
    private static let gap: CGFloat = 1.5

    private func color(for level: Int) -> Color {
        switch level {
        case 1: return Color.gdEmerald.opacity(0.30)
        case 2: return Color.gdEmerald.opacity(0.50)
        case 3: return Color.gdEmerald.opacity(0.70)
        case 4: return Color.gdEmerald.opacity(0.92)
        default: return Color.gdBorder
        }
    }

    var body: some View {
        HStack(spacing: Self.gap) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color(for: level))
                    .frame(width: Self.cell, height: Self.cell)
                    .overlay(
                        index == levels.count - 1
                            ? RoundedRectangle(cornerRadius: 1.5)
                                .stroke(Color.gdGold, lineWidth: 1)
                            : nil
                    )
                    .animation(.easeOut(duration: 0.4), value: level)
            }
        }
    }
}

/// A leaderboard row with its heatmap strip underneath — the "featured"
/// treatment for whichever participants a given widget size has room for.
/// Both RoomRaceMediumView and RoomRaceLargeView below give this to the
/// top 2 ranked participants specifically and fall back to the plain
/// RoomRaceRowView (no strip) for anyone past that - "the first one, and
/// the 2nd one in the group" is what this app settled on for "if no
/// space," rather than shrinking every row's strip to fit an arbitrary
/// roster size.
struct RoomRaceFeaturedRow: View {
    let row: RoomRaceRow
    var avatarSize: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            RoomRaceRowView(row: row, avatarSize: avatarSize)
            if let heatmap = row.heatmap, !heatmap.isEmpty {
                RoomRaceHeatmapStrip(levels: heatmap)
            }
        }
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
                .truncationMode(.tail)
                .layoutPriority(0)
            Spacer(minLength: 4)
            // Same fraction the Lock Screen shows, and the same reason it
            // can't be squeezed: fixedSize + priority means a long name
            // truncates instead of the score disappearing.
            Text(row.scoreLabel)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.gdEmerald)
                .fixedSize()
                .layoutPriority(2)
                .contentTransition(.numericText())
                .animation(.default, value: row.daysDone)
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
        .containerBackground(for: .widget) { WidgetGradientBackground() }
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
                    // Top 2 get their heatmap strip; anyone else just gets
                    // a count - see RoomRaceFeaturedRow's doc comment for
                    // why 2 specifically. Keyed by stableId (not rank) so a
                    // row that changes rank between refreshes slides to its
                    // new spot instead of the slot at that rank just
                    // swapping its text - see the .animation below.
                    ForEach(Array(entry.rows.prefix(2)), id: \.stableId) { row in
                        RoomRaceFeaturedRow(row: row, avatarSize: 20)
                    }
                    if entry.rows.count > 2 {
                        Text("+\(entry.rows.count - 2) more racing")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                // Drives the reorder above - same "animate between two
                // timeline entries" trick RoomRaceRowView's own rank/
                // percent numbers already use, just applied to row
                // position instead of row content.
                .animation(.easeInOut(duration: 0.45), value: entry.rows.map(\.rank))
            }
        }
        .padding()
        .containerBackground(for: .widget) { WidgetGradientBackground() }
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
                    // Top 2 get their heatmap strip; rows 3-6 stay the
                    // plain row they always were - see RoomRaceFeaturedRow's
                    // doc comment for why the cutoff is 2, not the full
                    // roster. Total shown (6) is unchanged from before.
                    // Keyed by stableId, not rank - see the .animation
                    // below and RoomRaceMediumView's matching comment.
                    ForEach(Array(entry.rows.prefix(2)), id: \.stableId) { row in
                        RoomRaceFeaturedRow(row: row, avatarSize: 26)
                    }
                    ForEach(Array(entry.rows.dropFirst(2).prefix(4)), id: \.stableId) { row in
                        RoomRaceRowView(row: row, avatarSize: 26)
                    }
                    if entry.rows.count > 6 {
                        Text("+\(entry.rows.count - 6) more racing")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .animation(.easeInOut(duration: 0.45), value: entry.rows.map(\.rank))
            }
        }
        .padding()
        .background(cornerMotif(), alignment: .topTrailing)
        .containerBackground(for: .widget) { WidgetGradientBackground() }
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

// MARK: - Room Race Lock Screen widgets
//
// Same "display-only, own compact views, shares the Home Screen widget's
// provider" shape as GrowDailyLockScreenWidget above - see that struct's
// doc comment for why Lock Screen widgets stay tap-free here (system tint,
// no room for fiddly buttons). Reuses RoomRaceProvider/RoomRaceEntry as-is -
// same roomRaceJson data, just laid out for a tiny accessory slot instead
// of a Home Screen size.
//
// Deliberately no explicit .foregroundColor(.gdGold/.gdEmerald/etc.) here,
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
                Text("#\(mine.rank)")
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
    // head-to-head instead of just a solo scoreboard: whoever's in 1st if
    // that isn't you (the gap you're closing), or whoever's in 2nd if it
    // is (the gap someone else is closing on you). Never both at once —
    // there's only room for one rival line here.
    private var rival: RoomRaceRow? {
        guard let mine else { return nil }
        let rivalRank = mine.rank == 1 ? 2 : 1
        return entry.rows.first(where: { $0.rank == rivalRank })
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
            Text("#\(rank)")
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
                Text("No active room")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }
}

struct RoomRaceLockScreenView: View {
    @Environment(\.widgetFamily) var family
    var entry: RoomRaceEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            RoomRaceRectangularView(entry: entry)
        default:
            RoomRaceCircularView(entry: entry)
        }
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
        .configurationDisplayName("Room Race")
        .description("Your rank in your starred room, on the Lock Screen.")
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

    init(id: String, title: String, quadrant: String, isDone: Bool, isFav: Bool, isLate: Bool) {
        self.id = id
        self.title = title
        self.quadrant = quadrant
        self.isDone = isDone
        self.isFav = isFav
        self.isLate = isLate
    }

    // Custom decode so a `matrixTasksJson` blob written by an older app
    // build (before isLate existed) still decodes instead of failing the
    // whole array — same "just missing the new bit" tolerance worth having
    // for any field added after this widget already shipped.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        quadrant = try c.decode(String.self, forKey: .quadrant)
        isDone = try c.decode(Bool.self, forKey: .isDone)
        isFav = try c.decode(Bool.self, forKey: .isFav)
        isLate = try c.decodeIfPresent(Bool.self, forKey: .isLate) ?? false
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
        let entry = loadEntry()
        // Same fallback-only cadence as GrowDailyProvider/RoomRaceProvider —
        // the real refresh trigger is HomeWidgetService.updateMatrixWidgetData
        // firing from main.dart's _matrixWidgetSub whenever the board changes.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> MatrixEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        let tasks = readJSON("matrixTasksJson", from: defaults, as: [WidgetMatrixTask].self) ?? []
        let doneToday = defaults?.integer(forKey: "matrixDoneTodayCount") ?? 0
        return MatrixEntry(date: Date(), tasks: tasks, doneToday: doneToday)
    }
}

/// Backs the checkmark on each task row. Exact same division of labor as
/// MarkHabitDoneIntent above — flips this task's cached `isDone` so the one
/// reload iOS guarantees right after `perform()` returns shows it checked
/// immediately, and queues the id for the real Flutter-side completion
/// (XP bonus included) the next time the app is open — see main.dart's
/// _processPendingWidgetTaskCompletions, which guards against re-toggling a
/// task the user already finished in-app in the meantime.
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

        if var tasks = readJSON("matrixTasksJson", from: defaults, as: [WidgetMatrixTask].self) {
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
                    .foregroundColor(task.isDone ? .gdEmerald : .white.opacity(0.35))
            }
            .buttonStyle(.plain)
            Text(task.title)
                .font(.system(size: 12, weight: .medium))
                .strikethrough(task.isDone)
                .foregroundColor(task.isDone ? .white.opacity(0.5) : .white)
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
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 20))
                .foregroundColor(.gdEmerald.opacity(0.8))
            Text("Nothing urgent")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
            Text("Your board is clear")
                .font(.system(size: 10.5))
                .foregroundColor(.white.opacity(0.55))
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

    var body: some View {
        HStack {
            Text("Matrix")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
            if openCount > 0 {
                Text("\(openCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .contentTransition(.numericText())
                    .animation(.default, value: openCount)
            }
            Spacer()
            Link(destination: matrixQuickAddURL) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.gdGold)
            }
        }
    }
}

struct MatrixMediumView: View {
    var entry: MatrixEntry

    var body: some View {
        Group {
            if entry.tasks.isEmpty {
                MatrixEmptyView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    MatrixHeaderRow(openCount: entry.tasks.count)
                    ForEach(Array(entry.tasks.prefix(3))) { task in
                        MatrixTaskRow(task: task)
                    }
                }
                .animation(.easeInOut(duration: 0.35),
                           value: entry.tasks.map { "\($0.id)|\($0.isDone)" })
            }
        }
        .padding()
        .containerBackground(for: .widget) { WidgetGradientBackground() }
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
                MatrixEmptyView()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    MatrixHeaderRow(openCount: entry.tasks.count)
                    Divider().background(Color.gdBorder)
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
                        Text("+\(entry.tasks.count - 8) more in app")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding()
        .background(cornerMotif(), alignment: .topTrailing)
        .containerBackground(for: .widget) { WidgetGradientBackground() }
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
                MatrixEmptyView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .foregroundColor(.gdGold)
                            .font(.system(size: 14))
                        Text("\(entry.tasks.count)")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundColor(.white)
                            .contentTransition(.numericText())
                            .animation(.default, value: entry.tasks.count)
                    }
                    Text(entry.tasks.count == 1 ? "task open" : "tasks open")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer(minLength: 0)
                    if let top = entry.tasks.first {
                        HStack(spacing: 5) {
                            QuadrantDot(quadrant: top.quadrant, size: 6)
                            Text(top.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
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
        .containerBackground(for: .widget) { WidgetGradientBackground() }
    }
}

struct MatrixWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: MatrixEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MatrixMediumView(entry: entry)
        case .systemLarge:
            MatrixLargeView(entry: entry)
        default:
            MatrixSmallView(entry: entry)
        }
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
        .configurationDisplayName("Matrix")
        .description("Your most urgent tasks — check them off or add a new one without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Matrix Lock Screen widget (starred task)
//
// A fifth widget kind, opt-in from the gallery like Room Race and the
// Matrix Home Screen widget above it — reuses that exact same
// MatrixProvider/MatrixEntry (matrixTasksJson already carries every open
// task, already sorted by quadrant priority — see main.dart's
// _matrixWidgetSub), just a different face on the same data: the
// *starred* (WidgetMatrixTask.isFav, mirrors MatrixTask.isFav's gold star
// toggle on the Tasks screen) tasks, falling back to the full list when
// nothing is starred — see MatrixEntry.lockScreenTasks below for why.
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
// starring); star nothing and it quietly falls back to the same
// priority-sorted task list every other Matrix widget shows, so it's
// useful out of the box either way.
//
// entry.tasks is already open-only and quadrant-sorted from the Dart side
// (see main.dart's _matrixWidgetSub), so "open tasks first" needs nothing
// extra here — the only done tasks that can appear are ones
// MarkTaskDoneIntent just marked locally, which its own sort already sinks
// to the bottom.
extension MatrixEntry {
    /// Starred tasks when there are any, otherwise every open task.
    var lockScreenTasks: [WidgetMatrixTask] {
        let starred = tasks.filter { $0.isFav }
        return starred.isEmpty ? tasks : starred
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
                    Text("\(remaining)")
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
                    Text("No tasks")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add one in Matrix")
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
                        Text("+\(overflow) more")
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
        switch family {
        case .accessoryRectangular:
            MatrixLockScreenRectangularView(entry: entry)
        default:
            MatrixLockScreenCircularView(entry: entry)
        }
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
        .configurationDisplayName("Starred Tasks")
        .description("Your starred tasks on the Lock Screen — or your top tasks if you haven't starred any.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Bundle

@main
struct GrowDailyWidgetBundle: WidgetBundle {
    var body: some Widget {
        GrowDailyWidget()
        GrowDailyLockScreenWidget()
        GrowDailyRoomRaceWidget()
        GrowDailyRoomRaceLockScreenWidget()
        GrowDailyMatrixWidget()
        GrowDailyMatrixLockScreenWidget()
    }
}
