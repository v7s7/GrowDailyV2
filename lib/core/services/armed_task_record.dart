// Which ids a task's reminders sit under, for the two buttons that finish a
// task from outside the app: the Matrix widget's checkmark
// (MarkTaskDoneIntent in GrowDailyWidget.swift) and «خلّصت المهمة» on a
// ringing task alarm (MarkAlarmTargetDoneIntent). Both read this record
// through TaskReminderStandDown.swift.
//
// A task is simpler than a habit (see armed_reminder_record.dart): its
// reminders are one-shot, so there is no day to file them under and nothing
// to keep for tomorrow. Finishing it takes down every slot it holds, which
// is exactly what NotificationService.cancelTaskReminder does from inside
// the app. The one thing the outside cannot do is name those ids: each is a
// fold of Dart's String.hashCode, which Swift has no way to reproduce. So
// the app writes them down beside the widget's task rows, and the buttons
// read them back.
//
// Pure, so the ids and the shape are pinned in
// test/core/armed_task_record_test.dart. HomeWidgetService owns the App
// Group key and writes this record with the very rows it names, so the two
// can never disagree about which tasks exist.
import 'dart:convert';

import 'armed_reminder_record.dart' show ReminderStandDown;

// 50,000 slots starting well past every other id range in
// NotificationService (the highest fixed id used elsewhere is 9000). Matrix
// tasks are plain UUIDs, not small stable habit ids, and a user can
// accumulate far more of them over time than habits, so this range is
// deliberately much wider than a habit's 1000 slots. A hash collision
// between two tasks' ids just means one's schedule silently overwrites the
// other's, the same accepted trade-off the habit ids already make.
const int _taskReminderBase = 10000;
const int _taskReminderRange = 50000;

/// How many reminder slots a single task can occupy. iOS caps an app at 64
/// *pending* local notifications in total, app-wide, and this app is already
/// spending that budget on habit reminders, streak nudges and quit
/// check-ins. Without a per-task ceiling, one task with a long alarm stack
/// would silently evict other reminders the user cares about more, with no
/// error anywhere: the OS just stops delivering. Eight escalating nudges for
/// one task is already well past what anyone realistically sets, so this
/// bounds the damage while staying invisible in practice.
///
/// Doubles as the cancel bound: NotificationService.cancelTaskReminder
/// sweeps exactly this many slots, and [ArmedTaskRecord] names exactly this
/// many, so a task can never leave an orphaned schedule behind for an index
/// that is no longer in its list. Raising this later is safe; *lowering* it
/// would strand already-scheduled slots above the new value, so don't,
/// without a one-off sweep at the old bound first.
///
/// Read by the rest of the app as NotificationService.kMaxTaskReminderSlots,
/// which is this.
const int kTaskReminderSlots = 8;

/// Notification id for [taskId]'s [index]-th reminder, and the id of the
/// AlarmKit alarm that takes that slot instead when the task rings as an
/// alarm.
///
/// Index 0 deliberately hashes the bare [taskId], producing the exact same
/// id this returned when a task could only have one reminder. That is what
/// lets an install upgrade cleanly: reminders already sitting in the OS
/// queue from a previous build stay addressable, so the first resync after
/// the update replaces them in place instead of leaving a ghost that fires
/// alongside its own replacement. Later indices hash a composite key so each
/// gets its own slot.
///
/// Lives here rather than in NotificationService because the record has to
/// name these ids for a Swift side that cannot fold a Dart hash, and the
/// service's own scheduling calls this same function, so the two can never
/// drift apart.
int taskReminderId(String taskId, [int index = 0]) =>
    _taskReminderBase +
    (index == 0 ? taskId.hashCode : '$taskId#$index'.hashCode).abs() %
        _taskReminderRange;

/// One task the app has reminders armed for, as the widget's rows see it.
///
/// [alarm] mirrors MatrixTask.alarm: the task asked to ring as a real alarm.
/// It is a request, not a fact, since AlarmKit refuses below iOS 26 and
/// without permission, and the app then falls back to a notification under
/// the same id.
typedef ArmedTaskCopy = ({String taskId, bool alarm});

abstract final class ArmedTaskRecord {
  /// Raised whenever the shape changes. A reader that meets another version
  /// treats it as no record at all, the same as before the first write.
  static const int version = 1;

  /// The record for [tasks]: every open task that has at least one reminder
  /// set. A task with none holds no ids and belongs nowhere in here.
  ///
  /// Names every slot a task could be holding rather than only the ones its
  /// current reminder list fills, because that is the sweep
  /// NotificationService.cancelTaskReminder makes: a stack the person
  /// shortened a moment ago, whose resync has not landed yet, still goes
  /// down whole. Naming an id nothing holds costs nothing on either side.
  ///
  /// An alarm-mode task files its ids under both kinds, because which one
  /// the app actually armed is not knowable from here: AlarmKit takes the
  /// slot when it can, and the app writes a plain notification under the
  /// same id when it cannot.
  static String encode(Iterable<ArmedTaskCopy> tasks) => jsonEncode({
        'v': version,
        'tasks': {
          for (final t in tasks)
            t.taskId: {
              'notifications': _slotsOf(t.taskId),
              if (t.alarm) 'alarms': _slotsOf(t.taskId),
            },
        },
      });

  /// What a tap that finishes [taskId] takes down, read from [json]; null
  /// when there is no record to read (never written, unreadable, or another
  /// version), which the caller answers with its own fallback.
  ///
  /// Everything that task holds, with no day and no sharing to reason about:
  /// a task's reminders are moments picked for that one task, so once it is
  /// done not one of them has anything left to say. A task the record does
  /// not name has nothing armed, which is an answer, not a failure: it is
  /// what the record says about a task whose reminders were never set.
  ///
  /// Whether an id is still pending is for the caller to check: the record
  /// says what the app armed, not what has fired since.
  static ReminderStandDown? standDownFor(
    String? json, {
    required String taskId,
  }) {
    if (json == null || json.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return null;
    }
    if (decoded is! Map || decoded['v'] != version) return null;
    final tasks = decoded['tasks'];
    final task = tasks is Map ? tasks[taskId] : null;
    if (task is! Map) {
      return (notifications: const <int>{}, alarms: const <int>{});
    }
    return (
      notifications: <int>{..._ints(task['notifications'])},
      alarms: <int>{..._ints(task['alarms'])},
    );
  }

  static List<int> _slotsOf(String taskId) => [
        for (var i = 0; i < kTaskReminderSlots; i++) taskReminderId(taskId, i),
      ];

  static Iterable<int> _ints(Object? value) =>
      value is List ? value.whereType<int>() : const <int>[];
}
