import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../models/square_state.dart';
import 'note_index_notifier.dart';

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

  /// Entries gathered by the all-months search, or null when the screen is
  /// just browsing one month.
  ///
  /// Kept beside [entries] rather than replacing them so leaving the search
  /// costs nothing: the browsed month is still loaded underneath.
  final List<GridJournalEntry>? allMonths;

  /// How far the walk has got, for the line under the search field. The
  /// results stream in a month at a time rather than waiting for all of
  /// them, so a hit in the first month is on screen immediately.
  final int searchedMonths;
  final int totalSearchMonths;

  const GridJournalState({
    required this.monthStart,
    required this.entries,
    required this.isLoading,
    this.allMonths,
    this.searchedMonths = 0,
    this.totalSearchMonths = 0,
  });

  bool get isSearchingAllMonths => allMonths != null;
  bool get searchWalkDone =>
      allMonths != null && searchedMonths >= totalSearchMonths;

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
    List<GridJournalEntry>? allMonths,
    int? searchedMonths,
    int? totalSearchMonths,
    bool clearAllMonths = false,
  }) =>
      GridJournalState(
        monthStart: monthStart ?? this.monthStart,
        entries: entries ?? this.entries,
        isLoading: isLoading ?? this.isLoading,
        allMonths: clearAllMonths ? null : (allMonths ?? this.allMonths),
        searchedMonths: searchedMonths ?? this.searchedMonths,
        totalSearchMonths: totalSearchMonths ?? this.totalSearchMonths,
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

  List<DateTime> _daysOf(DateTime month) {
    // Never fetch days past today — they can't have an entry, and for the
    // current month that's most of the grid.
    final today = DateTime.now().effectiveDay;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    return [
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(month.year, month.month, d),
    ].where((d) => !d.isAfter(today)).toList();
  }

  /// One month's journal-worthy entries, plus what the read learned about
  /// the note index.
  ///
  /// Shared by the month browser and the all-months search so the two can
  /// never disagree about what a month contains, and so the search heals the
  /// index for every month it visits exactly as browsing does.
  Future<
      ({
        List<GridJournalEntry> entries,
        Set<int> written,
        bool fromCache,
      })> _readMonth(DateTime month) async {
    final entries = <GridJournalEntry>[];
    // Days of this month that turned out to carry real writing, which is the
    // ground truth the note index gets reconciled against.
    final writtenDays = <int>{};
    var fromCache = true;
    final days = _daysOf(month);

    try {
      if (_uid != null) {
        // ONE range query, where this used to fan out 28 to 31 individual
        // get()s. Day ids are 'YYYY-MM-DD', which sorts lexicographically
        // exactly as it sorts chronologically, so a __name__ range is
        // precisely a month. It is billed by the days that actually exist
        // rather than a flat 31, it is one round trip, and it needs no
        // composite index and no rules change: firestore.rules grants read
        // on daily/{dateKey}, and read covers list.
        final monthKey = '${month.year}-'
            '${month.month.toString().padLeft(2, '0')}';
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('daily')
            .orderBy(FieldPath.documentId)
            .startAt(['$monthKey-01'])
            .endAt(['$monthKey-31'])
            .get();
        fromCache = snap.metadata.isFromCache;
        for (final doc in snap.docs) {
          final day = _dayFromKey(doc.id);
          if (day == null || day.isAfter(DateTime.now().effectiveDay)) continue;
          final data = doc.data();
          _parseInto(day, data, entries);
          if (notesRowHasWriting(
              (data['squareNotes'] as Map?)?.cast<String, dynamic>())) {
            writtenDays.add(day.day);
          }
        }
      } else {
        fromCache = false;
        for (final day in days) {
          final d = await LocalStoreService.getDailyMap(day.toDateKey());
          _parseInto(day, d, entries);
        }
      }
    } catch (_) {
      // Offline / first run — fall through with whatever was parsed.
      fromCache = true;
    }

    // Newest day first; same-day entries tie-broken by habitId purely for
    // run-to-run determinism (a Map's key iteration order isn't guaranteed
    // stable across reads) — not meant to reflect any real ordering.
    entries.sort((a, b) {
      final byDay = b.day.compareTo(a.day);
      return byDay != 0 ? byDay : a.habitId.compareTo(b.habitId);
    });
    return (entries: entries, written: writtenDays, fromCache: fromCache);
  }

  Future<void> _loadMonth() async {
    final month = state.monthStart;
    final read = await _readMonth(month);
    // The user may have flipped months again before this resolved — don't
    // clobber a newer month's loading state with a stale result.
    if (!mounted || !state.monthStart.isSameMonthAs(month)) return;
    state = state.copyWith(entries: read.entries, isLoading: false);
    _healIndex(month, read.written, fromCache: read.fromCache);
  }

  /// Reconciles the note index for a month this load just saw in full.
  ///
  /// A healer riding a read that was happening anyway, which is what keeps
  /// the index honest without ever paying the per-day reads it exists to
  /// avoid. It writes only on a difference, and it emits a DIFF rather than
  /// overwriting the month, so it cannot clobber a concurrent write from a
  /// second device.
  ///
  /// Removals are withheld whenever the snapshot could have come from the
  /// offline cache. Nothing in this app configures Firestore `Settings`, so
  /// persistence is on and an offline month resolves happily with every
  /// document missing: reconciling deletes against that would erase a year
  /// of true entries, which is the one failure here that destroys data.
  void _healIndex(
    DateTime month,
    Set<int> truth, {
    required bool fromCache,
  }) {
    if (_uid == null) return; // The guest folds the truth for free.
    final monthKey =
        '${month.year}-${month.month.toString().padLeft(2, '0')}';
    noteIndexRef(_uid).get().then((snap) {
      final indexed = parseNoteIndex(snap.data())[monthKey] ?? const <int>{};
      healNoteIndexMonth(
        uid: _uid,
        monthKey: monthKey,
        diff: diffNoteDays(
          indexed: indexed,
          truth: truth,
          trustRemovals: !fromCache && !snap.metadata.isFromCache,
        ),
      );
    }).ignore();
  }

  /// 'YYYY-MM-DD' back to a day, or null for anything else in the collection.
  static DateTime? _dayFromKey(String id) {
    if (id.length != 10) return null;
    return DateTime.tryParse(id);
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

  /// Jumps to any month, for the header's month picker. Never past the
  /// current month, so a picker built from stale bounds cannot strand the
  /// journal in the future.
  void goToMonth(DateTime month) {
    final now = DateTime.now().effectiveDay;
    final ceiling = DateTime(now.year, now.month, 1);
    final target = DateTime(month.year, month.month, 1);
    _goToMonth(target.isAfter(ceiling) ? ceiling : target);
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

  /// Walks [months] and gathers every journal-worthy entry in them.
  ///
  /// The months come from the note index, so this visits ONLY months that
  /// actually hold writing: the cost is bounded by how much the person has
  /// written, never by how long they have used the app. Without the index
  /// there is no honest way to do this at all, since "which months have
  /// notes" is exactly the question a day document cannot answer.
  ///
  /// Results stream in a month at a time rather than landing all at once, so
  /// a hit in the first month is on screen while the rest are still loading,
  /// and each month heals the index on its way past.
  ///
  /// Deliberately no text index and no server-side search: the corpus is a
  /// few hundred short strings, and the filtering happens on the screen over
  /// what this returns.
  Future<void> searchAllMonths(List<DateTime> months) async {
    if (months.isEmpty) return;
    state = state.copyWith(
      allMonths: const [],
      searchedMonths: 0,
      totalSearchMonths: months.length,
    );
    final gathered = <GridJournalEntry>[];
    for (var i = 0; i < months.length; i++) {
      final month = months[i];
      final read = await _readMonth(month);
      // The user may have cancelled the search, or left the screen, while
      // this month was in flight.
      if (!mounted || !state.isSearchingAllMonths) return;
      gathered.addAll(read.entries);
      state = state.copyWith(
        allMonths: List.unmodifiable(gathered),
        searchedMonths: i + 1,
      );
      _healIndex(month, read.written, fromCache: read.fromCache);
    }
  }

  /// Back to browsing one month. The browsed month never went anywhere, so
  /// this costs no reads.
  void exitAllMonths() {
    if (!state.isSearchingAllMonths) return;
    state = state.copyWith(
      clearAllMonths: true,
      searchedMonths: 0,
      totalSearchMonths: 0,
    );
  }

  /// Patches a note the Grid just wrote into the loaded month.
  ///
  /// This provider is not autoDispose: it loads once in its constructor and
  /// never re-reads, so a note written on the Grid left both this screen and
  /// the Progress hub's preview stale for the rest of the session. Patching
  /// in memory keeps that honest without spending a second month query.
  ///
  /// [squareState] is the square's current state, which only the caller
  /// knows.
  void noteChanged(
    DateTime day,
    String habitId,
    String note, {
    // NOT named `state`: that is the StateNotifier's own property, and
    // shadowing it here silently retargets every read in this method.
    required SquareState squareState,
  }) {
    if (!state.monthStart.isSameMonthAs(day)) return;
    final trimmed = note.trim();
    final entries = [...state.entries];
    final at = entries.indexWhere(
      (e) => e.habitId == habitId && e.day.isSameDayAs(day),
    );
    if (at >= 0) {
      final existing = entries[at];
      if (isJournalWorthy(existing.state, trimmed)) {
        entries[at] = GridJournalEntry(
          day: existing.day,
          habitId: habitId,
          state: existing.state,
          note: trimmed,
        );
      } else {
        // A cleared note on an otherwise ordinary square stops being worth
        // keeping, the same rule the loader applies.
        entries.removeAt(at);
      }
    } else if (trimmed.isNotEmpty) {
      // The caller passes the square's REAL state. Fabricating `none` here
      // labelled a note written on a green square «لم يكتمل» until the next
      // month reload, which is the journal contradicting the board.
      entries
        ..add(GridJournalEntry(
          day: day,
          habitId: habitId,
          state: squareState,
          note: trimmed,
        ))
        ..sort((a, b) {
          final byDay = b.day.compareTo(a.day);
          return byDay != 0 ? byDay : a.habitId.compareTo(b.habitId);
        });
    } else {
      return;
    }
    state = state.copyWith(entries: entries);
  }
}

final gridJournalProvider =
    StateNotifierProvider<GridJournalNotifier, GridJournalState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return GridJournalNotifier(uid);
});
