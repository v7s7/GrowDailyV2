import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/game_constants.dart';
import '../../../core/extensions/datetime_ext.dart';
import '../../../core/l10n/app_strings.dart' show localeProvider;
import '../../../core/services/local_store_service.dart';
import '../../../core/services/notification_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../settings/notifiers/notification_settings_notifier.dart'
    show notificationSettingsProvider;
import '../models/matrix_task.dart';
import '../task_day.dart';

/// Parses a `growdaily://matrix/add` deep link — the Matrix home-screen
/// widget's "+" button (see ios/GrowDailyWidget/GrowDailyWidget.swift's
/// MatrixQuickAddLink) — so tapping it jumps straight to Matrix with the
/// Add Task sheet already open instead of just opening the app to whatever
/// it last showed. Same shape/reasoning as rooms_notifier.dart's
/// parseRoomJoinLink: a malformed link, or a link some other feature/OS
/// handler hands this app for an unrelated reason, is just ignored rather
/// than force-fit into anything. See main.dart's AppLinks wiring, the only
/// caller.
bool isMatrixQuickAddLink(Uri uri) =>
    uri.scheme.toLowerCase() == 'growdaily' &&
    uri.host.toLowerCase() == 'matrix' &&
    uri.pathSegments.isNotEmpty &&
    uri.pathSegments.first.toLowerCase() == 'add';

/// Pure decision logic behind [MatrixNotifier._syncReminderSchedule] — kept
/// as a standalone top-level function, same reasoning as rooms_notifier.
/// dart's nextLeaderAfter: the conditions that gate whether a task's
/// reminder should actually be (re)scheduled right now can then be unit
/// tested directly, without touching Riverpod, NotificationService, or
/// Hive/Firestore at all. [now] defaults to the real clock but is
/// overridable so "is reminderAt still in the future" stays deterministic
/// under test — see test/features/matrix/matrix_reminder_test.dart.
@visibleForTesting
List<DateTime> futureTaskReminders(
  MatrixTask task, {
  required bool masterEnabled,
  DateTime? now,
}) {
  if (task.isDone || !masterEnabled) return const [];
  final at = now ?? DateTime.now();
  return task.reminderAts.where((r) => r.isAfter(at)).toList();
}

/// Whether [task] has any reminder still worth arming — the bool form of
/// [futureTaskReminders], kept because that's the question
/// [MatrixNotifier._syncReminderSchedule] actually branches on.
@visibleForTesting
bool shouldScheduleTaskReminder(
  MatrixTask task, {
  required bool masterEnabled,
  DateTime? now,
}) =>
    futureTaskReminders(task, masterEnabled: masterEnabled, now: now)
        .isNotEmpty;

/// The most recent reminder on [task] whose moment has already passed, or
/// null if none has. Drives the overdue catch-up in
/// [MatrixNotifier._fireOverdueReminderOnce].
///
/// Deliberately the *latest* missed moment rather than every missed one:
/// a task warned about at 3:00, 3:30 and 4:00 that the user only reopens
/// the app for at 4:15 has missed all three, but firing three identical
/// catch-up notifications at once would be indistinguishable from a bug.
/// One nudge saying "this needed you" is the whole point of the catch-up;
/// keying it to the last missed moment also means the [_
/// overdueTaskReminderFiredKey] guard advances as later reminders in the
/// same stack come due, so a stack that's missed progressively still
/// catches up once per newly-passed moment rather than going silent after
/// the first.
@visibleForTesting
DateTime? latestMissedTaskReminder(
  MatrixTask task, {
  required bool masterEnabled,
  DateTime? now,
}) {
  if (task.isDone || !masterEnabled) return null;
  final at = now ?? DateTime.now();
  // reminderAts is sorted ascending, so the last non-future entry is the
  // most recent one that's passed.
  final passed = task.reminderAts.where((r) => !r.isAfter(at));
  return passed.isEmpty ? null : passed.last;
}

/// [task] moved to [day], or null when the move is refused. Pure, with the
/// clock passed in, for the same reason as [futureTaskReminders]: the rules
/// are what matter and they can be tested without Riverpod, Hive or the
/// notification plugin. [MatrixNotifier.moveToDay] is the only caller.
///
/// A timed task keeps its clock time (or takes [time], when given) and its
/// whole stack of offsets, rebuilt around the new anchor, so a 17:00 task
/// with a "1 hour before" warning is still exactly that on the new day. The
/// alarm choice is untouched. Offset moments that have already passed are
/// dropped: moving a task to today at 17:00 at 16:30 must not store a 16:00
/// warning that could only ever fire as an overdue catch-up. The anchor
/// itself in the past is a refusal (null), not a drop, because that would
/// store a task whose time has already gone; the move sheet answers it by
/// asking for a time on the wheel and calling again with [time].
///
/// An untimed task just takes [day] as its plannedDay; [time] is ignored,
/// since there is no clock time to replace and adding a reminder nobody
/// asked for is not a move. A done task is never moved (null): its board
/// is history. A task already on [day] with no new [time] comes back
/// unchanged (the same instance), so the caller can skip the write.
@visibleForTesting
MatrixTask? taskMovedToDay(
  MatrixTask task,
  DateTime day, {
  TimeOfDay? time,
  required DateTime now,
}) {
  if (task.isDone) return null;
  final anchor = MatrixTask.resolveAnchor(
    task.reminderAnchorAt,
    task.reminderAts,
  )?.toLocal();
  if (anchor == null) {
    if (taskDay(task).isSameDayAs(day)) return task;
    return task.copyWith(plannedDay: dayKey(day));
  }
  if (time == null && taskDay(task).isSameDayAs(day)) return task;
  final newAnchor = DateTime(
    day.year,
    day.month,
    day.day,
    time?.hour ?? anchor.hour,
    time?.minute ?? anchor.minute,
  );
  if (!newAnchor.isAfter(now)) return null;
  final offsets = offsetsFrom(anchor: anchor, reminders: task.reminderAts);
  final moments = remindersFor(anchor: newAnchor, offsets: offsets)
      .where((r) => r.isAfter(now))
      .toList();
  return task.copyWith(
    reminderAts: moments,
    reminderAnchorAt: newAnchor,
    alarm: task.alarm,
    plannedDay: dayKey(newAnchor),
  );
}

/// [task] with the schedule it had before a move put back, for the move's
/// Undo ([MatrixNotifier.restoreSchedule]). Pure, clock passed in, like
/// [taskMovedToDay].
///
/// The previous [reminderAts] come back minus every moment that has passed
/// by [now]. Undo is pressed seconds after a move, but the schedule it
/// restores can be an overdue one (a task from yesterday moved to next
/// week), and putting a passed moment back would hand it straight to the
/// overdue catch-up: pressing Undo would ring about a task the person was
/// looking at a second ago.
///
/// When the previous anchor itself has passed, nothing timed comes back,
/// not even a follow-up still ahead of [now]. Kept on its own, that
/// follow-up would be re-read as the picked moment (resolveAnchor falls
/// back to the last reminder), so the row would show a time the person
/// never chose, and a follow-up past midnight would move the task to the
/// next day, the one thing an Undo must never do. It is the same line
/// [taskMovedToDay] draws: a time that has gone is not stored.
///
/// The day comes back even when the time does not. A timed task's day was
/// its anchor's day, so that day is stored as its plannedDay (the same
/// write rule as setReminders); without it a task whose every moment has
/// passed would fall back to the day it was created instead of the day it
/// was on before the move. An untimed task gets [plannedDay] back as given,
/// null included (a task that was on its created day stays that way).
@visibleForTesting
MatrixTask taskWithRestoredSchedule(
  MatrixTask task, {
  required List<DateTime> reminderAts,
  DateTime? anchor,
  String? plannedDay,
  required DateTime now,
}) {
  final previous = MatrixTask.normalizeReminders(reminderAts);
  final previousAnchor = MatrixTask.resolveAnchor(anchor, previous);
  final day = previousAnchor != null
      ? dayKey(previousAnchor.toLocal())
      : plannedDay;
  final timeKept = previousAnchor != null && previousAnchor.isAfter(now);
  return task.copyWith(
    reminderAts: timeKept
        ? previous.where((r) => r.isAfter(now)).toList()
        : const [],
    reminderAnchorAt: timeKept ? previousAnchor : null,
    clearReminderAnchorAt: !timeKept,
    plannedDay: day,
    clearPlannedDay: day == null,
  );
}

// Hive settings-box key for "task id -> the ISO8601 reminderAt this task's
// overdue catch-up notification has already fired for" - see
// MatrixNotifier._fireOverdueReminderOnce's own doc comment for the
// duplicate-notification bug this guards against. One shared map
// (taskId -> reminderAt string), matching LocalStoreService's existing
// whole-map-per-key shape (see rooms_hub_screen.dart's
// _roomNotifiedHabitCountsKey for the same pattern applied to Rooms).
const _overdueTaskReminderFiredKey = 'matrixOverdueTaskReminderFired';

/// taskId -> ISO instant of the LATEST reminder this device has actually
/// handed to the OS for that task. The catch-up path reads it to tell
/// "the OS already delivered this on time" apart from "this moment was
/// never armed here" (created on another device, or scheduling failed) —
/// a distinction [_syncReminderSchedule] itself has no other way to make,
/// which is why an on-time reminder used to earn one duplicate catch-up
/// at the next app open. See [shouldFireTaskCatchUp].
const _armedTaskReminderThroughKey = 'matrixTaskReminderArmedThrough';

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
  /// set one, else the built-in localized label. A saved title equal to the
  /// box's retired Arabic name is an old default frozen by a colour-only
  /// edit, not a choice, so it gives way to the current name.
  String titleFor(MatrixQuadrant quadrant, bool isAr) {
    final saved = quadrantTitles[quadrant.name];
    if (saved == null || saved == quadrant.retiredArLabel) {
      return quadrant.localLabel(isAr);
    }
    return saved;
  }

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

  // Whether state.tasks is the account's whole task list: set when a load
  // lands, and never when one is superseded (see [_mutatedBeforeLoad]),
  // after which the list holds only what was added before it. Every edit
  // after a landed load keeps the list whole. The reminder resync needs to
  // know, see [_resyncAllReminders].
  bool _taskListLoaded = false;

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
        // Per document: one unreadable task must not blank the page through
        // the catch-all below. See MatrixTask.listFromFirestore.
        final tasks = MatrixTask.listFromFirestore(colSnap.docs)
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        state = MatrixState(
          tasks: tasks,
          isLoading: false,
          quadrantTitles: quadrantTitles,
          quadrantColors: quadrantColors,
        );
        _taskListLoaded = true;
        _resyncAllReminders(tasks);
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
    } catch (e) {
      // Logged, not swallowed: a silent catch here is what kept an empty
      // Tasks page after a guest migration invisible.
      debugPrint('[MatrixNotifier] load failed: $e');
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
      _taskListLoaded = true;
      _resyncAllReminders(tasks);
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

  /// Re-derives every task's local-notification schedule right after a
  /// fresh load — cold start (or sign-in) is exactly when a reminder that
  /// was due while the app was closed gets its chance to catch up (see
  /// [_syncReminderSchedule]'s overdue branch), the same "resync everything
  /// on load, don't just trust whatever was scheduled last time" pattern
  /// main.dart's _recomputeNotifications already applies to every other
  /// notification type in this app.
  ///
  /// Passes every task with a [MatrixTask.reminderAt] through, done or not
  /// — [_syncReminderSchedule] itself already decides schedule/catch-up/
  /// cancel from the task's full state, so filtering here too would just
  /// be a second, easy-to-drift-out-of-sync copy of that same decision.
  /// This is also what guarantees a stale schedule left over from a
  /// completion whose cancel call silently failed still gets cleaned up on
  /// the very next load, instead of that gap only ever closing if the task
  /// happens to be touched again.
  ///
  /// All of it as one [TaskReminderResync], which is what keeps the done
  /// tasks cheap. They were not: every call is local, but a done task's
  /// cancel swept 16 platform slots whether or not anything was there, and
  /// on Aziz's account (39 done tasks with reminders) that was over 600
  /// calls per recompute, in the same lane the habit stand-downs use. The
  /// service now reads once what the system holds and cancels only that,
  /// and the alarms go in one reap at the end, which runs only when
  /// [_taskListLoaded] says the list is whole: the reap takes every task
  /// alarm this resync did not arm, and only a whole list can say that such
  /// an alarm belongs to no task.
  void _resyncAllReminders(List<MatrixTask> tasks) {
    final resync = NotificationService.instance
        .beginTaskResync(coversEveryTask: _taskListLoaded);
    for (final task in tasks) {
      if (task.reminderAt != null) {
        _syncReminderSchedule(task, resync: resync);
      }
    }
    NotificationService.instance.finishTaskResync(resync).ignore();
  }

  /// Public entry point for the exact same resync, called from
  /// main.dart's `_recomputeNotifications` on every app resume — not just
  /// the cold-start/sign-in call above. Every other reminder type in this
  /// app already gets re-derived on resume (see that method's own doc
  /// comment on why every trigger path should produce the same result);
  /// Matrix reminders previously didn't, which meant a reminder that
  /// silently failed to schedule earlier (denied notification permission,
  /// since granted from system Settings; or a transient plugin error) had
  /// no way to self-heal short of the user manually re-touching that exact
  /// task. Reads `state.tasks` fresh rather than taking a parameter, since
  /// callers outside this notifier have no other way to get the current
  /// list.
  void resyncReminders() => _resyncAllReminders(state.tasks);

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

  /// Adds a task and returns it (null for an empty title, which adds
  /// nothing), so the caller can tell whether the new task is on the board
  /// it is looking at and, if not, say which day it went to.
  ///
  /// [day] is the day the task is for, stored as its plannedDay: the Add
  /// sheet always passes one, today included, so a task added on the
  /// Wednesday board at 23:59 is Wednesday's even if the write lands after
  /// midnight. With reminders, the picked moment's day wins instead (the
  /// write rule in plannedDayOnWrite): the reminders decide the day while
  /// they exist, and storing it too keeps the task there if the time is
  /// removed later. With neither, plannedDay stays null and the task is on
  /// the day it was created, as every task was before plannedDay existed
  /// (the widget quick-add and one-tap suggestions still add that way).
  MatrixTask? add(
    String title,
    MatrixQuadrant quadrant, {
    String? description,
    List<VoiceNote> voiceNotes = const [],
    List<DateTime> reminderAts = const [],
    DateTime? reminderAnchorAt,
    bool alarm = false,
    DateTime? day,
  }) {
    if (title.trim().isEmpty) return null;
    _mutatedBeforeLoad = true;
    final anchor = MatrixTask.resolveAnchor(
      reminderAnchorAt,
      MatrixTask.normalizeReminders(reminderAts),
    );
    final task = MatrixTask.create(
      title,
      quadrant,
      description: description,
      voiceNotes: voiceNotes,
      reminderAts: reminderAts,
      reminderAnchorAt: reminderAnchorAt,
      alarm: alarm,
      plannedDay: anchor != null
          ? dayKey(anchor.toLocal())
          : (day == null ? null : dayKey(day)),
    );
    state = MatrixState(
      tasks: [...state.tasks, task],
      isLoading: false,
      quadrantTitles: state.quadrantTitles,
      quadrantColors: state.quadrantColors,
    );
    _persist(task);
    _syncReminderSchedule(task);
    return task;
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
    // The cap is consulted BEFORE `rewarded` is set, because that flag is
    // one-way: marking a task rewarded for a payout the ceiling refused would
    // strand the reward permanently. Short-circuits, so an ordinary re-tick
    // never touches the day's task allowance at all.
    final firstTimeDone = nowDone &&
        !current.rewarded &&
        _ref.read(dashboardProvider.notifier).claimTaskReward();
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
    // one — a still-future reminderAt just reschedules normally, and a
    // past one fires an immediate catch-up rather than staying silent, see
    // _syncReminderSchedule's own doc comment.
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
  /// `const []` to clear every reminder. AddTaskSheet never calls this —
  /// reminders picked before the task exists travel through [add]'s own
  /// `reminderAts` param instead.
  ///
  /// Takes the task's whole new reminder set rather than an add/remove
  /// delta, so the sheet stays the only place that has to reason about
  /// ordering or the free-tier cap; this just stores what it's given (the
  /// model normalizes) and resyncs the OS schedule to match.
  ///
  /// [reminderAnchorAt] is which of [reminderAts] the user actually picked;
  /// null clears it, which is right for the one caller that passes an empty
  /// list. The model re-validates it either way (MatrixTask.resolveAnchor),
  /// so a caller can't store an anchor the task doesn't fire at.
  ///
  /// Also writes the task's plannedDay by plannedDayOnWrite, so no edit here
  /// moves a task by accident: new reminders store the new anchor's day
  /// (picking another date in TaskDetailSheet is how a task changes day
  /// there), and clearing them keeps the task on the day it shows on now
  /// instead of dropping it back to the day it was typed.
  ///
  /// Does not refuse a past moment; the pickers that feed it already do.
  /// The day-move paths ([moveToDay], [restoreSchedule]) filter their own.
  void setReminders(
    String id,
    List<DateTime> reminderAts, {
    DateTime? reminderAnchorAt,
    // Null leaves the task's alarm choice as it was.
    bool? alarm,
  }) {
    _mutatedBeforeLoad = true;
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final updated = tasks[idx].copyWith(
      reminderAts: reminderAts,
      reminderAnchorAt: reminderAnchorAt,
      clearReminderAnchorAt: reminderAnchorAt == null,
      alarm: alarm,
      plannedDay: plannedDayOnWrite(
        before: tasks[idx],
        newReminders: reminderAts,
        newAnchor: reminderAnchorAt,
      ),
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

  /// Moves a task to another day: the move sheet's «نقل ليوم ثاني».
  ///
  /// A timed task keeps its clock time, its offsets and its alarm choice on
  /// the new day, minus any offset moment that has already passed; an
  /// untimed one just changes day. All the rules are in [taskMovedToDay].
  /// Returns false, changing nothing, when the task is done or when its
  /// time on [day] has already gone (moving a 9:00 task to today at noon).
  /// The sheet answers that one by asking for a time on today's wheel and
  /// calling again with [time], which replaces the clock time. True when the
  /// task is now on [day], including when it already was.
  ///
  /// Re-arms through [_syncReminderSchedule] like every other reminder
  /// change, which sweeps the old day's slots in the same call.
  bool moveToDay(String id, DateTime day, {TimeOfDay? time}) {
    final current = _taskById(id);
    if (current == null) return false;
    final moved =
        taskMovedToDay(current, day, time: time, now: DateTime.now());
    if (moved == null) return false;
    if (!identical(moved, current)) _commitTask(moved);
    return true;
  }

  /// The move's Undo: puts back the schedule a task had before
  /// [moveToDay], which the caller captured from the task just before it
  /// moved (its reminderAts, reminderAnchorAt and plannedDay). Every moment
  /// that has passed since is dropped rather than restored, so Undo can
  /// never set off an overdue catch-up; see [taskWithRestoredSchedule].
  void restoreSchedule(
    String id, {
    required List<DateTime> reminderAts,
    DateTime? anchor,
    String? plannedDay,
  }) {
    final current = _taskById(id);
    if (current == null) return;
    final restored = taskWithRestoredSchedule(
      current,
      reminderAts: reminderAts,
      anchor: anchor,
      plannedDay: plannedDay,
      now: DateTime.now(),
    );
    _commitTask(restored);
  }

  MatrixTask? _taskById(String id) {
    for (final t in state.tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Swaps [updated] in for the task with its id, saves it and resettles its
  /// reminders: the tail every schedule edit shares. Used by the day moves
  /// only; the older methods above keep their own copies of it.
  void _commitTask(MatrixTask updated) {
    final tasks = state.tasks.toList();
    final idx = tasks.indexWhere((t) => t.id == updated.id);
    if (idx < 0) return;
    _mutatedBeforeLoad = true;
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
    final updated =
        tasks[idx].copyWith(voiceNotes: [...tasks[idx].voiceNotes, note]);
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
    final notes = tasks[idx].voiceNotes.where((n) => n.id != noteId).toList();
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
    _enqueueBookkeeping(() => _pruneReminderBookkeeping([id]));
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
    _enqueueBookkeeping(() => _pruneReminderBookkeeping(idSet));
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
        newOrder = prev == null
            ? before.order - 1000
            : (prev.order + before.order) / 2;
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
    // Seed first, THEN sync, both through the queue: the catch-up decision
    // inside the sync reads the map the seed writes.
    _enqueueBookkeeping(() => _reseedRestoredMarkers(task));
    _enqueueBookkeeping(() async => _syncReminderSchedule(task));
  }

  /// Undoes a bulk delete (multi-select). Same double-restore guard as
  /// [restore], applied per task.
  void restoreMany(Iterable<MatrixTask> tasks) {
    final existingIds = state.tasks.map((t) => t.id).toSet();
    final toRestore = tasks.where((t) => !existingIds.contains(t.id)).toList();
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
      _enqueueBookkeeping(() => _reseedRestoredMarkers(task));
      _enqueueBookkeeping(() async => _syncReminderSchedule(task));
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
  /// live local-notification schedule right now, and makes it so — called
  /// after every mutation that could change the answer: [add], [toggle],
  /// [setReminders], [moveToDay]/[restoreSchedule] (through [_commitTask]),
  /// [restore]/[restoreMany], and [_resyncAllReminders] on
  /// every fresh load ([delete]/[deleteMany] instead call NotificationService.
  /// cancelTaskReminder directly, since there's no task left to reason
  /// about by that point). Three possible outcomes:
  ///
  /// - [shouldScheduleTaskReminder] says yes (reminderAt is still in the
  ///   future, task open, notifications on) → scheduled normally.
  /// - reminderAt already passed, but the task is still open and
  ///   notifications are still on → fires an immediate catch-up instead of
  ///   staying silent (see NotificationService.fireOverdueTaskReminder) —
  ///   deliberately different from a habit's recurring cue, which just
  ///   rolls forward to its next occurrence; a task reminder has no "next
  ///   occurrence," so "catch up now" is the closest equivalent to "don't
  ///   let a missed reminder just vanish."
  /// - Anything else (no reminderAt, task done, or notifications off
  ///   entirely) → cancelled. Clearing a stale schedule is always safe
  ///   even when nothing was actually scheduled, and inside a resync cheap
  ///   as well (see NotificationService.cancelTaskReminder's own doc
  ///   comment).
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
  /// Serializes every read-modify-write against the two reminder
  /// bookkeeping maps. They are whole-map Hive values, so two concurrent
  /// writers each spread a STALE copy and the last one wins — a resync
  /// loops all tasks at once, which made losing entries the common case
  /// rather than the race: on the first launch after this ships, every
  /// existing multi-reminder user re-records all their tasks in one batch,
  /// and without ordering only one entry survived. One queue, strictly
  /// FIFO, swallow-and-continue on error (bookkeeping must never wedge
  /// the queue for later writers).
  Future<void> _bookkeepingQueue = Future.value();

  void _enqueueBookkeeping(Future<void> Function() op) {
    _bookkeepingQueue = _bookkeepingQueue.then((_) => op()).catchError((_) {});
  }

  /// Persists the furthest reminder instant this device has armed for
  /// [id]. Forward-only, same reasoning as the catch-up marker: a stack
  /// edit that drops the latest slot must not un-remember that an earlier
  /// arming already covered the moments before it.
  Future<void> _recordArmedThrough(String id, DateTime through) async {
    final stored =
        await LocalStoreService.getSettingsMap(_armedTaskReminderThroughKey);
    final previous = DateTime.tryParse(stored[id]?.toString() ?? '');
    if (previous != null && !through.isAfter(previous)) return;
    await LocalStoreService.putSettingsMap(_armedTaskReminderThroughKey, {
      ...stored,
      id: through.toIso8601String(),
    });
  }

  Future<void> _revokeArmedThrough(String id) async {
    final stored =
        await LocalStoreService.getSettingsMap(_armedTaskReminderThroughKey);
    if (!stored.containsKey(id)) return;
    stored.remove(id);
    await LocalStoreService.putSettingsMap(
        _armedTaskReminderThroughKey, stored);
  }

  /// Re-seeds the bookkeeping for a task coming back through UNDO.
  ///
  /// Delete prunes both maps; restoring a task with a passed reminder then
  /// looked exactly like the cross-device case and fired an instant "It's
  /// time" on top of the undo snackbar — for a reminder the person already
  /// received, about a task they were looking at two seconds ago. Seeding
  /// the armed watermark to its latest already-passed moment keeps the
  /// restore silent while leaving every future reminder to arm normally.
  Future<void> _reseedRestoredMarkers(MatrixTask task) async {
    final now = DateTime.now();
    DateTime? latestPassed;
    for (final at in task.reminderAts) {
      if (at.isAfter(now)) continue;
      if (latestPassed == null || at.isAfter(latestPassed)) latestPassed = at;
    }
    if (latestPassed == null) return;
    await _recordArmedThrough(task.id, latestPassed);
  }

  /// Drops [ids] from both reminder bookkeeping maps. Called on delete —
  /// without this the settings box grew one orphaned entry per deleted
  /// task, forever (ids are UUIDs, so never reused; pure bloat).
  Future<void> _pruneReminderBookkeeping(Iterable<String> ids) async {
    for (final key in const [
      _overdueTaskReminderFiredKey,
      _armedTaskReminderThroughKey,
    ]) {
      final stored = await LocalStoreService.getSettingsMap(key);
      final before = stored.length;
      for (final id in ids) {
        stored.remove(id);
      }
      if (stored.length != before) {
        await LocalStoreService.putSettingsMap(key, stored);
      }
    }
  }

  // [resync] is set when this task is one of [_resyncAllReminders]' whole
  // pass, and travels to the service untouched; the decision below is the
  // same either way.
  void _syncReminderSchedule(MatrixTask task, {TaskReminderResync? resync}) {
    final masterEnabled = _ref.read(notificationSettingsProvider).masterEnabled;
    final isAr = _ref.read(localeProvider).languageCode == 'ar';

    // Passes the whole still-future set, not a delta —
    // scheduleTaskReminders re-arms exactly these and sweeps every slot
    // this task no longer uses, so partially-elapsed stacks (3:00 gone,
    // 3:30 and 4:00 still coming) resettle correctly with no orphans.
    final future = futureTaskReminders(task, masterEnabled: masterEnabled);
    if (future.isNotEmpty) {
      // Remember the furthest moment this device armed — but only once
      // scheduling has actually SUCCEEDED. Recording alongside a failed
      // plugin call would log a delivery that never became possible, and
      // the catch-up this marker feeds would be suppressed for a
      // notification nobody received (the denied-permission self-heal the
      // resync doc promises depends on exactly this distinction).
      final furthest = future.reduce((a, b) => a.isAfter(b) ? a : b);
      NotificationService.instance
          .scheduleTaskReminders(
            id: task.id,
            taskTitle: task.title,
            fireTimes: future,
            // What every fire time is measured against, so each slot's
            // notification can say whether it is early, on time, or a
            // follow-up. Not recoverable from `future` alone: already-passed
            // entries are filtered out of it, so the anchor is frequently
            // missing from the list entirely.
            anchorAt: task.reminderAnchorAt,
            isAr: isAr,
            alarm: task.alarm,
            resync: resync,
          )
          .then(
            (_) => _enqueueBookkeeping(
              () => _recordArmedThrough(task.id, furthest),
            ),
          )
          .ignore();
      return;
    }

    // Only once *nothing* is still armed does a missed moment deserve a
    // catch-up: while a later reminder in the same stack is still pending,
    // the task is about to nudge on its own anyway, and firing a catch-up
    // on top of it would just double up.
    final missed = latestMissedTaskReminder(task, masterEnabled: masterEnabled);
    if (missed != null) {
      // Through the queue: the fired-marker write inside shares the same
      // whole-map shape as the recorder and raced it identically.
      _enqueueBookkeeping(() => _fireOverdueReminderOnce(task, missed, isAr));
      return;
    }

    NotificationService.instance
        .cancelTaskReminder(task.id, resync: resync)
        .ignore();
    // Slots just cancelled will never fire, so the armed watermark that
    // covered them stops being a delivery record. Without this revocation,
    // complete -> the moment passes -> uncomplete lost its documented
    // catch-up: the marker claimed the OS had notified, but the cancel got
    // there first.
    _enqueueBookkeeping(() => _revokeArmedThrough(task.id));
  }

  /// Fires [NotificationService.fireOverdueTaskReminder] for [task] at most
  /// once per distinct [reminderAt] - without this guard, a task reminder
  /// that's already fired right on time still reads as "overdue and still
  /// open" to every later resync ([_syncReminderSchedule] has no way to
  /// tell "the OS already delivered this" apart from "this was silently
  /// missed"), so simply reopening the app again afterward (or any other
  /// _recomputeNotifications trigger - a habit/dashboard/grid change,
  /// another setting flipped) would re-fire the exact same catch-up
  /// notification a second, third, ... time for as long as the task stays
  /// open. This is the duplicate a user actually reported seeing. Keyed by
  /// [missedAt]'s own ISO string, not just the task id, so picking a new
  /// reminder time for the same task is still free to catch up once on its
  /// own later if that one is ever missed too — and so is each later
  /// moment in a multi-reminder stack as it comes due, since
  /// [latestMissedTaskReminder] hands over a new value each time one more
  /// passes.
  Future<void> _fireOverdueReminderOnce(
    MatrixTask task,
    DateTime missedAt,
    bool isAr,
  ) async {
    final stored =
        await LocalStoreService.getSettingsMap(_overdueTaskReminderFiredKey);
    final armed =
        await LocalStoreService.getSettingsMap(_armedTaskReminderThroughKey);
    final key = missedAt.toIso8601String();
    // Only ever move *forward*. An exact-match guard was enough when a task
    // had one reminder, but with a stack the "latest missed" moment can move
    // backwards: drop the 4:00 nudge from a 3:00/3:30/4:00 ladder that has
    // already elapsed and 3:30 becomes the latest missed, which is a key
    // we've never stored — so an exact-match guard fires a second catch-up
    // for a moment *older* than the one already delivered, once per edit.
    // Comparing instants instead means a catch-up only ever fires for
    // something newer than the last one, which still lets a progressively
    // elapsing stack catch up as each new moment comes due.
    final previous = DateTime.tryParse(stored[task.id]?.toString() ?? '');
    final armedThrough = DateTime.tryParse(armed[task.id]?.toString() ?? '');
    if (!shouldFireTaskCatchUp(
      missedAt: missedAt,
      previousCatchUp: previous,
      armedThrough: armedThrough,
    )) {
      return;
    }
    await LocalStoreService.putSettingsMap(_overdueTaskReminderFiredKey, {
      ...stored,
      task.id: key,
    });
    await NotificationService.instance.fireOverdueTaskReminder(
      id: task.id,
      taskTitle: task.title,
      // The task's own moment, not [missedAt]. They differ whenever the
      // reminder that went missing was itself an offset one, and "how late
      // is this task" is the question the catch-up answers. Falls back to
      // the missed moment for a task saved before the anchor was stored.
      dueAt: task.reminderAnchorAt ?? missedAt,
      isAr: isAr,
    );
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
      _userRef.set(
        {
          'matrixQuadrantTitles': newTitles,
          'matrixQuadrantColors': newColors,
        },
        SetOptions(merge: true),
      ).ignore();
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


/// Whether a passed-but-open reminder moment deserves an immediate
/// catch-up notification.
///
/// Three inputs, three rules, in order:
///  1. never re-fire for a moment at or before the last catch-up already
///     delivered ([previousCatchUp] — forward-only, see the caller);
///  2. never fire for a moment this device actually armed
///     ([armedThrough]): zonedSchedule notifications are delivered by the
///     OS whether or not the app is running, so "armed here and now past"
///     means the person was already notified on time — the catch-up would
///     be the duplicate a user reported seeing on every app open after an
///     on-time reminder;
///  3. otherwise fire: the moment was never armed on this device (task
///     synced from another device, or scheduling was impossible then),
///     which is the situation the catch-up exists for.
///
/// Top-level and pure so the truth table is testable without Hive or the
/// notifier — same reasoning as [futureTaskReminders].
bool shouldFireTaskCatchUp({
  required DateTime missedAt,
  DateTime? previousCatchUp,
  DateTime? armedThrough,
}) {
  if (previousCatchUp != null && !missedAt.isAfter(previousCatchUp)) {
    return false;
  }
  if (armedThrough != null && !missedAt.isAfter(armedThrough)) return false;
  return true;
}
