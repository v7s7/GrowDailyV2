//
//  ControlIntents.swift
//  Runner
//
//  The app's copies of the three Lock Screen / Control Center control
//  intents. The controls themselves, and the extension's copies of these same
//  intents, are in ios/GrowDailyWidget/GrowDailyControls.swift.
//
//  WHY THE APP NEEDS ITS OWN COPY. Until 2026-09-21 these intents existed in
//  the widget extension only, and the controls did not take anyone to the
//  page they named (Aziz on build 69, 2026-09-10, and again on 2026-09-21
//  after the switch to a universal link). Apple's rules, both of which the
//  extension-only version broke:
//    - "The system requires the Target Membership of the app intent to be
//      set to both the app and the widget extension to open the app."
//      (WidgetKit, "Creating controls to perform actions across the system")
//    - openAppWhenRun "generates an error if the app intent runs in an app
//      extension." (AppIntent.openAppWhenRun)
//  The built app's Metadata.appintents listed only the two alarm intents, so
//  the system had no copy in the app to bring forward and run.
//
//  Same names, titles and descriptions as the extension's copies, and the
//  same signature: an intent is matched across the two by its type name, and
//  iOS runs this one, in the app, in the foreground. Keep the two in step,
//  the way the alarm intents in AlarmKitBridge.swift and
//  GrowDailyAlarmLiveActivity.swift are kept.
//

import AppIntents
import Foundation
import app_links

/// The destinations, spelled exactly as NavTab's ids in
/// lib/core/providers/nav_layout_provider.dart (test/core/
/// open_tab_link_test.dart pins that they exist).
private enum ControlDestination: String {
    case habits = "grid"
    case tasks = "matrix"
}

/// Hands "open this tab" to Flutter the way any link reaches it: through
/// app_links, into main.dart's _handleDeepLink, the one place every link in
/// this app is resolved. So a control lands exactly where a widget tap or a
/// shared link naming the same tab would.
///
/// Straight to the plugin rather than out through the system as a URL. This
/// runs inside the app already, so a round trip through iOS would only add
/// the ways a URL can go astray (an association the phone cached before
/// /open was served opens Safari instead). The link's shape is
/// deep_links.dart's openTabUrl, which the Dart tests pin.
///
/// Safe at any point of a launch: when Flutter is not listening yet, the
/// plugin keeps the link as the launch link and hands it over when main.dart
/// asks for it (_initDeepLinks).
@MainActor
private func openInApp(_ destination: ControlDestination, quickAdd: Bool = false) {
    var link = URLComponents()
    link.scheme = "https"
    link.host = "grow-daily-339ef.web.app"
    link.path = "/open"
    link.queryItems = [URLQueryItem(name: "tab", value: destination.rawValue)]
    if quickAdd { link.queryItems?.append(URLQueryItem(name: "add", value: "1")) }
    guard let url = link.url else { return }
    AppLinks.shared.handleLink(url: url)
}

@available(iOS 18.0, *)
struct OpenGrowDailyHabitsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Habits"
    static var description = IntentDescription("Opens Grow Daily on your habit board.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        openInApp(.habits)
        return .result()
    }
}

@available(iOS 18.0, *)
struct OpenGrowDailyTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Tasks"
    static var description = IntentDescription("Opens Grow Daily on your tasks.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        openInApp(.tasks)
        return .result()
    }
}

@available(iOS 18.0, *)
struct AddGrowDailyTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Opens Grow Daily with a new task ready to type.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        openInApp(.tasks, quickAdd: true)
        return .result()
    }
}
