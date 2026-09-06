# Apple Watch — what already works, and how to add the companion app

Two of the three "watch" features need no watch app at all, and they are
already live in this codebase. Read this first so the companion app is a
choice, not an assumption.

## Already working with NO watch app

**1. Reminders on the watch.** iOS forwards every habit/prayer reminder
(`flutter_local_notifications`) and every room push to a paired watch
automatically whenever the iPhone is locked or asleep. Apple's rule: a
notification shows on the phone OR the watch, never both — phone unlocked
means phone.

**1b. The action buttons on the watch.** Mark Done / Snooze / On Track /
Slipped appear on the watch ONLY because they are registered as background
actions (no `DarwinNotificationActionOption.foreground`). A watch hides
foreground actions when the app has no watch app, since there is nothing on
the watch to bring forward; the watch SIMULATOR still draws them, so only a
real watch proves this. An earlier version of this file claimed the buttons
carried over while they were foreground actions; they did not. The tap is
handled in a headless engine and queued for the next app open, see
`lib/core/services/notification_action_background.dart`; that only works
because `AppDelegate.swift` makes itself the notification centre delegate
(otherwise firebase_messaging swallows the tap) and holds a background task
open while the engine runs (otherwise iOS suspends the process first). Both
were found on device on 2026-09-06 and are explained in that file. Prayer-anchored
reminders are also Time Sensitive (entitlement in `Runner.entitlements`),
so they reach through Focus on both devices. Keep both when adding the
companion app: with a watch app present, a foreground action would launch
the WATCH app, which would then have to handle the tap itself.

**2. Steps from the watch.** The walking-habit link
(`HealthStepsService`, `step_auto_complete.dart`) reads the daily step
total from Apple Health, and Apple Health already merges and de-duplicates
iPhone + Apple Watch steps at the OS level. A watch-recorded walk
completes a linked habit with zero extra code.

## The companion app (the actual Xcode project)

What it adds beyond the above: a habit list on the wrist that works
without a notification arriving, tap-to-complete from the watch face, and
complications. Budget 1–2 weeks of real work, not the widget's 15 minutes:
watchOS apps cannot be written in Flutter, so the UI is SwiftUI, and the
data has to move over Apple's WatchConnectivity bridge.

### Architecture (decided here so the code has one shape)

- **Transport:** `WCSession.updateApplicationContext` from phone → watch
  (latest habit list + today's completions — context survives the watch
  app being killed, and newer writes replace older ones, which is exactly
  right for "current state"). Watch → phone completions go over
  `transferUserInfo` (queued, delivered in order, survives reachability
  gaps) — mirroring the widget's Mark Done queue-and-drain pattern in
  `HomeWidgetService`.
- **Dart side:** the `watch_connectivity` pub package (add it only when
  this project starts). A new `lib/core/services/watch_bridge_service.dart`
  singleton, same private-constructor shape as every other service, pushes
  the same payload `HomeWidgetService` already assembles (habit id, local
  name, done state) and drains incoming completion messages through the
  same `completeHabit` path `main.dart`'s notification handler uses — no
  new completion logic, only a new entry door.
- **App Groups do NOT span iPhone ↔ watch.** The widget's shared storage
  cannot be read by the watch; WatchConnectivity is the only bridge. Do
  not try to reuse `group.com.growdaily.v2.widget` across devices.

### Target creation (Xcode GUI, cannot be scripted)

1. Open `ios/Runner.xcworkspace` (the workspace, not the project — pods).
2. File → New → Target… → **watchOS → App**. Check "Watch App for
   Existing iOS App" and pick Runner.
3. Product Name: `GrowDailyWatch`. Interface SwiftUI, language Swift.
   Uncheck the tests.
4. Team: same signing team as Runner. When asked to activate the scheme,
   Cancel — keep building the Runner scheme.
5. In the watch target's General tab set the minimum watchOS to 9.0
   (matches the iOS 15/16-era floor of the phone app; raise both together
   later if ever needed).
6. Runner side: nothing to add — `WCSession` needs no entitlement or
   capability, so Runner.entitlements stays untouched.

### Order of implementation once the target exists

1. Phone → watch context push (habit names + done flags), watch renders a
   static list. This alone is demo-able.
2. Watch → phone completion over transferUserInfo, drained into
   `completeHabit` (copy the guard sequence from `main.dart`'s
   notification-action handler VERBATIM — the awaits for auth/dashboard
   load exist because of real, documented bugs).
3. Complication (accessoryCircular showing done/total) reading the last
   pushed context.
4. Arabic: the watch list must render RTL with the Arabic habit names the
   phone sends — send `localName(isAr)` results, not raw `name`, so the
   watch never needs the locale logic.

Nothing in steps 1–4 touches the Android build, the widget, or the
walking-habit link; it is purely additive.
