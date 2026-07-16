import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/l10n/app_strings.dart' show localeProvider;
import '../../../core/services/local_store_service.dart';
import '../../../core/services/notification_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../settings/notifiers/notification_settings_notifier.dart'
    show notificationSettingsProvider;
import '../models/matrix_task.dart';

/// Pure decision logic behind [MatrixNotifier._syncReminderSchedule] — kept
/// as a standalone top-level function, same reasoning as rooms_notifier.
/// dart's nextLeaderAfter: the conditions that gate whether a task's
/// reminder should actually be (re)scheduled right now can then be unit
/// tested directly, without touching Riverpod, NotificationService, or
/// Hive/Firestore at all. [now] defaults to the real clock but is
/// overridable so "is reminderAt still in the future" stays deterministic
/// under test — see test/features/matrix/matrix_reminder_test.dart.
@visibleForTesting
bool shouldScheduleTaskReminder(
  MatrixTask task, {
  required bool masterEnabled,
  DateTime? now,
}) {
  final reminderAt = task.reminderAt;
  return reminderAt != null &&
      !task.isDone &&
      reminderAt.isAfter(now ?? DateTime.now()) &&
      masterEnabled;
}

class MatrixState {
  final List<MatrixTask> tasks;
  final bool isLoading;

  /// quadrant.name → user-chosen title, only present once a quadrant's
  /// been renamed via the Edit Quadrant sheet. Absent means "still the
  /// built-in label" — always read through [titleFor] rather than
  /// indexing this directly, so the fallback is never forgotten.
  final Map<String, String> quadrantTitles;

  /// quadrant.name → user-chosen color, as a 6-digit hex string with no
  /// leading '#' (same convention IslamicHabitTemplate.iconColorHex
  /// already uses). Always read through [colorFor].
  final Map<String, String> quadrantColors;

  const MatrixState({
    this.tasks = const [],
    this.isLoading = true,
    this.quadrantTitles = const {},
    this.quadrantColors = const {},
  });

  /// The label to show for [quadrant] — the user's own title if they've
  /// set one, else the built-in localized label.
  String titleFor(MatrixQuadrant quadrant, bool isAr) =>
      quadrantTitles[quadrant.name] ?? quadrant.localLabel(isAr);

  /// The color to show for [quadrant] — the user's own color if they've
  /// set one, else [MatrixQuadrant.defaultColor]. A malformed stored hex
  /// (shouldn't happen, since the only writer is the picker, but this
  /// reads data that round-tripped through Firestore/Hive) falls back to
  /// the default rather than crashing the whole screen over one bad quadrant.
  Color colorFor(MatrixQuadrant quadrant) {
    final hex = quadrantColors[quadrant.name];
    final parsed = hex == null ? null : int.tryParse(hex, radix: 16);
    return parsed == null ? quadrant.defaultColor : Color(0xFF000000 | parsed);
  }
}

class MatrixNotifier extends StateNotifier<MatrixState> {
  final Ref _ref;
  final String? _uid;

  // A guest can mutate (e.g. tap a one-tap suggestion) before the disk
  // read in _loadGuest resolves — both fire in the same tick right after
  // construction. Without this guard the disk read wins the race and
  // silently wipes out the just-added task.
  bool _mutatedBeforeLoad = false;

  // Same idea as [_mutatedBeforeLoad], kept as its own separate flag
  // rather than reusing that one: editing a quadrant's title/color is a
  // much slower, multi-step interaction (open sheet, type, tap Save) than
  // a single quick-add tap, so this window is far less likely to matter in
  // practice — but sharing one flag would mean a quadrant edit landing
  // before the initial load resolves could block the *task list* load
  // from ever applying, which would be a much worse outcome than the
  // narrow race this actually guards against.
  bool _quadrantsMutatedBeforeLoad = false;

  MatrixNotifier(this._ref, this._uid) : super(const MatrixState()) {
    if (_uid != null) {
      _load();
    } else {
      _loadGuest();
    }
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('matrix_tasks');

  DocumentReference<Map<String, dynamic>> get _userRef =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  (Map<String, String>, Map<String, String>) _readQuadrantSettings(
    Map<String, dynamic> d,
  ) {
    final rawTitles =
        (d['matrixQuadrantTitles'] as Map?)?.cast<String, dynamic>() ?? {};
    final rawColors =
        (d['matrixQuadrantColors'] as Map?)?.cast<String, dynamic>() ?? {};
    return (
      rawTitles.map((k, v) => MapEntry(k, v as String)),
      rawColors.map((k, v) => MapEntry(k, v as String)),
    );
  }

  Future<void> _load() async {
    if (_uid == null) return;
    try {
      // Started together, not one `await`ed after the other, so the two
      // requests actually run concurrently — Future.wait isn't used here
      // since a QuerySnapshot and a DocumentSnapshot aren't the same type.
      final colFuture = _col.get();
      final userFuture = _userRef.get();
      final colSnap = await colFuture;
      final userSnap = await userFuture;

      var quadrantTitles = state.quadrantTitles;
      var quadrantColors = state.quadrantColors;
      if (!_quadrantsMutatedBeforeLoad && userSnap.exists) {
        final settings = _readQuadrantSettings(userSnap.data()!);
        quadrantTitles = settings.$1;
        quadrantColors = settings.$2;
      }

      if (mounted && !_mutatedBeforeLoad) {
        final tasks = colSnap.docs
            .map((d) => MatrixTask.fromFirestore(d))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        state = MatrixState(
          tasks: tasks,
          isLoading: false,
          quadrantTitles: quadrantTitles,
          quadrantColors: quadrantColors,
        );
      } else if (mounted) {
        // Task list load was superseded by a mutation, but the quadrant
        // settings we just read may still be worth keeping.
        state = MatrixState(
          tasks: state.tasks,
          isLoading: false,
          quadrantTitles: quadrantTitles,
          quadrantColors: quadrantColors,
        );
      }
    } catch (_) {
      if (mounted && !_mutatedBeforeLoad) {
        state = MatrixState(
          tasks: state.tasks,
          isLoading: false,
          quadrantTitles: state.quadrantTitles,
          quadrantColors: state.quadrantColors,
        );
      }
    }
  }

  Future<void> _loadGuest() async {
    try {
      final box = await LocalStoreService.settingsBox();
      final raw = LocalStoreService.asMapList(
        box.get(LocalStoreService.guestMatrixTasksKey),
      );

      var quadrantTitles = state.quadrantTitles;
      var quadrantColors = state.quadrantColors;
      if (!_quadrantsMutatedBeforeLoad) {
        final saved = LocalStoreService.asStringMap(
          box.get(LocalStoreService.guestMatrixQuadrantsKey),
        );
        final settings = _readQuadrantSettings(saved);
        quadrantTitles = settings.$1;
        quadrantColors = settings.$2;
      }

      if (!mounted || _mutatedBeforeLoad) {
        if (mounted) {
          state = MatrixState(
            tasks: state.tasks,
            isLoading: false,
            quadrantTitles: quadrantTitles,
            quadrantColors: quadrantColors,
          );
        }
        return;
      }
      final tasks = raw.map(MatrixTask.fromMap).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      state = MatrixState(
        tasks: tasks,
        isLoading: false,
        quadrantTitles: quadrantTitles,
        quadrantColors: quadrantColors,
      );
    } catch (_) {
      if (mounted && !_mutatedBeforeLoad) {
        state = MatrixState(
          tasks: state.tasks,
          isLoading: false,
          quadrantTitles: state.quadrantTitles,
          quadrantColors: state.quadrantColors,
        );
      }
    }
  }

  Future<void> _saveGuest() async {
    final box = await LocalStoreService.settingsBox();
    await box.put(
      LocalStoreService.guestMatrixTasksKey,
      state.tasks.map((t) => t.toMap()).toList(),
    );
  }

  Future<void> _saveGuestQuadrantSettings() async {
    await LocalStoreService.putSettingsMap(
      LocalStoreService.guestMatrixQuadrantsKey,
      {
        'matrixQuadrantTitles': state.quadrantTitles,
        'matrixQuadrantColors': state.quadrantColors,
      },
    );
  }

  void add(
    String title,
    MatrixQuadrant quadrant, {
    String? description,
    List<VoiceNote> voiceNotes = const [],
    DateTime? reminderAt,
  }) {
    if (title.trim().isEmpty) return;
    _mutatedBeforeLoad = true;
    final task = MatrixTask.create(
      title,
      quadrant,
      description: description,
      voiceNotes: voiceNotes,
      reminderAt: reminderAt,
    );
    state = MatrixState(
      tasks: [...state.tasks, task],
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    _persist(task);
    _syncReminderSchedule(task);
  }

  void toggle(String id) {
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final current = tasks[idx];
    final nowDone = !current.isDone;
    // Pay XP/gold the first time this task is ever finished. rewarded stays
    // true forever after, so un-completing and re-completing the same task
    // (or just un-completing it) never pays out again or claws it back —
    // see the field doc on MatrixTask.rewarded for why.
    final firstTimeDone = nowDone && !current.rewarded;
    final updated = current.copyWith(
      isDone: nowDone,
      completedAt: nowDone ? DateTime.now() : null,
      clearCompletedAt: !nowDone,
      rewarded: firstTimeDone ? true : null,
    );
    tasks[idx] = updated;
    state = MatrixState(
      tasks: tasks,
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    _persist(updated);
    // Completing a task cancels its pending reminder (no point being
    // notified about something already finished); un-completing it resumes
    // one — but only if it's still in the future, see
    // _syncReminderSchedule's own doc comment for why a past reminderAt
    // deliberately isn't auto-rolled forward the way a habit's recurring
    // clock time is.
    _syncReminderSchedule(updated);
    if (firstTimeDone) {
      _ref.read(dashboardProvider.notifier).awardBonus(
            xp: GameConstants.matrixTaskXpReward,
            gold: GameConstants.matrixTaskGoldReward,
          );
    }
  }

  /// Flags/unflags a task as a favorite — independent of isDone and of
  /// quadrant, and never expires on its own. Powers the Fav/All filter; no
  /// reward is attached to this, only to actually finishing the task.
  void toggleFav(String id) {
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final updated = tasks[idx].copyWith(isFav: !tasks[idx].isFav);
    tasks[idx] = updated;
    state = MatrixState(
      tasks: tasks,
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    _persist(updated);
  }

  /// Renames a task from the pencil-icon TaskDetailSheet. A no-op on an
  /// empty/whitespace title, same guard as add() — editing a task's title
  /// down to nothing shouldn't silently blank it out.
  void rename(String id, String title) {
    if (title.trim().isEmpty) return;
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final updated = tasks[idx].copyWith(title: title.trim());
    tasks[idx] = updated;
    state = MatrixState(
      tasks: tasks,
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    _persist(updated);
  }

  /// Updates an existing task's description — the pencil-icon
  /// TaskDetailSheet's edit action, as opposed to add()'s optional "Add
  /// details" section at creation time. clearDescription removes it
  /// entirely rather than leaving it unchanged, since passing null for an
  /// already-unset field and passing null to *clear* a set field need to
  /// mean different things. Voice notes have their own
  /// add/rename/removeVoiceNote methods below instead of living here, since
  /// a task can carry many of them now — a single "set the voice note"
  /// call doesn't make sense the way it did for one.
  void updateDetails(
    String id, {
    String? description,
    bool clearDescription = false,
  }) {
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final updated = tasks[idx].copyWith(
      description: description,
      clearDescription: clearDescription,
    );
    tasks[idx] = updated;
    state = MatrixState(
      tasks: tasks,
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    _persist(updated);
  }

  /// Sets, changes, or clears a task's reminder — TaskDetailSheet's
  /// reminder row, saved immediately on pick rather than deferred to the
  /// sheet's dispose() the way title/description are. Same "don't risk
  /// losing a deliberate action to an accidental swipe-dismiss" reasoning
  /// as [addVoiceNote]/[removeVoiceNote] below: picking a reminder means
  /// clearing two native dialogs, not a stray keystroke, so it deserves the
  /// same immediate-save treatment as a just-recorded voice note. Pass
  /// `null` to clear an existing reminder. AddTaskSheet never calls this —
  /// a reminder picked before the task exists travels through [add]'s own
  /// `reminderAt` param instead.
  void setReminder(String id, DateTime? reminderAt) {
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final updated = tasks[idx].copyWith(
      reminderAt: reminderAt,
      clearReminderAt: reminderAt == null,
    );
    tasks[idx] = updated;
    state = MatrixState(
      tasks: tasks,
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    _persist(updated);
    _syncReminderSchedule(updated);
  }

  /// Appends a newly recorded voice note to a task — TaskDetailSheet's mic
  /// button, as many times as the user likes rather than just once. Takes
  /// the whole already-built [VoiceNote] rather than generating its id
  /// here, so the sheet's own optimistic local copy (shown immediately,
  /// before this round-trips through state) and the one that ends up
  /// persisted are guaranteed to be the exact same object — otherwise a
  /// rename fired right after recording could race and target an id nobody
  /// actually saved.
  void addVoiceNote(String id, VoiceNote note) {
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final updated = tasks[idx]
        .copyWith(voiceNotes: [...tasks[idx].voiceNotes, note]);
    tasks[idx] = updated;
    state = MatrixState(
      tasks: tasks,
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    _persist(updated);
  }

  /// Renames one of a task's voice notes in place — everything else about
  /// it (path, duration, id) stays the same.
  void renameVoiceNote(String id, String noteId, String name) {
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final notes = tasks[idx]
        .voiceNotes
        .map((n) => n.id == noteId ? n.copyWith(name: name) : n)
        .toList();
    final updated = tasks[idx].copyWith(voiceNotes: notes);
    tasks[idx] = updated;
    state = MatrixState(
      tasks: tasks,
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    _persist(updated);
  }

  /// Removes one voice note from a task — doesn't touch the file on disk
  /// (see [delete]'s doc comment on the same tradeoff for a whole deleted
  /// task); TaskDetailSheet deletes the file itself once it also knows to
  /// stop anything currently playing it.
  void removeVoiceNote(String id, String noteId) {
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final notes =
        tasks[idx].voiceNotes.where((n) => n.id != noteId).toList();
    final updated = tasks[idx].copyWith(voiceNotes: notes);
    tasks[idx] = updated;
    state = MatrixState(
      tasks: tasks,
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    _persist(updated);
  }

  // Deliberately doesn't touch a deleted task's voiceNotePath file on disk:
  // deletes here are undoable (see the SnackBar restore() call sites), and
  // eagerly deleting the recording would leave a restored task pointing at
  // a file that's already gone. The small amount of orphaned audio this
  // can leave behind is a fine trade for undo actually working.
  void delete(String id) {
    _mutatedBeforeLoad = true;
    state = MatrixState(
      tasks: state.tasks.where((t) => t.id != id).toList(),
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    if (_uid != null) {
      _col.doc(id).delete().ignore();
    } else {
      _saveGuest().ignore();
    }
    // Unconditional, same as every other cancel call in this file —
    // cancelling a task that never had a reminder scheduled is a safe
    // no-op, and this is simpler/safer than first checking whether it did.
    NotificationService.instance.cancelTaskReminder(id).ignore();
  }

  void deleteMany(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;
    _mutatedBeforeLoad = true;
    state = MatrixState(
      tasks: state.tasks.where((t) => !idSet.contains(t.id)).toList(),
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    if (_uid != null) {
      for (final id in idSet) {
        _col.doc(id).delete().ignore();
      }
    } else {
      _saveGuest().ignore();
    }
    for (final id in idSet) {
      NotificationService.instance.cancelTaskReminder(id).ignore();
    }
  }

  void move(String id, MatrixQuadrant newQuadrant) {
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final updated = tasks[idx].copyWith(quadrant: newQuadrant);
    tasks[idx] = updated;
    state = MatrixState(
      tasks: tasks,
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    _persist(updated);
  }

  /// Drag-and-drop reorder: drops [id] into [quadrant], immediately before
  /// [beforeId] — or at the end of that quadrant if [beforeId] is null
  /// (dropped on empty space rather than on a specific row). Changes
  /// quadrant too, if it's moving from a different one, so this one method
  /// covers both "reorder within the same group" and "move to a specific
  /// spot in another group."
  ///
  /// Only [id]'s own `order` value changes — the new value is just the
  /// midpoint between its new neighbors, so a single drag never has to
  /// rewrite every other task in the quadrant to keep them all sorted.
  void reorder(String id, MatrixQuadrant quadrant, {String? beforeId}) {
    if (id == beforeId) return;
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;

    final siblings = tasks
        .where((t) => t.quadrant == quadrant && t.id != id)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    double newOrder;
    if (siblings.isEmpty) {
      newOrder = 0;
    } else {
      final beforeIdx =
          beforeId == null ? -1 : siblings.indexWhere((t) => t.id == beforeId);
      if (beforeIdx == -1) {
        // No target row (dropped on empty space / the "add another" row) —
        // append after the last sibling.
        newOrder = siblings.last.order + 1000;
      } else {
        final before = siblings[beforeIdx];
        final prev = beforeIdx > 0 ? siblings[beforeIdx - 1] : null;
        newOrder =
            prev == null ? before.order - 1000 : (prev.order + before.order) / 2;
      }
    }

    final updated = tasks[idx].copyWith(quadrant: quadrant, order: newOrder);
    tasks[idx] = updated;
    state = MatrixState(
      tasks: tasks,
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    _persist(updated);
  }

  /// Undoes a single delete — re-inserts the exact task that was removed.
  /// Guards against double-restore (e.g. a stale SnackBar action firing
  /// twice) by skipping if a task with that id is already present.
  void restore(MatrixTask task) {
    if (state.tasks.any((t) => t.id == task.id)) return;
    _mutatedBeforeLoad = true;
    state = MatrixState(
      tasks: [...state.tasks, task],
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    _persist(task);
    _syncReminderSchedule(task);
  }

  /// Undoes a bulk delete (multi-select). Same double-restore guard as
  /// [restore], applied per task.
  void restoreMany(Iterable<MatrixTask> tasks) {
    final existingIds = state.tasks.map((t) => t.id).toSet();
    final toRestore =
        tasks.where((t) => !existingIds.contains(t.id)).toList();
    if (toRestore.isEmpty) return;
    _mutatedBeforeLoad = true;
    state = MatrixState(
      tasks: [...state.tasks, ...toRestore],
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    for (final task in toRestore) {
      _persist(task);
      _syncReminderSchedule(task);
    }
  }

  void _persist(MatrixTask task) {
    if (_uid != null) {
      _col
          .doc(task.id)
          .set(task.toFirestore(), SetOptions(merge: true))
          .ignore();
    } else {
      _saveGuest().ignore();
    }
  }

  /// The one place that decides whether [task] should actually have a
  /// live local-notification schedule right now (see
  /// [shouldScheduleTaskReminder] for exactly which conditions that takes),
  /// and makes it so — called after every mutation that could change the
  /// answer: [add], [toggle], [setReminder], [restore]/[restoreMany]
  /// ([delete]/[deleteMany] instead call NotificationService.
  /// cancelTaskReminder directly, since there's no task left to reason
  /// about by that point). Cancels whenever the answer is no — clearing a
  /// stale schedule is always safe/cheap even when nothing was actually
  /// scheduled (see NotificationService.cancelTaskReminder's own doc
  /// comment).
  ///
  /// Deliberately fire-and-forget (`.ignore()`'d), same as every Firestore/
  /// Hive write [_persist] itself already makes: every caller here is
  /// itself a synchronous `void` method, and a scheduling failure shouldn't
  /// roll back or block a state update that's already succeeded. `.ignore()`
  /// specifically (rather than a bare un-awaited call) matters in tests —
  /// nothing in this repo mocks flutter_local_notifications' platform
  /// channel, so a scheduling call throws MissingPluginException under
  /// `flutter test`, same as an unconfigured Firestore call would; without
  /// `.ignore()` that becomes an unhandled Future rejection and can fail a
  /// test that never itself asserted anything about notifications, exactly
  /// the failure mode `.ignore()` exists to prevent throughout this file.
  ///
  /// Doesn't request OS notification permission itself — that's the
  /// calling sheet's job (AddTaskSheet._submit / TaskDetailSheet's reminder
  /// handler), see NotificationService.scheduleTaskReminder's doc comment
  /// for why.
  void _syncReminderSchedule(MatrixTask task) {
    final masterEnabled = _ref.read(notificationSettingsProvider).masterEnabled;
    if (!shouldScheduleTaskReminder(task, masterEnabled: masterEnabled)) {
      NotificationService.instance.cancelTaskReminder(task.id).ignore();
      return;
    }
    NotificationService.instance
        .scheduleTaskReminder(
          id: task.id,
          title: task.title,
          fireTime: task.reminderAt!,
          isAr: _ref.read(localeProvider).languageCode == 'ar',
        )
        .ignore();
  }

  /// Renames and/or recolors a quadrant — the Edit Quadrant sheet's Save
  /// action. `null` for [title]/[colorHex] leaves that half alone;
  /// [clearTitle]/[clearColor] explicitly remove a previously-set custom
  /// value so it falls back to the built-in label/[MatrixQuadrant.defaultColor]
  /// — same null-vs-clear distinction [updateDetails] already uses for a
  /// task's description. Persists to the same `users/{uid}` document
  /// [DashboardNotifier], `CharacterNotifier`, and `PremiumNotifier` each
  /// already write their own fields to — every write everywhere on that
  /// document uses `SetOptions(merge: true)`, so this can't clobber
  /// anything any of them own, and none of them can clobber this.
  void updateQuadrant(
    MatrixQuadrant quadrant, {
    String? title,
    bool clearTitle = false,
    String? colorHex,
    bool clearColor = false,
  }) {
    _quadrantsMutatedBeforeLoad = true;
    final newTitles = {...state.quadrantTitles};
    if (clearTitle) {
      newTitles.remove(quadrant.name);
    } else if (title != null && title.trim().isNotEmpty) {
      newTitles[quadrant.name] = title.trim();
    }

    final newColors = {...state.quadrantColors};
    if (clearColor) {
      newColors.remove(quadrant.name);
    } else if (colorHex != null) {
      newColors[quadrant.name] = colorHex;
    }

    state = MatrixState(
      tasks: state.tasks,
      isLoading: false,
      quadrantTitles: newTitles,
      quadrantColors: newColors,
    );

    if (_uid != null) {
      _userRef.set({
        'matrixQuadrantTitles': newTitles,
        'matrixQuadrantColors': newColors,
      }, SetOptions(merge: true)).ignore();
    } else {
      _saveGuestQuadrantSettings().ignore();
    }
  }
}

final matrixProvider =
    StateNotifierProvider<MatrixNotifier, MatrixState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return MatrixNotifier(ref, uid);
});
