import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../models/square_state.dart';

/// Returns the Saturday that starts the week containing [d].
///
/// The Victory Grid runs Sat → Fri to match the app's deen-first rhythm
/// (and the product spec's example grid).
DateTime startOfGridWeek(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  final offset = (day.weekday - DateTime.saturday + 7) % 7;
  return day.subtract(Duration(days: offset));
}

class WeeklyGridState {
  /// Saturday that starts the visible week.
  final DateTime weekStart;

  /// dateKey → (habitId → square state) for the visible week.
  final Map<String, Map<String, SquareState>> states;

  /// dateKey → (habitId → note) for the visible week.
  final Map<String, Map<String, String>> notes;

  final bool isLoading;

  const WeeklyGridState({
    required this.weekStart,
    required this.states,
    required this.notes,
    this.isLoading = false,
  });

  factory WeeklyGridState.initial() => WeeklyGridState(
        // The real calendar week, not the reward-day's (effectiveDay) week
        // — see [canGoForward]'s doc comment for why those two can briefly
        // disagree. Opening the app during the 3-hour grace window right
        // after a week boundary (say, 1am Saturday — one hour into a brand
        // new Sat→Fri week) should land on the week Saturday actually
        // belongs to, not the previous one just because Friday's reward
        // day hasn't technically closed out yet. Friday is still one tap
        // back away and still fully editable there.
        weekStart: startOfGridWeek(DateTime.now()),
        states: const {},
        notes: const {},
        isLoading: true,
      );

  /// The seven days of the visible week, Saturday first.
  List<DateTime> get days =>
      List.generate(7, (i) => weekStart.add(Duration(days: i)));

  bool get isCurrentWeek =>
      weekStart.isSameDayAs(startOfGridWeek(DateTime.now().effectiveDay));

  /// Whether there's a later week worth arrowing into — compared against
  /// the *real* calendar week (see DateTimeGameExt.isRealToday), not
  /// [isCurrentWeek]'s reward-eligible one. Those two agree all but a few
  /// hours a week: right after a week boundary, effectiveDay can still be
  /// pointing at last week (its 3-hour grace period hasn't run out) while
  /// the real calendar has already moved into the new one. Gating forward
  /// navigation on [isCurrentWeek] there would trap the user on last
  /// week's board with no way to arrow into the new one — the exact bug
  /// this exists to avoid. Still never lets anyone go further than the
  /// real week — no logging ahead of time.
  bool get canGoForward => weekStart.isBefore(startOfGridWeek(DateTime.now()));

  SquareState squareFor(String habitId, DateTime day) =>
      states[day.toDateKey()]?[habitId] ?? SquareState.none;

  String noteFor(String habitId, DateTime day) =>
      notes[day.toDateKey()]?[habitId] ?? '';

  /// Green (or bonus) squares logged across the visible week.
  int greenSquares(Iterable<String> habitIds) {
    var count = 0;
    for (final day in days) {
      final row = states[day.toDateKey()];
      if (row == null) continue;
      for (final id in habitIds) {
        if ((row[id] ?? SquareState.none).isGreen) count++;
      }
    }
    return count;
  }

  /// Completion ratio for today's habit list in the visible week.
  ///
  /// The Grid can show a whole week of history, but the completion percent is
  /// a daily task metric: if there are 5 habits and 1 is green today, this is
  /// 20%, regardless of how many older squares were backfilled. A yellow
  /// partial square counts as half work, so 4 yellow marks across 4 tasks is
  /// 50% completion.
  double todayCompletionRatio(Iterable<String> habitIds) {
    final ids = habitIds.toList(growable: false);
    if (ids.isEmpty) return 0;

    final today = DateTime.now().effectiveDay;
    if (!isCurrentWeek || !days.any((d) => d.isSameDayAs(today))) return 0;

    final row = states[today.toDateKey()];
    if (row == null) return 0;

    var completedUnits = 0.0;
    for (final id in ids) {
      completedUnits += switch (row[id] ?? SquareState.none) {
        SquareState.complete || SquareState.bonus => 1.0,
        SquareState.partial => 0.5,
        SquareState.none || SquareState.failed || SquareState.skipped => 0.0,
      };
    }
    return completedUnits / ids.length;
  }

  /// Points that are actually reward-eligible for the visible week.
  ///
  /// Backfilled/past-day marks are an honest visual record, but they must not
  /// look like banked XP in the Grid summary. Only today's row in the current
  /// week can award progression, matching [setSquare]'s anti-backdating guard.
  int rewardEligiblePoints(Iterable<String> habitIds) {
    final today = DateTime.now().effectiveDay;
    if (!isCurrentWeek || !days.any((d) => d.isSameDayAs(today))) return 0;

    final row = states[today.toDateKey()];
    if (row == null) return 0;

    var points = 0;
    for (final id in habitIds) {
      points += (row[id] ?? SquareState.none).xpValue;
    }
    return points;
  }

  /// Every deliberately-marked square this week (any color).
  int markedSquares(Iterable<String> habitIds) {
    var count = 0;
    for (final day in days) {
      final row = states[day.toDateKey()];
      if (row == null) continue;
      for (final id in habitIds) {
        if ((row[id] ?? SquareState.none).isMarked) count++;
      }
    }
    return count;
  }

  WeeklyGridState copyWith({
    DateTime? weekStart,
    Map<String, Map<String, SquareState>>? states,
    Map<String, Map<String, String>>? notes,
    bool? isLoading,
  }) =>
      WeeklyGridState(
        weekStart: weekStart ?? this.weekStart,
        states: states ?? this.states,
        notes: notes ?? this.notes,
        isLoading: isLoading ?? this.isLoading,
      );
}

class WeeklyGridNotifier extends StateNotifier<WeeklyGridState> {
  final String? _uid;
  final Ref _ref;

  WeeklyGridNotifier(this._uid, this._ref) : super(WeeklyGridState.initial()) {
    _loadWeek();
  }

  DocumentReference<Map<String, dynamic>> _dayRef(DateTime day) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('daily')
          .doc(day.toDateKey());

  // ── Loading ──────────────────────────────────────────────────

  Future<void> _loadWeek() async {
    final week = state.weekStart;
    final states = <String, Map<String, SquareState>>{};
    final notes = <String, Map<String, String>>{};

    try {
      if (_uid != null) {
        final snaps = await Future.wait(
          state.days.map((d) => _dayRef(d).get()),
        );
        for (final snap in snaps) {
          if (!snap.exists) continue;
          final d = snap.data()!;
          _parseInto(snap.id, d, states, notes);
        }
      } else {
        for (final day in state.days) {
          final d = await LocalStoreService.getDailyMap(day.toDateKey());
          _parseInto(day.toDateKey(), d, states, notes);
        }
      }
    } catch (_) {
      // Offline / first run — fall through with whatever we parsed.
    }

    if (!mounted || !state.weekStart.isSameDayAs(week)) return;
    state = state.copyWith(states: states, notes: notes, isLoading: false);
  }

  void _parseInto(
    String dateKey,
    Map<String, dynamic> data,
    Map<String, Map<String, SquareState>> states,
    Map<String, Map<String, String>> notes,
  ) {
    final rawStates = data['squareStates'];
    if (rawStates is Map) {
      states[dateKey] = rawStates.map(
        (k, v) => MapEntry(k.toString(), SquareState.fromJson(v?.toString())),
      );
    }
    final rawNotes = data['squareNotes'];
    if (rawNotes is Map) {
      notes[dateKey] = rawNotes.map(
        (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
      );
    }
  }

  // ── Week navigation ──────────────────────────────────────────

  void previousWeek() =>
      _goToWeek(state.weekStart.subtract(const Duration(days: 7)));

  void nextWeek() {
    if (!state.canGoForward) return;
    _goToWeek(state.weekStart.add(const Duration(days: 7)));
  }

  /// Jumps to the real calendar's current week — see [WeeklyGridState.
  /// canGoForward]'s doc comment for why that's real-today's week and not
  /// effectiveDay's.
  void goToCurrentWeek() => _goToWeek(startOfGridWeek(DateTime.now()));

  void _goToWeek(DateTime newStart) {
    final start = startOfGridWeek(newStart);
    if (start.isSameDayAs(state.weekStart)) return;
    state = WeeklyGridState(
      weekStart: start,
      states: const {},
      notes: const {},
      isLoading: true,
    );
    _loadWeek();
  }

  // ── Mutations ────────────────────────────────────────────────

  /// Advance a square through the tap cycle: white → yellow → green → white.
  void cycleSquare(String habitId, DateTime day) {
    final current = state.squareFor(habitId, day);
    setSquare(habitId, day, current.next);
  }

  /// Set a square to an explicit state (used by the long-press palette).
  ///
  /// Every color change feeds the app's XP/green-square progression: the
  /// fixed XP for the new color minus the XP the old color already banked.
  /// This is delta-based so cycling a square back and forth nets to exactly
  /// what a single direct change would have earned; nothing to farm by
  /// tapping repeatedly. Does *not* touch the streak — see
  /// [DashboardNotifier.applyGridSquareChange]'s doc comment for why a Grid
  /// color change alone never earns today's streak point.
  void setSquare(String habitId, DateTime day, SquareState value) {
    final old = state.squareFor(habitId, day);
    final key = day.toDateKey();
    final states = {
      for (final e in state.states.entries) e.key: {...e.value},
    };
    (states[key] ??= {})[habitId] = value;
    state = state.copyWith(states: states);
    _persistSquare(habitId, day, value);

    final greenDelta = (value.isGreen ? 1 : 0) - (old.isGreen ? 1 : 0);

    // Anti-backdating: a square for any day other than today still colors
    // and saves normally, and now also correctly updates the heatmap's day
    // rollup (see DashboardNotifier.recordPastDayGreenDelta) — Grid and the
    // heatmap both stay an honest visual record of what you did. What a
    // past day never reaches is the actual reward system: no XP, no gold,
    // no streak, no achievement/green-square progress. Without that split,
    // navigating to a past week and coloring squares green would be a
    // free, repeatable way to farm real progress for days that were never
    // actually lived through.
    //
    // day.isToday itself is cutoff-aware (see DateTimeGameExt.effectiveDay)
    // — a 1:30 AM tap on yesterday's square still passes this guard,
    // because the app day genuinely hasn't ended yet. The moment the
    // cutoff hour passes, that same square starts being treated as a past
    // day here, exactly like any other backdated square.
    if (!day.isToday) {
      if (greenDelta != 0) {
        _ref
            .read(dashboardProvider.notifier)
            .recordPastDayGreenDelta(key, greenDelta);
      }
      return;
    }

    final xpDelta = value.xpValue - old.xpValue;
    if (xpDelta != 0 || greenDelta != 0) {
      _ref.read(dashboardProvider.notifier).applyGridSquareChange(
            xpDelta: xpDelta,
            greenDelta: greenDelta,
            dateKey: key,
          );
    }
  }

  /// Sets a square's visual state without touching any reward system —
  /// for the cases where the reward is (or was already) handled by the
  /// canonical `DashboardNotifier.completeHabit`/`uncompleteHabit` path,
  /// so Grid's own flat-rate delta math ([setSquare]/
  /// `applyGridSquareChange`) must not also fire for the same change.
  void setSquareStateOnly(String habitId, DateTime day, SquareState value) {
    final key = day.toDateKey();
    final states = {
      for (final e in state.states.entries) e.key: {...e.value},
    };
    (states[key] ??= {})[habitId] = value;
    state = state.copyWith(states: states);
    _persistSquare(habitId, day, value);
  }

  /// Mirrors a habit completion already rewarded by
  /// `DashboardNotifier.completeHabit` onto today's Grid square. A no-op
  /// if the square is already `complete` (e.g. repairing the mirror after
  /// `completeHabit` succeeded but the visual write hadn't landed yet).
  void markCompleteFromHabit(String habitId, DateTime day) =>
      markResultFromHabit(habitId, day, SquareState.complete);

  /// General form of [markCompleteFromHabit] — mirrors *any* outcome
  /// (not just a green complete) onto a Grid square without touching the
  /// reward system, same division of labor as [setSquareStateOnly]: the
  /// caller (e.g. `DashboardNotifier.completeHabit`/`uncompleteHabit`) is
  /// always the one place a habit-day's XP/gold/streak actually changes.
  ///
  /// Added for quit-habit slip/over-limit days, which need a square color
  /// distinct from both "green" and "never touched" (`SquareState.failed`,
  /// the grid's existing red state) — see `HabitCard`'s quit-goal action
  /// row. A no-op if the square already shows [value], mirroring
  /// [markCompleteFromHabit]'s own repair-safe guard.
  void markResultFromHabit(String habitId, DateTime day, SquareState value) {
    if (state.squareFor(habitId, day) == value) return;
    setSquareStateOnly(habitId, day, value);
  }

  /// Attach (or clear) a daily reflection note for a habit's square.
  void setNote(String habitId, DateTime day, String note) {
    final key = day.toDateKey();
    final trimmed = note.trim();
    final notes = {
      for (final e in state.notes.entries) e.key: {...e.value},
    };
    (notes[key] ??= {})[habitId] = trimmed;
    state = state.copyWith(notes: notes);
    _persistNote(habitId, day, trimmed);
  }

  Future<void> _persistSquare(
      String habitId, DateTime day, SquareState value) async {
    if (_uid != null) {
      _dayRef(day).set(
        {
          'squareStates': {habitId: value.toJson()},
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ).ignore();
      return;
    }
    await _mergeGuestDaily(day, (map) {
      final squares = Map<String, dynamic>.from(
          (map['squareStates'] as Map?)?.cast<String, dynamic>() ?? {});
      squares[habitId] = value.toJson();
      map['squareStates'] = squares;
    });
  }

  Future<void> _persistNote(
      String habitId, DateTime day, String note) async {
    if (_uid != null) {
      _dayRef(day).set(
        {
          'squareNotes': {habitId: note},
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ).ignore();
      return;
    }
    await _mergeGuestDaily(day, (map) {
      final notes = Map<String, dynamic>.from(
          (map['squareNotes'] as Map?)?.cast<String, dynamic>() ?? {});
      notes[habitId] = note;
      map['squareNotes'] = notes;
    });
  }

  Future<void> _mergeGuestDaily(
      DateTime day, void Function(Map<String, dynamic>) mutate) async {
    final key = day.toDateKey();
    final map = await LocalStoreService.getDailyMap(key);
    mutate(map);
    map['date'] = day.startOfDay.toIso8601String();
    await LocalStoreService.putDailyMap(key, map);
  }

  /// Retroactively marks [day]'s square green for each quit habit in
  /// [habitIds] whose square is still untouched — the "silence means
  /// clean" half of the quit-habit evening check-in flow (see
  /// NotificationService.scheduleQuitCheckIns for the other half). A quit
  /// habit's success is *not doing* something, so an unanswered day
  /// shouldn't quietly read as a hole in the record the way a build
  /// habit's genuinely does.
  ///
  /// Deliberately visual-record only, same anti-backdating stance as
  /// [setSquare]'s past-day branch: no XP, no gold, no streak — those
  /// stay exclusive to same-day actions (the check-in's On Track button,
  /// or the card's own pill). Reads the day straight from Firestore/Hive
  /// rather than [state], since [day] (typically yesterday) can fall
  /// outside the visible week — e.g. every Saturday, when the grid week
  /// rolls over. Only ever writes over [SquareState.none]: an explicit
  /// slip, skip, or anything else the user (or a past pass) already said
  /// about that day always wins over an assumption.
  ///
  /// Callers decide *which* habits qualify — see
  /// [isQuitAutoCleanEligible] for the shared rule.
  Future<void> autoCleanQuitDay(List<String> habitIds, DateTime day) async {
    if (habitIds.isEmpty) return;
    Map<String, dynamic> data;
    try {
      if (_uid != null) {
        final snap = await _dayRef(day).get();
        data = snap.data() ?? const {};
      } else {
        data = await LocalStoreService.getDailyMap(day.toDateKey());
      }
    } catch (_) {
      // Offline with no cached doc — skip rather than risk overwriting a
      // slip logged on another device that just hasn't synced here yet.
      return;
    }
    if (!mounted) return;
    final raw = (data['squareStates'] as Map?) ?? const {};
    for (final id in habitIds) {
      final existing = SquareState.fromJson(raw[id]?.toString());
      if (existing != SquareState.none) continue;
      setSquareStateOnly(id, day, SquareState.complete);
    }
  }

  Future<void> refresh() => _loadWeek();
}

/// Whether a habit qualifies for [WeeklyGridNotifier.autoCleanQuitDay]'s
/// "an unanswered day counts as clean" treatment. Pure so the rule is
/// unit-testable — see test/features/grid/quit_auto_clean_test.dart.
///
/// All four must hold:
///  - [isQuit]: build habits genuinely require action, silence IS a miss;
///  - [isSingleTap]: weekly-target quit habits never sync per-day squares
///    anywhere else either (same rule as HabitCard's slip link and
///    completeHabit's Grid mirror);
///  - [wasScheduled]: a day the habit wasn't even scheduled for has
///    nothing to be clean *about*;
///  - [hasEverCompleted]: auto-clean only continues an established record,
///    it never invents the first day — a freshly created quit habit that's
///    never once been affirmed shouldn't wake up to auto-greened history
///    (this also covers "created today, don't green the day before it
///    existed", since the app doesn't store a per-habit creation date).
bool isQuitAutoCleanEligible({
  required bool isQuit,
  required bool isSingleTap,
  required bool wasScheduled,
  required bool hasEverCompleted,
}) =>
    isQuit && isSingleTap && wasScheduled && hasEverCompleted;

/// Whether a habit's entire visible-week row is green — the "full row"
/// celebration trigger (see GridScreen's _maybeCelebrateFullRow). Only the
/// days the habit is actually scheduled for count; future days can't be
/// green (they're locked), so this naturally only ever becomes true on the
/// week's last scheduled day — the moment the row genuinely completes.
/// Requires at least 2 scheduled days: a once-a-week habit's single square
/// isn't a "row" story worth a fanfare every week. Pure so it's
/// unit-testable — see test/features/grid/weekly_recap_test.dart.
bool isHabitRowComplete({
  required List<DateTime> days,
  required bool Function(DateTime day) isScheduled,
  required SquareState Function(DateTime day) squareFor,
}) {
  var scheduled = 0;
  for (final day in days) {
    if (!isScheduled(day)) continue;
    scheduled++;
    if (!squareFor(day).isGreen) return false;
  }
  return scheduled >= 2;
}

final weeklyGridProvider =
    StateNotifierProvider<WeeklyGridNotifier, WeeklyGridState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return WeeklyGridNotifier(uid, ref);
});
