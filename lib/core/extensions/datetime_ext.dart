extension DateTimeGameExt on DateTime {
  /// Returns 'YYYY-MM-DD' key used as Firestore document IDs for daily logs.
  String toDateKey() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  bool isSameDayAs(DateTime other) =>
      year == other.year && month == other.month && day == other.day;

  bool get isToday => isSameDayAs(DateTime.now());

  bool get isYesterday =>
      isSameDayAs(DateTime.now().subtract(const Duration(days: 1)));

  /// Returns the start of this day (00:00:00).
  DateTime get startOfDay => DateTime(year, month, day);

  /// Returns the start of the ISO week (Monday) containing this date.
  DateTime get startOfWeek {
    final daysFromMonday = weekday - DateTime.monday;
    return startOfDay.subtract(Duration(days: daysFromMonday));
  }
}
