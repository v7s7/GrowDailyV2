// The habit reminder pass sends a cancel only where one can change
// something.
//
// A pass used to clear slots blind: all 48 slot ids and 12 snooze ids of
// every habit with no reminder, every slot the 64-request budget trimmed,
// every member of a bundle, and an AlarmKit cancel beside each, whether or
// not either system held anything there. Measured on an account shaped like
// Aziz's (12 habits, four of them with nothing to remind), an unchanged
// pass sent 315 notification cancels and 296 AlarmKit cancels, and two of
// them found something. Now a notification cancel goes out for an id the
// system held when the pass began or one the pass has armed since, and an
// AlarmKit cancel for an id AlarmKit lists or the bridge recorded when the
// pass began, or one the pass has tried to arm since.
//
// A cancel of an id nothing holds does nothing, so skipping it leaves every
// system exactly where it would have been. That is what most of this file
// pins, and those tests were run green against the code before the change.
// The two that count calls ('an unchanged pass cancels only ...') are the
// change itself and failed on that code, by the counts above.
//
// The pass runs on the real clock (NotificationService reads
// tz.TZDateTime.now), like armed_reminder_pass_test: every habit sits at
// least 20 minutes from now, and a test is skipped in the minutes around
// midnight and the 10:00 cutoff, where two passes a moment apart can rightly
// resolve different days.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/services/alarm_service.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// How the fake bridge answers 'heldSlots'.
enum _HeldReply { answer, none, throws, malformed, unimplemented }

/// Every system a habit pass writes to, kept the way the real ones keep it.
class _System {
  /// Pending notification requests, every argument the plugin sent.
  final pending = <int, Map>{};

  /// Delivered notifications, still in the list.
  final delivered = <int, Map>{};

  /// What AlarmKit lists, and the bridge's own App Group record of what it
  /// armed (AlarmSlotRecords). Two maps because they can disagree: an alarm
  /// that rang is gone from the listing and still recorded, and one armed
  /// by a build older than the records is listed with no record.
  final listed = <int, Map>{};
  final records = <int, Map>{};

  /// The App Group store home_widget writes to.
  final store = <String, Object?>{};

  /// Both channels in call order, one line per call.
  final trace = <String>[];

  bool pendingReadFails = false;
  bool alarmsAuthorized = true;
  _HeldReply heldReply = _HeldReply.answer;

  /// Alarm ids the bridge fails to arm after its checks pass, which clears
  /// whatever was under the id first, as AlarmKitBridge.schedule does.
  final refuseAlarms = <int>{};

  /// Notification ids whose zonedSchedule throws.
  final failArming = <int>{};

  _System();

  /// A copy holding the same entries, for running one pass from one state
  /// several times.
  _System.from(_System other) {
    pending.addAll(other.pending);
    delivered.addAll(other.delivered);
    listed.addAll(other.listed);
    records.addAll(other.records);
    store.addAll(other.store);
  }

  Set<int> alarmsHeldIn(int low, int high) => {
        for (final id in [...listed.keys, ...records.keys])
          if (id >= low && id <= high) id,
      };

  /// Everything the systems hold, in one comparable string.
  String state() {
    String dump(Map<Object, Object?> m) {
      final keys = m.keys.map((k) => '$k').toList()..sort();
      final byKey = {for (final e in m.entries) '${e.key}': e.value};
      return [for (final k in keys) '$k=${byKey[k]}'].join('\n');
    }

    return 'pending\n${dump(pending)}\ndelivered\n${dump(delivered)}\n'
        'listed\n${dump(listed)}\nrecords\n${dump(records)}\n'
        'store\n${dump(store)}';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // A fresh one for every test (see setUp); the channel mocks below always
  // answer from whichever is current.
  late _System sys;
  const widgetChannel = MethodChannel('home_widget');
  const alarmChannel = MethodChannel('com.growdaily.v2/alarm');
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');

  final service = NotificationService.instance;
  const settings = NotificationSettings();

  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
    IOSFlutterLocalNotificationsPlugin.registerWith();
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    sys = _System();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(widgetChannel, (call) async {
      final args = call.arguments;
      switch (call.method) {
        case 'saveWidgetData':
          sys.store[(args as Map)['id'] as String] = args['data'];
          return true;
        case 'getWidgetData':
          return sys.store[(args as Map)['id'] as String];
      }
      return true;
    });
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      final a = call.arguments;
      switch (call.method) {
        case 'zonedSchedule':
          final m = Map<Object?, Object?>.of(a as Map);
          final id = m['id'] as int;
          sys.trace.add('notify:zonedSchedule:$id');
          if (sys.failArming.contains(id)) {
            throw PlatformException(code: 'boom');
          }
          // An add under a held id replaces the pending request; a copy
          // already delivered stays in the list until the new one lands.
          sys.pending[id] = m;
        case 'cancel':
          // The plugin's cancel: on iOS, pending and delivered both go
          // (FlutterLocalNotificationsPlugin.m).
          final id = a as int;
          sys.trace.add('notify:cancel:$id');
          sys.pending.remove(id);
          sys.delivered.remove(id);
        case 'pendingNotificationRequests':
          sys.trace.add('notify:pending');
          if (sys.pendingReadFails) {
            throw PlatformException(code: 'unreadable');
          }
          return [
            for (final e in sys.pending.entries)
              {
                'id': e.key,
                'title': e.value['title'],
                'body': e.value['body'],
                'payload': e.value['payload'],
              },
          ];
        case 'getActiveNotifications':
          sys.trace.add('notify:active');
          return [
            for (final e in sys.delivered.entries)
              {
                'id': e.key,
                'title': e.value['title'],
                'body': e.value['body'],
                'payload': e.value['payload'],
              },
          ];
      }
      return null;
    });
    // iOS 26 with alarms allowed, keeping to AlarmKitBridge.swift's rules.
    messenger.setMockMethodCallHandler(alarmChannel, (call) async {
      final a = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'isSupported':
          return true;
        case 'authorizationState':
          return sys.alarmsAuthorized ? 'authorized' : 'denied';
        case 'schedule':
          final id = a['id'] as int;
          sys.trace.add('alarm:schedule:$id');
          if (!sys.alarmsAuthorized) return false;
          final at = DateTime.fromMillisecondsSinceEpoch(
              (a['fireAtMs'] as num).toInt());
          if (!at.isAfter(DateTime.now())) return false;
          // Replace rather than duplicate, and a failure after that forgets.
          sys.listed.remove(id);
          if (sys.refuseAlarms.contains(id)) {
            sys.records.remove(id);
            return false;
          }
          sys.listed[id] = Map.of(a);
          sys.records[id] = Map.of(a);
          return true;
        case 'cancel':
          final id = a['id'] as int;
          sys.trace.add('alarm:cancel:$id');
          sys.listed.remove(id);
          sys.records.remove(id);
          return null;
        case 'heldSlots':
          final low = a['lowId'] as int;
          final high = a['highId'] as int;
          sys.trace.add('alarm:heldSlots:$low-$high');
          switch (sys.heldReply) {
            case _HeldReply.answer:
              return sys.alarmsHeldIn(low, high).toList()..sort();
            case _HeldReply.none:
              return null;
            case _HeldReply.throws:
              throw PlatformException(code: 'unlisted');
            case _HeldReply.malformed:
              return <Object?>['$low', null];
            case _HeldReply.unimplemented:
              throw MissingPluginException();
          }
        case 'reapOrphans':
          final low = a['lowId'] as int;
          final high = a['highId'] as int;
          final keep = (a['keepIds'] as List).cast<int>().toSet();
          sys.trace.add('alarm:reapOrphans:$low-$high');
          var reaped = 0;
          for (final id in sys.alarmsHeldIn(low, high)) {
            if (keep.contains(id)) continue;
            sys.listed.remove(id);
            sys.records.remove(id);
            reaped++;
          }
          return reaped;
        case 'syncWindow':
          final low = a['lowId'] as int;
          final high = a['highId'] as int;
          sys.trace.add('alarm:syncWindow:$low-$high');
          final wanted = {
            for (final raw in a['alarms'] as List)
              (raw as Map)['id'] as int: Map.of(raw),
          };
          for (final id in sys.alarmsHeldIn(low, high)) {
            if (wanted.containsKey(id)) continue;
            sys.listed.remove(id);
            sys.records.remove(id);
          }
          sys.listed.addAll(wanted);
          sys.records.addAll(wanted);
          return <String, int>{'scheduled': wanted.length};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
        timezoneChannel, (call) async => 'Asia/Bahrain');

    // The service is one instance for the whole file and remembers which
    // habits it armed; an empty pass forgets them, so a habit from an
    // earlier test is not swept as stale into this one's counts.
    await service.scheduleSmartReminders(const [], settings, isAr: true);
    sys = _System();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      widgetChannel,
      alarmChannel,
      notificationsChannel,
      timezoneChannel,
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  // Too near a day edge for two passes a moment apart to agree on the day.
  bool nearADayEdge() {
    final now = tz.TZDateTime.now(tz.local);
    final minute = now.hour * 60 + now.minute;
    return minute < 5 || minute > 1434 || (minute > 594 && minute < 606);
  }

  // The minute [minutes] from now, which may be tomorrow's.
  TimeOfDay ahead(int minutes) {
    final at = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
    return TimeOfDay(hour: at.hour, minute: at.minute);
  }

  HabitReminderInput habit(
    String id, {
    List<TimeOfDay> times = const [],
    String? prayerKey,
    bool alarm = false,
    bool quit = false,
  }) {
    // Ascending, as HabitCue.clockTimes hands them over.
    final sorted = [...times]..sort(
        (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
    return (
      id: id,
      name: 'عادة $id',
      clockTimes: sorted,
      clockOffsets: [for (final _ in sorted) 0],
      remindersPerOccurrence: 1,
      extraReminderOffsets: const [],
      prayerKey: prayerKey,
      prayerSlots: const [],
      streak: 3,
      completedCount: 0,
      dailyTarget: sorted.isEmpty ? 1 : sorted.length,
      lastDoneDaysAgo: 1,
      timerSeconds: null,
      reminderOffsetMinutes: 0,
      ignoreQuietHours: false,
      isQuit: quit,
      isLimit: false,
      alarm: alarm,
      scheduledWeekdays: const {},
      anchorLabel: null,
      weekTarget: null,
      weekDoneDays: null,
    );
  }

  // The account the counts above were measured on: four habits with
  // nothing to remind (two with no cue, two anchored to a prayer with no
  // place saved), one alarm habit at two times, and seven notification
  // habits at 26 times, more than the 48-slot budget holds, several of
  // them close enough to bundle. The clock times of that account, moved to
  // start 20 minutes from now.
  List<HabitReminderInput> measuredAccount() {
    TimeOfDay at(int hour, int minute) =>
        ahead(20 + hour * 60 + minute - (4 * 60 + 30));
    return [
      habit('none-0'),
      habit('none-1'),
      habit('none-2', prayerKey: 'fajr'),
      habit('none-3', prayerKey: 'maghrib'),
      habit('fajr', times: [at(4, 30), at(5, 0)], alarm: true),
      habit('a', times: [
        at(7, 0), at(9, 0), at(11, 0), at(13, 0), at(15, 0), at(17, 0), //
      ]),
      habit('b', times: [at(7, 5), at(10, 0), at(14, 0), at(18, 0), at(21, 0)]),
      habit('c', times: [at(8, 0), at(12, 0), at(16, 0), at(20, 0)]),
      habit('d', times: [at(8, 10), at(12, 5), at(19, 0), at(22, 0)]),
      habit('e', times: [at(6, 0), at(18, 5), at(23, 0)]),
      habit('f', times: [at(9, 30), at(21, 30)]),
      habit('g', times: [at(20, 10), at(22, 30)]),
    ];
  }

  // The id NotificationService gives [habitId]'s [slot] at [depth], and its
  // snooze: the private _habitReminderId and _snoozeId, spelled out.
  int slotId(String habitId, int depth, [int slot = 0]) {
    final offset = NotificationService.reminderSlotOffset(habitId, slot);
    return depth == 0 ? 5000 + offset : 400000 + (depth - 1) * 1000 + offset;
  }

  int snoozeId(String habitId, [int slot = 0]) =>
      6000 + NotificationService.reminderSlotOffset(habitId, slot);

  const depths = NotificationService.kOccurrencesPerSlot;

  // Two habit ids whose first slots fold to the same id at every depth. The
  // fold is a hash into 1000, so a few dozen names always hold a pair.
  (String, String) collidingPair(String prefix) {
    final seen = <int, String>{};
    for (var i = 0;; i++) {
      final id = '$prefix-$i';
      final offset = NotificationService.reminderSlotOffset(id, 0);
      final earlier = seen.putIfAbsent(offset, () => id);
      if (earlier != id) return (earlier, id);
    }
  }

  // [count] more ids whose first slots fold nowhere near [taken] or each
  // other, so the only collision in a test is the one it is about.
  List<String> apartFrom(Iterable<String> taken, String prefix, int count) {
    final used = {
      for (final id in taken) NotificationService.reminderSlotOffset(id, 0),
    };
    return [
      for (var i = 0; used.length < taken.length + count; i++)
        if (used.add(NotificationService.reminderSlotOffset('$prefix-$i', 0)))
          '$prefix-$i',
    ];
  }

  Iterable<int> idsOf(String kind, String method) => sys.trace
      .where((t) => t.startsWith('$kind:$method:'))
      .map((t) => int.parse(t.split(':').last));

  bool inHabitBands(int id) =>
      (id >= 5000 && id < 7000) || (id >= 400000 && id < 403000);

  group('notification cancels', () {
    test('an unchanged second pass leaves every system exactly as the first '
        'left it', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      final habits = measuredAccount();
      await service.scheduleSmartReminders(habits, settings, isAr: true);
      final first = sys.state();
      expect(sys.pending, isNotEmpty);
      expect(sys.listed, isNotEmpty);
      await service.scheduleSmartReminders(habits, settings, isAr: true);
      expect(sys.state(), first);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('an unchanged pass cancels only what the system held when it began, '
        'or what it armed since', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      final habits = measuredAccount();
      await service.scheduleSmartReminders(habits, settings, isAr: true);
      final heldAtStart = {...sys.pending.keys, ...sys.delivered.keys};
      sys.trace.clear();
      await service.scheduleSmartReminders(habits, settings, isAr: true);
      final armed = <int>{};
      final blind = <int>[];
      var cancels = 0;
      for (final line in sys.trace) {
        final parts = line.split(':');
        if (parts[0] != 'notify' || parts.length < 3) continue;
        final id = int.parse(parts[2]);
        if (parts[1] == 'zonedSchedule') armed.add(id);
        if (parts[1] != 'cancel') continue;
        cancels++;
        if (!heldAtStart.contains(id) && !armed.contains(id)) blind.add(id);
      }
      printOnFailure('notification cancels: $cancels, blind: ${blind.length}');
      expect(blind, isEmpty,
          reason: 'a cancel of an id nothing holds cannot change anything');
      // A cancel that remains is a real collision: an id another habit's
      // slot armed earlier in the same pass, cancelled as it always was.
      expect(cancels, lessThan(10));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a slot trimmed from the budget still cancels a copy another habit '
        'armed under its id earlier in the pass', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      // Bundling off so every copy is its own group: with two habits more
      // than the budget holds at four depths, the latest few depth-3 copies
      // are trimmed. The first habit is the earliest of the day, so its
      // depth-3 copy is armed; the second is the latest, so its own is
      // trimmed, and it shares the first one's id.
      final (early, late) = collidingPair('trim');
      final fillers = apartFrom([early], 'filler',
          NotificationService.kMaxPendingHabitSlots ~/ depths);
      final habits = [
        habit(early, times: [ahead(30)]),
        for (var i = 0; i < fillers.length; i++)
          habit(fillers[i], times: [ahead(60 + i * 30)]),
        habit(late, times: [ahead(1200)]),
      ];
      await service.scheduleSmartReminders(
          habits, const NotificationSettings(bundleEnabled: false),
          isAr: true);
      final shared = slotId(early, depths - 1);
      expect(slotId(late, depths - 1), shared);
      final armedAt = sys.trace.indexOf('notify:zonedSchedule:$shared');
      final cancelledAt = sys.trace.lastIndexOf('notify:cancel:$shared');
      expect(armedAt, isNonNegative);
      expect(cancelledAt, greaterThan(armedAt),
          reason: 'the trim cancel runs after the copy under its id was '
              'armed, exactly as it always has');
      expect(sys.pending.containsKey(shared), isFalse);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a bundled slot still cancels a copy another habit armed under its '
        'id earlier in the pass', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      final (alone, bundled) = collidingPair('bundle');
      final partner = apartFrom([alone], 'partner', 1).single;
      final habits = [
        habit(alone, times: [ahead(30)]),
        habit(bundled, times: [ahead(300)]),
        habit(partner, times: [ahead(300)]),
      ];
      await service.scheduleSmartReminders(habits, settings, isAr: true);
      for (var depth = 0; depth < depths; depth++) {
        final shared = slotId(alone, depth);
        expect(slotId(bundled, depth), shared);
        final armedAt = sys.trace.indexOf('notify:zonedSchedule:$shared');
        expect(armedAt, isNonNegative);
        expect(sys.trace.lastIndexOf('notify:cancel:$shared'),
            greaterThan(armedAt));
        expect(sys.pending.containsKey(shared), isFalse);
      }
      expect(sys.pending.keys.where((id) => id >= 7000 && id < 8000),
          hasLength(depths),
          reason: 'one bundle a day, and the pass really did bundle');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('an alarm slot still cancels a check-in another habit armed under '
        'its id earlier in the pass', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      final (quit, alarm) = collidingPair('alone');
      final habits = [
        habit(quit, times: [ahead(30)], quit: true),
        habit(alarm, times: [ahead(300)], alarm: true),
      ];
      await service.scheduleSmartReminders(habits, settings, isAr: true);
      for (var depth = 0; depth < depths; depth++) {
        final shared = slotId(quit, depth);
        final armedAt = sys.trace.indexOf('notify:zonedSchedule:$shared');
        expect(armedAt, isNonNegative);
        expect(sys.trace.lastIndexOf('notify:cancel:$shared'),
            greaterThan(armedAt));
        expect(sys.pending.containsKey(shared), isFalse);
        expect(sys.listed.containsKey(shared), isTrue,
            reason: 'the alarm is what holds the id now');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a habit that loses its cue loses its delivered copy and its '
        'pending snooze too', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      await service.scheduleSmartReminders(
          [habit('walk', times: [ahead(60)])], settings,
          isAr: true);
      final today = slotId('walk', 0);
      // It rang, and was snoozed from the lock screen.
      sys.delivered[today] = sys.pending.remove(today)!;
      await service.snoozeHabitReminder('walk', 'walk', isAr: true);
      expect(sys.pending.containsKey(snoozeId('walk')), isTrue);

      await service.scheduleSmartReminders(
          [habit('walk')], settings, isAr: true);
      expect(sys.delivered, isEmpty);
      expect(sys.pending.values.where((m) => m['payload'] == 'walk'), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('when the system cannot be read, a habit with no reminder is '
        'cleared blind in both systems, as before', () async {
      sys.pendingReadFails = true;
      // As on a build whose bridge has no listing: every alarm cancel goes.
      sys.heldReply = _HeldReply.unimplemented;
      await service.scheduleSmartReminders(
          [habit('nothing')], settings, isAr: true);
      expect(idsOf('notify', 'cancel').where(inHabitBands),
          hasLength(12 * depths + 12),
          reason: 'every slot at every depth, and every slot\'s snooze');
      expect(idsOf('alarm', 'cancel'), hasLength(12 * depths));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('AlarmKit cancels', () {
    test('an unchanged pass cancels only alarms held when it began, or ones '
        'it tried to arm since', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      final habits = measuredAccount();
      await service.scheduleSmartReminders(habits, settings, isAr: true);
      final heldAtStart = {
        ...sys.alarmsHeldIn(5000, 5999),
        ...sys.alarmsHeldIn(400000, 402999),
      };
      expect(heldAtStart, hasLength(2 * depths));
      final before = sys.state();
      sys.trace.clear();
      await service.scheduleSmartReminders(habits, settings, isAr: true);
      final tried = <int>{};
      final blind = <int>[];
      var cancels = 0;
      for (final line in sys.trace) {
        final parts = line.split(':');
        if (parts[0] != 'alarm' || parts.length < 3) continue;
        if (parts[1] == 'schedule') tried.add(int.parse(parts[2]));
        if (parts[1] != 'cancel') continue;
        final id = int.parse(parts[2]);
        cancels++;
        if (!heldAtStart.contains(id) && !tried.contains(id)) blind.add(id);
      }
      printOnFailure('alarm cancels: $cancels, blind: ${blind.length}');
      expect(blind, isEmpty);
      expect(sys.state(), before);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a habit left with no reminder has each alarm it holds cancelled '
        'before the pass arms anything', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      final [gone, kept] = apartFrom(const [], 'loop', 2);
      await service.scheduleSmartReminders([
        habit(gone, times: [ahead(40)], alarm: true),
        habit(kept, times: [ahead(90)]),
      ], settings, isAr: true);
      final held = [for (var d = 0; d < depths; d++) slotId(gone, d)];
      expect(sys.listed.keys, containsAll(held));

      sys.trace.clear();
      await service.scheduleSmartReminders(
          [habit(gone), habit(kept, times: [ahead(90)])], settings,
          isAr: true);
      final firstArm = sys.trace.indexWhere((t) =>
          t.startsWith('notify:zonedSchedule:') ||
          t.startsWith('alarm:schedule:'));
      expect(firstArm, isNonNegative);
      for (final id in held) {
        final at = sys.trace.indexOf('alarm:cancel:$id');
        expect(at, isNonNegative, reason: 'alarm $id is cancelled');
        expect(at, lessThan(firstArm),
            reason: 'inside the habit loop, not left to the reap at the end');
        expect(sys.listed.containsKey(id), isFalse);
        expect(sys.records.containsKey(id), isFalse);
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a habit deleted, and then reminders switched off, still have each '
        'alarm they hold cancelled by name, before the reap', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      final [gone, kept] = apartFrom(const [], 'stale', 2);
      await service.scheduleSmartReminders([
        habit(gone, times: [ahead(40)], alarm: true),
        habit(kept, times: [ahead(90)], alarm: true),
      ], settings, isAr: true);
      final goneIds = [for (var d = 0; d < depths; d++) slotId(gone, d)];
      final keptIds = [for (var d = 0; d < depths; d++) slotId(kept, d)];
      expect(sys.listed.keys, containsAll([...goneIds, ...keptIds]));

      // Deleted with the app remembering it, so the stale sweep names it.
      sys.trace.clear();
      await service.scheduleSmartReminders(
          [habit(kept, times: [ahead(90)], alarm: true)], settings,
          isAr: true);
      final firstArm = sys.trace.indexWhere((t) =>
          t.startsWith('notify:zonedSchedule:') ||
          t.startsWith('alarm:schedule:'));
      expect(firstArm, isNonNegative);
      for (final id in goneIds) {
        final at = sys.trace.indexOf('alarm:cancel:$id');
        expect(at, isNonNegative, reason: 'alarm $id is cancelled');
        expect(at, lessThan(firstArm));
        expect(sys.listed.containsKey(id), isFalse);
        expect(sys.records.containsKey(id), isFalse);
      }
      expect(sys.listed.keys, containsAll(keptIds));

      // Switched off: every alarm the remembered habit holds goes by name,
      // not only through the reap at the end, and every notification slot
      // and snooze is cancelled blind, as it always was.
      sys.trace.clear();
      await service.scheduleSmartReminders(
          [habit(kept, times: [ahead(90)], alarm: true)],
          const NotificationSettings(habitRemindersEnabled: false),
          isAr: true);
      final reapAt =
          sys.trace.indexWhere((t) => t.startsWith('alarm:reapOrphans:'));
      expect(reapAt, isNonNegative);
      for (final id in keptIds) {
        final at = sys.trace.indexOf('alarm:cancel:$id');
        expect(at, isNonNegative, reason: 'alarm $id is cancelled');
        expect(at, lessThan(reapAt));
      }
      expect(sys.alarmsHeldIn(5000, 5999), isEmpty);
      expect(sys.alarmsHeldIn(400000, 402999), isEmpty);
      expect(idsOf('notify', 'cancel').where(inHabitBands),
          hasLength(12 * depths + 12));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a habit switched from alarm to notification clears each alarm '
        'before its notification is armed', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      await service.scheduleSmartReminders(
          [habit('switch', times: [ahead(45)], alarm: true)], settings,
          isAr: true);
      sys.trace.clear();
      await service.scheduleSmartReminders(
          [habit('switch', times: [ahead(45)])], settings,
          isAr: true);
      for (var d = 0; d < depths; d++) {
        final id = slotId('switch', d);
        final cancelledAt = sys.trace.indexOf('alarm:cancel:$id');
        expect(cancelledAt, isNonNegative);
        expect(cancelledAt,
            lessThan(sys.trace.indexOf('notify:zonedSchedule:$id')));
        expect(sys.listed.containsKey(id), isFalse);
        expect(sys.pending.containsKey(id), isTrue);
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('an alarm the bridge fails to arm still has its id cancelled before '
        'the notification that replaces it', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      final ids = [for (var d = 0; d < depths; d++) slotId('refused', d)];
      sys.refuseAlarms.addAll(ids);
      await service.scheduleSmartReminders(
          [habit('refused', times: [ahead(50)], alarm: true)], settings,
          isAr: true);
      for (final id in ids) {
        final triedAt = sys.trace.indexOf('alarm:schedule:$id');
        final cancelledAt = sys.trace.indexOf('alarm:cancel:$id');
        expect(triedAt, isNonNegative);
        expect(cancelledAt, greaterThan(triedAt));
        expect(cancelledAt,
            lessThan(sys.trace.indexOf('notify:zonedSchedule:$id')));
        expect(sys.pending.containsKey(id), isTrue,
            reason: 'the notification took over');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a notification slot still cancels an alarm another habit armed '
        'under its id earlier in the pass', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      // The check-in test above with the roles reversed. Alarm slots are
      // armed before any notification slot, and the system starts empty, so
      // the alarm is made under an id AlarmKit did not hold when the pass
      // began: the only thing that tells the later notification slot's cancel
      // the id is held is the pass having tried it, and that has to be true
      // of an alarm that was made, not only of one the bridge refused.
      final (rings, notes) = collidingPair('rings');
      final habits = [
        habit(rings, times: [ahead(30)], alarm: true),
        habit(notes, times: [ahead(300)]),
      ];
      await service.scheduleSmartReminders(habits, settings, isAr: true);
      for (var depth = 0; depth < depths; depth++) {
        final shared = slotId(rings, depth);
        expect(slotId(notes, depth), shared);
        final triedAt = sys.trace.indexOf('alarm:schedule:$shared');
        final cancelledAt = sys.trace.lastIndexOf('alarm:cancel:$shared');
        expect(triedAt, isNonNegative);
        expect(cancelledAt, greaterThan(triedAt),
            reason: 'the notification slot cancels the alarm armed under its '
                'id, exactly as it always has');
        expect(cancelledAt,
            lessThan(sys.trace.indexOf('notify:zonedSchedule:$shared')));
        expect(sys.listed.containsKey(shared), isFalse);
        expect(sys.records.containsKey(shared), isFalse);
        expect(sys.pending.containsKey(shared), isTrue,
            reason: 'the notification is what holds the id now');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('whatever the bridge says about what it holds, when it cannot say, '
        'the pass cancels exactly as it did before it asked', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      final habits = [
        habit('empty'),
        habit('rings', times: [ahead(35)], alarm: true),
        habit('notes', times: [ahead(70), ahead(400)]),
      ];
      await service.scheduleSmartReminders(habits, settings, isAr: true);
      final start = _System.from(sys);
      final traces = <_HeldReply, List<String>>{};
      final states = <_HeldReply, String>{};
      for (final reply in [
        _HeldReply.unimplemented,
        _HeldReply.none,
        _HeldReply.throws,
        _HeldReply.malformed,
      ]) {
        sys = _System.from(start)..heldReply = reply;
        await service.scheduleSmartReminders(habits, settings, isAr: true);
        traces[reply] = [
          for (final t in sys.trace)
            if (!t.startsWith('alarm:heldSlots:')) t,
        ];
        states[reply] = sys.state();
      }
      final blind = traces[_HeldReply.unimplemented]!;
      expect(blind.where((t) => t.startsWith('alarm:cancel:')),
          hasLength(12 * depths + 2 * depths),
          reason: 'every slot of the habit with no reminder, and one for '
              'each notification slot');
      for (final reply in traces.keys) {
        expect(traces[reply], blind, reason: '$reply');
        expect(states[reply], states[_HeldReply.unimplemented],
            reason: '$reply');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('cancelHabitReminders cancels every alarm id blind, after a pass that '
        'finished and after one that threw', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      await service.scheduleSmartReminders(
          [habit('stays', times: [ahead(55)], alarm: true)], settings,
          isAr: true);
      sys.trace.clear();
      await service.cancelHabitReminders('deleted-1');
      expect(idsOf('alarm', 'cancel'), hasLength(12 * depths));
      expect(idsOf('notify', 'cancel'), hasLength(12 * depths + 12));

      sys.failArming.add(slotId('breaks', 0));
      await expectLater(
        service.scheduleSmartReminders(
            [habit('breaks', times: [ahead(65)])], settings,
            isAr: true),
        throwsA(isA<PlatformException>()),
      );
      sys.trace.clear();
      await service.cancelHabitReminders('deleted-2');
      expect(idsOf('alarm', 'cancel'), hasLength(12 * depths));
      expect(idsOf('notify', 'cancel'), hasLength(12 * depths + 12));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('an alarm cancel skipped because nothing holds it still forgets the '
        'words a ring with the app open would show', () async {
      if (nearADayEdge()) {
        markTestSkipped('too near a day edge');
        return;
      }
      await service.scheduleSmartReminders(
          [habit('words', times: [ahead(75)], alarm: true)], settings,
          isAr: true);
      final today = slotId('words', 0);
      expect(AlarmService.instance.scheduledFor(today), isNotNull);
      // Stood down outside the app (the lock screen's Done runs in another
      // engine, whose AlarmService this one never hears from).
      sys.listed.remove(today);
      sys.records.remove(today);
      // Switched to a notification, and the pass stops at that very slot,
      // before the reap that would otherwise forget the words anyway.
      sys.failArming.add(today);
      await expectLater(
        service.scheduleSmartReminders(
            [habit('words', times: [ahead(75)])], settings,
            isAr: true),
        throwsA(isA<PlatformException>()),
      );
      expect(AlarmService.instance.scheduledFor(today), isNull);
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
