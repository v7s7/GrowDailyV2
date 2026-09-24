// Which reminders the last reminder pass armed for each habit, filed under
// the day each one fires on, and the rule the two Done paths outside the app
// read it by: the Home Screen widget's checkmark (MarkHabitDoneIntent in
// GrowDailyWidget.swift, which reads the same JSON in
// HabitReminderStandDown.swift) and a lock screen or Watch «تمت»
// (notification_action_background.dart).
//
// Neither path can work the ids out for itself. An id is a hash of the habit
// id folded into a band (NotificationService._habitReminderId), which Swift
// cannot reproduce, and which id holds a given day's copy depends on when
// the last pass ran: today's copy is depth 0 when the pass ran this morning,
// depth 1 when it ran yesterday before yesterday's reminder, depth 2 when it
// ran the day before that. Guessing depth 0, which the lock screen path used
// to do, missed today's copy in the second case and took TOMORROW's when the
// pass had run after today's reminder. The pass is the one place that knows,
// so it writes down every copy it armed with its day, and a tap reads back
// the ones for the day it is made on, whatever day the pass ran.
//
// Pure, so the shape and the rule are pinned in
// test/core/armed_reminder_record_test.dart. HomeWidgetService owns the App
// Group key; NotificationService writes the record at the end of every pass.
import 'dart:convert';

import '../extensions/datetime_ext.dart';

/// How one armed copy reaches the person: a notification, or an AlarmKit
/// alarm under the same integer id (see AlarmService). The two are taken
/// down by different calls, so the record keeps them apart.
enum ArmedReminderKind { notification, alarm }

/// One copy of one habit's own reminder, as the pass armed it.
typedef ArmedHabitCopy = ({
  String habitId,
  int id,
  DateTime fireTime,
  ArmedReminderKind kind,
});

/// One combined notification for several habits due within minutes of each
/// other («عادتان جاهزتان»), as the pass armed it.
typedef ArmedBundle = ({int id, DateTime fireTime, List<String> habitIds});

/// What a finishing tap takes down: pending notification requests by id,
/// and alarms by the same integer ids.
typedef ReminderStandDown = ({Set<int> notifications, Set<int> alarms});

abstract final class ArmedReminderRecord {
  /// Raised whenever the shape changes. A reader that meets another version
  /// treats it as no record at all, the same as before the first pass.
  static const int version = 1;

  /// The record for one finished pass.
  ///
  /// [snoozeIds] names the id a snooze of each habit would sit under (see
  /// NotificationService.snoozeHabitReminder), for every habit the pass
  /// covered, including those with nothing armed: a snooze is armed outside
  /// the pass, so the pass cannot know whether one is waiting, and the
  /// widget cannot compute the id.
  ///
  /// Days are effective days (DateTimeGameExt.effectiveDay), the rule the
  /// pass itself uses to decide which copies a completion stands down, and
  /// the day a lock screen tap is queued under. Empty lists are left out,
  /// so an account with a dozen habits stays a few kilobytes.
  static String encode({
    required Iterable<ArmedHabitCopy> copies,
    required Iterable<ArmedBundle> bundles,
    required Map<String, int> snoozeIds,
  }) {
    final habits = <String, _HabitEntry>{
      for (final e in snoozeIds.entries) e.key: _HabitEntry(snooze: e.value),
    };
    _DayEntry dayOf(String habitId, DateTime fireTime) => habits
        .putIfAbsent(habitId, _HabitEntry.new)
        .days
        .putIfAbsent(fireTime.effectiveDay.toDateKey(), _DayEntry.new);
    for (final c in copies) {
      final day = dayOf(c.habitId, c.fireTime);
      (c.kind == ArmedReminderKind.alarm ? day.alarms : day.notifications)
          .add(c.id);
    }
    final members = <String, List<String>>{};
    for (final b in bundles) {
      members['${b.id}'] = [...b.habitIds];
      for (final habitId in b.habitIds.toSet()) {
        dayOf(habitId, b.fireTime).bundles.add(b.id);
      }
    }
    return jsonEncode({
      'v': version,
      'habits': {
        for (final e in habits.entries) e.key: e.value.toJson(),
      },
      if (members.isNotEmpty) 'bundles': members,
    });
  }

  /// What a tap that finishes [habitId] for the day [day] (a 'YYYY-MM-DD'
  /// effective day) takes down, read from [json]; null when there is no
  /// record to read (never written, unreadable, or another version), which
  /// the caller answers with its own fallback.
  ///
  /// - The habit's own copies filed under [day]. Only that day's: the copies
  ///   for the days after it are that habit's next reminders, and a phone
  ///   left closed after the tap still has them.
  /// - A pending snooze of the habit, which the person asked for about a
  ///   reminder of a habit they have now finished.
  /// - A bundle filed under [day], only once every OTHER habit in it is in
  ///   [doneOnDay]. A bundle is one notification for all of its habits:
  ///   taking it down for one finished habit would silence the reminder of
  ///   another that is still owed, and a stale name in a list is the smaller
  ///   harm. [doneOnDay] must be KNOWN done on [day]; a habit whose state is
  ///   unknown keeps its bundle.
  ///
  /// Whether an id is still pending is for the caller to check: the record
  /// says what the pass armed, not what has fired since.
  static ReminderStandDown? standDownFor(
    String? json, {
    required String habitId,
    required String day,
    required Set<String> doneOnDay,
  }) {
    final record = _decode(json);
    if (record == null) return null;
    final habit = _asMap(_asMap(record['habits'])?[habitId]);
    final today = _asMap(_asMap(habit?['days'])?[day]);
    final notifications = <int>{..._ints(today?['notifications'])};
    final snooze = habit?['snooze'];
    if (snooze is int) notifications.add(snooze);
    final bundleMembers = _asMap(record['bundles']);
    for (final bundleId in _ints(today?['bundles'])) {
      final members = bundleMembers?['$bundleId'];
      if (members is! List) continue;
      final othersDone = members.every(
        (m) => m == habitId || (m is String && doneOnDay.contains(m)),
      );
      if (othersDone) notifications.add(bundleId);
    }
    return (
      notifications: notifications,
      alarms: <int>{..._ints(today?['alarms'])},
    );
  }

  static Map<String, Object?>? _decode(String? json) {
    if (json == null || json.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return null;
    }
    final record = _asMap(decoded);
    if (record == null || record['v'] != version) return null;
    return record;
  }

  static Map<String, Object?>? _asMap(Object? value) =>
      value is Map ? value.cast<String, Object?>() : null;

  static Iterable<int> _ints(Object? value) =>
      value is List ? value.whereType<int>() : const <int>[];
}

class _HabitEntry {
  _HabitEntry({this.snooze});
  final int? snooze;
  final days = <String, _DayEntry>{};

  Map<String, Object?> toJson() => {
        if (snooze != null) 'snooze': snooze,
        if (days.isNotEmpty)
          'days': {for (final e in days.entries) e.key: e.value.toJson()},
      };
}

class _DayEntry {
  final notifications = <int>[];
  final alarms = <int>[];
  final bundles = <int>[];

  Map<String, Object?> toJson() => {
        if (notifications.isNotEmpty) 'notifications': notifications,
        if (alarms.isNotEmpty) 'alarms': alarms,
        if (bundles.isNotEmpty) 'bundles': bundles,
      };
}
