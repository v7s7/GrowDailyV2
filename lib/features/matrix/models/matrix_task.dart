import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

enum MatrixQuadrant {
  doFirst,
  schedule,
  delegate,
  eliminate;

  String get label => switch (this) {
        MatrixQuadrant.doFirst => 'DO FIRST',
        MatrixQuadrant.schedule => 'SCHEDULE',
        MatrixQuadrant.delegate => 'DELEGATE',
        MatrixQuadrant.eliminate => 'ELIMINATE',
      };

  String get subtitle => switch (this) {
        MatrixQuadrant.doFirst => 'Urgent · Important',
        MatrixQuadrant.schedule => 'Important, not urgent',
        MatrixQuadrant.delegate => 'Urgent, not important',
        MatrixQuadrant.eliminate => 'Neither',
      };

  String localLabel(bool isAr) => isAr
      ? switch (this) {
          MatrixQuadrant.doFirst => 'أولاً',
          MatrixQuadrant.schedule => 'جدول',
          MatrixQuadrant.delegate => 'فوّض',
          MatrixQuadrant.eliminate => 'احذف',
        }
      : label;

  String localSubtitle(bool isAr) => isAr
      ? switch (this) {
          MatrixQuadrant.doFirst => 'عاجل · مهم',
          MatrixQuadrant.schedule => 'مهم، غير عاجل',
          MatrixQuadrant.delegate => 'عاجل، غير مهم',
          MatrixQuadrant.eliminate => 'لا عاجل ولا مهم',
        }
      : subtitle;
}

class MatrixTask {
  final String id;
  final String title;
  final MatrixQuadrant quadrant;
  final bool isDone;
  final DateTime createdAt;

  const MatrixTask({
    required this.id,
    required this.title,
    required this.quadrant,
    required this.isDone,
    required this.createdAt,
  });

  factory MatrixTask.create(String title, MatrixQuadrant quadrant) =>
      MatrixTask(
        id: const Uuid().v4(),
        title: title.trim(),
        quadrant: quadrant,
        isDone: false,
        createdAt: DateTime.now(),
      );

  factory MatrixTask.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;
    return MatrixTask(
      id: doc.id,
      title: d['title'] as String,
      quadrant: MatrixQuadrant.values.firstWhere(
        (q) => q.name == (d['quadrant'] as String? ?? 'doFirst'),
        orElse: () => MatrixQuadrant.doFirst,
      ),
      isDone: d['isDone'] as bool? ?? false,
      createdAt:
          (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Plain-map (de)serialization for the guest's local Hive store — no
  /// Firestore Timestamp involved, so createdAt is a plain ISO-8601 string.
  factory MatrixTask.fromMap(Map<String, dynamic> d) => MatrixTask(
        id: d['id'] as String? ?? const Uuid().v4(),
        title: d['title'] as String? ?? '',
        quadrant: MatrixQuadrant.values.firstWhere(
          (q) => q.name == (d['quadrant'] as String? ?? 'doFirst'),
          orElse: () => MatrixQuadrant.doFirst,
        ),
        isDone: d['isDone'] as bool? ?? false,
        createdAt: DateTime.tryParse(d['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'quadrant': quadrant.name,
        'isDone': isDone,
        'createdAt': createdAt.toIso8601String(),
      };

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'quadrant': quadrant.name,
        'isDone': isDone,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  MatrixTask copyWith({
    String? title,
    MatrixQuadrant? quadrant,
    bool? isDone,
  }) =>
      MatrixTask(
        id: id,
        title: title ?? this.title,
        quadrant: quadrant ?? this.quadrant,
        isDone: isDone ?? this.isDone,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MatrixTask && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
