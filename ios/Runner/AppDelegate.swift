import Flutter
import UIKit
import UserNotifications
// Required for FlutterLocalNotificationsPlugin.setPluginRegistrantCallback.
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Background notification actions (Mark Done / Snooze / On Track /
    // Slipped tapped without opening the app, which is also what makes them
    // appear on a paired Apple Watch) run in a second, headless Flutter
    // engine that flutter_local_notifications starts on demand. That engine
    // needs the plugins registered the same way the main one gets them, or
    // the Dart callback (lib/core/services/notification_action_background
    // .dart) has no home_widget or timezone channel to talk to. The plugin
    // asserts this was set before it starts that engine, so it lives here
    // rather than in the implicit-engine hook below, which only runs when
    // the main engine does. See the plugin README's "notification actions"
    // section for this exact call.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      NSLog("[GrowDaily] background notification engine: registering plugins")
      GeneratedPluginRegistrant.register(with: registry)
    }
    // Make this app delegate the notification centre's delegate, before
    // anything else can. FlutterAppDelegate forwards every
    // UNUserNotificationCenterDelegate call to the registered plugins, and
    // Flutter's own header (FlutterPlugin.h, FlutterAppLifeCycleProvider) says
    // the app must install it for plugins to receive those calls at all; this
    // implicit-engine style of AppDelegate does not do it by itself. Without
    // this line the first plugin to touch the centre took the delegate over:
    // firebase_messaging saw a nil delegate, kept nothing to forward to, and
    // swallowed every response that was not one of its own pushes. A Mark
    // Done / Snooze tap therefore reached the process (UIKit logged the
    // UINotificationResponseAction) and flutter_local_notifications never
    // heard of it. Seen live on 2026-09-06 with the app both closed and
    // alive in the background. With a delegate that conforms to
    // FlutterAppLifeCycleProvider already installed, firebase_messaging
    // explicitly leaves it alone (see its "shouldReplaceDelegate").
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Notification action taps need a moment of background time

  /// A tap on a notification button while the app is closed or in the
  /// background is handled by a headless Flutter engine (see
  /// lib/core/services/notification_action_background.dart), which
  /// flutter_local_notifications starts from this very callback and then
  /// immediately reports the response as handled. iOS takes that report at
  /// its word and suspends the process, and in the traces of 2026-09-06 the
  /// engine's Dart code had not run yet: the tap sat frozen in a suspended
  /// isolate until the app was next opened, minutes or hours later, and was
  /// only then queued, stamped with whatever day it was by then. Holding a
  /// background task open around the forwarded call keeps the process
  /// running for the few seconds the engine needs to start, queue the tap
  /// and stand down the habit's remaining reminders. `super` is
  /// FlutterAppDelegate's implementation, which fans the response out to
  /// every registered plugin.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let app = UIApplication.shared
    var task = UIBackgroundTaskIdentifier.invalid
    let finish: () -> Void = {
      if task != .invalid {
        app.endBackgroundTask(task)
        task = .invalid
      }
    }
    task = app.beginBackgroundTask(withName: "GrowDaily.notificationAction",
                                   expirationHandler: finish)
    super.userNotificationCenter(center, didReceive: response) {
      completionHandler()
      // The plugin calls this the instant it has queued the tap for its
      // engine, not when the engine has finished. Fifteen seconds is
      // generous for a debug-mode JIT start and well inside what iOS grants.
      DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: finish)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Real alarms for reminders (iOS 26+), see AlarmKitBridge.swift and
    // lib/core/services/alarm_service.dart. Same direct-channel shape as the
    // badge below; below iOS 26 the bridge answers unsupported.
    AlarmKitBridge.register(with: engineBridge.applicationRegistrar.messenger())

    // App icon badge — see lib/core/services/app_badge_service.dart. A tiny
    // direct MethodChannel rather than a third-party plugin, since
    // flutter_local_notifications explicitly doesn't offer a "just set the
    // badge to N" call (only a badge riding along with a shown/scheduled
    // notification). setBadgeCount is iOS 16+; applicationIconBadgeNumber
    // is the pre-16 fallback (older, but still works, just soft-deprecated).
    // .messenger is a method inherited from <FlutterBaseRegistrar> (old
    // Objective-C protocol, not a Swift property) — confirmed by the real
    // compiler error this produced without the call parens. Must be called.
    let badgeChannel = FlutterMethodChannel(
      name: "com.growdaily.v2/badge",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    badgeChannel.setMethodCallHandler { call, result in
      guard call.method == "setBadgeCount",
            let args = call.arguments as? [String: Any],
            let count = args["count"] as? Int
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
      } else {
        UIApplication.shared.applicationIconBadgeNumber = count
      }
      result(nil)
    }
  }
}
