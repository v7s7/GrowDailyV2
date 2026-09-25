import Flutter
import UIKit

/// The Home Screen icon's native half. See
/// lib/features/app_icon/app_icon_service.dart for the Dart side and
/// lib/features/app_icon/app_icon_catalog.dart for what the names mean.
///
/// Three calls, no state. The alternate icons themselves are the
/// AppIcon-<shape>-<colour> sets under Assets.xcassets/AlternateIcons, which
/// the Runner target's ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS hands
/// to iOS in the built Info.plist; nil is the shipped icon.
///
/// iOS shows its own "You have changed the icon" alert after every change
/// and there is no way to hide it, which is why the app only ever calls
/// `set` from a person's own tap (the App icon page's button, the theme
/// offer's «غيّرها», the plant card's «استخدمها», or a theme they just
/// picked while «مع المظهر» is on), never from a launch or a sync.
enum AppIconBridge {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.growdaily.v2/app_icon",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      let app = UIApplication.shared
      switch call.method {
      case "supported":
        result(app.supportsAlternateIcons)
      case "current":
        result(app.alternateIconName)
      case "set":
        let name = (call.arguments as? [String: Any])?["name"] as? String
        guard app.supportsAlternateIcons else {
          result(FlutterError(code: "unsupported", message: nil, details: nil))
          return
        }
        // Setting the icon it already has still raises the alert, for
        // nothing. Answer as if it changed.
        if app.alternateIconName == name {
          result(true)
          return
        }
        app.setAlternateIconName(name) { error in
          // UIKit calls this on a queue of its own choosing; a Flutter
          // result belongs on the platform thread.
          DispatchQueue.main.async {
            if let error = error {
              NSLog("[GrowDaily] app icon change to %@ failed: %@",
                    name ?? "AppIcon", error.localizedDescription)
              result(FlutterError(code: "failed",
                                  message: error.localizedDescription,
                                  details: nil))
            } else {
              result(true)
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
