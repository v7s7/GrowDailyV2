import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../extensions/datetime_ext.dart';
import 'local_store_service.dart';

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

  /// The streak Lock Screen widget's own kind string — must exactly match
  /// `struct GrowDailyLockScreenWidget: Widget` in GrowDailyWidget.swift.
  /// Reloaded alongside [_iOSWidgetName] itself since both read the same
  /// data this method writes; without this explicit second call the Lock
  /// Screen face would only pick up a change on its own hourly fallback
  /// timeline instead of within moments, same reasoning as
  /// [_iOSRoomRaceLockScreenWidgetName] below.
  static const _iOSLockScreenWidgetName = 'GrowDailyLockScreenWidget';

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
        jsonEncode(recentHeatmap(dailyGreenCounts)),
      );
      await HomeWidget.updateWidget(iOSName: _iOSWidgetName);
      await HomeWidget.updateWidget(iOSName: _iOSLockScreenWidgetName);
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
  /// reads, just windowed to what a widget has room to draw. [now] defaults
  /// to the real current time; overridable (and this promoted to a public,
  /// `@visibleForTesting` static method rather than staying a private
  /// instance method) purely so a test can pin down a fixed instant instead
  /// of the windowing math depending on whatever day the suite happens to
  /// run — the [effectiveDay] cutoff it goes through means a test running
  /// between midnight and [kDayCutoffHour] would otherwise silently land on
  /// a different calendar day than one running any other time.
  @visibleForTesting
  static List<Map<String, Object?>> recentHeatmap(
    Map<String, int> dailyGreenCounts, {
    DateTime? now,
  }) {
    final today = (now ?? DateTime.now()).effectiveDay;
    return List.generate(28, (i) {
      final day = today.subtract(Duration(days: 27 - i));
      return {'date': day.toDateKey(), 'count': dailyGreenCounts[day.toDateKey()] ?? 0};
    });
  }

  /// Name of the Room Race widget's SwiftUI provider struct — must exactly
  /// match `struct GrowDailyRoomRaceWidget: Widget` in GrowDailyWidget.swift,
  /// same convention as [_iOSWidgetName] above.
  static const _iOSRoomRaceWidgetName = 'GrowDailyRoomRaceWidget';

  /// The Room Race Lock Screen widget's own kind string — must exactly
  /// match `struct GrowDailyRoomRaceLockScreenWidget: Widget` in
  /// GrowDailyWidget.swift. Shares [RoomRaceEntry]/roomRaceJson with
  /// [_iOSRoomRaceWidgetName] (same provider, just a smaller accessory-
  /// family view - see that Swift file's "Room Race Lock Screen widgets"
  /// section), so it needs its own explicit reload here too, same
  /// reasoning as [_iOSLockScreenWidgetName] above.
  static const _iOSRoomRaceLockScreenWidgetName =
      'GrowDailyRoomRaceLockScreenWidget';

  /// Pushes the widget's Room Race face and asks iOS to redraw it — both
  /// the Home Screen size and the Lock Screen size, which share the same
  /// pushed data. See rooms_notifier.dart's `myRoomRaceSnapshotProvider`
  /// for how "the one room" to show and its ranking get computed (starred
  /// rooms win first, see that provider's doc comment) — this only ever
  /// writes the already-finished result, same division of labor as
  /// [updateWidgetData] (today's habits/heatmap computed elsewhere,
  /// this just serializes and pushes).
  ///
  /// Takes plain primitives/records rather than RoomRaceSnapshot/
  /// RoomRaceRow directly, on purpose — this file has no other dependency
  /// on the rooms feature's model classes, and staying that way means a
  /// change to Rooms' internals can never silently break widget syncing
  /// through an import neither file's own tests would think to check.
  ///
  /// Call with `hasRoom: false` (the rest of the arguments default to
  /// empty) whenever [myRoomRaceSnapshotProvider] is null — leaving a
  /// room, or every room this account is in ending, needs to actively
  /// clear the widget's race face back to its own placeholder, not leave
  /// the last real snapshot frozen there forever.
  Future<void> updateRoomRaceData({
    required bool hasRoom,
    String roomName = '',
    bool isLive = false,
    int daysRemaining = 0,
    List<
            ({
              String name,
              int rank,
              int percent,
              bool isMe,
              String uid,
              int daysDone,
              int daysTotal,
              List<int> heatmap
            })>
        rows = const [],
  }) async {
    if (kIsWeb) return;
    try {
      await HomeWidget.saveWidgetData<String>(
        'roomRaceJson',
        jsonEncode({
          'hasRoom': hasRoom,
          'roomName': roomName,
          'isLive': isLive,
          'daysRemaining': daysRemaining,
          'rows': rows
              .map((r) => {
                    'name': r.name,
                    'rank': r.rank,
                    'percent': r.percent,
                    'isMe': r.isMe,
                    'uid': r.uid,
                    'daysDone': r.daysDone,
                    'daysTotal': r.daysTotal,
                    'heatmap': r.heatmap,
                  })
              .toList(),
        }),
      );
      await HomeWidget.updateWidget(iOSName: _iOSRoomRaceWidgetName);
      await HomeWidget.updateWidget(iOSName: _iOSRoomRaceLockScreenWidgetName);
    } catch (e) {
      // Same reasoning as updateWidgetData's catch — silently no-ops until
      // the widget target/this widget kind exists, never worth crashing
      // the app over.
      debugPrint('[HomeWidgetService] room-race update skipped: $e');
    }
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
      return await _takeQueue(_pendingKey);
    } catch (e) {
      debugPrint('[HomeWidgetService] pending-completions read skipped: $e');
      return const [];
    }
  }

  /// Serializes every queue take behind one future chain.
  ///
  /// The take is a get-then-clear across two platform-channel awaits, so
  /// two CONCURRENT takes both read the same non-empty queue before either
  /// writes the clear — and both hand the same ids to their drain. That is
  /// not theoretical: the cold-start drain now waits on auth + data
  /// readiness (see main.dart's _processPendingWidgetCompletions), and an
  /// app-resume during that window starts a second drain that blocks on
  /// the SAME provider emissions, so the two enter here in back-to-back
  /// microtasks. A single-tap habit survives that (completeHabit refuses a
  /// same-day repeat), but a counted habit credits a second slice for one
  /// physical widget tap. Chaining means the second take runs after the
  /// first's clear has landed, reads '[]', and returns empty — which is
  /// what the doc comments above have always promised.
  Future<void> _takeChain = Future.value();

  Future<List<String>> _takeQueue(String key) {
    final result = _takeChain.then((_) async {
      final raw = await HomeWidget.getWidgetData<String>(key);
      if (raw == null || raw.isEmpty) return const <String>[];
      await HomeWidget.saveWidgetData<String>(key, '[]');
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return decoded.whereType<String>().toList();
    });
    // The chain must survive a failed take, or one platform-channel error
    // would wedge every future take behind a rejected future.
    _takeChain = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Name of the Matrix widget's SwiftUI provider struct — must exactly
  /// match `struct GrowDailyMatrixWidget: Widget` in GrowDailyWidget.swift,
  /// same convention as [_iOSWidgetName]/[_iOSRoomRaceWidgetName] above.
  static const _iOSMatrixWidgetName = 'GrowDailyMatrixWidget';

  /// The starred-task Lock Screen widget's own kind string — must exactly
  /// match `struct GrowDailyMatrixLockScreenWidget: Widget` in
  /// GrowDailyWidget.swift. Shares `matrixTasksJson` with
  /// [_iOSMatrixWidgetName] (same provider, reads the same list and just
  /// picks out the highest-priority starred one — see that Swift file's
  /// "Matrix Lock Screen widget" section), so it needs its own explicit
  /// reload here too, same reasoning as [_iOSLockScreenWidgetName] above.
  static const _iOSMatrixLockScreenWidgetName = 'GrowDailyMatrixLockScreenWidget';

  static const _pendingTaskKey = 'pendingWidgetTaskCompletions';

  /// Pushes the Matrix widget's task list and asks iOS to redraw it. Takes
  /// every *open* task the caller wants considered, already sorted
  /// caller-side (main.dart sorts by quadrant priority — Do First first,
  /// Eliminate last — then by each task's own board order, mirroring the
  /// in-app quadrant ordering); this just serializes and pushes, same
  /// division of labor as [updateWidgetData] with today's habits. Not
  /// capped here — same reasoning as the habit list: the Swift side decides
  /// how many rows a given widget size actually has room for
  /// (GrowDailyLargeView's `.prefix(5)` and its own "+N more" line), so
  /// this stays the one source both today's Home Screen widget size and any
  /// future larger size can read from without Dart needing to know about
  /// per-size row limits.
  ///
  /// [isFav] mirrors [MatrixTask.isFav] (the gold star toggle on the Tasks
  /// screen) — added so the Lock Screen starred-task widget
  /// (GrowDailyMatrixLockScreenWidget in GrowDailyWidget.swift) has
  /// something to pick out from this same list without a second write path;
  /// the Home Screen Matrix widget ignores it today (no star shown there
  /// yet), but every task still carries it since both widgets read this one
  /// shared `matrixTasksJson` blob.
  ///
  /// [isLate] mirrors the exact same "overdue" definition MatrixNotifier
  /// already uses to decide whether a missed reminder still needs to fire
  /// (a reminder set, in the past, task still open) — see
  /// `latestMissedTaskReminder` in matrix_notifier.dart. Reused here rather
  /// than inventing a second definition, and computed caller-side
  /// (main.dart) since that's the only place this list already touches
  /// `DateTime.now()`. Tasks with no reminder set are never late — there's
  /// nothing to be late against, and a task whose stack is only partly
  /// elapsed isn't late either until its *last* reminder has passed.
  Future<void> updateMatrixWidgetData(
    List<
            ({
              String id,
              String title,
              String quadrant,
              bool isDone,
              bool isFav,
              bool isLate,
            })>
        tasks, {
    // Written as its own key rather than folded into the list: every list
    // face on the Swift side assumes matrixTasksJson is open-only, and the
    // lock-screen ring needs completed-today to fill at all — see
    // MatrixEntry.doneToday in GrowDailyWidget.swift.
    required int doneTodayCount,
  }) async {
    if (kIsWeb) return;
    try {
      await HomeWidget.saveWidgetData<int>(
        'matrixDoneTodayCount',
        doneTodayCount,
      );
      // The count's calendar day. Without it the widget kept yesterday's
      // done count in today's denominator until the app next foregrounded;
      // the Swift side treats a stale stamp as zero, and its hourly
      // timeline refresh picks that up shortly after midnight on its own.
      await HomeWidget.saveWidgetData<String>(
        'matrixDoneTodayDate',
        LocalStoreService.dateKey(DateTime.now()),
      );
      await HomeWidget.saveWidgetData<String>(
        'matrixTasksJson',
        jsonEncode(tasks
            .map((t) => {
                  'id': t.id,
                  'title': t.title,
                  'quadrant': t.quadrant,
                  'isDone': t.isDone,
                  'isFav': t.isFav,
                  'isLate': t.isLate,
                })
            .toList()),
      );
      await HomeWidget.updateWidget(iOSName: _iOSMatrixWidgetName);
      await HomeWidget.updateWidget(iOSName: _iOSMatrixLockScreenWidgetName);
    } catch (e) {
      // Same reasoning as updateWidgetData's catch — silently no-ops until
      // the widget target/this widget kind exists, never worth crashing
      // the app over.
      debugPrint('[HomeWidgetService] matrix update skipped: $e');
    }
  }

  /// Task ids the Matrix widget's checkmark queued while the app wasn't
  /// open — see MarkTaskDoneIntent in GrowDailyWidget.swift. Exact same
  /// provisional-now/real-reward-on-next-open split as
  /// [takePendingCompletions], just for Matrix tasks instead of habits: the
  /// widget's AppIntent already flips its own cached copy so the row shows
  /// checked immediately, and this queue is what main.dart drains through
  /// the real MatrixNotifier.toggle path (XP bonus included) once the app
  /// is actually open. Clears the queue as it reads it, same double-credit
  /// guard as the habit version.
  Future<List<String>> takePendingTaskCompletions() async {
    if (kIsWeb) return const [];
    try {
      return await _takeQueue(_pendingTaskKey);
    } catch (e) {
      debugPrint(
          '[HomeWidgetService] pending-task-completions read skipped: $e');
      return const [];
    }
  }
}
