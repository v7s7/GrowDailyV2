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

// MARK: - Where a control can go

/// The destinations, spelled exactly as NavTab's ids in
/// lib/core/providers/nav_layout_provider.dart. The Dart side resolves the
/// id with NavTab.byId and falls back to the usual tab when it does not
/// recognise one, so a control left on the lock screen after a tab is
/// renamed opens the app rather than doing nothing.
private enum ControlDestination: String {
    case habits = "grid"
    case tasks = "matrix"

    /// `growdaily://open?tab=<id>` — one parameterised link rather than a
    /// path per page. See parseOpenTabLink in
    /// lib/core/constants/deep_links.dart, which is the only place that
    /// spelling has to agree.
    var url: URL {
        URL(string: "growdaily://open?tab=\(rawValue)")!
    }
}

/// The Matrix widget's existing quick-add link, reused verbatim. A capture
/// action is the one thing a lock screen is genuinely better at than the
/// app icon, so it earns a control of its own rather than being a second
/// tap inside the Tasks one.
private let quickAddTaskURL = URL(string: "growdaily://matrix/add")!

// MARK: - Intents

/// Opens a URL in the app.
///
/// A control cannot open a URL directly: ControlWidgetButton takes an
/// AppIntent, so the intent is the thing that has to do the opening. Going
/// out through the URL rather than navigating from Swift is deliberate — it
/// lands in main.dart's _handleDeepLink, which is already the single place
/// every link in this app is resolved, so a control cannot drift away from
/// what a shared link, a widget tap or a notification action would do.
@available(iOS 18.0, *)
private protocol OpensGrowDaily: AppIntent {
    var destinationURL: URL { get }
}

@available(iOS 18.0, *)
extension OpensGrowDaily {
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(destinationURL))
    }
}

@available(iOS 18.0, *)
struct OpenGrowDailyHabitsIntent: AppIntent, OpensGrowDaily {
    static var title: LocalizedStringResource = "Open Habits"
    static var description = IntentDescription("Opens Grow Daily on your habit board.")
    static var openAppWhenRun: Bool { true }
    fileprivate var destinationURL: URL { ControlDestination.habits.url }
}

@available(iOS 18.0, *)
struct OpenGrowDailyTasksIntent: AppIntent, OpensGrowDaily {
    static var title: LocalizedStringResource = "Open Tasks"
    static var description = IntentDescription("Opens Grow Daily on your tasks.")
    static var openAppWhenRun: Bool { true }
    fileprivate var destinationURL: URL { ControlDestination.tasks.url }
}

@available(iOS 18.0, *)
struct AddGrowDailyTaskIntent: AppIntent, OpensGrowDaily {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Opens Grow Daily with a new task ready to type.")
    static var openAppWhenRun: Bool { true }
    fileprivate var destinationURL: URL { quickAddTaskURL }
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
