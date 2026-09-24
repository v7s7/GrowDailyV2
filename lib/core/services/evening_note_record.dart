/// What the evening note's last pass left armed, kept across launches so a
/// later pass can tell whether tonight's note has already gone out.
///
/// Page item 7 (Aziz, 2026-09-24): the note went out at 20:30, the person
/// moved the time to 21:00, and a second note came at 21:00. Every pass
/// re-arms tonight's note for whatever time is set, and nothing knew one
/// had been delivered. A local notification leaves no trace when it fires,
/// so the only way to know is to remember what was armed, and when for.
///
/// Either copy counts: tonight's worded note (1010), or the weekly fallback
/// for today's weekday (1001 to 1007), armed on some earlier day and fired
/// with the app closed. Once either has gone out, today is done: a new time
/// starts tomorrow. Stored in the Hive settings box by NotificationService.
class EveningNoteRecord {
  const EveningNoteRecord({
    required this.armedAt,
    required this.hour,
    required this.minute,
    this.tonightAt,
    this.tonightDay,
    this.fallbackWeekdays = const {},
    this.wentOutOn,
  });

  /// Only that a note went out on [day], with nothing armed.
  EveningNoteRecord.wentOut(String day)
      : this(
          armedAt: DateTime.fromMillisecondsSinceEpoch(0),
          hour: 0,
          minute: 0,
          wentOutOn: day,
        );

  /// Since when this schedule has stood unchanged. A weekly fallback armed
  /// before its minute today has fired at that minute.
  final DateTime armedAt;

  /// The clock time the note and its fallbacks were armed for.
  final int hour;
  final int minute;

  /// Tonight's worded note (1010) and its day ("yyyy-MM-dd", on the clock
  /// that armed it), when one was armed.
  final DateTime? tonightAt;
  final String? tonightDay;

  /// The weekdays (DateTime.monday..sunday) whose weekly fallback is armed.
  final Set<int> fallbackWeekdays;

  /// A day ("yyyy-MM-dd") on which an evening note is known to have gone out.
  final String? wentOutOn;

  /// Whether [other] arms the same notifications, whenever it was armed.
  bool sameScheduleAs(EveningNoteRecord other) =>
      hour == other.hour &&
      minute == other.minute &&
      tonightAt?.millisecondsSinceEpoch ==
          other.tonightAt?.millisecondsSinceEpoch &&
      tonightDay == other.tonightDay &&
      fallbackWeekdays.length == other.fallbackWeekdays.length &&
      fallbackWeekdays.containsAll(other.fallbackWeekdays);

  EveningNoteRecord withArmedAt(DateTime at) => EveningNoteRecord(
        armedAt: at,
        hour: hour,
        minute: minute,
        tonightAt: tonightAt,
        tonightDay: tonightDay,
        fallbackWeekdays: fallbackWeekdays,
        wentOutOn: wentOutOn,
      );

  Map<String, dynamic> toMap() => {
        'armedAt': armedAt.millisecondsSinceEpoch,
        'hour': hour,
        'minute': minute,
        if (tonightAt != null) 'tonightAt': tonightAt!.millisecondsSinceEpoch,
        if (tonightDay != null) 'tonightDay': tonightDay,
        'weekdays': (fallbackWeekdays.toList()..sort()),
        if (wentOutOn != null) 'wentOutOn': wentOutOn,
      };

  /// Null for an empty or unreadable map: nothing is known to have gone out.
  static EveningNoteRecord? fromMap(Map<String, dynamic> map) {
    final armedAt = map['armedAt'];
    final hour = map['hour'];
    final minute = map['minute'];
    if (armedAt is! int || hour is! int || minute is! int) return null;
    final tonightAt = map['tonightAt'];
    final tonightDay = map['tonightDay'];
    final weekdays = map['weekdays'];
    final wentOutOn = map['wentOutOn'];
    return EveningNoteRecord(
      armedAt: DateTime.fromMillisecondsSinceEpoch(armedAt),
      hour: hour,
      minute: minute,
      tonightAt: tonightAt is int
          ? DateTime.fromMillisecondsSinceEpoch(tonightAt)
          : null,
      tonightDay: tonightDay is String ? tonightDay : null,
      fallbackWeekdays: {
        if (weekdays is List)
          for (final w in weekdays)
            if (w is int) w,
      },
      wentOutOn: wentOutOn is String ? wentOutOn : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EveningNoteRecord &&
      sameScheduleAs(other) &&
      armedAt.millisecondsSinceEpoch == other.armedAt.millisecondsSinceEpoch &&
      wentOutOn == other.wentOutOn;

  @override
  int get hashCode => Object.hash(
        armedAt.millisecondsSinceEpoch,
        hour,
        minute,
        tonightAt?.millisecondsSinceEpoch,
        tonightDay,
        Object.hashAllUnordered(fallbackWeekdays),
        wentOutOn,
      );
}

/// [at]'s calendar day as "yyyy-MM-dd", on [at]'s own clock (a TZDateTime
/// reads its zone's fields).
String eveningDayKey(DateTime at) => '${at.year}-'
    '${at.month.toString().padLeft(2, '0')}-'
    '${at.day.toString().padLeft(2, '0')}';

/// Whether an evening note has already gone out on [now]'s day, by what
/// [record] says was armed. See [EveningNoteRecord].
bool eveningNoteWentOut(EveningNoteRecord? record, DateTime now) {
  if (record == null) return false;
  final today = eveningDayKey(now);
  if (record.wentOutOn == today) return true;
  final tonightAt = record.tonightAt;
  if (tonightAt != null &&
      record.tonightDay == today &&
      !tonightAt.isAfter(now)) {
    return true;
  }
  if (record.fallbackWeekdays.contains(now.weekday)) {
    // Today at the armed minute, on [now]'s own clock.
    final fire = now
        .subtract(Duration(
          hours: now.hour,
          minutes: now.minute,
          seconds: now.second,
          milliseconds: now.millisecond,
          microseconds: now.microsecond,
        ))
        .add(Duration(hours: record.hour, minutes: record.minute));
    if (record.armedAt.isBefore(fire) && !fire.isAfter(now)) return true;
  }
  return false;
}
