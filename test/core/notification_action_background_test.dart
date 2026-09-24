// The background half of a notification action, run against mocked plugin
// channels (lib/core/services/notification_action_background.dart).
//
// notification_action_queue_test.dart pins the pure rules. This file pins
// the WIRING around them: which App Group keys the handler reads and
// writes, that the queue entry carries the effective day of the tap, that a
// habit finished for the day has that day's reminders taken down by the ids
// the last reminder pass recorded for it (armed_reminder_record_test.dart
// pins the record itself), and nothing of the days after, that a counted
// habit with slices left has none cancelled, and that Snooze reschedules
// through the plugin with the cached name in the app's language. None of
// that can be watched on a simulator from outside the process, and a
// mistake in it loses a tap silently, which is the failure this whole path
// exists to avoid.
//
// It also pins the one rule for the two notes whose numbers a tap here makes
// false (1010 and 9001): each is cleared only while the OS still holds it
// PENDING, because on iOS the plugin's cancel removes a delivered
// notification as well, and a note already delivered was true when it came.
// The mocked channel below therefore keeps a pending set, and a Done tapped
// after the note has gone out must leave it alone.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/armed_reminder_record.dart';
import 'package:grow_daily_v2/core/services/notification_action_background.dart';
import 'package:grow_daily_v2/core/services/notification_action_queue.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const widgetChannel = MethodChannel('home_widget');
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');
  // AppDelegate registers the alarm channel on this engine too, so a Done
  // tapped here can take the day's alarms down with the notifications.
  const alarmChannel = MethodChannel('com.growdaily.v2/alarm');

  /// The App Group store, keyed the way home_widget keys it.
  late Map<String, Object?> store;
  late List<MethodCall> widgetCalls;
  late List<MethodCall> notificationCalls;
  late List<MethodCall> alarmCalls;

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
    alarmCalls = <MethodCall>[];
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
    // iOS 26, where alarms exist. AlarmService caches the answer for the
    // process, so it is mocked for every test, not only the alarm ones.
    messenger.setMockMethodCallHandler(alarmChannel, (call) async {
      if (call.method == 'isSupported') return true;
      alarmCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(widgetChannel, null);
    messenger.setMockMethodCallHandler(notificationsChannel, null);
    messenger.setMockMethodCallHandler(timezoneChannel, null);
    messenger.setMockMethodCallHandler(alarmChannel, null);
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

  Iterable<int> alarmsCancelled() => alarmCalls
      .where((c) => c.method == 'cancel')
      .map((c) => (c.arguments as Map)['id'] as int);

  // The ids NotificationService arms a habit's copies under
  // (_habitReminderId): the next occurrence of a slot in the 5000 band, the
  // ones after it in the 400000 bands, and a snooze in the 6000 band.
  int nextCopy(String habit, [int slot = 0]) =>
      5000 + NotificationService.reminderSlotOffset(habit, slot);
  int laterCopy(String habit, int depth, [int slot = 0]) =>
      400000 +
      (depth - 1) * 1000 +
      NotificationService.reminderSlotOffset(habit, slot);
  int snoozeOf(String habit) =>
      6000 + NotificationService.reminderSlotOffset(habit, 0);

  /// What the last reminder pass left in the App Group, see
  /// ArmedReminderRecord.encode.
  void recordArmed({
    List<ArmedHabitCopy> copies = const [],
    List<ArmedBundle> bundles = const [],
    Map<String, int> snoozeIds = const {},
  }) {
    store['armedHabitRemindersJson'] = ArmedReminderRecord.encode(
      copies: copies,
      bundles: bundles,
      snoozeIds: snoozeIds,
    );
  }

  ArmedHabitCopy copy(String habit, int id, DateTime at,
          {bool alarm = false}) =>
      (
        habitId: habit,
        id: id,
        fireTime: at,
        kind: alarm ? ArmedReminderKind.alarm : ArmedReminderKind.notification,
      );

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

    test("takes down the day's reminder at whatever depth the last pass put "
        'it, and none of the days after', () async {
      // «صلاة الضحى» at 10:47. The app was last opened on the 5th at 08:00,
      // before that day's reminder, so the 5th's copy went out under the
      // next-occurrence id and the 6th's sits one further along. Guessing
      // the next-occurrence id, as this path used to, cancelled nothing
      // pending and the 6th's reminder rang for a habit already ticked.
      recordArmed(
        copies: [
          copy('duha', nextCopy('duha'), DateTime(2026, 9, 5, 10, 47)),
          copy('duha', laterCopy('duha', 1), DateTime(2026, 9, 6, 10, 47)),
          copy('duha', laterCopy('duha', 2), DateTime(2026, 9, 7, 10, 47)),
          copy('duha', laterCopy('duha', 3), DateTime(2026, 9, 8, 10, 47)),
        ],
        snoozeIds: {'duha': snoozeOf('duha')},
      );
      // The 5th's has fired; the three after it are waiting.
      pending.addAll({
        laterCopy('duha', 1),
        laterCopy('duha', 2),
        laterCopy('duha', 3),
      });
      store['todayHabitsJson'] = todayList([
        {'id': 'duha', 'name': 'الضحى', 'done': false, 'count': 0, 'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'duha',
        now: DateTime(2026, 9, 6, 9, 25),
      );
      expect(pending, {laterCopy('duha', 2), laterCopy('duha', 3)},
          reason: "the 6th's reminder is gone; the 7th's and 8th's are that "
              "habit's next reminders, and a phone left closed after the "
              'tap still needs them');
      expect(alarmsCancelled(), isEmpty, reason: 'nothing here is an alarm');
    });

    test("does not take tomorrow's reminder when today's has already gone",
        () async {
      // Opened at 11:00 on the 6th, after the 10:47 reminder: the pass armed
      // the 7th under the next-occurrence id, which the old rule cancelled.
      recordArmed(
        copies: [
          copy('duha', nextCopy('duha'), DateTime(2026, 9, 7, 10, 47)),
          copy('duha', laterCopy('duha', 1), DateTime(2026, 9, 8, 10, 47)),
        ],
        snoozeIds: {'duha': snoozeOf('duha')},
      );
      pending.addAll({nextCopy('duha'), laterCopy('duha', 1)});
      store['todayHabitsJson'] = todayList([
        {'id': 'duha', 'name': 'الضحى', 'done': false, 'count': 0, 'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'duha',
        now: DateTime(2026, 9, 6, 21),
      );
      expect(pending, {nextCopy('duha'), laterCopy('duha', 1)});
      expect(cancels(), isEmpty);
    });

    test("every slot of a stacked habit that is still to come that day, and "
        'its snooze', () async {
      // An hour before Maghrib and on the dot. Armed on the 5th between the
      // two, so the 6th's early copy is slot 0's next occurrence and its
      // on-time copy is slot 1's second. A snooze is waiting too.
      recordArmed(
        copies: [
          copy('adhkar', nextCopy('adhkar', 0), DateTime(2026, 9, 6, 16, 50)),
          copy('adhkar', nextCopy('adhkar', 1), DateTime(2026, 9, 5, 17, 50)),
          copy('adhkar', laterCopy('adhkar', 1, 1),
              DateTime(2026, 9, 6, 17, 50)),
          copy('adhkar', laterCopy('adhkar', 1, 0),
              DateTime(2026, 9, 7, 16, 50)),
        ],
        snoozeIds: {'adhkar': snoozeOf('adhkar')},
      );
      pending.addAll({
        nextCopy('adhkar', 0),
        laterCopy('adhkar', 1, 1),
        laterCopy('adhkar', 1, 0),
        snoozeOf('adhkar'),
      });
      store['todayHabitsJson'] = todayList([
        {'id': 'adhkar', 'name': 'أذكار', 'done': false, 'count': 0,
          'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'adhkar',
        now: DateTime(2026, 9, 6, 15),
      );
      expect(pending, {laterCopy('adhkar', 1, 0)});
    });

    test('leaves a reminder of the day that has already been delivered',
        () async {
      // The 16:50 reminder came and is on the lock screen, the 17:50 one is
      // still to come. A Done at 17:00 takes the one still waiting and
      // leaves the notification list as it is, the rule the evening note
      // follows below; the plugin's cancel would remove a delivered one too.
      recordArmed(
        copies: [
          copy('adhkar', nextCopy('adhkar', 0), DateTime(2026, 9, 6, 16, 50)),
          copy('adhkar', nextCopy('adhkar', 1), DateTime(2026, 9, 6, 17, 50)),
        ],
      );
      pending.add(nextCopy('adhkar', 1));
      store['todayHabitsJson'] = todayList([
        {'id': 'adhkar', 'name': 'أذكار', 'done': false, 'count': 0,
          'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'adhkar',
        now: DateTime(2026, 9, 6, 17),
      );
      expect(cancels().map((c) => c.arguments), [nextCopy('adhkar', 1)]);
    });

    test("takes the day's alarms down with it", () async {
      recordArmed(
        copies: [
          copy('fajr', nextCopy('fajr'), DateTime(2026, 9, 6, 3, 1),
              alarm: true),
          copy('fajr', laterCopy('fajr', 1), DateTime(2026, 9, 7, 3, 1),
              alarm: true),
          // The far, day-keyed end of the alarm's month.
          copy('fajr', 523456, DateTime(2026, 9, 10, 3, 3), alarm: true),
        ],
      );
      store['todayHabitsJson'] = todayList([
        {'id': 'fajr', 'name': 'الفجر', 'done': false, 'count': 0, 'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'fajr',
        now: DateTime(2026, 9, 6, 2),
      );
      expect(alarmsCancelled(), [nextCopy('fajr')]);
    });

    test('takes a bundle down only once every habit in it is done that day',
        () async {
      // «سنة المغرب» and «أذكار المساء» share one notification at 17:50.
      recordArmed(
        bundles: [
          (
            id: 7000,
            fireTime: DateTime(2026, 9, 6, 17, 50),
            habitIds: ['sunnah', 'adhkar'],
          ),
        ],
      );
      store['todayHabitsDay'] = '2026-09-06';
      store['todayHabitsJson'] = todayList([
        {'id': 'sunnah', 'name': 'سنة', 'done': false, 'count': 0,
          'perDay': 1},
        {'id': 'adhkar', 'name': 'أذكار', 'done': false, 'count': 0,
          'perDay': 1},
      ]);
      pending.add(7000);
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'sunnah',
        now: DateTime(2026, 9, 6, 16),
      );
      expect(pending, contains(7000),
          reason: 'it still reminds about أذكار المساء, which is owed');

      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'adhkar',
        now: DateTime(2026, 9, 6, 16, 30),
      );
      expect(pending, isNot(contains(7000)),
          reason: 'both done: it would only name two finished habits');
    });

    test("does not trust yesterday's checkmarks with a shared reminder",
        () async {
      // The app was last opened yesterday, so the list, and the done mark
      // beside «أذكار المساء», is yesterday's.
      recordArmed(
        bundles: [
          (
            id: 7000,
            fireTime: DateTime(2026, 9, 6, 17, 50),
            habitIds: ['sunnah', 'adhkar'],
          ),
        ],
      );
      store['todayHabitsDay'] = '2026-09-05';
      store['todayHabitsJson'] = todayList([
        {'id': 'sunnah', 'name': 'سنة', 'done': false, 'count': 0,
          'perDay': 1},
        {'id': 'adhkar', 'name': 'أذكار', 'done': true, 'count': 1,
          'perDay': 1},
      ]);
      pending.add(7000);
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'sunnah',
        now: DateTime(2026, 9, 6, 16),
      );
      expect(pending, contains(7000));
    });

    test('with no record yet, takes the next copy of each slot and the '
        'snoozes, only those still waiting', () async {
      // An app updated from a build that wrote no record and not opened
      // since: the old rule is all there is to go on.
      pending.addAll({
        1010,
        nextCopy('fajr', 0),
        nextCopy('fajr', 1),
        laterCopy('fajr', 1),
        snoozeOf('fajr'),
      });
      store['todayHabitsJson'] = todayList([
        {'id': 'fajr', 'name': 'الفجر', 'done': false, 'count': 0, 'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
          actionId: 'mark_done', habitId: 'fajr', now: DateTime(2026, 9, 6));
      expect(
        {
          for (final c in cancels())
            if (c.arguments != 1010) c.arguments as int,
        },
        {nextCopy('fajr', 0), nextCopy('fajr', 1), snoozeOf('fajr')},
      );
      expect(pending, {laterCopy('fajr', 1)},
          reason: 'the days AHEAD stay armed — a habit marked done from the '
              'lock screen must not go silent for the rest of the window '
              'when the app is not opened again');
      expect(
        alarmsCancelled().toSet(),
        {for (var slot = 0; slot < 12; slot++) nextCopy('fajr', slot)},
      );
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
      pending.add(1010);
      store['todayHabitsJson'] = todayList([
        {'id': 'maghrib', 'name': 'المغرب', 'done': false, 'count': 0, 'perDay': 1},
        {'id': 'isha', 'name': 'العشاء', 'done': false, 'count': 0, 'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'maghrib',
        now: DateTime(2026, 9, 11, 19, 40),
      );
      expect(cancels().where((c) => c.arguments == 1010), hasLength(1));
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
        cancels().where((c) => c.arguments == 1010),
        isEmpty,
        reason: 'delivered at 20:30, so nothing pending to clear',
      );
      expect(
        queued().single.habitId,
        'maghrib',
        reason: 'the tap itself still counts, whatever the note does',
      );
    });

    test('clears it for a last round, and leaves it for a quit habit kept '
        'clean', () async {
      // The note stopped counting quit habits on 2026-09-24, so «التزام»
      // leaves its numbers true, and clearing it would lose tonight's note
      // until the app is next opened.
      pending.add(1010);
      store['todayHabitsJson'] = todayList([
        {'id': 'coffee', 'name': 'قهوة', 'done': false, 'count': 0, 'perDay': 1},
        {'id': 'water', 'name': 'ماء', 'done': false, 'count': 2, 'perDay': 3},
      ]);
      await handleBackgroundNotificationAction(
        actionId: 'quit_on_track',
        habitId: 'coffee',
        now: DateTime(2026, 9, 11, 19),
      );
      expect(cancels().where((c) => c.arguments == 1010), isEmpty);
      expect(pending, contains(1010));

      pending.add(1010);
      notificationCalls.clear();
      await handleBackgroundNotificationAction(
        actionId: 'mark_done',
        habitId: 'water',
        now: DateTime(2026, 9, 11, 19),
      );
      expect(
        cancels().where((c) => c.arguments == 1010),
        hasLength(1),
        reason: 'the third of three finishes the habit for the day',
      );
    });

    test("clears the week's numbered note on a finishing tap on its Friday",
        () async {
      // Armed today for tomorrow morning as «٥ أيام خضرا في أسبوعك 👏🏼
      // واليوم يبدأ أسبوع جديد.» under the habit with the most green days.
      // A habit finished here can add a green day or overtake that habit,
      // and this engine has no Grid to count with.
      expect(DateTime(2026, 9, 11).weekday, DateTime.friday);
      for (final (actionId, habitId) in [
        ('mark_done', 'maghrib'),
        ('quit_on_track', 'coffee'),
      ]) {
        notificationCalls.clear();
        pending.addAll({1010, 9001});
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

    test("leaves the week's note on other days, and on a tap that does not "
        'finish the habit', () async {
      for (final now in [
        // Not a Friday: either the note has been delivered already or the
        // week it is about has not started closing.
        DateTime(2026, 9, 10, 18),
        DateTime(2026, 9, 12, 9),
        DateTime(2026, 9, 12, 20),
      ]) {
        notificationCalls.clear();
        // Listed as pending on purpose: what holds 9001 back at these
        // moments is the WINDOW, the note being about today, and not
        // whether the OS still has it.
        pending.addAll({1010, 9001});
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
          cancels().where((c) => c.arguments == 1010),
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
      // reach for an id it does not own — 1010 (the evening note) and 9001
      // are the only two they may touch.
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
          if (c.arguments == 1010 || c.arguments == 9001) c.arguments as int,
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

  group("Didn't keep it", () {
    test('queues the answer and stands down the rest of that day, nothing '
        'else', () async {
      // «ما التزمت» answers the day as surely as «التزام» does (Aziz,
      // 2026-09-24): the habit's later check-in that day stands down, the
      // next day's stays, and the evening note is left alone.
      recordArmed(
        copies: [
          copy('coffee', nextCopy('coffee'), DateTime(2026, 9, 6, 9)),
          copy('coffee', laterCopy('coffee', 1), DateTime(2026, 9, 6, 17)),
          copy('coffee', laterCopy('coffee', 2), DateTime(2026, 9, 7, 9)),
        ],
        snoozeIds: {'coffee': snoozeOf('coffee')},
      );
      pending.addAll({laterCopy('coffee', 1), laterCopy('coffee', 2), 1010});
      store['todayHabitsJson'] = todayList([
        {'id': 'coffee', 'name': 'قهوة', 'done': false, 'count': 0, 'perDay': 1},
      ]);
      await handleBackgroundNotificationAction(
          actionId: 'quit_slipped',
          habitId: 'coffee',
          now: DateTime(2026, 9, 6, 12));
      expect(queued().single,
          const QueuedNotificationAction(
              action: 'quit_slipped', habitId: 'coffee', day: '2026-09-06'));
      final entry = (jsonDecode(store['todayHabitsJson'] as String) as List)
          .first as Map;
      expect(entry['done'], isFalse,
          reason: '«ما التزمت» is not a completion');
      expect(pending, {laterCopy('coffee', 2), 1010},
          reason: "the 17:00 check-in would ask again about a day already "
              "answered; the 7th's is that day's own question");
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
      expect(titles, containsAll(['تمت', 'تأجيل ساعة', 'التزام', 'ما التزمت']),
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
