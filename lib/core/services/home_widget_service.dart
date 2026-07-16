import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../extensions/datetime_ext.dart';

/// Dart-side bridge to the iOS home screen + Lock Screen widgets. This is
/// only half the feature — home_widget explicitly does not let Flutter draw
/// the widget itself, so the actual on-screen widget is native Swift, added
/// once the Xcode Widget Extension target exists. See ios/WIDGET_SETUP.md
/// for that half. This class just keeps the shared App Group data current
/// so the widget has something real to show whenever iOS asks it to redraw,
/// and drains whatever the widget's Mark Done button queued while the app
/// wasn't open.
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

  static const _pendingKey = 'pendingWidgetCompletions';

  Future<void> init() async {
    if (kIsWeb) return;
    await HomeWidget.setAppGroupId(_appGroupId);
  }

  /// Pushes everything the widgets show and asks iOS to redraw them. Safe to
  /// call often — cheap local writes, no network. Called from main.dart via
  /// ref.listenManual on dashboardProvider/habitListProvider, same pattern
  /// as the notification wiring, so it's always current from cold start
  /// onward.
  ///
  /// [todayHabits] is today's scheduled habits with their current
  /// done-state — the large widget renders these as tappable rows (see the
  /// AppIntent in WIDGET_SETUP.md), so this needs real ids/names, not just
  /// a count. [dailyGreenCounts] is DashboardState.dailyGreenCounts as-is —
  /// the same rollup the Monthly Heatmap screen reads — windowed here to
  /// the last 28 days for the widget's mini heatmap.
  Future<void> updateWidgetData({
    required int streak,
    required int level,
    required int gold,
    required int completedToday,
    required int totalToday,
    required List<({String id, String name, bool done})> todayHabits,
    required Map<String, int> dailyGreenCounts,
  }) async {
    if (kIsWeb) return;
    try {
      await HomeWidget.saveWidgetData<int>('streak', streak);
      await HomeWidget.saveWidgetData<int>('level', level);
      await HomeWidget.saveWidgetData<int>('gold', gold);
      await HomeWidget.saveWidgetData<int>('completedToday', completedToday);
      await HomeWidget.saveWidgetData<int>('totalToday', totalToday);
      await HomeWidget.saveWidgetData<String>(
        'todayHabitsJson',
        jsonEncode(todayHabits
            .map((h) => {'id': h.id, 'name': h.name, 'done': h.done})
            .toList()),
      );
      await HomeWidget.saveWidgetData<String>(
        'heatmapJson',
        jsonEncode(_recentHeatmap(dailyGreenCounts)),
      );
      await HomeWidget.updateWidget(iOSName: _iOSWidgetName);
    } catch (e) {
      // Silently no-ops until the Xcode widget target exists (or on
      // Android/web, where this plugin call isn't wired up here at all —
      // see WIDGET_SETUP.md, iOS-only for now). Never worth crashing the
      // app over a home screen widget failing to redraw.
      debugPrint('[HomeWidgetService] update skipped: $e');
    }
  }

  /// Last 28 days of [dailyGreenCounts], oldest first, as plain
  /// JSON-friendly maps — same underlying data the Monthly Heatmap screen
  /// reads, just windowed to what a widget has room to draw.
  List<Map<String, Object?>> _recentHeatmap(Map<String, int> dailyGreenCounts) {
    final today = DateTime.now().effectiveDay;
    return List.generate(28, (i) {
      final day = today.subtract(Duration(days: 27 - i));
      return {'date': day.toDateKey(), 'count': dailyGreenCounts[day.toDateKey()] ?? 0};
    });
  }

  /// Habit ids the widget's Mark Done button queued while the app wasn't
  /// open to actually process them — see the AppIntent in WIDGET_SETUP.md.
  /// The widget shows a tapped habit as done immediately (its AppIntent
  /// flips the cached `todayHabitsJson` entry itself, before this queue is
  /// ever read), but the real XP/streak/gold reward only posts once the app
  /// drains this queue through the normal completeHabit path — see
  /// main.dart's app-resume handling. Clears the queue as it reads it, so a
  /// habit can't get double-credited if this runs twice.
  Future<List<String>> takePendingCompletions() async {
    if (kIsWeb) return const [];
    try {
      final raw = await HomeWidget.getWidgetData<String>(_pendingKey);
      if (raw == null || raw.isEmpty) return const [];
      await HomeWidget.saveWidgetData<String>(_pendingKey, '[]');
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList();
    } catch (e) {
      debugPrint('[HomeWidgetService] pending-completions read skipped: $e');
      return const [];
    }
  }
}
