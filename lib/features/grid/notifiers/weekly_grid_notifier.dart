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
        weekStart: startOfGridWeek(DateTime.now()),
        states: const {},
        notes: const {},
        isLoading: true,
      );

  /// The seven days of the visible week, Saturday first.
  List<DateTime> get days =>
      List.generate(7, (i) => weekStart.add(Duration(days: i)));

  bool get isCurrentWeek =>
      weekStart.isSameDayAs(startOfGridWeek(DateTime.now()));

  /// The next week is in the future — never let the user log ahead of time.
  bool get canGoForward => !isCurrentWeek;

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
  /// Every color change feeds the app's single progression system: the fixed
  /// XP for the new color minus the XP the old color already banked, and —
  /// only for a square newly turned green on *today* — the once-per-day
  /// streak bump. This is delta-based so cycling a square back and forth
  /// nets to exactly what a single direct change would have earned; nothing
  /// to farm by tapping repeatedly.
  void setSquare(String habitId, DateTime day, SquareState value) {
    final old = state.squareFor(habitId, day);
    final key = day.toDateKey();
    final states = {
      for (final e in state.states.entries) e.key: {...e.value},
    };
    (states[key] ??= {})[habitId] = value;
    state = state.copyWith(states: states);
    _persistSquare(habitId, day, value);

    final xpDelta = value.xpValue - old.xpValue;
    final greenDelta = (value.isGreen ? 1 : 0) - (old.isGreen ? 1 : 0);
    if (xpDelta != 0 || greenDelta != 0) {
      // Whether any square is still green today after this change — lets
      // the dashboard tell a "still earned it some other way today" edit
      // apart from "the only green square today just got un-marked", which
      // should give the once-per-day streak point back.
      final stillGreenToday =
          (states[key] ?? const {}).values.any((s) => s.isGreen);
      _ref.read(dashboardProvider.notifier).applyGridSquareChange(
            xpDelta: xpDelta,
            greenDelta: greenDelta,
            isToday: day.isToday,
            dateKey: key,
            stillGreenToday: stillGreenToday,
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
  void markCompleteFromHabit(String habitId, DateTime day) {
    if (state.squareFor(habitId, day) == SquareState.complete) return;
    setSquareStateOnly(habitId, day, SquareState.complete);
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

  Future<void> refresh() => _loadWeek();
}

final weeklyGridProvider =
    StateNotifierProvider<WeeklyGridNotifier, WeeklyGridState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return WeeklyGridNotifier(uid, ref);
});
