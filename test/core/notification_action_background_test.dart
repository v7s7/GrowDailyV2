// The background half of a notification action, run against mocked plugin
// channels (lib/core/services/notification_action_background.dart).
//
// notification_action_queue_test.dart pins the pure rules. This file pins
// the WIRING around them: which App Group keys the handler reads and
// writes, that the queue entry carries the effective day of the tap, that a
// habit finished for the day has every reminder slot cancelled, that a
// counted habit with slices left has none cancelled, and that Snooze
// reschedules through the plugin with the cached name in the app's
// language. None of that can be watched on a simulator from outside the
// process, and a mistake in it loses a tap silently, which is the failure
// this whole path exists to avoid.
//
// It also pins the one rule for the two notes whose numbers a tap here makes
// false (8000 and 9001): each is cleared only while the OS still holds it
// PENDING, because on iOS the plugin's cancel removes a delivered
// notification as well, and a note already delivered was true when it came.
// The mocked channel below therefore keeps a pending set, and a Done tapped
// after the note has gone out must leave it alone.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/notification_action_background.dart';
import 'package:grow_daily_v2/core/services/notification_action_queue.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const widgetChannel = MethodChannel('home_widget');
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');

  /// The App Group store, keyed the way home_widget keys it.
  late Map<String, Object?> store;
  late List<MethodCall> widgetCalls;
  late List<MethodCall> notificationCalls;

  /// What the OS still holds as PENDING, which is the only thing the two
  /// stand-downs here may cancel. A note that has fired is delivered, not
  /// pending, so a test represents delivery by leaving its id out of this.
  late Set<int> pending;

  String todayList(List<Map<String, Object?>> entries) => jsonEncode(entries);

  setUp(() {
    // HomeWidgetService only talks to the store on iOS, which is also the
    // only platform whose actions reach this handler.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // What the app's generated plugin registrant does at start-up and a test
    // process never sees: the plugin facade dispatches to this instance.
    IOSFlutterLocalNotificationsPlugin.registerWith();
    store = <String, Object?>{};
    widgetCalls = <MethodCall>[];
    notificationCalls = <MethodCall>[];
    pending = <int>{};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(widgetChannel, (call) async {
      widgetCalls.add(call);
      final args = call.arguments;
      switch (call.method) {
        case 'setAppGroupId':
          return true;
        case 'saveWidgetData':
          store[(args as Map)['id'] as String] = args['data'];
          return true;
        case 'getWidgetData':
          return store[(args as Map)['id'] as String];
        case 'updateWidget':
          return true;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      notificationCalls.add(call);
      switch (call.method) {
        case 'cancel':
          pending.remove(call.arguments as int);
        case 'pendingNotificationRequests':
          // The shape the plugin's iOS half answers in: one map per request,
          // keyed by the Dart id (see FlutterLocalNotificationsPlugin.m).
          return [
            for (final id in pending)
              {'id': id, 'title': '', 'body': '', 'payload': null},
          ];
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
        timezoneChannel, (call) async => 'Asia/Bahrain');
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(widgetChannel, null);
    messenger.setMockMethodCallHandler(notificationsChannel, null);
    messenger.setMockMethodCallHandler(timezoneChannel, null);
  });

  List<QueuedNotificationAction> queued() =>
      NotificationActionRules.decodeQueue(
          store['pendingNotificationActions'] as String?);

  Iterable<MethodCall> cancels() =>
      notificationCalls.where((c) => c.method == 'cancel');

  // home_widget sends the iOS kind under 'ios'; 'name' is its Android key.
  Iterable<String> widgetsRefreshed() => widgetCalls
      .where((c) => c.method == 'updateWidget')
      .map((c) => (c.arguments as Map)['ios'] as String);

  group('Mark Done', () {
    test('queues the tap on the day it was made, not the day it is read',
        () async {
      store['todayHabitsJson'] = todayList([
        {'id': 'fajr', 'name': 'الفجر', 'done': false, 'count': 0, 'perDay': 1},
      ]);
      // 22:30 on the 6th. The effective day rolls at midnight, so the queue
      // must say the 6th even though the app may only drain it on the 7th.
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'fajr',
        now: DateTime(2026, 9, 6, 22, 30),
      );
      expect(queued(), [
        const QueuedNotificationAction(
            action: 'mark_done', habitId: 'fajr', day: '2026-09-06'),
      ]);
    });

    test('flips the widget cache and redraws both habit widgets', () async {
      store['todayHabitsJson'] = todayList([
        {'id': 'fajr', 'name': 'الفجر', 'done': false, 'count': 0, 'perDay': 1},
        {'id': 'quran', 'name': 'قرآن', 'done': false, 'count': 0, 'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
          actionId: 'mark_done', habitId: 'fajr', now: DateTime(2026, 9, 6));
      final list = jsonDecode(store['todayHabitsJson'] as String) as List;
      expect(list[0]['done'], isTrue);
      expect(list[1]['done'], isFalse);
      expect(widgetsRefreshed(),
          containsAll(['GrowDailyWidget', 'GrowDailyLockScreenWidget']));
    });

    test('stands down every reminder slot of a habit now done for the day',
        () async {
      pending.add(8000);
      store['todayHabitsJson'] = todayList([
        {'id': 'fajr', 'name': 'الفجر', 'done': false, 'count': 0, 'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
          actionId: 'mark_done', habitId: 'fajr', now: DateTime(2026, 9, 6));
      // 12 slots, each with TODAY's reminder id and a snooze id: see
      // NotificationService.standDownHabitReminders. The one other cancel
      // is the evening streak note (8000), pinned in its own tests below.
      final slotCancels = [
        for (final c in cancels())
          if (c.arguments != 8000) c.arguments as int,
      ];
      expect(slotCancels.length, 24);
      final ids = slotCancels.toSet();
      expect(ids.length, 24, reason: 'every slot has its own id');
      expect(ids.every((id) => id >= 5000 && id < 7000), isTrue,
          reason: 'only the habit reminder (5000) and snooze (6000) bands');
      expect(ids.any((id) => id >= 400000), isFalse,
          reason: 'the days AHEAD stay armed — a habit marked done from the '
              'lock screen must not go silent for the rest of the window '
              'when the app is not opened again');
    });

    test('leaves the reminders of a counted habit with slices still owed',
        () async {
      store['todayHabitsJson'] = todayList([
        {'id': 'water', 'name': 'ماء', 'done': false, 'count': 0, 'perDay': 3},
      ]);
      await handleBackgroundNotificationAction(
          actionId: 'mark_done', habitId: 'water', now: DateTime(2026, 9, 6));
      expect(
        cancels(),
        isEmpty,
        reason: 'one of three is not done: the other two reminders stand, '
            'and so does the evening note, which counts whole habits',
      );
      expect(queued().single.habitId, 'water');
      final entry = (jsonDecode(store['todayHabitsJson'] as String) as List)
          .first as Map;
      expect(entry['count'], 1);
      expect(entry['done'], isFalse);
    });

    test('clears the evening streak note while it is still waiting', () async {
      // Armed for 20:30 as «٢ من ٥ خلّصت 👏🏼 سوي عادتين بس، وتصير ٨ أيام.».
      // A habit finished here at 19:40 makes that count false and may earn
      // the point it asks for, and this engine cannot re-word the note.
      pending.add(8000);
      store['todayHabitsJson'] = todayList([
        {'id': 'maghrib', 'name': 'المغرب', 'done': false, 'count': 0, 'perDay': 1},
        {'id': 'isha', 'name': 'العشاء', 'done': false, 'count': 0, 'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'maghrib',
        now: DateTime(2026, 9, 11, 19, 40),
      );
      expect(cancels().where((c) => c.arguments == 8000), hasLength(1));
    });

    test('leaves the evening note alone once it has been delivered', () async {
      // It came at 20:30 and is sitting on the lock screen. A Done at 22:30
      // must not take it off the list: it was true when it came, and the
      // plugin's cancel would remove a delivered notification too.
      store['todayHabitsJson'] = todayList([
        {'id': 'maghrib', 'name': 'المغرب', 'done': false, 'count': 0, 'perDay': 1},
        {'id': 'isha', 'name': 'العشاء', 'done': false, 'count': 0, 'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'maghrib',
        now: DateTime(2026, 9, 11, 22, 30),
      );
      expect(
        cancels().where((c) => c.arguments == 8000),
        isEmpty,
        reason: 'delivered at 20:30, so nothing pending to clear',
      );
      expect(
        queued().single.habitId,
        'maghrib',
        reason: 'the tap itself still counts, whatever the note does',
      );
    });

    test('clears it for a quit habit kept clean and for a last round',
        () async {
      pending.add(8000);
      store['todayHabitsJson'] = todayList([
        {'id': 'coffee', 'name': 'قهوة', 'done': false, 'count': 0, 'perDay': 1},
        {'id': 'water', 'name': 'ماء', 'done': false, 'count': 2, 'perDay': 3},
      ]);
      await handleBackgroundNotificationAction(
        actionId: 'quit_on_track',
        habitId: 'coffee',
        now: DateTime(2026, 9, 11, 19),
      );
      expect(cancels().where((c) => c.arguments == 8000), hasLength(1));

      pending.add(8000);
      notificationCalls.clear();
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'water',
        now: DateTime(2026, 9, 11, 19),
      );
      expect(
        cancels().where((c) => c.arguments == 8000),
        hasLength(1),
        reason: 'the third of three finishes the habit for the day',
      );
    });

    test("clears this Friday's numbered note on a finishing tap before 19:00",
        () async {
      // Armed this morning for 19:00 as «٥ أيام خضرا هذا الأسبوع 👏🏼 والليلة
      // تختم الأسبوع.» under the habit with the most green days. A habit
      // finished here can add a green day or overtake that habit, and this
      // engine has no Grid to count with.
      expect(DateTime(2026, 9, 11).weekday, DateTime.friday);
      for (final (actionId, habitId) in [
        ('mark_done', 'maghrib'),
        ('quit_on_track', 'coffee'),
      ]) {
        notificationCalls.clear();
        pending.addAll({8000, 9001});
        store['todayHabitsJson'] = todayList([
          {'id': 'maghrib', 'name': 'المغرب', 'done': false, 'count': 0, 'perDay': 1},
          {'id': 'coffee', 'name': 'قهوة', 'done': false, 'count': 0, 'perDay': 1},
        ]);
        await handleBackgroundNotificationAction(
          actionId: actionId,
          habitId: habitId,
          now: DateTime(2026, 9, 11, 18, 59),
        );
        expect(
          cancels().where((c) => c.arguments == 9001),
          hasLength(1),
          reason: actionId,
        );
      }
    });

    test('leaves the Friday note from 19:00, on other days, and on a tap '
        'that does not finish the habit', () async {
      for (final now in [
        // Delivered at 19:00: clearing it would take it off the list.
        DateTime(2026, 9, 11, 19),
        DateTime(2026, 9, 11, 22, 30),
        DateTime(2026, 9, 10, 18),
        DateTime(2026, 9, 12, 9),
      ]) {
        notificationCalls.clear();
        // Listed as pending on purpose: what holds 9001 back at these
        // moments is the WINDOW, the note being about today, and not
        // whether the OS still has it.
        pending.addAll({8000, 9001});
        store['todayHabitsJson'] = todayList([
          {'id': 'fajr', 'name': 'الفجر', 'done': false, 'count': 0, 'perDay': 1},
        ]);
        await handleBackgroundNotificationAction(
          actionId: 'mark_done',
          habitId: 'fajr',
          now: now,
        );
        expect(
          cancels().where((c) => c.arguments == 9001),
          isEmpty,
          reason: '$now',
        );
        expect(
          cancels().where((c) => c.arguments == 8000),
          hasLength(1),
          reason: 'the tap still finished the habit at $now',
        );
      }
      notificationCalls.clear();
      store['todayHabitsJson'] = todayList([
        {'id': 'water', 'name': 'ماء', 'done': false, 'count': 0, 'perDay': 3},
      ]);
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'water',
        now: DateTime(2026, 9, 11, 12),
      );
      expect(cancels(), isEmpty, reason: 'one of three turns no square green');
    });

    test('inside the window, a note that was never armed is not cancelled',
        () async {
      // A Friday whose week was not worth numbering: the claim-free repeat
      // (9000) is armed and 9001 never existed, so a finishing tap at 18:40
      // has nothing of the note's to stand down. Neither stand-down may
      // reach for an id it does not own.
      expect(DateTime(2026, 9, 11).weekday, DateTime.friday);
      pending.addAll({9000, 9002});
      store['todayHabitsJson'] = todayList([
        {'id': 'fajr', 'name': 'الفجر', 'done': false, 'count': 0, 'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'fajr',
        now: DateTime(2026, 9, 11, 18, 40),
      );
      final touched = [
        for (final c in cancels())
          if ((c.arguments as int) >= 8000) c.arguments as int,
      ];
      expect(touched, isEmpty, reason: '$touched');
      expect(pending, {9000, 9002});
    });

    test('the Friday window is the one weeklyNotePlan arms the note in', () {
      const top = (name: 'قراءة القرآن', greenDays: 5, isQuit: false);
      for (final now in [
        DateTime(2026, 9, 11),
        DateTime(2026, 9, 11, 18, 59, 59),
        DateTime(2026, 9, 11, 19),
        DateTime(2026, 9, 11, 23, 59),
        DateTime(2026, 9, 10, 18),
        DateTime(2026, 9, 12, 9),
      ]) {
        final arms = NotificationService.weeklyNotePlan(
          now: now,
          topHabit: top,
          longestStreak: 14,
          isAr: true,
        ).arm.any((s) => s.id == 9001);
        expect(
          NotificationService.weeklyNumberedNoteAhead(now),
          arms,
          reason: '$now',
        );
      }
    });

    test('still queues a habit the widget cache does not know', () async {
      store['todayHabitsJson'] = todayList([]);
      await handleBackgroundNotificationAction(
          actionId: 'mark_done', habitId: 'ghost', now: DateTime(2026, 9, 6));
      expect(queued().single.habitId, 'ghost',
          reason: 'the app decides what the id means; the cache is only a '
              'picture of today');
    });

    test('appends behind taps already waiting', () async {
      store['pendingNotificationActions'] = NotificationActionRules.encodeQueue(
        [
          const QueuedNotificationAction(
              action: 'mark_done', habitId: 'earlier', day: '2026-09-05'),
        ],
      );
      await handleBackgroundNotificationAction(
          actionId: 'quit_on_track', habitId: 'coffee', now: DateTime(2026, 9, 6));
      expect(queued().map((e) => e.habitId), ['earlier', 'coffee']);
      expect(queued().last.action, 'quit_on_track');
    });
  });

  group('Slipped', () {
    test('queues the answer and touches nothing else', () async {
      store['todayHabitsJson'] = todayList([
        {'id': 'coffee', 'name': 'قهوة', 'done': false, 'count': 0, 'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
          actionId: 'quit_slipped', habitId: 'coffee', now: DateTime(2026, 9, 6));
      expect(queued().single,
          const QueuedNotificationAction(
              action: 'quit_slipped', habitId: 'coffee', day: '2026-09-06'));
      final entry = (jsonDecode(store['todayHabitsJson'] as String) as List)
          .first as Map;
      expect(entry['done'], isFalse, reason: 'a slip is not a completion');
      expect(cancels(), isEmpty);
      expect(widgetsRefreshed(), isEmpty);
    });
  });

  group('ignored input', () {
    test('an empty action or habit does nothing at all', () async {
      await handleBackgroundNotificationAction(actionId: '', habitId: 'x');
      await handleBackgroundNotificationAction(actionId: 'mark_done', habitId: '');
      expect(widgetCalls, isEmpty);
      expect(notificationCalls, isEmpty);
    });

    test('an unknown action id is not queued', () async {
      await handleBackgroundNotificationAction(
          actionId: 'something_new', habitId: 'x', now: DateTime(2026, 9, 6));
      expect(queued(), isEmpty);
    });
  });

  group('Snooze', () {
    // Last, and alone in its group: it is the one action that initialises
    // NotificationService's plugin, and that singleton keeps its state for
    // the rest of the process.
    test('reschedules in an hour under the cached name, in the app language',
        () async {
      store['localeIsAr'] = true;
      store['todayHabitsJson'] = todayList([
        {'id': 'fajr', 'name': 'صلاة الفجر', 'done': false, 'count': 0,
          'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
          actionId: 'snooze_1h', habitId: 'fajr', now: DateTime(2026, 9, 6));

      expect(queued(), isEmpty, reason: 'a snooze acts now, nothing to drain');

      final init = notificationCalls.firstWhere((c) => c.method == 'initialize');
      final categories =
          (init.arguments as Map)['notificationCategories'] as List;
      final titles = [
        for (final c in categories)
          for (final a in (c as Map)['actions'] as List) (a as Map)['title'],
      ];
      expect(titles, containsAll(['تمت', 'تأجيل ساعة', 'التزام', 'زلة']),
          reason: 'the first registration in this engine is already Arabic');
      final options = [
        for (final c in categories)
          for (final a in (c as Map)['actions'] as List)
            (a as Map)['options'] as List,
      ];
      expect(options.every((o) => o.isEmpty), isTrue,
          reason: 'no foreground option, or the watch hides the button');

      final scheduled =
          notificationCalls.firstWhere((c) => c.method == 'zonedSchedule');
      final args = scheduled.arguments as Map;
      expect(args['title'], 'صلاة الفجر');
      expect(args['body'], 'صار لها ساعة من التأجيل.');
      expect(args['payload'], 'fajr');
      expect(args['id'], 6000 + 'fajr'.hashCode.abs() % 1000,
          reason: 'the snooze band, so it does not clobber the reminder');
      expect((args['platformSpecifics'] as Map)['categoryIdentifier'],
          'habitReminderCategory');
    });
  });
}
