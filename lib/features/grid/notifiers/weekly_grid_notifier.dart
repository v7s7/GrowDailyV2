import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../milestones/reports/habit_day_marks.dart';
import '../../premium/notifiers/premium_notifier.dart'
    show canBrowseHistoryMonth, kFreeHistoryMonths;
import '../models/square_state.dart';

/// Returns the Saturday that starts the week containing [d].
///
/// The Victory Grid runs Sat → Fri to match the app's deen-first rhythm
/// (and the product spec's example grid).
/// Delegates to DateTimeGameExt.startOfDisplayWeek so the Saturday-week rule
/// lives in exactly one place - see that getter's doc comment for why having
/// two definitions of "this week" was an actual bug.
DateTime startOfGridWeek(DateTime d) => d.startOfDisplayWeek;

class WeeklyGridState {
  /// Saturday that starts the visible week.
  final DateTime weekStart;

  /// dateKey → (habitId → square state) for the visible week.
  final Map<String, Map<String, SquareState>> states;

  /// dateKey → (habitId → note) for the visible week.
  final Map<String, Map<String, String>> notes;

  /// dateKey → (habitId → the flat-rate XP [WeeklyGridNotifier.setSquare]
  /// actually paid for that square).
  ///
  /// A receipt, not a derivation. [WeeklyGridNotifier.setSquareStateOnlyAsync]
  /// has to give back whatever the flat-rate path banked on a square before the
  /// canonical completion path takes it over, and it used to work that amount
  /// out from the square's COLOUR — which is only right when the colour was set
  /// by [WeeklyGridNotifier.setSquare], the one method that pays. A habit
  /// counted several times a day paints its own square جزئي from the count
  /// (see markResultFromHabit) and is paid in reward SLICES instead, so
  /// inferring five XP from the yellow and refunding it took back money that
  /// was never handed out: every counted habit quietly lost 5 XP on the tap
  /// that finished its day. Recording what was paid makes the refund exact in
  /// both directions, which is what keeps a none → جزئي → أخضر → none palette
  /// lap summing to zero.
  ///
  /// Absent means nothing was paid, which is the safe default: no refund is
  /// recoverable, a phantom refund is not.
  final Map<String, Map<String, int>> flatPaid;

  final bool isLoading;

  const WeeklyGridState({
    required this.weekStart,
    required this.states,
    required this.notes,
    this.flatPaid = const {},
    this.isLoading = false,
  });

  factory WeeklyGridState.initial() => WeeklyGridState(
        // The real calendar week, not the reward-day's (effectiveDay) week
        // — see [canGoForward]'s doc comment for why those two can briefly
        // disagree. Opening the app during the grace window right
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
  /// pointing at last week (its grace period hasn't run out) while
  /// the real calendar has already moved into the new one. Gating forward
  /// navigation on [isCurrentWeek] there would trap the user on last
  /// week's board with no way to arrow into the new one — the exact bug
  /// this exists to avoid. Still never lets anyone go further than the
  /// real week — no logging ahead of time.
  bool get canGoForward => weekStart.isBefore(startOfGridWeek(DateTime.now()));

  SquareState squareFor(String habitId, DateTime day) =>
      states[day.toDateKey()]?[habitId] ?? SquareState.none;

  /// The flat-rate XP banked on this square, or zero if none ever was.
  int flatPaidFor(String habitId, DateTime day) =>
      flatPaid[day.toDateKey()]?[habitId] ?? 0;

  String noteFor(String habitId, DateTime day) =>
      notes[day.toDateKey()]?[habitId] ?? '';

  /// Whether the note stored on [day] is one the free tier may no longer
  /// read.
  ///
  /// Past WEEKS stay free on the Grid by design (see _pickWeek: "a picker is
  /// not the place to introduce a paywall that did not exist a moment ago"),
  /// so this gates nothing about navigation, the board, or the palette. The
  /// leak it closes is narrower: Grid Journal paywalls notes older than
  /// [kFreeHistoryMonths], and long-pressing the same square on the board
  /// handed the same sentence over for free.
  ///
  /// False whenever the note is EMPTY, and that is the safety property, not
  /// a convenience. Writing a fresh note on an old day stays open, and more
  /// importantly the editor only swaps its text field and Save button out
  /// when this is true, so there is no state in which a blanked field can be
  /// saved over a note the user was not allowed to see. Withholding must
  /// never be able to destroy.
  ///
  /// Pure so the boundary is unit-testable without Riverpod or RevenueCat.
  /// See test/features/grid/grid_note_gate_test.dart.
  static bool noteIsWalled({
    required String note,
    required DateTime day,
    required DateTime now,
    required bool isPremium,
  }) =>
      note.isNotEmpty &&
      !canBrowseHistoryMonth(
        monthStart: DateTime(day.year, day.month),
        now: now,
        isPremium: isPremium,
      );

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

  /// Today's habits sitting on a جزئي square.
  ///
  /// Fed to [willCompleteAllHabitsToday] so a half-done habit counts half
  /// toward the streak threshold. Only today's row, and only when the
  /// visible week actually contains today, for the same reason
  /// [todayCompletionRatio] guards that way: a backfilled square on some
  /// other week is history, not a claim about today.
  Set<String> halfDoneTodayIds() {
    final today = DateTime.now().effectiveDay;
    if (!isCurrentWeek || !days.any((d) => d.isSameDayAs(today))) return const {};
    final row = states[today.toDateKey()];
    if (row == null) return const {};
    return {
      for (final entry in row.entries)
        if (entry.value == SquareState.partial) entry.key,
    };
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
    // Habits that were actually owed today. A تخطّي leaves this entirely
    // rather than scoring zero inside it.
    //
    // It used to score zero and STAY in the denominator, which meant marking
    // a deliberate rest lowered your percentage by exactly as much as
    // forgetting would have. The app's whole position is that a rest day is
    // not a missed day, and until this line the arithmetic on the app's own
    // home screen disagreed with it, while the reports (see
    // expectedCompletions) had already been fixed.
    //
    // Safe to exempt here because this ratio is DISPLAY ONLY: it feeds the
    // "إنجاز اليوم" figure in grid_screen_summary and nothing else. No XP, no
    // gold, no streak reads it, so there is nothing to game by resting. The
    // Rooms leaderboard, which IS ranked, deliberately does not do this; see
    // RoomParticipant.dailyRestedCount for why.
    var owed = 0;
    for (final id in ids) {
      final state = row[id] ?? SquareState.none;
      if (state == SquareState.skipped) continue;
      owed++;
      completedUnits += switch (state) {
        SquareState.complete || SquareState.bonus => 1.0,
        SquareState.partial => 0.5,
        SquareState.none || SquareState.failed || SquareState.skipped => 0.0,
      };
    }
    // Nothing was owed, because everything was deliberately stood down. That
    // is a finished day, not an empty one, which is the same answer
    // RoomParticipant.creditFor gives when its scheduled count reaches zero.
    if (owed == 0) return 1;
    return completedUnits / owed;
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
    Map<String, Map<String, int>>? flatPaid,
    bool? isLoading,
  }) =>
      WeeklyGridState(
        weekStart: weekStart ?? this.weekStart,
        states: states ?? this.states,
        notes: notes ?? this.notes,
        flatPaid: flatPaid ?? this.flatPaid,
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
    final flatPaid = <String, Map<String, int>>{};

    try {
      if (_uid != null) {
        // Each day read is awaited and caught on its OWN, never batched.
        //
        // Future.wait rejects on the first failure and discards the rest, and
        // a missing day is the normal case offline: a `get()` for a date the
        // person never coloured throws "client is offline" rather than
        // returning a non-existent doc. One such day therefore blanked the
        // ENTIRE week — six successful reads thrown away with it — and the
        // catch below, which promises to "fall through with whatever we
        // parsed", had nothing parsed to fall through with. Colour Sat–Mon,
        // board a plane, reopen: the whole week reads empty, and re-tapping
        // squares to fix it pays rewards against a state that has forgotten
        // they were already earned.
        //
        // dashboard_notifier_loading.dart already un-batched its own two
        // reads for exactly this reason; this is the same fix applied to the
        // seven the Grid does.
        for (final day in state.days) {
          try {
            final snap = await _dayRef(day).get();
            if (!snap.exists) continue;
            _parseInto(snap.id, snap.data()!, states, notes, flatPaid);
          } catch (_) {
            // This one day is unreadable; the rest of the week still is.
            continue;
          }
        }
      } else {
        for (final day in state.days) {
          final d = await LocalStoreService.getDailyMap(day.toDateKey());
          _parseInto(day.toDateKey(), d, states, notes, flatPaid);
        }
      }
    } catch (_) {
      // Offline / first run — fall through with whatever we parsed.
    }

    if (!mounted || !state.weekStart.isSameDayAs(week)) return;
    state = state.copyWith(
        states: states, notes: notes, flatPaid: flatPaid, isLoading: false);
  }

  void _parseInto(
    String dateKey,
    Map<String, dynamic> data,
    Map<String, Map<String, SquareState>> states,
    Map<String, Map<String, String>> notes,
    Map<String, Map<String, int>> flatPaid,
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
    // The flat-rate receipts (see WeeklyGridState.flatPaid). A day written
    // before this field existed simply has none, which reads as "nothing was
    // paid" and is the safe direction: the refund is skipped rather than
    // invented.
    final rawPaid = data['squareFlatXp'];
    if (rawPaid is Map) {
      flatPaid[dateKey] = {
        for (final e in rawPaid.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toInt(),
      };
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

  /// Jumps to the week holding [day] — what the header's week picker calls.
  /// Never past the newest real week, so a picker built from stale bounds
  /// can't strand the board in the future.
  void goToWeek(DateTime day) {
    final target = startOfGridWeek(day);
    final newest = startOfGridWeek(DateTime.now());
    _goToWeek(target.isAfter(newest) ? newest : target);
  }

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
      // The single past-day case that IS allowed to reach the reward system,
      // and the exception the paragraph above needs: this exact habit-day was
      // completed for real, the app itself undid it, and it kept a receipt
      // saying so (see UndoneCompletion). Redeeming that is restoring a
      // record, not backfilling one. A day with no receipt still gets
      // nothing, which is every day nobody ever completed, so there is still
      // no square anywhere that colouring in can farm.
      if (greenDelta > 0) {
        _ref
            .read(dashboardProvider.notifier)
            .restoreUndoneCompletion(habitId: habitId, day: day)
            .ignore();
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
    // The receipt. This is the ONE method that pays the flat rate, so it is the
    // one that records what is owed back if the canonical completion path later
    // takes this square over — see WeeklyGridState.flatPaid and
    // setSquareStateOnlyAsync, which used to infer the amount from the colour
    // and so refunded five XP for a جزئي that a counted habit had painted from
    // its own count and never been paid for.
    _recordFlatPaid(habitId, day, _flatRateXp(value));
  }

  /// Records (or clears, at zero) the flat-rate XP banked on one square, in
  /// state and in the stored day, so a restart cannot lose the receipt and turn
  /// a later refund into a guess.
  void _recordFlatPaid(String habitId, DateTime day, int paid) {
    final key = day.toDateKey();
    if (state.flatPaidFor(habitId, day) == paid) return;
    final next = {
      for (final e in state.flatPaid.entries) e.key: {...e.value},
    };
    final row = next[key] ??= <String, int>{};
    if (paid == 0) {
      row.remove(habitId);
    } else {
      row[habitId] = paid;
    }
    state = state.copyWith(flatPaid: next);
    _persistFlatPaid(habitId, day, paid);
  }

  Future<void> _persistFlatPaid(String habitId, DateTime day, int paid) async {
    if (_uid != null) {
      _dayRef(day).set(
        {
          'squareFlatXp': {habitId: paid == 0 ? FieldValue.delete() : paid},
        },
        SetOptions(merge: true),
      ).ignore();
      return;
    }
    await LocalStoreService.updateDailyMap(day.toDateKey(), (stored) {
      final paidMap = Map<String, dynamic>.from(
          (stored['squareFlatXp'] as Map?)?.cast<String, dynamic>() ?? {});
      if (paid == 0) {
        paidMap.remove(habitId);
      } else {
        paidMap[habitId] = paid;
      }
      if (paidMap.isEmpty) {
        stored.remove('squareFlatXp');
      } else {
        stored['squareFlatXp'] = paidMap;
      }
    });
  }

  /// The XP a square showing [s] was paid by [setSquare]'s flat-rate delta
  /// math, and therefore the amount still owed back if something else takes
  /// that square over.
  ///
  /// `complete` is deliberately zero rather than its own 10: on today it is
  /// special-cased straight to `DashboardNotifier.completeHabit` (see
  /// grid_screen_table's tap handler), so a green square's XP never came
  /// from the flat rate and reversing it here would refund it twice — once
  /// via this path and again via `uncompleteHabit`.
  static int _flatRateXp(SquareState s) =>
      s == SquareState.complete ? 0 : s.xpValue;

  /// Sets a square's visual state without touching any reward system —
  /// for the cases where the reward is (or was already) handled by the
  /// canonical `DashboardNotifier.completeHabit`/`uncompleteHabit` path,
  /// so Grid's own flat-rate delta math ([setSquare]/
  /// `applyGridSquareChange`) must not also fire for the same change.
  ///
  /// It must still fire *backwards*, though, and that half was missing.
  /// [setSquare] pays a flat rate for every colour it sets, so a square
  /// sitting on yellow has already been paid 5 XP. When the canonical path
  /// then takes that same square over, only the new state's reward is
  /// handled — the old colour's 5 XP was left banked with nothing on screen
  /// to show for it. Tapping none → partial → complete → none therefore
  /// netted +5 XP per lap, repeatable forever, since the complete → none
  /// leg only ever refunds what `completeHabit` paid. Reversing the old
  /// colour here makes a full lap sum to exactly zero again.
  void setSquareStateOnly(String habitId, DateTime day, SquareState value) =>
      setSquareStateOnlyAsync(habitId, day, value);

  /// [setSquareStateOnly], but hands back the write so a caller that changes
  /// several squares at once can wait for all of them.
  ///
  /// The visible state is set synchronously either way, so awaiting this
  /// never delays the square turning. What it buys is knowing the day has
  /// actually been written: [autoCleanQuitDay] marks several habits in one
  /// go, and firing those writes without waiting used to let them race each
  /// other into the same stored day so that only the last one survived a
  /// restart. They queue correctly now (see LocalStoreService.updateDailyMap),
  /// but a caller that walks away still cannot know when the day is safe.
  Future<void> setSquareStateOnlyAsync(
      String habitId, DateTime day, SquareState value) {
    final old = state.squareFor(habitId, day);
    final key = day.toDateKey();
    final states = {
      for (final e in state.states.entries) e.key: {...e.value},
    };
    (states[key] ??= {})[habitId] = value;
    state = state.copyWith(states: states);
    final written = _persistSquare(habitId, day, value);

    // Only today ever earned flat-rate XP in the first place — [setSquare]
    // returns before the reward call on any other day (anti-backdating), so
    // there is nothing banked on a past square to give back.
    if (!day.isToday || old == value) return written;
    // What was ACTUALLY paid for this square, not what its colour is worth.
    //
    // Reading _flatRateXp(old) here assumed every yellow square had been paid
    // the flat five XP, which is true only of a square [setSquare] coloured. A
    // habit counted several times a day paints its own square جزئي from its
    // count (markResultFromHabit) and is paid in reward slices instead, so the
    // inference refunded five XP that had never been handed out — every counted
    // habit lost exactly that on the tap that finished its day, and lost it
    // again on every lap of tap-to-full-then-clear. The receipt says zero for
    // those squares and five for a palette-painted one, so the anti-farm
    // property this refund exists for (a none → جزئي → أخضر → none lap must sum
    // to zero) still holds exactly.
    final stranded = state.flatPaidFor(habitId, day);
    if (stranded == 0) return written;
    // Spent, so a second take-over of the same square cannot refund it twice.
    _recordFlatPaid(habitId, day, 0);
    // greenDelta stays 0 on purpose: the green-square counters belong to
    // whichever canonical call is taking this square over, and it is
    // already adjusting them for both the old and new state.
    _ref.read(dashboardProvider.notifier).applyGridSquareChange(
          xpDelta: -stranded,
          greenDelta: 0,
          dateKey: key,
        );
    return written;
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
      // Writer 3 of 3 for the report mirror — the one that covers PAST days,
      // since the complete/uncomplete pair only ever writes today. This is
      // also the ONLY writer that knows about the four non-green states, so
      // it is what makes تخطّي, فشل and جزئي reportable at all.
      final historyRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('habit_history')
          .doc(habitId);
      final dayKey = LocalStoreService.dateKey(day);
      if (value.isGreen) {
        // Written as painted, so bonus keeps its flavour instead of being
        // flattened into complete. Idempotent: repainting the same day is a
        // no-op and the mirror cannot drift.
        historyRef.set(
          {
            'days': {dayKey: markToStored(value)},
          },
          SetOptions(merge: true),
        ).ignore();
      } else {
        // Everything below the green line is conditional on the OTHER arm of
        // the union rule (see dayMark): a multi-tap habit completed from
        // Today has habitCompletions > 0 and an unpainted square, so acting
        // on square state alone un-did days the completion arm still owns
        // (the review's trace: paint, unpaint, mirror gone, count still 2).
        // One doc read on this path buys agreement with dayMark.
        _dayRef(day).get().then((snap) {
          final completions = (snap.data()?['habitCompletions'] as Map?)
              ?.cast<String, dynamic>();
          final count = completions?[habitId];
          if (count is num && count > 0) {
            // LEAVE IT ALONE. The completion arm of the union owns this key
            // (completeHabit writes it, uncompleteHabit deletes it), and this
            // writer must not touch a day a completion is speaking for.
            //
            // A version of this wrote 'complete' here instead, reasoning that
            // a real completion outranks a non-green label. It reads well and
            // it is a race: un-completing runs uncompleteHabit's batch (which
            // removes the completion AND deletes this key) alongside
            // setSquare's fire-and-forget read here. When the read lands
            // first it still sees the old count and writes 'complete' back,
            // resurrecting exactly what the undo just removed. Reproduced on
            // device: complete a habit, undo it, and the reports kept showing
            // it as مكتمل while the Grid, the XP and the day percentage had
            // all correctly returned to zero.
            //
            // Single ownership is the fix. Reading a value to decide whether
            // to overwrite another writer's key is the shape of the bug, not
            // the details.
            return;
          }
          historyRef.set(
            {
              // none is an absence, and absence is how the mirror spells it.
              // partial, failed and skipped are recorded facts and are kept.
              'days': {
                dayKey: value == SquareState.none
                    ? FieldValue.delete()
                    : markToStored(value),
              },
            },
            SetOptions(merge: true),
          ).ignore();
        }).ignore();
      }
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
      DateTime day, void Function(Map<String, dynamic>) mutate) =>
      // updateDailyMap, not a read then a put. The dashboard writes its own
      // fields into this same stored day, and a hand-rolled read, modify,
      // write here raced it: see LocalStoreService.updateDailyMap.
      LocalStoreService.updateDailyMap(day.toDateKey(), (map) {
        mutate(map);
        map['date'] = day.startOfDay.toIso8601String();
      });

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
    // Awaited, one after another. These all write the SAME stored day, and
    // walking away from them meant this method could return while several
    // writes were still in flight, which is how three auto cleaned quit
    // habits could come back from a restart as one.
    for (final id in habitIds) {
      final existing = SquareState.fromJson(raw[id]?.toString());
      if (existing != SquareState.none) continue;
      await setSquareStateOnlyAsync(id, day, SquareState.complete);
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
