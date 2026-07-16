import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/game_theme.dart';

/// One recorded voice note attached to a task. A task can carry any number
/// of these — record a "step1", "step2", etc. for a multi-part task — each
/// independently playable, renameable, and deletable from TaskDetailSheet.
///
/// Dates are stored as plain ISO-8601 strings even on the Firestore path
/// (unlike MatrixTask.createdAt, which uses a native Timestamp) — nested
/// array entries don't need query-able Timestamps the way a top-level field
/// might, so one plain (de)serialization works for both the guest-Hive and
/// signed-in-Firestore backends instead of needing two.
class VoiceNote {
  final String id;
  final String path;
  // Empty string, not null, means "not yet named" — TaskDetailSheet shows
  // a placeholder like "Recording 1" for these rather than an empty label.
  final String name;
  final int durationSeconds;
  final DateTime createdAt;
  // Base64-encoded audio — only set when the recording was small enough to
  // fit this task's sync budget at record time (see
  // VoiceNoteService.encodeForSync). This is what lets a note actually
  // follow a signed-in user to a second device: [path] alone is a
  // device-local file a second device will never have. On playback,
  // VoiceNoteService prefers the local file at [path] when it exists (the
  // recording device, or a device that already downloaded it once) and
  // falls back to decoding this field only when that file is missing. Null
  // for notes that were skipped for being over budget, or recorded before
  // this field existed — both play back fine on the device that recorded
  // them, they just won't be there on a second device.
  final String? audioBase64;

  const VoiceNote({
    required this.id,
    required this.path,
    required this.name,
    required this.durationSeconds,
    required this.createdAt,
    this.audioBase64,
  });

  factory VoiceNote.fromMap(Map<String, dynamic> d) => VoiceNote(
        id: d['id'] as String? ?? const Uuid().v4(),
        path: d['path'] as String? ?? '',
        name: d['name'] as String? ?? '',
        durationSeconds: (d['durationSeconds'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(d['createdAt'] as String? ?? '') ??
            DateTime.now(),
        audioBase64: d['audioBase64'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'path': path,
        'name': name,
        'durationSeconds': durationSeconds,
        'createdAt': createdAt.toIso8601String(),
        if (audioBase64 != null) 'audioBase64': audioBase64,
      };

  VoiceNote copyWith({String? name}) => VoiceNote(
        id: id,
        path: path,
        name: name ?? this.name,
        durationSeconds: durationSeconds,
        createdAt: createdAt,
        audioBase64: audioBase64,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is VoiceNote && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

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

  /// The built-in color for this quadrant — single source of truth, used
  /// as the fallback everywhere a user hasn't set their own custom color
  /// (see MatrixState.colorFor). Previously this exact switch was
  /// duplicated across five separate widget files, which is exactly the
  /// kind of copy that quietly drifts; consolidated here once so every
  /// call site reads the same value by construction.
  Color get defaultColor => switch (this) {
        MatrixQuadrant.doFirst => GameColors.error,
        MatrixQuadrant.schedule => GameColors.iconXp,
        MatrixQuadrant.delegate => GameColors.iconStreak,
        MatrixQuadrant.eliminate => GameColors.textTertiary,
      };
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
  // Recorded voice notes attached to this task — zero, one, or many. See
  // VoiceNoteService/VoiceNote. Deliberately device-local file paths, not
  // Firebase Storage URLs: the audio never leaves the device, so it won't
  // follow a signed-in user to a second device, but it also means no
  // upload step, no Storage bucket/rules to configure, and no privacy
  // question about where the recording is sent. Premium-gated (see
  // voice_note_gate.dart). Replaces the old single voiceNotePath/
  // voiceNoteDurationSeconds pair — see _voiceNotesFromMap for how a task
  // saved under that old format migrates into a one-item list here the
  // first time it's read after this change, with nothing rewritten in
  // storage until the task is next saved.
  final List<VoiceNote> voiceNotes;
  // Exact moment to fire a one-off local notification about this task —
  // set from AddTaskSheet's "Add details" section at creation, or from
  // TaskDetailSheet afterward (see ReminderRow in reminder_picker.dart,
  // shared by both). Unlike a habit's cue (HabitReminderInput.clockTime/
  // prayerKey), this is a plain absolute DateTime, not a recurring daily
  // wall-clock time or prayer link: a task is one thing to do, not a
  // routine, so there's exactly one moment worth firing at, ever. Null
  // (the common case — this sheet defaults to fast, title-only add) means
  // no reminder. Actual scheduling/cancelling through
  // NotificationService.scheduleTaskReminder/cancelTaskReminder is owned
  // entirely by MatrixNotifier, never called from these widgets directly —
  // see MatrixNotifier._syncReminderSchedule for exactly when each happens.
  final DateTime? reminderAt;
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
    this.voiceNotes = const [],
    this.reminderAt,
    required this.order,
  });

  /// [voiceNotes] are already-built VoiceNote instances (id/path/name/
  /// duration all set) by the time this is called — AddTaskSheet now
  /// supports recording and naming several notes before the task even
  /// exists, the same client-generates-the-id pattern TaskDetailSheet uses
  /// for a note added after the fact, so there's nothing left for this
  /// factory to synthesize; it just takes the list as-is.
  factory MatrixTask.create(
    String title,
    MatrixQuadrant quadrant, {
    String? description,
    List<VoiceNote> voiceNotes = const [],
    DateTime? reminderAt,
  }) {
    final now = DateTime.now();
    return MatrixTask(
      id: const Uuid().v4(),
      title: title.trim(),
      quadrant: quadrant,
      isDone: false,
      createdAt: now,
      description: description,
      voiceNotes: voiceNotes,
      reminderAt: reminderAt,
      order: now.millisecondsSinceEpoch.toDouble(),
    );
  }

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
      voiceNotes: _voiceNotesFromMap(d, createdAt),
      reminderAt: (d['reminderAt'] as Timestamp?)?.toDate(),
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
      voiceNotes: _voiceNotesFromMap(d, createdAt),
      reminderAt: d['reminderAt'] == null
          ? null
          : DateTime.tryParse(d['reminderAt'] as String),
      order: (d['order'] as num?)?.toDouble() ??
          createdAt.millisecondsSinceEpoch.toDouble(),
    );
  }

  /// Shared by [fromMap] and [fromFirestore]: reads the current
  /// `voiceNotes` array if present, otherwise migrates an older task's
  /// single `voiceNotePath`/`voiceNoteDurationSeconds` pair into a one-item
  /// list, unnamed. Read-time only — doesn't touch what's actually stored
  /// until this task is next saved, so it's safe to run on every load.
  static List<VoiceNote> _voiceNotesFromMap(
      Map<String, dynamic> d, DateTime fallbackCreatedAt) {
    final raw = d['voiceNotes'];
    if (raw is List) {
      return raw
          .map((m) => VoiceNote.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList();
    }
    final legacyPath = d['voiceNotePath'] as String?;
    if (legacyPath == null) return const [];
    return [
      VoiceNote(
        id: const Uuid().v4(),
        path: legacyPath,
        name: '',
        durationSeconds: (d['voiceNoteDurationSeconds'] as num?)?.toInt() ?? 0,
        createdAt: fallbackCreatedAt,
      ),
    ];
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
        'voiceNotes': voiceNotes.map((n) => n.toMap()).toList(),
        if (reminderAt != null) 'reminderAt': reminderAt!.toIso8601String(),
        'order': order,
      };

  // `_persist` always writes with SetOptions(merge: true), so any field that
  // can go from "set" back to "cleared" (completedAt on restore; description
  // via MatrixNotifier.updateDetails; reminderAt via MatrixNotifier.
  // setReminder) needs FieldValue.delete() here — simply omitting the key
  // from a merge-set leaves the old value sitting in Firestore forever
  // instead of actually clearing it. voiceNotes doesn't need that
  // treatment: writing `[]` already clears an array field outright, no
  // delete sentinel required. The old scalar voiceNotePath/
  // voiceNoteDurationSeconds keys *do* get FieldValue.delete()'d here, so a
  // task saved once under the new format stops carrying the stale pair
  // around forever.
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
        'voiceNotes': voiceNotes.map((n) => n.toMap()).toList(),
        'voiceNotePath': FieldValue.delete(),
        'voiceNoteDurationSeconds': FieldValue.delete(),
        'reminderAt':
            reminderAt != null ? Timestamp.fromDate(reminderAt!) : FieldValue.delete(),
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
    List<VoiceNote>? voiceNotes,
    DateTime? reminderAt,
    bool clearReminderAt = false,
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
        voiceNotes: voiceNotes ?? this.voiceNotes,
        reminderAt: clearReminderAt ? null : reminderAt ?? this.reminderAt,
        order: order ?? this.order,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MatrixTask && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
