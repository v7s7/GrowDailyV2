import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../models/square_state.dart';

/// Whether a (state, note) pair is worth keeping in the Habit Notes journal
/// (see grid_journal_notifier.dart's own doc comment) — a note with real
/// text always qualifies (that's the whole point of writing one), and so
/// does any of the three "advanced" palette states even with an empty note,
/// since deliberately picking Skipped/Failed/Bonus over the plain tap cycle
/// (none/partial/complete) is itself worth remembering on its own — "I
/// skipped Fajr today" is meaningful even with no explanation attached. A
/// plain, note-less complete/partial/none square is never journal-worthy —
/// that's just the Grid itself, nothing to browse back to later.
///
/// A top-level pure function (not a GridJournalNotifier method) so this
/// exact rule is unit-testable without any Firestore involved — same
/// reasoning as this app's other extracted pure-logic helpers (see
/// rooms_notifier.dart's nextLeaderAfter/suggestExistingMatch).
bool isJournalWorthy(SquareState state, String note) =>
    note.trim().isNotEmpty ||
    state == SquareState.skipped ||
    state == SquareState.failed ||
    state == SquareState.bonus;

/// One past (day, habit) pair surfaced in the journal. Deliberately doesn't
/// carry the habit's name — squareStates/squareNotes only ever stored
/// habitId in the first place (see WeeklyGridNotifier._persistSquare), so
/// there's nothing to denormalize; GridJournalScreen resolves a display
/// name from the *current* habitListProvider at render time instead
/// (falling back to S.gridJournalDeletedHabit for one that's since been
/// removed) — same "resolve live, explain if it's gone" pattern
/// RoomDetailScreen's _MyPlanCard already uses for the identical situation.
class GridJournalEntry {
  final DateTime day;
  final String habitId;
  final SquareState state;
  final String note;

  const GridJournalEntry({
    required this.day,
    required this.habitId,
    required this.state,
    required this.note,
  });
}

class GridJournalState {
  /// First day of the visible month.
  final DateTime monthStart;

  /// Journal-worthy entries for the visible month, newest day first (see
  /// GridJournalNotifier._loadMonth).
  final List<GridJournalEntry> entries;

  final bool isLoading;

  const GridJournalState({
    required this.monthStart,
    required this.entries,
    required this.isLoading,
  });

  factory GridJournalState.initial() {
    final now = DateTime.now().effectiveDay;
    return GridJournalState(
      monthStart: DateTime(now.year, now.month, 1),
      entries: const [],
      isLoading: true,
    );
  }

  bool get isCurrentMonth =>
      monthStart.isSameMonthAs(DateTime.now().effectiveDay);

  /// Never let the user browse into a month that hasn't happened yet.
  bool get canGoForward => !isCurrentMonth;

  GridJournalState copyWith({
    DateTime? monthStart,
    List<GridJournalEntry>? entries,
    bool? isLoading,
  }) =>
      GridJournalState(
        monthStart: monthStart ?? this.monthStart,
        entries: entries ?? this.entries,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// Loads a month at a time of past journal-worthy squares (see
/// [isJournalWorthy]) for the Habit Notes history screen — the "browse
/// everything I've ever written or skipped, later, nicely" view Grid's own
/// long-press editor (see grid_screen.dart's _CellEditorSheet, where a note
/// and an advanced state are actually set) has no room to offer itself.
/// Reuses the exact same per-day `daily` documents Grid/Dashboard/Night
/// Review already write (`squareStates`, `squareNotes`) rather than
/// introducing a second place this data lives, so nothing needs
/// backfilling — every note and skip ever saved is already sitting there,
/// one document per day, waiting to be read. Mirrors
/// NightReviewHistoryNotifier's exact month-at-a-time, Future.wait-per-day
/// loading shape for the same reason that one does: simple, and this app's
/// established pattern for "browse history" screens.
class GridJournalNotifier extends StateNotifier<GridJournalState> {
  final String? _uid;

  GridJournalNotifier(this._uid) : super(GridJournalState.initial()) {
    _loadMonth();
  }

  DocumentReference<Map<String, dynamic>> _dayRef(DateTime day) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('daily')
          .doc(day.toDateKey());

  List<DateTime> get _visibleDays {
    final month = state.monthStart;
    // Never fetch days past today — they can't have an entry, and for the
    // current month that's most of the grid.
    final today = DateTime.now().effectiveDay;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    return [
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(month.year, month.month, d),
    ].where((d) => !d.isAfter(today)).toList();
  }

  Future<void> _loadMonth() async {
    final month = state.monthStart;
    final days = _visibleDays;
    final entries = <GridJournalEntry>[];

    try {
      if (_uid != null) {
        final snaps = await Future.wait(days.map((d) => _dayRef(d).get()));
        for (var i = 0; i < days.length; i++) {
          final d = snaps[i].data();
          if (d == null) continue;
          _parseInto(days[i], d, entries);
        }
      } else {
        for (final day in days) {
          final d = await LocalStoreService.getDailyMap(day.toDateKey());
          _parseInto(day, d, entries);
        }
      }
    } catch (_) {
      // Offline / first run — fall through with whatever was parsed.
    }

    // The user may have flipped months again before this resolved — don't
    // clobber a newer month's loading state with a stale result.
    if (!mounted || !state.monthStart.isSameMonthAs(month)) return;
    // Newest day first; same-day entries tie-broken by habitId purely for
    // run-to-run determinism (a Map's key iteration order isn't guaranteed
    // stable across reads) — not meant to reflect any real ordering.
    entries.sort((a, b) {
      final byDay = b.day.compareTo(a.day);
      return byDay != 0 ? byDay : a.habitId.compareTo(b.habitId);
    });
    state = state.copyWith(entries: entries, isLoading: false);
  }

  void _parseInto(
    DateTime day,
    Map<String, dynamic> d,
    List<GridJournalEntry> entries,
  ) {
    final rawStates = d['squareStates'];
    final states = rawStates is Map
        ? rawStates.map((k, v) =>
            MapEntry(k.toString(), SquareState.fromJson(v?.toString())))
        : const <String, SquareState>{};
    final rawNotes = d['squareNotes'];
    final notes = rawNotes is Map
        ? rawNotes.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
        : const <String, String>{};
    for (final habitId in {...states.keys, ...notes.keys}) {
      final squareState = states[habitId] ?? SquareState.none;
      final note = notes[habitId] ?? '';
      if (isJournalWorthy(squareState, note)) {
        entries.add(GridJournalEntry(
          day: day,
          habitId: habitId,
          state: squareState,
          note: note,
        ));
      }
    }
  }

  void previousMonth() {
    final m = state.monthStart;
    _goToMonth(DateTime(m.year, m.month - 1, 1));
  }

  void nextMonth() {
    if (!state.canGoForward) return;
    final m = state.monthStart;
    _goToMonth(DateTime(m.year, m.month + 1, 1));
  }

  void _goToMonth(DateTime newMonth) {
    if (newMonth.isSameMonthAs(state.monthStart)) return;
    state = GridJournalState(
      monthStart: newMonth,
      entries: const [],
      isLoading: true,
    );
    _loadMonth();
  }

  Future<void> refresh() => _loadMonth();
}

final gridJournalProvider =
    StateNotifierProvider<GridJournalNotifier, GridJournalState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return GridJournalNotifier(uid);
});
