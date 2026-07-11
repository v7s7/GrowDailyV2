# Home screen + Lock Screen widgets — setup

The Dart side is already done (`home_widget` in `pubspec.yaml`,
`lib/core/services/home_widget_service.dart`, wired into `main.dart` so it
pushes your current streak/level/gold/today's-habits/heatmap to shared
storage every time they change, and drains anything the widget's Mark Done
button queued whenever the app comes back to the foreground). What's left is
entirely inside Xcode, on your Mac — this is the one part of this feature
nothing outside Xcode can do, since `home_widget` explicitly doesn't let
Flutter draw the widget itself; it has to be real Swift.

Budget about 15 minutes — a bit more than before, since this version adds a
large size with a mini heatmap and tappable habits, plus two Lock Screen
widgets.

**What this version can do that a plain display-only widget can't:** the
large widget's habit rows have a real checkmark button. Tapping it marks
that habit done right there — no need to open the app. The widget shows it
as done instantly. The actual XP/streak/gold reward posts the next time you
open the app (that's a deliberate choice, explained in the AppIntent's
comments below — not a bug).

## 1. Create the widget extension target

1. Open `ios/Runner.xcworkspace` in Xcode (the `.xcworkspace`, not
   `.xcodeproj` — this project uses CocoaPods for Firebase, and the
   workspace is what pulls those pods in).
2. **File → New → Target…**
3. Pick **Widget Extension**, click Next.
4. Product Name: **`GrowDailyWidget`** (exact spelling matters — the Dart
   side already calls `HomeWidget.updateWidget(iOSName: 'GrowDailyWidget')`,
   so a mismatch here means the widget silently never refreshes).
5. Uncheck **"Include Live Activity"**.
6. Uncheck **"Include Configuration Intent"** — this widget has nothing to
   configure, keeping this off skips a bunch of boilerplate you don't need.
   (This is unrelated to the `MarkHabitDoneIntent` AppIntent below, which is
   for the button, not widget configuration.)
7. Team: your existing signing team (same one Runner uses).
8. Click Finish. When Xcode asks "Activate GrowDailyWidget scheme?", click
   **Cancel** — you still want to build/run the Runner scheme normally from
   Flutter, not the widget's own scheme.

This creates a new `GrowDailyWidget/` folder next to `Runner/`, with a
boilerplate `GrowDailyWidget.swift`.

Everything below lives in that one target — no Podfile changes, no
AppDelegate changes beyond the badge handler from the notifications setup,
no extra Target Membership boxes to check. The interactive button uses a
plain `AppIntent` that only ever touches shared storage, so it never needs
to run inside the main app's process the way some interactive-widget
tutorials require.

## 2. Replace the boilerplate Swift

Open `GrowDailyWidget/GrowDailyWidget.swift` and replace its **entire
contents** with:

```swift
import WidgetKit
import SwiftUI
import AppIntents

// Must match HomeWidgetService's _appGroupId exactly (lib/core/services/
// home_widget_service.dart) — this is how the widget reads what the Flutter
// app last saved, and how MarkHabitDoneIntent below writes back to it.
let appGroupId = "group.com.growdaily.v2.widget"

// MARK: - Shared data models
//
// These mirror the JSON HomeWidgetService.updateWidgetData encodes
// (todayHabitsJson, heatmapJson) — Codable so both reading and (for
// TodayHabit) writing back from the AppIntent are a couple of lines each,
// not manual dictionary poking.

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

// MARK: - Timeline

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

/// completedToday/totalToday as a small ring. Hand-rolled with
/// Circle().trim rather than ProgressView(value:) so it renders identically
/// across OS versions. Turns amber instead of green in the evening if
/// there's still something left today — a small nod to how Duolingo's owl
/// gets more insistent as the day goes on, expressed through this app's own
/// color language instead of a mascot.
struct ProgressRing: View {
    let completed: Int
    let total: Int
    var progress: Double { total <= 0 ? 0 : min(1, Double(completed) / Double(total)) }
    private var isUrgent: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 18 && total > 0 && completed < total
    }
    private var ringColor: Color { isUrgent ? .orange : .green }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(completed)/\(total)")
                .font(.system(size: 11, weight: .bold))
                .minimumScaleFactor(0.7)
        }
    }
}

/// 4-week mini heatmap — same dailyGreenCounts rollup the in-app Monthly
/// Heatmap screen reads, just windowed to the last 28 days.
struct HeatmapGrid: View {
    let days: [HeatmapDay]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    private func color(for count: Int) -> Color {
        switch count {
        case 0: return Color.secondary.opacity(0.15)
        case 1: return Color.green.opacity(0.35)
        case 2, 3: return Color.green.opacity(0.65)
        default: return Color.green
        }
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(days, id: \.date) { day in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: day.count))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}

// MARK: - Home Screen widget views

struct GrowDailySmallView: View {
    var entry: GrowDailyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text("\(entry.streak)")
                    .font(.system(size: 22, weight: .heavy))
            }
            Text("day streak")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            HStack {
                ProgressRing(completed: entry.completedToday, total: entry.totalToday)
                    .frame(width: 26, height: 26)
                Spacer()
                Label("\(entry.gold)", systemImage: "circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.yellow)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

struct GrowDailyMediumView: View {
    var entry: GrowDailyEntry

    var body: some View {
        HStack(spacing: 16) {
            ProgressRing(completed: entry.completedToday, total: entry.totalToday)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.completedToday) of \(entry.totalToday) done today")
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 10) {
                    Label("\(entry.streak)d", systemImage: "flame.fill")
                        .foregroundColor(.orange)
                    Label("Lvl \(entry.level)", systemImage: "star.fill")
                        .foregroundColor(.yellow)
                    Label("\(entry.gold)", systemImage: "circle.fill")
                        .foregroundColor(.yellow)
                }
                .font(.system(size: 11, weight: .semibold))
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

/// The "pro" size — mini heatmap plus today's actual habits, each with a
/// real checkmark button (see MarkHabitDoneIntent above). Shows at most 5
/// rows; a widget can't scroll, so anything past that is a count, not a
/// list — same idea as Streaks' large widget, just built from this app's
/// own grid/heatmap visual language instead of borrowing someone else's.
struct GrowDailyLargeView: View {
    var entry: GrowDailyEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(entry.streak)", systemImage: "flame.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 15, weight: .heavy))
                Spacer()
                Text("\(entry.completedToday)/\(entry.totalToday) today")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            HeatmapGrid(days: entry.heatmap)
                .frame(height: 64)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                if entry.habits.isEmpty {
                    Text("No habits scheduled today")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(entry.habits.prefix(5))) { habit in
                        HStack(spacing: 8) {
                            Button(intent: MarkHabitDoneIntent(habitId: habit.id)) {
                                Image(systemName: habit.done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(habit.done ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            Text(habit.name)
                                .font(.system(size: 12, weight: .medium))
                                .strikethrough(habit.done)
                                .foregroundColor(habit.done ? .secondary : .primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    if entry.habits.count > 5 {
                        Text("+\(entry.habits.count - 5) more in app")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
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
// trying to tap fiddly buttons. Duolingo and Streaks both keep theirs to
// glance-only info too.

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

// MARK: - Bundle

@main
struct GrowDailyWidgetBundle: WidgetBundle {
    var body: some Widget {
        GrowDailyWidget()
        GrowDailyLockScreenWidget()
    }
}
```

If Xcode's boilerplate already generated a `@main struct` at the bottom of
the file wrapping a single widget, **delete it** — the code above provides
its own `@main` `GrowDailyWidgetBundle` that wraps both widgets. Having two
`@main` entry points in the same file won't build.

## 3. Share data between the app and the widget: App Group

The widget runs in its own sandboxed process — it can only see what you
explicitly share via an App Group container. This is also how
`MarkHabitDoneIntent` above writes back — same container, same keys.

1. Select the **Runner** target → **Signing & Capabilities** → **+
   Capability** → **App Groups**.
2. Click **+** under App Groups, enter exactly:
   `group.com.growdaily.v2.widget`
3. Select the **GrowDailyWidgetExtension** target → **Signing &
   Capabilities** → **+ Capability** → **App Groups**.
4. Check the *same* group you just created (it should now appear in the
   list — don't create a second, differently-spelled one).

Both targets must show the identical string checked, or the widget will
always read empty defaults.

## 4. Build and add it

1. Switch back to the **Runner** scheme (top of Xcode, next to the
   Play/Stop buttons) and build/run as normal from Flutter
   (`flutter run`) — the widget extension builds automatically as part of
   Runner now that it exists.
2. On your device/simulator: long-press the home screen → **+** in the
   corner → search **GrowDaily** → you'll see small, medium, and large to
   choose from (swipe between them before adding). For the Lock Screen
   version: lock the device, long-press the Lock Screen → **Customize** →
   add **GrowDaily Streak** to the circular or rectangular slot.
3. Open the app, complete a habit, background it — the home screen widget
   should update within a few seconds (it calls `updateWidget()`
   immediately; iOS may still throttle the actual redraw briefly, that's an
   OS-level limit, not a bug).
4. On the large widget, tap a habit's circle. It should fill in as checked
   right away. Reopen the app (or just bring it forward) — that's when the
   real XP/streak/gold actually posts; you'll see the usual completion
   celebration play once the app catches up. This two-step feel (instant on
   the widget, real reward on next open) is deliberate — see
   `MarkHabitDoneIntent`'s comment for why.

Tapping anywhere on a widget *other* than a habit's checkmark just opens the
app — that's free, built-in iOS behavior, no code above does anything
special for it.

## If it doesn't work

- **Widget shows 0 / stays blank:** almost always the App Group string not
  matching exactly across both targets and `home_widget_service.dart` —
  re-check step 3, copy-paste the string rather than retyping it.
- **"GrowDailyWidget" doesn't appear in the widget picker:** the target
  name in step 1.4 doesn't match `iOSName: 'GrowDailyWidget'` in
  `home_widget_service.dart`, or the app hasn't been built/run at least
  once since adding the target.
- **Tapping a habit's checkmark does nothing visible:** check that you
  fully replaced the boilerplate file (not merged it) — a leftover
  duplicate `@main` from the Xcode template is the most common cause of a
  build that silently doesn't run the code you'd expect. Two `@main`s
  should actually fail the build rather than stay silent, so if it built
  fine, look here first anyway.
- **Habit shows checked on the widget but the app never seems to credit
  it:** open the app fully (not just glance at a notification) — the
  reward only posts on `didChangeAppLifecycleState`'s `resumed` case, which
  needs the app to actually come to the foreground, not just be visible for
  an instant.
- **New target's deployment target:** Xcode will likely set the widget
  extension's own minimum iOS version higher than Runner's (14.0) — that's
  normal and fine, they're independent per-target settings. The interactive
  button (`Button(intent:)`) needs iOS 17+ on the *widget extension's*
  target specifically; Runner can stay lower since none of this runs there.
