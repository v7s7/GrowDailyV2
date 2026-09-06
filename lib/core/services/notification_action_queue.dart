// The pure half of a background notification action: what gets queued for
// the app, and what the widget's cached today-list should show meanwhile.
// No platform calls live here, so every rule can be pinned in
// test/core/notification_action_queue_test.dart. The isolate that applies
// these rules is notification_action_background.dart.
import 'dart:convert';

/// One action-button tap made while the app was closed, waiting for the
/// app's next open to be turned into a real completion.
///
/// [day] is the effective day the tap was made on (see
/// DateTimeGameExt.effectiveDay), as a 'YYYY-MM-DD' key. It is the whole
/// reason this is a record and not a bare habit id like the widget's
/// pendingWidgetCompletions queue: a reminder tapped at 22:00 and drained at
/// 11:00 the next morning belongs to the evening, and a drain that read the
/// clock instead of this field would credit the morning's habit, which the
/// person has not done.
class QueuedNotificationAction {
  /// One of NotificationService's action ids (mark_done, quit_on_track,
  /// quit_slipped). Snooze is never queued: it acts in the isolate itself.
  final String action;
  final String habitId;
  final String day;

  const QueuedNotificationAction({
    required this.action,
    required this.habitId,
    required this.day,
  });

  Map<String, Object> toJson() =>
      {'action': action, 'habitId': habitId, 'day': day};

  /// Null for anything that is not a complete entry, so one damaged record
  /// costs itself and not the whole queue.
  static QueuedNotificationAction? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final action = raw['action'];
    final habitId = raw['habitId'];
    final day = raw['day'];
    if (action is! String || habitId is! String || day is! String) {
      return null;
    }
    if (action.isEmpty || habitId.isEmpty || day.isEmpty) return null;
    return QueuedNotificationAction(
      action: action,
      habitId: habitId,
      day: day,
    );
  }

  /// [day] as a local midnight, or null for a key nothing can parse. A
  /// bare date parses as LOCAL time, which is what toDateKey produced.
  DateTime? get dayDate {
    final parsed = DateTime.tryParse(day);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  @override
  bool operator ==(Object other) =>
      other is QueuedNotificationAction &&
      other.action == action &&
      other.habitId == habitId &&
      other.day == day;

  @override
  int get hashCode => Object.hash(action, habitId, day);

  @override
  String toString() => 'QueuedNotificationAction($action, $habitId, $day)';
}

/// The decisions the background isolate makes, as pure functions over the
/// JSON strings it reads out of the App Group store.
abstract final class NotificationActionRules {
  /// Oldest entries fall off past this. A queue only grows while the app
  /// stays closed, and anything this deep is weeks of taps on days long
  /// closed, whose squares a later drain would only be back-filling.
  static const int maxQueued = 200;

  static List<QueuedNotificationAction> decodeQueue(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (QueuedNotificationAction.fromJson(e) case final entry?) entry,
    ];
  }

  static String encodeQueue(Iterable<QueuedNotificationAction> queue) =>
      jsonEncode([for (final e in queue) e.toJson()]);

  /// [raw] with [entry] appended, trimmed to [maxQueued] from the front.
  static String appendToQueue(String? raw, QueuedNotificationAction entry) {
    final queue = [...decodeQueue(raw), entry];
    final overflow = queue.length - maxQueued;
    return encodeQueue(overflow > 0 ? queue.sublist(overflow) : queue);
  }

  /// The widget's cached today-list (HomeWidgetService.updateWidgetData's
  /// `todayHabitsJson`) with one more completion recorded for [habitId], or
  /// null when there is nothing to rewrite: no list, an unreadable one, or
  /// a habit that is not in it.
  ///
  /// `done` is what the widget draws. `count` and `perDay` are the finer
  /// truth when present: a habit counted three times a day is not done
  /// after one tap, and the widget should keep showing it open. Both fields
  /// are optional because the widget's own Mark Done button re-encodes the
  /// list through a Swift Codable that only knows id/name/done, so they can
  /// legitimately be missing; without them one tap means done, exactly as
  /// that button has always treated it.
  static String? markOneDone(String? todayHabitsJson, String habitId) {
    final list = _decodeTodayList(todayHabitsJson);
    if (list == null) return null;
    var found = false;
    for (final entry in list) {
      if (entry['id'] != habitId) continue;
      found = true;
      final perDay = entry['perDay'];
      final count = entry['count'];
      if (perDay is int && count is int && perDay > 1) {
        final next = count + 1 > perDay ? perDay : count + 1;
        entry['count'] = next;
        entry['done'] = next >= perDay;
      } else {
        if (perDay is int && count is int) entry['count'] = perDay;
        entry['done'] = true;
      }
    }
    return found ? jsonEncode(list) : null;
  }

  /// Whether one more completion of [habitId] finishes it for the day,
  /// which is when its remaining reminder slots should be stood down so the
  /// person is not reminded about a habit they just marked done.
  ///
  /// True when the answer cannot be known (no list, habit absent, counts
  /// missing): the app's own rule is that a done habit is never nagged
  /// about, and the next app open re-arms whatever is genuinely still owed.
  static bool finishesDay(String? todayHabitsJson, String habitId) {
    final list = _decodeTodayList(todayHabitsJson);
    if (list == null) return true;
    for (final entry in list) {
      if (entry['id'] != habitId) continue;
      final perDay = entry['perDay'];
      final count = entry['count'];
      if (perDay is int && count is int) return count + 1 >= perDay;
      return true;
    }
    return true;
  }

  /// The localized name the app last wrote for [habitId], for a snooze that
  /// has to title its own notification without the habit list.
  static String? habitName(String? todayHabitsJson, String habitId) {
    final list = _decodeTodayList(todayHabitsJson);
    if (list == null) return null;
    for (final entry in list) {
      if (entry['id'] != habitId) continue;
      final name = entry['name'];
      return name is String && name.isNotEmpty ? name : null;
    }
    return null;
  }

  static List<Map<String, Object?>>? _decodeTodayList(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! List) return null;
    final out = <Map<String, Object?>>[];
    for (final e in decoded) {
      if (e is! Map) return null;
      out.add(Map<String, Object?>.from(e));
    }
    return out;
  }
}
