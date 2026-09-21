//
//  GrowDailyControls.swift
//  GrowDailyWidget
//
//  The two circular slots at the bottom of the iOS Lock Screen, plus
//  Control Center and the Action Button. These are CONTROLS (iOS 18's
//  ControlWidget), a different API from the accessory widgets in
//  GrowDailyWidget.swift: an accessory widget DRAWS state around the clock,
//  a control is a BUTTON. Asked for by Aziz on 2026-09-10, pointing at the
//  stock flashlight and voice-memo buttons: "can we create here that opens
//  the tasks page, or the habit page direct".
//
//  Gated at iOS 18 the same way GrowDailyAlarmLiveActivity is gated at 26,
//  so the extension keeps its 17.0 deployment target and older systems
//  simply never see these.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Intents
//
// The extension's copies. The APP's copies, in ios/Runner/ControlIntents
// .swift, are the ones that run: same names, titles and signature, matched
// by type name, and iOS brings the app forward and runs its copy there. This
// copy exists so a control in this extension can name its action; its
// perform() never runs, because openAppWhenRun "generates an error if the
// app intent runs in an app extension" (Apple, AppIntent.openAppWhenRun).
//
// That is what was wrong from build 69 on. These intents lived here ONLY,
// so the app had no copy for iOS to open it with, and a tap did not reach
// the page it named ("the locked buttom are here but its not opening",
// Aziz, 2026-09-10; "they still dont send to task, or to habit", 2026-09-21).
// The switch from growdaily:// to a universal link in between did not
// address this, and the app's copies no longer go out through a URL at all.
//
// Each intent declares its own `perform()`, deliberately, rather than
// inheriting one from a shared protocol extension. App Intents builds its
// metadata from the concrete type, and a `perform()` supplied by a protocol
// default is a way to end up registered but inert. Keep these in step with
// the app's copies, the way the alarm intents are kept in step between
// AlarmKitBridge.swift and GrowDailyAlarmLiveActivity.swift.

@available(iOS 18.0, *)
struct OpenGrowDailyHabitsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Habits"
    static var description = IntentDescription("Opens Grow Daily on your habit board.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 18.0, *)
struct OpenGrowDailyTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Tasks"
    static var description = IntentDescription("Opens Grow Daily on your tasks.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 18.0, *)
struct AddGrowDailyTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Opens Grow Daily with a new task ready to type.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        .result()
    }
}

// MARK: - Controls

/// Names are English, matching every existing widget in this bundle
/// (.configurationDisplayName is "Grow Daily", "Room Race", "Matrix"). The
/// extension carries no .lproj, and on the lock screen only the GLYPH shows
/// anyway — the name is what the person reads once, in the picker.
///
/// Tinted, not plain: the two stock buttons Aziz screenshotted are grey
/// glass, so the app's own green is what makes its control findable at a
/// glance in a row of them.
@available(iOS 18.0, *)
struct GrowDailyHabitsControl: ControlWidget {
    static let kind = "com.growdaily.v2.control.habits"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenGrowDailyHabitsIntent()) {
                // The app's own bottom-bar mark for العادات, so the control
                // is recognisably the same thing as the tab it opens.
                Label("Habits", systemImage: "square.grid.2x2.fill")
            }
            .tint(.growDailyEmerald)
        }
        .displayName("Grow Daily Habits")
        .description("Open your habit board straight from the Lock Screen.")
    }
}

@available(iOS 18.0, *)
struct GrowDailyTasksControl: ControlWidget {
    static let kind = "com.growdaily.v2.control.tasks"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenGrowDailyTasksIntent()) {
                Label("Tasks", systemImage: "checklist")
            }
            .tint(.growDailyEmerald)
        }
        .displayName("Grow Daily Tasks")
        .description("Open your tasks straight from the Lock Screen.")
    }
}

@available(iOS 18.0, *)
struct GrowDailyAddTaskControl: ControlWidget {
    static let kind = "com.growdaily.v2.control.addTask"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: AddGrowDailyTaskIntent()) {
                Label("Add Task", systemImage: "text.badge.plus")
            }
            // Gold, not green: this one WRITES something. Same split the app
            // uses everywhere — green is the record, gold is the action.
            .tint(.growDailyGold)
        }
        .displayName("Grow Daily Add Task")
        .description("Capture a task without unlocking to the home screen first.")
    }
}

// MARK: - Palette

private extension Color {
    /// GameColors.emerald and GameColors.iconGold, the two the app's own
    /// bottom bar uses. Hard-coded because an extension cannot read the
    /// Dart palette, and a control's tint is picked once by the system
    /// rather than rebuilt per theme.
    static let growDailyEmerald = Color(red: 0.18, green: 0.81, blue: 0.56)
    static let growDailyGold = Color(red: 0.89, green: 0.71, blue: 0.37)
}
