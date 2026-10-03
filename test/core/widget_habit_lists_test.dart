// The two habit lists the app leaves for the Habits widgets
// (HomeWidgetService.updateWidgetData), the swap that makes the second one
// today's (rollTodayHabitsTo), and the task queue's requeue, read back
// through a mocked home_widget channel.
//
// Until 2026-09-29 the app wrote only today's list, and a phone left alone
// overnight showed yesterday on every Habits face the next morning: a
// finished day's ticks with nothing to tap, and an open row from yesterday
// whose tap was paid to today. The widget can build no list of its own, so
// what these pin is the contract it now reads: the next day's list under
// `nextHabitsJson`, its day under `nextHabitsDay`, both written before
// today's pair, and a rest the person chose marked as one («راحة»), not as
// a day that asked nothing. GrowDailyProvider.loadEntry and rollHabitList
// (GrowDailyWidget.swift) are the readers.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/extensions/datetime_ext.dart';
import 'package:grow_daily_v2/core/services/home_widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const widgetChannel = MethodChannel('home_widget');

  /// The App Group store, keyed the way home_widget keys it.
  late Map<String, Object?> store;

  /// Every key written, in order.
  late List<String> writes;

  setUp(() {
    // HomeWidgetService only talks to the store on iOS.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    store = <String, Object?>{};
    writes = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(widgetChannel, (call) async {
      final args = call.arguments;
      switch (call.method) {
        case 'saveWidgetData':
          final id = (args as Map)['id'] as String;
          store[id] = args['data'];
          writes.add(id);
          return true;
        case 'getWidgetData':
          return store[(args as Map)['id'] as String];
      }
      return true;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(widgetChannel, null);
  });

  WidgetHabitRow row(
    String id, {
    bool done = false,
    int count = 0,
    int perDay = 1,
    bool notDue = false,
    bool rest = false,
    bool half = false,
  }) =>
      (
        id: id,
        name: id,
        done: done,
        count: count,
        perDay: perDay,
        notDue: notDue,
        half: half,
        rest: rest,
        category: 'faith',
        color: null,
      );

  List<Map<String, dynamic>> decoded(String key) =>
      (jsonDecode(store[key]! as String) as List).cast<Map<String, dynamic>>();

  group('updateWidgetData', () {
    test('leaves the next day beside today, written before it', () async {
      final tomorrow = DateTime(2030, 1, 2);
      await HomeWidgetService.instance.updateWidgetData(
        streak: 4,
        completedToday: 1,
        totalToday: 2,
        todayHabits: [row('fajr', done: true, count: 1), row('quran')],
        nextDay: tomorrow,
        nextHabits: [row('fajr'), row('quran'), row('gym', notDue: true)],
      );

      expect(store['nextHabitsDay'], '2030-01-02');
      expect(decoded('nextHabitsJson').map((h) => h['id']),
          ['fajr', 'quran', 'gym']);
      expect(decoded('nextHabitsJson').every((h) => h['done'] == false),
          isTrue);
      expect(decoded('nextHabitsJson').last['notDue'], isTrue);
      expect(store['todayHabitsDay'], DateTime.now().effectiveDay.toDateKey());
      // Tomorrow's pair lands first and today's day key last: a reader in
      // between must never find a new list under an old day.
      expect(writes.indexOf('nextHabitsDay'),
          lessThan(writes.indexOf('todayHabitsJson')));
      expect(writes.last, 'todayHabitsDay');
    });

    test('marks a chosen rest, and only a rest that is not done', () async {
      await HomeWidgetService.instance.updateWidgetData(
        streak: 0,
        completedToday: 0,
        totalToday: 1,
        todayHabits: [
          row('walk', notDue: true, rest: true),
          row('quran'),
        ],
      );
      final today = decoded('todayHabitsJson');
      expect(today.first['rest'], isTrue);
      expect(today.first['notDue'], isTrue,
          reason: 'a rest still leaves the count');
      expect(today.last.containsKey('rest'), isFalse,
          reason: 'written only when true');
    });

    test('an older caller with no next day writes no next list', () async {
      await HomeWidgetService.instance.updateWidgetData(
        streak: 0,
        completedToday: 0,
        totalToday: 0,
        todayHabits: const [],
      );
      expect(store.containsKey('nextHabitsJson'), isFalse);
      expect(store.containsKey('nextHabitsDay'), isFalse);
    });
  });

  group('rollTodayHabitsTo', () {
    test("swaps in the next list once it is that list's day", () async {
      store['todayHabitsJson'] = '[{"id":"a","name":"a","done":true}]';
      store['todayHabitsDay'] = '2030-01-01';
      store['nextHabitsJson'] = '[{"id":"a","name":"a","done":false}]';
      store['nextHabitsDay'] = '2030-01-02';

      expect(await HomeWidgetService.instance.rollTodayHabitsTo('2030-01-02'),
          isTrue);
      expect(store['todayHabitsJson'], '[{"id":"a","name":"a","done":false}]');
      expect(store['todayHabitsDay'], '2030-01-02');
      expect(writes, ['todayHabitsJson', 'todayHabitsDay'],
          reason: 'the list first, its day after');
    });

    test('leaves a list that is already the day alone', () async {
      store['todayHabitsJson'] = '[]';
      store['todayHabitsDay'] = '2030-01-02';
      store['nextHabitsJson'] = '[{"id":"b","name":"b","done":false}]';
      store['nextHabitsDay'] = '2030-01-03';

      expect(await HomeWidgetService.instance.rollTodayHabitsTo('2030-01-02'),
          isTrue);
      expect(writes, isEmpty);
    });

    test('answers false when neither list is the day', () async {
      store['todayHabitsJson'] = '[]';
      store['todayHabitsDay'] = '2030-01-01';
      store['nextHabitsJson'] = '[]';
      store['nextHabitsDay'] = '2030-01-02';

      expect(await HomeWidgetService.instance.rollTodayHabitsTo('2030-01-04'),
          isFalse);
      expect(writes, isEmpty);
    });

    test('trusts a list from a build before the day key', () async {
      store['todayHabitsJson'] = '[]';
      expect(await HomeWidgetService.instance.rollTodayHabitsTo('2030-01-04'),
          isTrue);
    });
  });

  group('requeuePendingTaskCompletions', () {
    test('puts the taps back ahead of any queued since, once each', () async {
      store['pendingWidgetTaskCompletions'] = jsonEncode(['c', 'a']);
      await HomeWidgetService.instance
          .requeuePendingTaskCompletions(['a', 'b']);
      expect(
        jsonDecode(store['pendingWidgetTaskCompletions']! as String),
        ['a', 'b', 'c'],
      );
    });

    test('into an empty queue', () async {
      await HomeWidgetService.instance.requeuePendingTaskCompletions(['a']);
      expect(jsonDecode(store['pendingWidgetTaskCompletions']! as String),
          ['a']);
    });
  });
}
