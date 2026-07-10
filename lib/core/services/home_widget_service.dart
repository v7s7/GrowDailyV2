import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Dart-side bridge to the iOS home screen widget. This is only half the
/// feature — home_widget explicitly does not let Flutter draw the widget
/// itself, so the actual on-screen widget is native Swift, added once the
/// Xcode Widget Extension target exists. See ios/WIDGET_SETUP.md for that
/// half. This class just keeps the shared App Group data current so the
/// widget has something real to show whenever iOS asks it to redraw.
class HomeWidgetService {
  HomeWidgetService._();
  static final instance = HomeWidgetService._();

  /// Must exactly match the App Group ID entered in Xcode for both the
  /// Runner and widget extension targets' Signing & Capabilities — see
  /// step 3 in ios/WIDGET_SETUP.md. Bundle id is com.growdaily.v2, so this
  /// follows Apple's group.<bundle-id> convention.
  static const _appGroupId = 'group.com.growdaily.v2.widget';

  /// Name of the widget's SwiftUI provider struct — must exactly match the
  /// struct name used in `struct GrowDailyWidget: Widget` in the Swift file
  /// from ios/WIDGET_SETUP.md, or updateWidget silently no-ops.
  static const _iOSWidgetName = 'GrowDailyWidget';

  Future<void> init() async {
    if (kIsWeb) return;
    await HomeWidget.setAppGroupId(_appGroupId);
  }

  /// Pushes the numbers the widget shows and asks iOS to redraw it. Safe to
  /// call often — cheap local writes, no network. Called from main.dart
  /// via ref.listenManual on dashboardProvider, same pattern as the
  /// notification wiring, so it's always current from cold start onward.
  Future<void> updateWidgetData({
    required int streak,
    required int level,
    required int gold,
  }) async {
    if (kIsWeb) return;
    try {
      await HomeWidget.saveWidgetData<int>('streak', streak);
      await HomeWidget.saveWidgetData<int>('level', level);
      await HomeWidget.saveWidgetData<int>('gold', gold);
      await HomeWidget.updateWidget(iOSName: _iOSWidgetName);
    } catch (e) {
      // Silently no-ops until the Xcode widget target exists (or on
      // Android/web, where this plugin call isn't wired up here at all —
      // see WIDGET_SETUP.md, iOS-only for now). Never worth crashing the
      // app over a home screen widget failing to redraw.
      debugPrint('[HomeWidgetService] update skipped: $e');
    }
  }
}
