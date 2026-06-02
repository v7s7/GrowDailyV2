import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/extensions/datetime_ext.dart';

/// Stored at: users/{uid}/daily/{YYYY-MM-DD}
///
/// One document per day per user. Designed for high-frequency writes
/// (each habit tap is a single field increment via FieldValue.increment).
/// Never grows unbounded — max fields = number of equipped habits.
class DailyLogModel {
  final String dateKey; // 'YYYY-MM-DD' — also the Firestore document ID
  final String uid;
  final DateTime date;

  // habitId → completion count for this day
  final Map<String, int> habitCompletions;

  // habitId → accumulated timer seconds for timed habits
  final Map<String, int> timerSeconds;

  // Rolling summary — updated on every write
  final int totalXpEarned;
  final int totalGoldEarned;

  final DateTime? lastUpdated;

  const DailyLogModel({
    required this.dateKey,
    required this.uid,
    required this.date,
    required this.habitCompletions,
    required this.timerSeconds,
    required this.totalXpEarned,
    required this.totalGoldEarned,
    this.lastUpdated,
  });

  // ── Computed ─────────────────────────────────────────────────

  String get firestorePath => 'users/$uid/daily/$dateKey';

  bool get hasAnyCompletion =>
      habitCompletions.values.any((count) => count > 0);

  int completionsForHabit(String habitId) =>
      habitCompletions[habitId] ?? 0;

  int timerSecondsForHabit(String habitId) =>
      timerSeconds[habitId] ?? 0;

  // ── Constructors ─────────────────────────────────────────────

  factory DailyLogModel.empty(String uid, DateTime date) => DailyLogModel(
        dateKey: date.toDateKey(),
        uid: uid,
        date: date.startOfDay,
        habitCompletions: const {},
        timerSeconds: const {},
        totalXpEarned: 0,
        totalGoldEarned: 0,
      );

  factory DailyLogModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String uid,
  ) {
    final d = doc.data()!;
    return DailyLogModel(
      dateKey: doc.id,
      uid: uid,
      date: DateTime.parse(doc.id),
      habitCompletions: Map<String, int>.from(
        d['habitCompletions'] as Map? ?? {},
      ),
      timerSeconds: Map<String, int>.from(
        d['timerSeconds'] as Map? ?? {},
      ),
      totalXpEarned: d['totalXpEarned'] as int? ?? 0,
      totalGoldEarned: d['totalGoldEarned'] as int? ?? 0,
      lastUpdated: (d['lastUpdated'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'habitCompletions': habitCompletions,
        'timerSeconds': timerSeconds,
        'totalXpEarned': totalXpEarned,
        'totalGoldEarned': totalGoldEarned,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

  /// Returns an update map suitable for Firestore `update()` call when
  /// a user taps a habit — uses atomic increments to avoid race conditions.
  static Map<String, dynamic> habitIncrementUpdate({
    required String habitId,
    required int xpDelta,
    required int goldDelta,
    int timerSecondsDelta = 0,
  }) =>
      {
        'habitCompletions.$habitId': FieldValue.increment(1),
        'totalXpEarned': FieldValue.increment(xpDelta),
        'totalGoldEarned': FieldValue.increment(goldDelta),
        if (timerSecondsDelta > 0)
          'timerSeconds.$habitId': FieldValue.increment(timerSecondsDelta),
        'lastUpdated': FieldValue.serverTimestamp(),
      };

  DailyLogModel copyWith({
    Map<String, int>? habitCompletions,
    Map<String, int>? timerSeconds,
    int? totalXpEarned,
    int? totalGoldEarned,
    DateTime? lastUpdated,
  }) =>
      DailyLogModel(
        dateKey: dateKey,
        uid: uid,
        date: date,
        habitCompletions: habitCompletions ?? this.habitCompletions,
        timerSeconds: timerSeconds ?? this.timerSeconds,
        totalXpEarned: totalXpEarned ?? this.totalXpEarned,
        totalGoldEarned: totalGoldEarned ?? this.totalGoldEarned,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyLogModel &&
          runtimeType == other.runtimeType &&
          uid == other.uid &&
          dateKey == other.dateKey;

  @override
  int get hashCode => uid.hashCode ^ dateKey.hashCode;

  @override
  String toString() =>
      'DailyLogModel($dateKey, xp: $totalXpEarned, completions: ${habitCompletions.length})';
}
