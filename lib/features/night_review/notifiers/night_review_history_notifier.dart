import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../grid/models/square_state.dart';
import '../models/mood.dart';

/// One past day's saved check-in, as shown on the history calendar. Distinct
/// from [NightReviewState] (see night_review_notifier.dart), which only
/// ever tracks *today's* in-progress mood/reflection — this is a read-only
/// snapshot of whatever was saved for a given day, past or present.
///
/// [habitsDone]/[greenSquares] make looking back genuinely useful: the
/// day's actual numbers, not just its mood. Both are parsed out of the
/// same daily doc the mood/reflection already come from
/// (`habitCompletions` / `squareStates`), so they cost zero extra reads.
/// Matrix tasks aren't here on purpose — they live in their own
/// collection, not the daily docs; the history screen counts them from
/// the already-loaded matrixProvider at display time instead.
class NightReviewDayEntry {
  final Mood? mood;
  final String reflection;

  /// Habits with at least one completion recorded that day. A count of
  /// "worked on", not "hit its full weekly target" — a past day's doc
  /// doesn't store what each habit's target *was* back then, and judging
  /// old days by today's edited targets would misgrade history.
  final int habitsDone;

  /// Squares colored green (complete/bonus) on the Grid that day.
  final int greenSquares;

  const NightReviewDayEntry({
    this.mood,
    this.reflection = '',
    this.habitsDone = 0,
    this.greenSquares = 0,
  });

  /// Whether there's a saved review (mood/reflection). Days with only
  /// activity stats still show on the calendar (see [hasAnything]) but
  /// render dot-only, without a mood tint.
  bool get hasEntry => mood != null || reflection.isNotEmpty;

  /// Whether the day has anything at all worth opening — a review, or
  /// plain activity numbers.
  bool get hasAnything => hasEntry || habitsDone > 0 || greenSquares > 0;
}

class NightReviewHistoryState {
  /// First day of the visible month.
  final DateTime monthStart;

  /// dateKey → that day's entry. Only populated for days that actually have
  /// a mood and/or reflection saved — a day with neither simply has no key,
  /// so the calendar can tell "nothing saved" apart from "saved, but empty".
  final Map<String, NightReviewDayEntry> entries;

  final bool isLoading;

  const NightReviewHistoryState({
    required this.monthStart,
    required this.entries,
    required this.isLoading,
  });

  factory NightReviewHistoryState.initial() {
    final now = DateTime.now().effectiveDay;
    return NightReviewHistoryState(
      monthStart: DateTime(now.year, now.month, 1),
      entries: const {},
      isLoading: true,
    );
  }

  bool get isCurrentMonth =>
      monthStart.isSameMonthAs(DateTime.now().effectiveDay);

  /// Never let the user browse into a month that hasn't happened yet.
  bool get canGoForward => !isCurrentMonth;

  int get daysInMonth =>
      DateTime(monthStart.year, monthStart.month + 1, 0).day;

  NightReviewHistoryState copyWith({
    DateTime? monthStart,
    Map<String, NightReviewDayEntry>? entries,
    bool? isLoading,
  }) =>
      NightReviewHistoryState(
        monthStart: monthStart ?? this.monthStart,
        entries: entries ?? this.entries,
        isLoading: isLoading ?? this.isLoading,
      );
}

/// Loads a month at a time of past mood/reflection check-ins for the
/// history calendar — the browsing view NightReviewNotifier's own doc
/// comment explicitly says doesn't exist yet. Reuses the exact same
/// per-day `daily` documents Grid/Dashboard/NightReview already write
/// (`mood`, `dailyReflection`) rather than introducing a second place that
/// data lives, so nothing needs backfilling or migrating for existing
/// accounts — every review ever saved is already sitting there, one
/// document per day, waiting to be read.
class NightReviewHistoryNotifier extends StateNotifier<NightReviewHistoryState> {
  final String? _uid;

  NightReviewHistoryNotifier(this._uid)
      : super(NightReviewHistoryState.initial()) {
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
    return [
      for (var d = 1; d <= state.daysInMonth; d++)
        DateTime(month.year, month.month, d),
    ].where((d) => !d.isAfter(today)).toList();
  }

  Future<void> _loadMonth() async {
    final month = state.monthStart;
    final days = _visibleDays;
    final entries = <String, NightReviewDayEntry>{};

    try {
      if (_uid != null) {
        final snaps = await Future.wait(days.map((d) => _dayRef(d).get()));
        for (var i = 0; i < days.length; i++) {
          final d = snaps[i].data();
          if (d == null) continue;
          _parseInto(days[i].toDateKey(), d, entries);
        }
      } else {
        for (final day in days) {
          final d = await LocalStoreService.getDailyMap(day.toDateKey());
          _parseInto(day.toDateKey(), d, entries);
        }
      }
    } catch (_) {
      // Offline / first run — fall through with whatever was parsed.
    }

    // The user may have flipped months again before this resolved — don't
    // clobber a newer month's loading state with a stale result.
    if (!mounted || !state.monthStart.isSameMonthAs(month)) return;
    state = state.copyWith(entries: entries, isLoading: false);
  }

  void _parseInto(
    String dateKey,
    Map<String, dynamic> d,
    Map<String, NightReviewDayEntry> entries,
  ) {
    final mood = Mood.fromJsonOrNull(d['mood'] as String?);
    final reflection = d['dailyReflection'] as String? ?? '';
    final habitsDone = (d['habitCompletions'] as Map?)
            ?.values
            .where((v) => v is num && v > 0)
            .length ??
        0;
    var greenSquares = 0;
    final rawSquares = d['squareStates'];
    if (rawSquares is Map) {
      for (final v in rawSquares.values) {
        if (SquareState.fromJson(v?.toString()).isGreen) greenSquares++;
      }
    }
    final entry = NightReviewDayEntry(
      mood: mood,
      reflection: reflection,
      habitsDone: habitsDone,
      greenSquares: greenSquares,
    );
    if (!entry.hasAnything) return;
    entries[dateKey] = entry;
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
    state = NightReviewHistoryState(
      monthStart: newMonth,
      entries: const {},
      isLoading: true,
    );
    _loadMonth();
  }

  Future<void> refresh() => _loadMonth();
}

final nightReviewHistoryProvider = StateNotifierProvider<
    NightReviewHistoryNotifier, NightReviewHistoryState>((ref) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  return NightReviewHistoryNotifier(uid);
});
