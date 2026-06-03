import 'package:cloud_firestore/cloud_firestore.dart';

class DailyFocusPlan {
  final String dateKey;
  final String topTask;
  final String cue;
  final String action;
  final bool planDone;
  final bool sprintDone;
  final bool reviewDone;
  final int focusSessions;
  final DateTime updatedAt;

  const DailyFocusPlan({
    required this.dateKey,
    this.topTask = '',
    this.cue = '',
    this.action = '',
    this.planDone = false,
    this.sprintDone = false,
    this.reviewDone = false,
    this.focusSessions = 0,
    required this.updatedAt,
  });

  factory DailyFocusPlan.empty(String dateKey) => DailyFocusPlan(
        dateKey: dateKey,
        updatedAt: DateTime.now(),
      );


  factory DailyFocusPlan.fromLocal(String dateKey, Map<String, dynamic> data) =>
      DailyFocusPlan(
        dateKey: dateKey,
        topTask: data['topTask'] as String? ?? '',
        cue: data['cue'] as String? ?? '',
        action: data['action'] as String? ?? '',
        planDone: data['planDone'] as bool? ?? false,
        sprintDone: data['sprintDone'] as bool? ?? false,
        reviewDone: data['reviewDone'] as bool? ?? false,
        focusSessions: data['focusSessions'] as int? ?? 0,
        updatedAt: DateTime.tryParse(data['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toLocal() => {
        'topTask': topTask,
        'cue': cue,
        'action': action,
        'planDone': planDone,
        'sprintDone': sprintDone,
        'reviewDone': reviewDone,
        'focusSessions': focusSessions,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory DailyFocusPlan.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return DailyFocusPlan(
      dateKey: doc.id,
      topTask: data['topTask'] as String? ?? '',
      cue: data['cue'] as String? ?? '',
      action: data['action'] as String? ?? '',
      planDone: data['planDone'] as bool? ?? false,
      sprintDone: data['sprintDone'] as bool? ?? false,
      reviewDone: data['reviewDone'] as bool? ?? false,
      focusSessions: data['focusSessions'] as int? ?? 0,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'topTask': topTask,
        'cue': cue,
        'action': action,
        'planDone': planDone,
        'sprintDone': sprintDone,
        'reviewDone': reviewDone,
        'focusSessions': focusSessions,
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  int get completedSteps => [planDone, sprintDone, reviewDone]
      .where((isComplete) => isComplete)
      .length;

  double get progress => completedSteps / 3;

  bool get hasImplementationIntention =>
      cue.trim().isNotEmpty && action.trim().isNotEmpty;

  DailyFocusPlan copyWith({
    String? topTask,
    String? cue,
    String? action,
    bool? planDone,
    bool? sprintDone,
    bool? reviewDone,
    int? focusSessions,
  }) =>
      DailyFocusPlan(
        dateKey: dateKey,
        topTask: topTask ?? this.topTask,
        cue: cue ?? this.cue,
        action: action ?? this.action,
        planDone: planDone ?? this.planDone,
        sprintDone: sprintDone ?? this.sprintDone,
        reviewDone: reviewDone ?? this.reviewDone,
        focusSessions: focusSessions ?? this.focusSessions,
        updatedAt: DateTime.now(),
      );
}
