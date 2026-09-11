// The background half of a notification action tap.
//
// Every action button under a habit reminder or quit check-in used to be a
// FOREGROUND action: the tap opened the app, and main.dart's
// _handleNotificationAction ran the completion through the live provider
// tree. That guaranteed the real reward logic ran, and it had one cost that
// only showed on a wrist: a paired Apple Watch hides foreground actions when
// the iOS app has no watch app, because there is nothing on the watch to
// bring forward. So the buttons existed on the phone and were simply absent
// on the watch, where the reminder showed only Dismiss. (The watch simulator
// still draws them, which is how this went unnoticed.)
//
// A BACKGROUND action is shown on both devices and, wherever it is tapped,
// is delivered to the iPhone app without opening it. flutter_local_
// notifications handles that by starting a second, headless Flutter engine
// and calling [notificationActionBackground] in it. That engine has none of
// the app's state: no Riverpod tree, no Firebase, no habit list. So it does
// not try to complete the habit itself. It does the things that can be done
// correctly with nothing but the shared App Group store:
//
//  1. Records the tap in a queue the app drains on its next open, through
//     the exact _handleNotificationAction path a foreground tap always used
//     (see main.dart's _processPendingNotificationActions). The reward, the
//     square and the room sync are therefore never computed here, and every
//     queued tap carries the effective day it was made on so a drain the
//     next morning credits the right evening.
//  2. Makes the tap visible immediately where it can be: the widget's cached
//     today-list flips to done and the widgets redraw, and a habit that is
//     now done for the day has its remaining reminder slots stood down so it
//     is not nagged about again before the app opens.
//  3. Snooze is the exception that must act now, because "in an hour" cannot
//     wait for an app open; it reschedules through the same
//     NotificationService call the foreground path used.
//
// This is the same provisional-now, real-reward-on-next-open split the home
// screen widget's Mark Done button has always used (MarkHabitDoneIntent in
// GrowDailyWidget.swift). The pure rules are in notification_action_queue.dart
// so they can be tested without a platform channel.
//
// Two things in ios/Runner/AppDelegate.swift are load-bearing for any of this
// to run, both found by watching the simulator's log on 2026-09-06: the app
// delegate must be the notification centre's delegate (or firebase_messaging
// takes it over and swallows every response that is not its own push, so the
// plugin never hears of the tap), and a background task must be held open
// around the response (or iOS suspends the process the instant the plugin
// reports the tap handled, before this engine has had any CPU time, and the
// tap only runs at the next app open, stamped with that day).
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../extensions/datetime_ext.dart';
import 'home_widget_service.dart';
import 'notification_action_queue.dart';
import 'notification_service.dart';

/// Entry point flutter_local_notifications runs in its headless engine when
/// an action button is tapped and the action does not open the app. Top
/// level and marked as an entry point because the plugin reaches it through
/// a raw callback handle rather than a Dart reference, so tree shaking would
/// otherwise drop it from a release build. Registered by
/// NotificationService.init; the native half needs
/// FlutterLocalNotificationsPlugin.setPluginRegistrantCallback in
/// AppDelegate.swift, or this engine has no plugin channels to talk to.
@pragma('vm:entry-point')
Future<void> notificationActionBackground(
    NotificationResponse response) async {
  debugPrint('[NotificationAction] background engine got '
      '${response.actionId} for ${response.payload}');
  try {
    await handleBackgroundNotificationAction(
      actionId: response.actionId ?? '',
      habitId: response.payload ?? '',
    );
  } catch (e, st) {
    // Nothing here is worth crashing a headless engine over, and there is
    // no UI to show. A print is the one trace this engine can leave.
    debugPrint('[NotificationAction] background tap failed: $e\n$st');
  }
}

/// The engine's work for one tap, split from the entry point so it can be
/// called with a clock. See the file comment for what it does and does not
/// take on.
Future<void> handleBackgroundNotificationAction({
  required String actionId,
  required String habitId,
  DateTime? now,
}) async {
  // A body tap has no action id and opens the app on its own; a bundled
  // "N habits ready" ping has no habit. Neither reaches here in practice,
  // and neither has anything to queue if it did.
  if (actionId.isEmpty || habitId.isEmpty) return;

  final widgets = HomeWidgetService.instance;
  await widgets.init();
  final todayList = await widgets.readTodayHabitsJson();
  final clock = now ?? DateTime.now();
  final day = clock.effectiveDay.toDateKey();

  switch (actionId) {
    case NotificationService.actionSnooze:
      // The title comes from the widget cache because this engine has no
      // habit list; the app's own name stands in when the cache has moved
      // on. applyLocale rather than init: this engine's first registration
      // must be in the app's language, or the buttons under the snoozed
      // reminder come back in English for an Arabic user.
      final isAr = await widgets.readLocaleIsAr();
      await NotificationService.instance.applyLocale(isAr);
      final name = NotificationActionRules.habitName(todayList, habitId) ??
          'Grow Daily';
      await NotificationService.instance
          .snoozeHabitReminder(habitId, name, isAr: isAr);
      return;

    case NotificationService.actionMarkDone:
    case NotificationService.actionStayedClean:
      // Decided BEFORE the cache is rewritten, since the rewrite bumps the
      // count this reads. The queue write goes first of all: it is the one
      // step that must land for the tap to count.
      final finishes = NotificationActionRules.finishesDay(todayList, habitId);
      await widgets.queueNotificationAction(QueuedNotificationAction(
        action: actionId,
        habitId: habitId,
        day: day,
      ));
      debugPrint('[NotificationAction] queued $actionId for $habitId on $day');
      final rewritten = NotificationActionRules.markOneDone(todayList, habitId);
      if (rewritten != null) await widgets.writeTodayHabitsJson(rewritten);
      if (finishes) {
        await NotificationService.instance.standDownHabitReminders(habitId);
        // Tonight's evening streak note counts today's finished habits and
        // asks for the rest («٢ من ٥ خلّصت 👏🏼 سوي عادتين بس، وتصير ٨
        // أيام.»), so a habit finished here makes both numbers false and may
        // earn the very point the note asks for. This engine cannot re-word
        // it: it has no streak settings, no urgent task count and no goal
        // types. So the note is cleared, and the next app open arms it again
        // with true counts if the streak still needs anything. A tap that
        // does not finish the habit leaves the note true, because it counts
        // whole habits.
        await NotificationService.instance.standDownEveningStreakNote();
        // This Friday's numbered note («٥ أيام خضرا هذا الأسبوع 👏🏼») counts
        // the week's green days and names the habit with the most. Before
        // 19:00 a habit finished here can add a green day or overtake that
        // habit, so it is cleared for the same reason, and the next app open
        // before 19:00 arms it again with the true count. From 19:00 it has
        // been delivered, and is left where it is.
        if (NotificationService.weeklyNumberedNoteAhead(clock)) {
          await NotificationService.instance.standDownWeeklyNumberedNote();
        }
        // Both stand-downs clear a note only while it is still PENDING, the
        // one rule every path here follows: a note already delivered was
        // true when it came and stays in the notification list. A Done
        // tapped at 22:30 therefore leaves tonight's 20:30 note alone, and
        // it takes a pending read to get that, because the plugin's cancel
        // removes a delivered notification too on iOS (see
        // NotificationService._cancelIfPending).
        //
        // The home screen widget's Done never reaches this engine, so it does
        // the same in Swift, pending requests only: MarkHabitDoneIntent, by
        // this same whole-habit rule, removes the pending 8000 and, on a
        // Friday before 19:00, 9001; MarkTaskDoneIntent removes 8000 when it
        // ticks an open Do First task, which the note's urgent tasks sentence
        // counts. See standDownNotesWithStaleCounts in GrowDailyWidget.swift.
        // Apple documents the notification center for app extensions, but
        // that removal has not been seen working on a device.
        //
        // One path does NOT clear these notes yet: a task finished from its
        // ringing alarm's Done button, which runs in the app's own process
        // and only queues the completion (AlarmDoneQueue.record in
        // AlarmKitBridge.swift). A Do First task ticked there leaves «وعندك
        // مهمة عاجلة وحدة.» in tonight's note until the app is opened.
        // Habit alarms carry Stop alone (Aziz, 2026-09-11), so only the task
        // alarm is affected, and that alarm work is uncommitted in another
        // branch: the removal belongs with it, not here.
        //
        // Habit reminders already armed cannot be re-worded from here or from
        // the widget, for the same reason. Until the app opens, a copy armed
        // for a later day can still say «بسم الله، أول مربع لها.» about a
        // habit first done here, and a habit done several times a day keeps
        // the round and the count it was armed with («وقت المرة الثانية.
        // سويها الحين. ١ من ٣ خلّصت 👏🏼») after a round is ticked here
        // without finishing the day.
      }
      await widgets.refreshHabitWidgets();
      return;

    case NotificationService.actionSlipped:
      // Nothing to show meanwhile: the widget has no red state, and the
      // check-in that was answered is gone from the shade already.
      await widgets.queueNotificationAction(QueuedNotificationAction(
        action: actionId,
        habitId: habitId,
        day: day,
      ));
      debugPrint('[NotificationAction] queued $actionId for $habitId on $day');
      return;

    default:
      return;
  }
}
