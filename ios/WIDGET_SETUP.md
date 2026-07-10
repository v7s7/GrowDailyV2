# Home screen widget — setup

The Dart side is already done (`home_widget` in `pubspec.yaml`,
`lib/core/services/home_widget_service.dart`, wired into `main.dart` so it
pushes your current streak/level/gold to shared storage every time they
change). What's left is entirely inside Xcode, on your Mac — this is the one
part of this feature nothing outside Xcode can do, since `home_widget`
explicitly doesn't let Flutter draw the widget itself; it has to be real
Swift.

Budget about 10 minutes. Do this after you've pulled the
`feature/engagement-improvements` branch and run `flutter pub get`.

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
7. Team: your existing signing team (same one Runner uses).
8. Click Finish. When Xcode asks "Activate GrowDailyWidget scheme?", click
   **Cancel** — you still want to build/run the Runner scheme normally from
   Flutter, not the widget's own scheme.

This creates a new `GrowDailyWidget/` folder next to `Runner/`, with a
boilerplate `GrowDailyWidget.swift`.

## 2. Replace the boilerplate Swift

Open `GrowDailyWidget/GrowDailyWidget.swift` and replace its **entire
contents** with:

```swift
import WidgetKit
import SwiftUI

// Must match HomeWidgetService's _appGroupId exactly (lib/core/services/
// home_widget_service.dart) — this is how the widget reads what the Flutter
// app last saved.
let appGroupId = "group.com.growdaily.v2.widget"

struct GrowDailyEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let level: Int
    let gold: Int
}

struct GrowDailyProvider: TimelineProvider {
    func placeholder(in context: Context) -> GrowDailyEntry {
        GrowDailyEntry(date: Date(), streak: 0, level: 1, gold: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (GrowDailyEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GrowDailyEntry>) -> Void) {
        let entry = loadEntry()
        // Widgets don't get live pushes — this just tells iOS "check back
        // in an hour." The real refresh trigger is HomeWidgetService calling
        // updateWidget() from Flutter every time streak/level/gold change;
        // this timeline is only the fallback for while the app isn't open.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> GrowDailyEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        return GrowDailyEntry(
            date: Date(),
            streak: defaults?.integer(forKey: "streak") ?? 0,
            level: defaults?.integer(forKey: "level") ?? 1,
            gold: defaults?.integer(forKey: "gold") ?? 0
        )
    }
}

struct GrowDailyWidgetView: View {
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
                Label("Lvl \(entry.level)", systemImage: "star.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.yellow)
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

struct GrowDailyWidget: Widget {
    let kind: String = "GrowDailyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GrowDailyProvider()) { entry in
            GrowDailyWidgetView(entry: entry)
        }
        .configurationDisplayName("GrowDaily")
        .description("Your streak, level, and gold at a glance.")
        .supportedFamilies([.systemSmall])
    }
}
```

If Xcode generated a `@main` struct at the bottom of the boilerplate file
(a `GrowDailyWidgetBundle`), leave that part as-is — it just needs to
reference `GrowDailyWidget()`, which the code above provides.

## 3. Share data between the app and the widget: App Group

The widget runs in its own sandboxed process — it can only see what you
explicitly share via an App Group container.

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
   corner → search **GrowDaily** → add the small widget.
3. Open the app, complete a habit, background it — the widget should update
   within a few seconds (it calls `updateWidget()` immediately; iOS may
   still throttle the actual redraw briefly, that's an OS-level limit, not
   a bug).

## If it doesn't work

- **Widget shows 0 / stays blank:** almost always the App Group string not
  matching exactly across both targets and `home_widget_service.dart` —
  re-check step 3, copy-paste the string rather than retyping it.
- **"GrowDailyWidget" doesn't appear in the widget picker:** the target
  name in step 1.4 doesn't match `iOSName: 'GrowDailyWidget'` in
  `home_widget_service.dart`, or the app hasn't been built/run at least
  once since adding the target.
- **New target's deployment target:** Xcode will likely set the widget
  extension's own minimum iOS version higher than Runner's (14.0) — that's
  normal and fine, they're independent per-target settings. The Swift above
  deliberately uses `.background()` rather than the iOS-17-only
  `containerBackground` so it compiles regardless of what Xcode picks.
