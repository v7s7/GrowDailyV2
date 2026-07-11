import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

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
