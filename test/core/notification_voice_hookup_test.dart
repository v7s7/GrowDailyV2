// The one-line hookups between NotificationService and the words it sends,
// driven through scheduleSmartReminders with the plugin's method channel
// mocked, the way reminder_window_ahead_test.dart does.
//
// The copy itself is pinned in reminder_copy_test.dart. What is pinned here
// is that the scheduler hands it the right facts: the prayer's name at the
// adhan, an ask rotated by the day each copy fires, and a bundle praised on
// each member's streak and cadence as they stand on the day it fires.
// Reverting any of those left every copy test green.
//
// The same holds for the gates on the evening streak note and the Friday
// note. notification_voice_gates_test.dart pins the pure decisions; the
// last two groups here pin what reaches the plugin: no 8000 once the point
// is earned or after its time, and this week's numbered copy as a one-shot
// (no matchDateTimeComponents) with no weekly repeat beside it. Arming the
// numbered copy as a repeat, or dropping the cancel when the note has
// nothing to say, left every pure test green.
//
// Two more things live here because only the plugin can show them. A note
// whose numbers have gone stale is cleared only while it is still PENDING,
// so the mocked channel below keeps a pending set: zonedSchedule adds an id,
// cancel removes one, and a test represents delivery by removing the id
// itself. And the Friday note's ids are counted: at most 9001 and 9002 at
// once, which is what keeps the fixed ids on a Friday afternoon at 10 of
// iOS's 64 rather than 13.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/core/l10n/reminder_copy.dart';
import 'package:grow_daily_v2/core/services/bahrain_prayer_table.dart';
import 'package:grow_daily_v2/core/services/notification_service.dart';
import 'package:grow_daily_v2/core/services/prayer_times_service.dart';
import 'package:grow_daily_v2/features/settings/models/notification_settings.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const _manama = NotificationLocation(
  lat: 26.2285,
  lng: 50.5860,
  label: 'Manama, Bahrain',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const alarmChannel = MethodChannel('com.growdaily.v2/alarm');
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  const timezoneChannel = MethodChannel('flutter_timezone');

  late List<MethodCall> notificationCalls;

  /// What the OS holds pending: every id armed and not since cancelled. A
  /// note that has fired is delivered rather than pending, which a test says
  /// by removing its id.
  late Set<int> pending;

  setUpAll(() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Bahrain'));
    IOSFlutterLocalNotificationsPlugin.registerWith();
    await BahrainPrayerTable.ensureLoaded();
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    notificationCalls = <MethodCall>[];
    pending = <int>{};
    PrayerTimesService.resetMonthCache();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      alarmChannel,
      (call) async => call.method == 'isSupported' ? false : null,
    );
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      notificationCalls.add(call);
      switch (call.method) {
        case 'zonedSchedule':
          pending.add((call.arguments as Map)['id'] as int);
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
      timezoneChannel,
      (call) async => 'Asia/Bahrain',
    );
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(alarmChannel, null);
    messenger.setMockMethodCallHandler(notificationsChannel, null);
    messenger.setMockMethodCallHandler(timezoneChannel, null);
  });

  const settings = NotificationSettings(
    quietHoursEnabled: false,
    location: _manama,
    resolvedCountryCode: 'BH',
  );

  /// A Fajr habit. The label is what main.dart passes for the prayer.
  HabitReminderInput habit({
    required String id,
    required String name,
    required int offset,
    int streak = 0,
    int? lastDoneDaysAgo,
    int completedCount = 0,
    Set<int> scheduledWeekdays = const {},
  }) =>
      (
        id: id,
        name: name,
        clockTimes: const [],
        clockOffsets: const [],
        remindersPerOccurrence: 1,
        extraReminderOffsets: const [],
        prayerKey: 'fajr',
        streak: streak,
        completedCount: completedCount,
        dailyTarget: 1,
        lastDoneDaysAgo: lastDoneDaysAgo,
        timerSeconds: null,
        reminderOffsetMinutes: offset,
        ignoreQuietHours: true,
        isQuit: false,
        isLimit: false,
        alarm: false,
        scheduledWeekdays: scheduledWeekdays,
        anchorLabel: 'الفجر',
        weekTarget: null,
        weekDoneDays: null,
      );

  /// Every notification scheduled, with the calendar day it fires on.
  List<({int id, DateTime day, String title, String body})> scheduled() => [
        for (final call in notificationCalls)
          if (call.method == 'zonedSchedule')
            (() {
              final args = call.arguments as Map;
              final at = tz.TZDateTime.parse(
                tz.local,
                args['scheduledDateTime'] as String,
              );
              return (
                id: args['id'] as int,
                day: DateTime(at.year, at.month, at.day),
                title: args['title'] as String,
                body: args['body'] as String,
              );
            })(),
      ];

  DateTime dayAfterToday(int n) {
    final now = tz.TZDateTime.now(tz.local);
    return DateTime(now.year, now.month, now.day + n);
  }

  // Done today with a live streak: today's copy stands down, tomorrow's
  // morning still has the run, and on any later day a morning will have
  // passed without it, so the streak re-based onto that day is 0 (see
  // reminderFactsAtFireDay). Praise therefore belongs on tomorrow's copy
  // and on no copy after it, whatever time these tests run.
  bool praisedDay(DateTime day) => !day.isAfter(dayAfterToday(1));

  test('at the adhan every copy names the prayer, praised only where true',
      () async {
    await NotificationService.instance.scheduleSmartReminders(
      [
        habit(
          id: 'sunnah-fajr',
          name: 'سنة الفجر',
          offset: 0,
          streak: 3,
          lastDoneDaysAgo: 0,
          completedCount: 1,
        ),
      ],
      settings,
      isAr: true,
    );
    final copies = scheduled();
    expect(copies.map((c) => c.day), contains(dayAfterToday(1)));
    expect(copies.map((c) => c.day), contains(dayAfterToday(2)));
    for (final c in copies) {
      expect(c.title, 'سنة الفجر');
      expect(
        c.body,
        praisedDay(c.day)
            ? 'اذن الفجر. سوي عادتك الحين. ملتزم صارلك ٣ أيام 👏🏼'
            : 'اذن الفجر. سوي عادتك الحين.',
        reason: '${c.day}',
      );
    }
  });

  test('a late reminder draws its ask from the day it fires', () async {
    await NotificationService.instance.scheduleSmartReminders(
      [
        habit(
          id: 'sunnah-fajr',
          name: 'سنة الفجر',
          offset: 15,
          lastDoneDaysAgo: 2,
        ),
      ],
      settings,
      isAr: true,
    );
    final copies = scheduled();
    expect(copies.length, greaterThan(1));
    const stamp = 'اذن الفجر قبل ١٥ دقيقة. ';
    final asks = <String>{};
    for (final c in copies) {
      expect(c.body, startsWith(stamp), reason: '${c.day}');
      final ask = c.body.substring(stamp.length);
      expect(
        ask,
        lateReminderAsk(
          NotificationService.reminderVariantSeed(c.day, 'sunnah-fajr'),
          true,
        ),
        reason: '${c.day}',
      );
      asks.add(ask);
    }
    // Seeded by the day it was armed, every morning read the same ask.
    expect(asks.length, greaterThan(1));
  });

  group('a bundle', () {
    List<({int id, DateTime day, String title, String body})> bundles() => [
          for (final c in scheduled())
            if (c.id >= 7000 && c.id < 8000) c,
        ];

    Future<void> arm({
      Set<int> firstWeekdays = const {},
      Set<int> secondWeekdays = const {},
    }) =>
        NotificationService.instance.scheduleSmartReminders(
          [
            habit(
              id: 'sunnah-fajr',
              name: 'سنة الفجر',
              offset: 15,
              streak: 5,
              lastDoneDaysAgo: 0,
              completedCount: 1,
              scheduledWeekdays: firstWeekdays,
            ),
            habit(
              id: 'morning-adhkar',
              name: 'أذكار الصباح',
              offset: 15,
              streak: 3,
              lastDoneDaysAgo: 0,
              completedCount: 1,
              scheduledWeekdays: secondWeekdays,
            ),
          ],
          settings,
          isAr: true,
        );

    const everyWeekday = {1, 2, 3, 4, 5, 6, 7};
    const lead = 'اذن الفجر قبل ١٥ دقيقة. سوي عاداتك الحين.';

    test('names its habits and praises each fire day on its own streaks',
        () async {
      await arm();
      final all = bundles();
      expect(all.map((b) => b.day), contains(dayAfterToday(1)));
      expect(all.map((b) => b.day), contains(dayAfterToday(2)));
      for (final b in all) {
        expect(
          b.title,
          anyOf('سنة الفجر وأذكار الصباح', 'أذكار الصباح وسنة الفجر'),
        );
        expect(
          b.body,
          praisedDay(b.day) ? '$lead ملتزم صارلك ٣ أيام 👏🏼' : lead,
          reason: '${b.day}',
        );
      }
    });

    test('praises weekday habits in times, and a mix of cadences not at all',
        () async {
      await arm(firstWeekdays: everyWeekday, secondWeekdays: everyWeekday);
      final weekdays = bundles();
      expect(weekdays.map((b) => b.day), contains(dayAfterToday(1)));
      for (final b in weekdays) {
        expect(
          b.body,
          praisedDay(b.day) ? '$lead ملتزم ٣ مرات ورا بعض 👏🏼' : lead,
          reason: '${b.day}',
        );
      }

      notificationCalls.clear();
      await arm(firstWeekdays: everyWeekday);
      final mixed = bundles();
      expect(mixed.map((b) => b.day), contains(dayAfterToday(1)));
      for (final b in mixed) {
        expect(b.body, lead, reason: '${b.day}');
      }
    });
  });

  /// A Friday at least a week after the real clock, at [hour]:[minute] in
  /// Bahrain. The plugin refuses a one-shot dated before the real clock, so
  /// a fixed calendar date here would start failing once it had passed.
  tz.TZDateTime fridayAhead(int hour, [int minute = 0]) {
    final real = tz.TZDateTime.now(tz.local);
    var day = DateTime(real.year, real.month, real.day + 7);
    while (day.weekday != DateTime.friday) {
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return tz.TZDateTime(tz.local, day.year, day.month, day.day, hour, minute);
  }

  /// The arguments of every zonedSchedule call under [id].
  List<Map> armedUnder(int id) => [
        for (final call in notificationCalls)
          if (call.method == 'zonedSchedule' &&
              (call.arguments as Map)['id'] == id)
            call.arguments as Map,
      ];

  List<int> cancelled() => [
        for (final call in notificationCalls)
          if (call.method == 'cancel') call.arguments as int,
      ];

  /// When a scheduled notification fires, on the wall clock in Bahrain.
  DateTime firesAt(Map args) {
    final at =
        tz.TZDateTime.parse(tz.local, args['scheduledDateTime'] as String);
    return DateTime(at.year, at.month, at.day, at.hour, at.minute);
  }

  group('the evening streak note, where it is armed', () {
    Future<void> recompute({required bool earned, required DateTime now}) =>
        NotificationService.instance.scheduleStreakRiskCheck(
          settings: settings,
          streak: 7,
          streakEarnedToday: earned,
          doneHabitCount: 2,
          pendingHabitCount: 3,
          pendingBuildHabitCount: 3,
          urgentMatrixCount: 0,
          isAr: true,
          now: now,
        );

    test('with the point still open, armed once for 20:30 tonight', () async {
      final sixPm = fridayAhead(18);
      await recompute(earned: false, now: sixPm);
      final note = armedUnder(8000).single;
      expect(note['title'], 'سلسلتك ماشية ٧ أيام');
      expect(note['body'], '٢ من ٥ خلّصت 👏🏼 سوي عادتين بس، وتصير ٨ أيام.');
      expect(
        firesAt(note),
        DateTime(sixPm.year, sixPm.month, sixPm.day, 20, 30),
      );
      expect(note.containsKey('matchDateTimeComponents'), isFalse);
    });

    test("once today's point is earned, the note waiting is cleared",
        () async {
      final sixPm = fridayAhead(18);
      await recompute(earned: false, now: sixPm);
      expect(pending, contains(8000));
      notificationCalls.clear();
      await recompute(earned: true, now: sixPm);
      expect(armedUnder(8000), isEmpty);
      expect(
        cancelled(),
        contains(8000),
        reason: 'a note armed before the point landed must not go out',
      );
    });

    // Quiet hours are not the note being switched off: the window can be
    // edited, or start covering 20:30, after tonight's note has gone out.
    test('quiet hours over 20:30: one waiting is cleared, a delivered one '
        'stays', () async {
      const quiet = NotificationSettings(
        quietHoursEnabled: true,
        quietHoursStart: TimeOfDay(hour: 20, minute: 0),
        quietHoursEnd: TimeOfDay(hour: 7, minute: 0),
        location: _manama,
        resolvedCountryCode: 'BH',
      );
      Future<void> recomputeQuiet(DateTime now) =>
          NotificationService.instance.scheduleStreakRiskCheck(
            settings: quiet,
            streak: 7,
            streakEarnedToday: false,
            doneHabitCount: 2,
            pendingHabitCount: 3,
            pendingBuildHabitCount: 3,
            urgentMatrixCount: 0,
            isAr: true,
            now: now,
          );

      final sixPm = fridayAhead(18);
      await recompute(earned: false, now: sixPm);
      expect(pending, contains(8000));
      notificationCalls.clear();
      await recomputeQuiet(sixPm);
      expect(armedUnder(8000), isEmpty);
      expect(
        cancelled(),
        contains(8000),
        reason: 'quiet hours now cover 20:30 and it had not gone out yet',
      );

      // The same window edited after the note went out at 20:30.
      await recompute(earned: false, now: sixPm);
      pending.remove(8000);
      notificationCalls.clear();
      await recomputeQuiet(fridayAhead(21));
      expect(
        cancelled(),
        isNot(contains(8000)),
        reason: 'a delivered note was true when it came and stays on the list',
      );
    });

    test('after 20:30: never armed for tomorrow, and a delivered note stays',
        () async {
      await recompute(earned: false, now: fridayAhead(18));
      expect(pending, contains(8000));
      // 20:30 came and went: the note is delivered, so it is not pending.
      pending.remove(8000);
      notificationCalls.clear();
      await recompute(earned: false, now: fridayAhead(21));
      expect(
        armedUnder(8000),
        isEmpty,
        reason: "tomorrow's note must not carry today's counts",
      );
      expect(
        cancelled(),
        isNot(contains(8000)),
        reason: 'it went out at 20:30, and the plugin cancel would take it '
            'off the notification list as well',
      );

      // The same recompute, with the note somehow still waiting, clears it.
      pending.add(8000);
      notificationCalls.clear();
      await recompute(earned: false, now: fridayAhead(21));
      expect(cancelled(), contains(8000));
    });
  });

  group('the Friday note, where it is armed', () {
    const top = (name: 'أذكار الصباح', greenDays: 5, isQuit: false);
    final repeat = weeklyRepeatCopy(longestStreak: 14, isAr: true);

    Future<void> recompute(DateTime now) =>
        NotificationService.instance.scheduleWeeklyDigest(
          settings: settings,
          topHabit: top,
          longestStreak: 14,
          isAr: true,
          now: now,
        );

    test('Friday before 19:00: this week counted once, and no weekly repeat',
        () async {
      final friday = fridayAhead(15);
      // A repeat left armed by a recompute on an earlier week. It is
      // PENDING, which is what makes clearing it observable at all now that
      // the whole plan clears pending ids only: an id the OS is not holding
      // has nothing to clear.
      pending.add(9000);
      await recompute(friday);

      final numbered = armedUnder(9001).single;
      expect(numbered['title'], 'أذكار الصباح');
      expect(
        numbered['body'],
        '٥ أيام خضرا هذا الأسبوع 👏🏼 والليلة تختم الأسبوع.',
      );
      expect(
        firesAt(numbered),
        DateTime(friday.year, friday.month, friday.day, 19),
      );
      expect(
        numbered.containsKey('matchDateTimeComponents'),
        isFalse,
        reason: "a repeat would say this week's count every Friday after",
      );

      for (var k = 0; k < NotificationService.kWeeklyRepeatFridaysAhead; k++) {
        final ahead = armedUnder(9002 + k).single;
        expect(ahead['title'], repeat.title);
        expect(ahead['body'], repeat.body);
        expect(
          firesAt(ahead),
          DateTime(friday.year, friday.month, friday.day + 7 * (k + 1), 19),
        );
        expect(ahead.containsKey('matchDateTimeComponents'), isFalse);
      }
      // A weekly repeat armed now would also fire tonight, on iOS and
      // Android alike (see weeklyNotePlan), so the one that was armed is
      // cleared. A repeat is pending for as long as it is armed, so the
      // pending read never spares it.
      expect(armedUnder(9000), isEmpty);
      expect(cancelled(), contains(9000));
      // And the whole note is two requests on this afternoon, not five.
      expect(NotificationService.kWeeklyRepeatFridaysAhead, 1);
      expect(armedUnder(9003), isEmpty);
      expect(
        pending.where((id) => id >= 9000 && id < 9010).toSet(),
        {9001, 9002},
      );
    });

    test('Friday after 19:00: only the claim-free weekly repeat', () async {
      final friday = fridayAhead(19, 30);
      // This afternoon's recompute armed both one-shots, and 19:00 has
      // since delivered the numbered one, so it is no longer pending.
      await recompute(fridayAhead(15));
      pending.remove(9001);
      notificationCalls.clear();
      await recompute(friday);

      final weekly = armedUnder(9000).single;
      expect(weekly['title'], 'أسبوع جديد باجر');
      expect(
        weekly['body'],
        'سبق ووصلت ١٤ يوم ورا بعض 👏🏼 ومربع واحد يفتح الأسبوع.',
      );
      expect(
        weekly['matchDateTimeComponents'],
        DateTimeComponents.dayOfWeekAndTime.index,
      );
      expect(
        firesAt(weekly),
        DateTime(friday.year, friday.month, friday.day + 7, 19),
      );
      expect(armedUnder(9001), isEmpty);
      expect(
        cancelled(),
        isNot(contains(9001)),
        reason: 'delivered at 19:00, and clearing it would take it out of '
            'the notification list',
      );
      expect(
        cancelled().where((id) => id >= 9000 && id < 9010).toSet(),
        {9002},
        reason: 'the claim-free one-shot behind it was still waiting, and '
            'two copies must not be armed for one 19:00',
      );
    });

    test('a claim-free one-shot already delivered is left where it is',
        () async {
      // The case 9002 exists for: a phone left closed for a week. This
      // afternoon armed both one-shots, 19:00 delivered the numbered one,
      // and the Friday after delivered 9002 with the app never opened in
      // between, so neither is pending any more.
      await recompute(fridayAhead(15));
      pending..remove(9001)..remove(9002);
      notificationCalls.clear();
      await recompute(fridayAhead(19, 30));

      expect(
        cancelled().where((id) => id >= 9000 && id < 9010).toSet(),
        isEmpty,
        reason: 'delivered, and the plugin cancel would take «أسبوع جديد '
            'باجر» off the notification list on the next app open',
      );
      // The weekly repeat still goes back up, which is the whole point of
      // this recompute.
      expect(armedUnder(9000).single['body'], repeat.body);
    });

    test('switched off, every id the note can hold is cleared', () async {
      await NotificationService.instance.scheduleWeeklyDigest(
        settings: settings.copyWith(weeklyDigestEnabled: false),
        topHabit: top,
        longestStreak: 14,
        isAr: true,
        now: fridayAhead(15),
      );
      expect(
        cancelled().where((id) => id >= 9000 && id < 9010).toSet(),
        {9000, 9001, 9002},
        reason: 'exactly the ids weeklyNotePlan can arm, and no id it cannot',
      );
    });

    test('a Grid pinned to another week, and back, leaves one copy tonight',
        () async {
      final friday = fridayAhead(15);
      Iterable<int> armedNoteIds() =>
          pending.where((id) => id >= 9000 && id < 9010).toSet();

      // On this week: tonight's numbered copy, plus next Friday's.
      await recompute(friday);
      expect(armedNoteIds(), {9001, 9002});

      // Paged back to a past week. This week's squares are not in hand, so
      // the claim-free repeat takes over and the numbered copy goes rather
      // than firing at 19:00 with a count nothing can vouch for.
      notificationCalls.clear();
      await NotificationService.instance.scheduleWeeklyDigest(
        settings: settings,
        topHabit: null,
        longestStreak: 14,
        isAr: true,
        now: friday,
      );
      expect(armedNoteIds(), {9000});
      expect(armedUnder(9000).single['body'], repeat.body);
      expect(cancelled(), containsAll([9001, 9002]));

      // Back on this week before 19:00: the numbered copy again, with
      // nothing left over to fire beside it.
      notificationCalls.clear();
      await recompute(friday);
      expect(armedNoteIds(), {9001, 9002});
      expect(
        armedUnder(9001).single['body'],
        '٥ أيام خضرا هذا الأسبوع 👏🏼 والليلة تختم الأسبوع.',
      );
      expect(cancelled(), contains(9000));
    });
  });

  group("the daily reminder's own line", () {
    // Nothing is owed once the whole board is done, so there is no line to
    // arm tonight (dailyReminderLine returns null at done == total) and
    // scheduleDailyReminder takes its clearing path. The same path covers
    // the reminder's time having passed and no state ever being reported.
    Future<void> recomputeWithNothingOwed() =>
        NotificationService.instance.scheduleDailyReminder(
          hour: 20,
          isAr: true,
          done: 5,
          total: 5,
          streak: 7,
        );

    test("tonight's line is cleared while waiting, and left once delivered",
        () async {
      // Armed earlier this evening, when something was still owed.
      pending.add(1010);
      await recomputeWithNothingOwed();
      expect(
        cancelled(),
        contains(1010),
        reason: 'a line counting «٢ من ٥ خلّصت» must not fire once the '
            'board is finished',
      );

      // 20:00 came and went: the line is delivered, so it is not pending.
      pending.remove(1010);
      notificationCalls.clear();
      await recomputeWithNothingOwed();
      expect(
        cancelled(),
        isNot(contains(1010)),
        reason: 'it was true when it came, and the plugin cancel would take '
            'it off the notification list',
      );
    });
  });
}
