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
  // Stamped when isDone flips to true, cleared when restored — lets
  // Completed history sort by "most recently finished" instead of by
  // creation order, which is what actually matters when looking back at
  // what you got done.
  final DateTime? completedAt;
  // User-set flag: "this one matters to me", independent of quadrant and
  // never date-scoped — it stays flagged until you clear it yourself, same
  // as any other favorite/priority marker. Powers the Fav/All filter on
  // the Tasks screen (see MatrixScreen._favOnly). For the separate,
  // actually date-based "still open from before today" filter, see
  // MatrixScreen._carriedOverOnly, which is computed from createdAt +
  // isDone instead — this field has nothing to do with that one. Stored
  // under the Firestore/Hive key 'isToday' still, for backward
  // compatibility with tasks flagged before this field was renamed — only
  // the Dart-side name changed, not the wire format.
  final bool isFav;
  // True once XP/gold has ever been paid out for this task. Completing it
  // pays out the first time isDone flips to true; un-completing it does NOT
  // clear this flag and does NOT claw the reward back, so toggling a task
  // done/undone/done can't be used to farm repeat payouts, and finishing a
  // task never feels like it can be "taken away" again later.
  final bool rewarded;
  // Free-text notes — set either at creation (AddTaskSheet's optional "Add
  // details" section) or afterward (the pencil icon's TaskDetailSheet).
  // Unlike voiceNotePath, this is not premium-gated: every competitor task
  // app treats a plain notes field as table stakes, not an upsell.
  final String? description;
  // Local path to a recorded voice note attached to this task, if any — see
  // VoiceNoteService. Deliberately a device-local file path, not a Firebase
  // Storage URL: the audio never leaves the device, so it won't follow a
  // signed-in user to a second device, but it also means no upload step, no
  // Storage bucket/rules to configure, and no privacy question about where
  // the recording is sent. Premium-gated (see voice_note_gate.dart).
  final String? voiceNotePath;
  // Recorded length, seconds — stored alongside the path so the task row
  // can show a duration without opening/decoding the audio file just to
  // read it.
  final int? voiceNoteDurationSeconds;
  // Manual sort rank within a quadrant — a plain double, not an int index,
  // so dragging a task between two others (see MatrixNotifier.reorder) can
  // just average its new neighbors' order values without ever having to
  // rewrite every other task's rank. Higher sorts later. Defaults to a
  // timestamp (see the factories below), so a board nobody has ever
  // manually reordered still reads in creation order, same as before this
  // field existed.
  final double order;

  const MatrixTask({
    required this.id,
    required this.title,
    required this.quadrant,
    required this.isDone,
    required this.createdAt,
    this.completedAt,
    this.isFav = false,
    this.rewarded = false,
    this.description,
    this.voiceNotePath,
    this.voiceNoteDurationSeconds,
    required this.order,
  });

  factory MatrixTask.create(
    String title,
    MatrixQuadrant quadrant, {
    String? description,
    String? voiceNotePath,
    int? voiceNoteDurationSeconds,
  }) =>
      MatrixTask(
        id: const Uuid().v4(),
        title: title.trim(),
        quadrant: quadrant,
        isDone: false,
        createdAt: DateTime.now(),
        description: description,
        voiceNotePath: voiceNotePath,
        voiceNoteDurationSeconds: voiceNoteDurationSeconds,
        order: DateTime.now().millisecondsSinceEpoch.toDouble(),
      );

  factory MatrixTask.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data()!;
    final createdAt =
        (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    return MatrixTask(
      id: doc.id,
      title: d['title'] as String,
      quadrant: MatrixQuadrant.values.firstWhere(
        (q) => q.name == d['quadrant'],
        orElse: () => MatrixQuadrant.doFirst,
      ),
      isDone: d['isDone'] as bool? ?? false,
      createdAt: createdAt,
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
      // Both default false for tasks written before these fields existed —
      // an old task is neither flagged as a favorite nor already rewarded.
      // Key stays 'isToday' on the wire — see the field doc on isFav.
      isFav: d['isToday'] as bool? ?? false,
      rewarded: d['rewarded'] as bool? ?? false,
      description: d['description'] as String?,
      voiceNotePath: d['voiceNotePath'] as String?,
      voiceNoteDurationSeconds: (d['voiceNoteDurationSeconds'] as num?)?.toInt(),
      // A task written before `order` existed falls back to its creation
      // time, so an untouched board still reads in the same order it
      // always has.
      order: (d['order'] as num?)?.toDouble() ??
          createdAt.millisecondsSinceEpoch.toDouble(),
    );
  }

  /// Plain-map (de)serialization for the guest's local Hive store — no
  /// Firestore Timestamp involved, so createdAt is a plain ISO-8601 string.
  factory MatrixTask.fromMap(Map<String, dynamic> d) {
    final createdAt = DateTime.tryParse(d['createdAt'] as String? ?? '') ??
        DateTime.now();
    return MatrixTask(
      id: d['id'] as String? ?? const Uuid().v4(),
      title: d['title'] as String? ?? '',
      quadrant: MatrixQuadrant.values.firstWhere(
        (q) => q.name == d['quadrant'],
        orElse: () => MatrixQuadrant.doFirst,
      ),
      isDone: d['isDone'] as bool? ?? false,
      createdAt: createdAt,
      completedAt: d['completedAt'] == null
          ? null
          : DateTime.tryParse(d['completedAt'] as String),
      isFav: d['isToday'] as bool? ?? false,
      rewarded: d['rewarded'] as bool? ?? false,
      description: d['description'] as String?,
      voiceNotePath: d['voiceNotePath'] as String?,
      voiceNoteDurationSeconds: (d['voiceNoteDurationSeconds'] as num?)?.toInt(),
      order: (d['order'] as num?)?.toDouble() ??
          createdAt.millisecondsSinceEpoch.toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'quadrant': quadrant.name,
        'isDone': isDone,
        'createdAt': createdAt.toIso8601String(),
        if (completedAt != null)
          'completedAt': completedAt!.toIso8601String(),
        'isToday': isFav, // key unchanged on the wire — see isFav's doc
        'rewarded': rewarded,
        if (description != null) 'description': description,
        if (voiceNotePath != null) 'voiceNotePath': voiceNotePath,
        if (voiceNoteDurationSeconds != null)
          'voiceNoteDurationSeconds': voiceNoteDurationSeconds,
        'order': order,
      };

  // `_persist` always writes with SetOptions(merge: true), so any field that
  // can go from "set" back to "cleared" (completedAt on restore; now also
  // description/voiceNotePath/voiceNoteDurationSeconds via
  // MatrixNotifier.updateDetails) needs FieldValue.delete() here — simply
  // omitting the key from a merge-set leaves the old value sitting in
  // Firestore forever instead of actually clearing it.
  Map<String, dynamic> toFirestore() => {
        'title': title,
        'quadrant': quadrant.name,
        'isDone': isDone,
        'createdAt': Timestamp.fromDate(createdAt),
        'completedAt': completedAt != null
            ? Timestamp.fromDate(completedAt!)
            : FieldValue.delete(),
        'isToday': isFav, // key unchanged on the wire — see isFav's doc
        'rewarded': rewarded,
        'description': description ?? FieldValue.delete(),
        'voiceNotePath': voiceNotePath ?? FieldValue.delete(),
        'voiceNoteDurationSeconds':
            voiceNoteDurationSeconds ?? FieldValue.delete(),
        'order': order,
      };

  MatrixTask copyWith({
    String? title,
    MatrixQuadrant? quadrant,
    bool? isDone,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    bool? isFav,
    bool? rewarded,
    String? description,
    bool clearDescription = false,
    String? voiceNotePath,
    int? voiceNoteDurationSeconds,
    bool clearVoiceNote = false,
    double? order,
  }) =>
      MatrixTask(
        id: id,
        title: title ?? this.title,
        quadrant: quadrant ?? this.quadrant,
        isDone: isDone ?? this.isDone,
        createdAt: createdAt,
        completedAt: clearCompletedAt
            ? null
            : completedAt ?? this.completedAt,
        isFav: isFav ?? this.isFav,
        rewarded: rewarded ?? this.rewarded,
        description:
            clearDescription ? null : description ?? this.description,
        voiceNotePath:
            clearVoiceNote ? null : voiceNotePath ?? this.voiceNotePath,
        voiceNoteDurationSeconds: clearVoiceNote
            ? null
            : voiceNoteDurationSeconds ?? this.voiceNoteDurationSeconds,
        order: order ?? this.order,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MatrixTask && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
