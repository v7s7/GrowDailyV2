import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/datetime_ext.dart';
import '../../../core/services/local_store_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../habits/catalog/islamic_habit_catalog.dart'
    show IslamicHabitTemplate;
import '../../habits/notifiers/custom_habits_notifier.dart'
    show allHabitsEverProvider, habitListProvider;
import '../../habits/models/habit_day_demand.dart';
import '../../milestones/reports/habit_day_marks.dart';
import '../../premium/notifiers/premium_notifier.dart'
    show canBrowseHistoryMonth, kFreeHistoryMonths;
import '../models/square_state.dart';
import 'square_audit.dart';
import 'note_index_notifier.dart'
    show dayStillHasWriting, monthKeyOf, noteIndexRef;

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

  /// This week's completed sessions, in the shape a flexible weekly quota
  /// needs to know which of its days were load-bearing (see [habitOwesDay]),
  /// or NULL when this state cannot speak for the current week — still
  /// loading, or scrolled back to another one.
  ///
  /// Null is a real answer, not a failure: every live caller treats it as
  /// "assume the habit is still owed", which is what the board did before
  /// quotas were resolved at all. Reading an unloaded week instead would
  /// report seven empty days and hand a quota three free rest days on the
  /// strength of data that had not arrived, which is the one direction this
  /// must never be wrong in.
  GreenOnDay? get currentWeekGreen =>
      isCurrentWeek ? greenForWeekOf(DateTime.now().effectiveDay) : null;

  /// [currentWeekGreen] for any day: a reader for the week containing [day],
  /// or null when this state does not hold that week loaded.
  GreenOnDay? greenForWeekOf(DateTime day) =>
      !isLoading && weekStart.isSameDayAs(startOfGridWeek(day))
          ? (habitId, d) => squareFor(habitId, d).isGreen
          : null;

  /// [currentWeekGreen]'s twin for the whole mark, which the moved-session
  /// rule needs: a session on a day off a specific-days plan covers only a
  /// planned day with nothing on it, never one marked فشل, تخطّي or جزئي
  /// (see moved_day_plan.dart). Null exactly when [currentWeekGreen] is.
  MarkOnDay? get currentWeekMark =>
      isCurrentWeek ? markForWeekOf(DateTime.now().effectiveDay) : null;

  /// [greenForWeekOf]'s twin; see [currentWeekMark].
  MarkOnDay? markForWeekOf(DateTime day) =>
      !isLoading && weekStart.isSameDayAs(startOfGridWeek(day))
          ? squareFor
          : null;

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
  Set<String> halfDoneTodayIds() => _todayIdsMarked(SquareState.partial);

  /// Today's habits sitting on a تخطّي square, which leave the day's streak
  /// count entirely (see [streakCreditOf]). Read exactly as
  /// [halfDoneTodayIds] is.
  Set<String> skippedTodayIds() => _todayIdsMarked(SquareState.skipped);

  Set<String> _todayIdsMarked(SquareState mark) {
    final today = DateTime.now().effectiveDay;
    if (!isCurrentWeek || !days.any((d) => d.isSameDayAs(today))) return const {};
    final row = states[today.toDateKey()];
    if (row == null) return const {};
    return {
      for (final entry in row.entries)
        if (entry.value == mark) entry.key,
    };
  }

  /// Completion ratio for today's habit list in the visible week.
  ///
  /// The Grid can show a whole week of history, but the completion percent is
  /// a daily task metric: if there are 5 habits and 1 is green today, this is
  /// 20%, regardless of how many older squares were backfilled. A yellow
  /// partial square counts as half work, so 4 yellow marks across 4 tasks is
  /// 50% completion.
  ///
  /// [partialUnits] carries part-done credit for habits whose square is still
  /// empty because nothing has been tapped — today only the steps link uses
  /// it, handing in steps-over-goal for a linked walking habit. Kept as a
  /// parameter rather than read here because this class knows squares, not
  /// habits: the caller is the one holding the habit list and the day's step
  /// count. Empty by default, so every existing call is unchanged.
  double todayCompletionRatio(
    Iterable<String> habitIds, {
    Map<String, double> partialUnits = const {},
  }) {
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
      // A step count's measured share of its goal, when the caller knows it.
      final measured = (partialUnits[id] ?? 0.0).clamp(0.0, 1.0);
      completedUnits += switch (state) {
        SquareState.complete || SquareState.bonus => 1.0,
        // The flat half for a hand-marked جزئي, or the real share when the
        // step count set this square and has walked past half: 9,000 of
        // 10,000 is a جزئي square that scores 0.9, not 0.5.
        SquareState.partial => measured > 0.5 ? measured : 0.5,
        // An empty square can still be part done: a walking habit linked to
        // the step count contributes its real fraction of the goal here.
        //
        // The flat half a جزئي square gets is right for a tap — one of four
        // taps is a decision to do the thing, and the app rounds that
        // decision up. Steps are measured, not decided: 300 of 6,000 is not
        // half a walk, and paying half for it would put credit on the home
        // screen for carrying the phone to the kitchen. So this one is the
        // true proportion, clamped below 1 by the caller (at the goal the
        // habit is already complete and scores through its square).
        SquareState.none => measured,
        SquareState.failed || SquareState.skipped => 0.0,
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

  /// Every habit's stored square for [day], read from the store rather than
  /// from the visible week. Null when the store could not be read at all,
  /// which is NOT the same answer as "no marks".
  ///
  /// [WeeklyGridState.squareFor] can only speak for the seven days actually
  /// loaded. For every other day it returns `none`, which is indistinguishable
  /// from "nobody ever marked it". That is harmless for drawing a board that
  /// only shows those seven, and wrong for anything that has to DECIDE
  /// something about a day off screen. The steps back-fill is exactly that: on
  /// the first day of a grid week yesterday belongs to the week before, so an
  /// unloaded تخطّي would have read as a blank day and been painted green.
  ///
  /// The null is the other half of the same care. An unreadable day (offline,
  /// a cold first run) must not be reported as an empty one, or a caller
  /// deciding "nobody has spoken about this day" acts on a day it never saw.
  Future<Map<String, SquareState>?> storedSquaresFor(DateTime day) async {
    final states = <String, Map<String, SquareState>>{};
    final notes = <String, Map<String, String>>{};
    final flatPaid = <String, Map<String, int>>{};
    final key = day.toDateKey();
    try {
      if (_uid != null) {
        final snap = await _dayRef(day).get();
        if (snap.exists) {
          _parseInto(snap.id, snap.data()!, states, notes, flatPaid);
        }
      } else {
        _parseInto(
          key,
          await LocalStoreService.getDailyMap(key),
          states,
          notes,
          flatPaid,
        );
      }
    } catch (_) {
      return null;
    }
    return states[key] ?? const {};
  }

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
        // Seven independent reads still — that isolation is the whole point
        // of the comment above — but issued together rather than one after
        // another, so the board waits one round trip instead of seven. Each
        // carries its own onError, so a day that throws yields null and the
        // rest of the week is unaffected, exactly as the loop did. NOT a
        // range query over the seven: that would batch them back into a
        // single get() and bring the blanked-week bug straight back.
        final snaps = await Future.wait([
          for (final day in state.days)
            _dayRef(day).get().then<DocumentSnapshot<Map<String, dynamic>>?>(
                  (snap) => snap,
                  onError: (Object _) => null,
                ),
        ]);
        for (final snap in snaps) {
          if (snap == null || !snap.exists) continue;
          _parseInto(snap.id, snap.data()!, states, notes, flatPaid);
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

  /// True while the user has deliberately navigated AWAY from the current
  /// week. [refresh] respects it: a resume must not yank someone off a
  /// past week they are reading, but a board that was simply left on
  /// "this week" must follow the calendar across a Saturday boundary.
  bool _userPinnedWeek = false;

  void previousWeek() {
    _userPinnedWeek = true;
    _goToWeek(state.weekStart.subtract(const Duration(days: 7)));
  }

  void nextWeek() {
    if (!state.canGoForward) return;
    final target = state.weekStart.add(const Duration(days: 7));
    _userPinnedWeek = !target.isSameDayAs(startOfGridWeek(DateTime.now()));
    _goToWeek(target);
  }

  /// Jumps to the real calendar's current week — see [WeeklyGridState.
  /// canGoForward]'s doc comment for why that's real-today's week and not
  /// effectiveDay's.
  void goToCurrentWeek() {
    _userPinnedWeek = false;
    _goToWeek(startOfGridWeek(DateTime.now()));
  }

  /// Jumps to the week holding [day] — what the header's week picker calls.
  /// Never past the newest real week, so a picker built from stale bounds
  /// can't strand the board in the future.
  void goToWeek(DateTime day) {
    final target = startOfGridWeek(day);
    final newest = startOfGridWeek(DateTime.now());
    _userPinnedWeek = target.isBefore(newest);
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
    setSquare(habitId, day, current.next, source: kSquareSourceTap);
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
  void setSquare(
    String habitId,
    DateTime day,
    SquareState value, {
    String source = kSquareSourceUnknown,
  }) {
    final old = state.squareFor(habitId, day);
    final key = day.toDateKey();
    final states = {
      for (final e in state.states.entries) e.key: {...e.value},
    };
    (states[key] ??= {})[habitId] = value;
    state = state.copyWith(states: states);
    _persistSquare(habitId, day, value, previous: old, source: source);

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
    // isOpenDay, not isToday. Yesterday is still payable until the day cutoff
    // (see DateTimeGameExt.isOpenDay), so it must NOT take the no-reward path
    // — its square goes through the canonical completion like today's. This
    // said isToday, and between midnight and the cutoff that sent the square
    // the app itself was calling TODAY down here: coloured, counted by Rooms,
    // and paid nothing.
    if (!day.isOpenDay) {
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
        // A day recorded late can also undo a streak-gap judgement that
        // charged for it: the freezes it spent go back, and a streak it broke
        // comes back once the window owes nothing. Nothing is paid here, see
        // DashboardNotifier.refreshStreakGapCharge; this only stops a day the
        // person really did from being counted as missed.
        _ref
            .read(dashboardProvider.notifier)
            .repairStreakGapForDay(
              day: day,
              habits: _ref.read(allHabitsEverProvider),
              squaresOn: storedSquaresFor,
            )
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
  void setSquareStateOnly(
    String habitId,
    DateTime day,
    SquareState value, {
    String source = kSquareSourceUnknown,
  }) =>
      setSquareStateOnlyAsync(habitId, day, value, source: source);

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
    String habitId,
    DateTime day,
    SquareState value, {
    String source = kSquareSourceUnknown,
  }) {
    final old = state.squareFor(habitId, day);
    final key = day.toDateKey();
    final states = {
      for (final e in state.states.entries) e.key: {...e.value},
    };
    (states[key] ??= {})[habitId] = value;
    state = state.copyWith(states: states);
    final written =
        _persistSquare(habitId, day, value, previous: old, source: source);

    // Only today ever earned flat-rate XP in the first place — [setSquare]
    // returns before the reward call on any other day (anti-backdating), so
    // there is nothing banked on a past square to give back.
    if (!day.isOpenDay || old == value) return written;
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
  void markCompleteFromHabit(
    String habitId,
    DateTime day, {
    String source = kSquareSourceUnknown,
  }) =>
      markResultFromHabit(habitId, day, SquareState.complete,
          source: source);

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
  void markResultFromHabit(
    String habitId,
    DateTime day,
    SquareState value, {
    String source = kSquareSourceUnknown,
  }) {
    if (state.squareFor(habitId, day) == value) return;
    setSquareStateOnly(habitId, day, value, source: source);
  }

  /// Mirrors a completion of a habit counted [perDay] times a day onto
  /// [day]'s square, from that day's own count: جزئي while slots are still
  /// owed, complete once the count is full. Answers whether it painted, so
  /// the caller can tell the room (syncRoomToday).
  ///
  /// For completions made off the Grid, where nothing else paints the
  /// square: completeHabit answers isGridSyncable (`frequencyTarget == 1`),
  /// false for every tap of a counted habit, so main.dart's notification
  /// Mark Done, and the Home Screen widget's tick that runs through it, paint
  /// here by hand.
  ///
  /// The count is DashboardState.countOn's: today's `completions` for today
  /// and, for yesterday while it is still open, graceCompletions, which
  /// completeHabit writes whenever a call on yesterday lands. main.dart read
  /// `completions` for both, and a tap queued with the app closed is paid on
  /// the day it was made, yesterday when the app opens after midnight: the
  /// square stayed empty while yesterday's count moved, or went green at 2
  /// of 4 because today was finished. Rooms, the heatmap and the reports
  /// read that square. A day this state holds no count for paints nothing:
  /// not held is not zero, and it is never today's. See
  /// notification_counted_square_test.dart.
  bool markCountFromHabit(
    String habitId,
    DateTime day, {
    required int perDay,
    String source = kSquareSourceUnknown,
  }) {
    final done = _ref.read(dashboardProvider).countOn(habitId, day);
    if (done == null || done <= 0) return false;
    markResultFromHabit(
      habitId,
      day,
      done >= perDay ? SquareState.complete : SquareState.partial,
      source: source,
    );
    return true;
  }

  /// "Once ONE more completion of [habit] lands on [day], is [day]'s list
  /// at the streak threshold?", for a day whose counts `completions` does
  /// not hold (yesterday while it is still open), answered from its squares
  /// with [habit]'s own judged as that completion leaves it: green once it
  /// fills the count ([doneBefore], the day's count before it, plus one
  /// reaches the habit's daily target), جزئي before that. At a target of 1
  /// every completion fills the count, so a habit done once a day is judged
  /// exactly as willCompleteAllSquaresOn judges it.
  ///
  /// main.dart's notification Mark Done asked willCompleteAllSquaresOn for
  /// every tap on yesterday, which judges the square green whether or not
  /// the tap finished the count: yesterday with two habits, one done and one
  /// counted four times going from 1 to 2, was judged 2 of 2 and earned its
  /// streak point at 1.5 of 2. The Grid's own counter tap already asked it
  /// this way (_GridTableState._addOneToday). See
  /// notification_slot_streak_test.dart.
  bool slotCrossesStreakOn(
    IslamicHabitTemplate habit,
    DateTime day, {
    required int doneBefore,
  }) =>
      _crossesOnMark(
        habit,
        day,
        doneBefore + 1 >= habit.effectiveDailyTarget
            ? SquareState.complete
            : SquareState.partial,
      );

  /// [squaresCrossStreakThreshold] over [day]'s own board and this state's
  /// squares: the day's answerable roster, not everything allowed on it (a
  /// flexible quota's rest day leaves the denominator, see boardHabitsOn),
  /// with [habit], the one being marked right now, kept in it whatever its
  /// week says and judged as [mark]. The one place the Grid's streak
  /// questions for a day other than today are put together.
  bool _crossesOnMark(
    IslamicHabitTemplate habit,
    DateTime day,
    SquareState mark,
  ) =>
      squaresCrossStreakThreshold(
        dayHabits: boardHabitsOn(
          habits: _ref.read(habitListProvider),
          day: day,
          isGreen: state.greenForWeekOf(day),
          markOn: state.markForWeekOf(day),
          alsoOwing: {habit.id},
        ).map((h) => h.id),
        squareOf: (id) => state.squareFor(id, day),
        habitId: habit.id,
        mark: mark,
      );

  /// Attach (or clear) a daily reflection note for a habit's square.
  ///
  /// Returns the persist future so the editor can raise a failure bar. The
  /// in-memory write above it is synchronous and is never rolled back: the
  /// note is the user's own sentence, and deleting it to punish a bad
  /// network is a worse outcome than a stale-until-refresh square.
  Future<void> setNote(String habitId, DateTime day, String note) {
    final key = day.toDateKey();
    final trimmed = note.trim();
    final notes = {
      for (final e in state.notes.entries) e.key: {...e.value},
    };
    (notes[key] ??= {})[habitId] = trimmed;
    state = state.copyWith(notes: notes);
    return _persistNote(habitId, day, trimmed, notes[key]!);
  }

  Future<void> _persistSquare(
    String habitId,
    DateTime day,
    SquareState value, {
    required SquareState previous,
    required String source,
  }) async {
    // The one choke point every square write passes through, which makes it
    // the only place a trail can be complete. Records losses only — see
    // squareChangeLosesCredit.
    SquareAudit.record(
      uid: _uid,
      habitId: habitId,
      day: day,
      from: previous,
      to: value,
      source: source,
    );
    if (_uid != null) {
      _dayRef(day).set(
        {
          'squareStates': {habitId: value.toJson()},
          // A sibling map, not a field on squareStates itself: every
          // existing reader of squareStates (the Grid, the heatmap, Rooms,
          // this doc's own toJson/fromJson round trip) keeps reading a bare
          // enum string, unchanged. This is purely additive — admin_lookup
          // is its only reader today (see renderRecordLedger's sourceFor) —
          // so a square colored before this shipped simply has no entry
          // here, not a wrong one.
          'squareSources': {habitId: source},
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

  /// Writes the note AND the day's entry in the note index as one batch.
  ///
  /// Atomic on purpose. A second copy of "this day has writing" has always
  /// been unsafe here, but not because it is a copy: because the write it
  /// copies was unobserved. This used to be `.ignore()`d, so the app could
  /// not tell a saved note from a lost one, index or no index. A batch
  /// commits both documents or neither, so the index inherits the note's own
  /// reliability instead of adding a second, worse one, and the returned
  /// future finally gives the editor something to show a failure from.
  ///
  /// [dayNotes] is the day's whole note row after this edit, which is what
  /// makes the index exact: clearing one of two notes on a day correctly
  /// leaves the day marked.
  Future<void> _persistNote(
    String habitId,
    DateTime day,
    String note,
    Map<String, String> dayNotes,
  ) async {
    if (_uid != null) {
      // Clearing DELETES the key rather than writing ''. The old behaviour
      // left a permanent tombstone on every note ever cleared, which any
      // presence check built on key existence would count as writing. Same
      // shape as _persistFlatPaid's `paid == 0 ? FieldValue.delete() : paid`.
      //
      // Built INSIDE this branch: FieldValue is a Firestore platform call,
      // and the guest path must not touch Firestore at all (in a widget test
      // there is no Firebase app, so constructing one here threw and took
      // every guest note write with it).
      final value = note.isEmpty ? FieldValue.delete() : note;
      final batch = FirebaseFirestore.instance.batch();
      batch.set(
        _dayRef(day),
        {
          'squareNotes': {habitId: value},
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      // Adding is unconditional: a day that now carries writing carries it
      // whatever else is in the row. REMOVING depends on knowing the whole
      // row, and _goToWeek wipes `notes` to const {} while a week loads, so
      // a clear landing in that window would see a one-entry row, conclude
      // the day is empty, and arrayRemove a day another habit still writes
      // on. Skipping the index write there leaves the previous, correct
      // value for the healer, which is the safe direction to fail in.
      final still = dayStillHasWriting(dayNotes, habitId, note);
      if (still || !state.isLoading) {
        batch.set(
          noteIndexRef(_uid),
          {
            'months': {
              monthKeyOf(day.toDateKey()): still
                  ? FieldValue.arrayUnion([day.day])
                  : FieldValue.arrayRemove([day.day]),
            },
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      return;
    }
    // The guest keeps no index: allDailyMaps() folds the truth for free.
    await _mergeGuestDaily(day, (map) {
      final notes = Map<String, dynamic>.from(
          (map['squareNotes'] as Map?)?.cast<String, dynamic>() ?? {});
      if (note.isEmpty) {
        notes.remove(habitId);
      } else {
        notes[habitId] = note;
      }
      if (notes.isEmpty) {
        map.remove('squareNotes');
      } else {
        map['squareNotes'] = notes;
      }
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
  /// NotificationService.scheduleEveningNote for the other half). A quit
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
  ///
  /// Returns whether it marked anything. Only then has a stored square
  /// changed, so only then does main.dart re-grade the rooms: it re-graded
  /// every room on every launch that had an eligible habit, about 150 reads
  /// for a member of three rooms, almost always to find nothing new.
  Future<bool> autoCleanQuitDay(List<String> habitIds, DateTime day) async {
    if (habitIds.isEmpty) return false;
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
      return false;
    }
    if (!mounted) return false;
    final raw = (data['squareStates'] as Map?) ?? const {};
    var marked = false;
    // Awaited, one after another. These all write the SAME stored day, and
    // walking away from them meant this method could return while several
    // writes were still in flight, which is how three auto cleaned quit
    // habits could come back from a restart as one.
    for (final id in habitIds) {
      final existing = SquareState.fromJson(raw[id]?.toString());
      if (existing != SquareState.none) continue;
      await setSquareStateOnlyAsync(id, day, SquareState.complete,
          source: kSquareSourceQuitAutoClean);
      marked = true;
    }
    return marked;
  }

  /// Reloads the visible week — and, unless the user deliberately parked
  /// the board on a past week, first snaps to the CURRENT week. refresh()
  /// used to be a bare _loadWeek(), which re-read whatever weekStart the
  /// notifier was constructed with; main.dart's resume path calls this
  /// with a comment promising it fixes the stale-board-across-a-Saturday
  /// case, and without the snap that promise was empty: an app left open
  /// across the week boundary kept showing last week until a restart.
  Future<void> refresh() async {
    if (!_userPinnedWeek) {
      final newest = startOfGridWeek(DateTime.now());
      if (!state.weekStart.isSameDayAs(newest)) {
        _goToWeek(newest);
        return;
      }
    }
    await _loadWeek();
  }
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

/// The roster a Grid mark on [day] judges TODAY's streak point against, in
/// the shape [willCompleteAllHabitsToday] takes: the day's own board (see
/// boardHabitsOn), the list the summary card counts «من N عادات اليوم» from,
/// with [markingId], the habit being marked, kept on it whatever its week
/// says.
///
/// The Grid used every habit allowed on that weekday (isScheduledFor), so a
/// weekly quota's rest day sat in its denominator while the card, Today's
/// Mark Done, Tasbih, steps and every grace-day mark
/// ([willCompleteAllSquaresOn]) left it out. With تمرين resting, a day the
/// card showed as 7 of 8 (88%) was judged 7 of 9 (78%) and earned no point.
Iterable<({String id, int frequencyTarget})> gridStreakRoster({
  required Iterable<IslamicHabitTemplate> habits,
  required WeeklyGridState grid,
  required String markingId,
  required DateTime day,
}) =>
    boardHabitsOn(
      habits: habits,
      day: day,
      isGreen: grid.greenForWeekOf(day),
      markOn: grid.markForWeekOf(day),
      alsoOwing: {markingId},
    ).map((h) => (id: h.id, frequencyTarget: h.effectiveDailyTarget));

/// "Will this day's whole list be done once this tap lands?", answered from
/// the day's own SQUARES instead of from `DashboardState.completions`.
///
/// [willCompleteAllHabitsToday] reads `completions`, which only ever holds
/// TODAY's counts — correct for today and meaningless for any other day. A
/// day inside its grace window (yesterday, before the cutoff) still needs a
/// real answer, because that answer is what earns its streak point, and
/// getting it from today's map would either invent a point or withhold one.
///
/// The squares are the right source for that day: they are what the Grid is
/// showing the person, what the yearly strip reports, and what a Room grades
/// them on. جزئي counts half, exactly as it does everywhere else.
///
/// Lives here, beside the squares it reads, rather than in the Grid screen
/// where it started: main.dart's notification-action drain pays a tap made
/// on a grace day (a lock-screen «تمت» at 22:00, app opened at 09:00)
/// through this same rule, and a `part` of the Grid screen cannot be
/// imported.
bool willCompleteAllSquaresOn(
  WidgetRef ref,
  IslamicHabitTemplate habit,
  DateTime day,
) =>
    _squaresCrossOnMark(ref, habit, day, SquareState.complete);

/// The جزئي twin of [willCompleteAllSquaresOn]: "does marking [habit] جزئي
/// (rather than complete) cross [kStreakDayCompletionThreshold]?" — the
/// question a palette pick of yellow needs answered, exactly as a palette
/// pick of green needs [willCompleteAllSquaresOn].
///
/// [habit] is credited HALF, not the full point [willCompleteAllSquaresOn]
/// gives its own target — a جزئي is half the work everywhere else in this
/// app, and crediting it in full here would let marking one habit half-done
/// finish the day on its own.
///
/// No separate guard is needed against a day made entirely of جزئي squares
/// (the "day made entirely of half-done squares" case
/// [DashboardState.streakEarnedToday] says must never qualify on its own):
/// every square here is worth at most 0.5, so a day with no green or blue
/// square anywhere can never average above 0.5, and
/// [kStreakDayCompletionThreshold] is 0.8. The arithmetic already refuses
/// it.
bool willCrossStreakThresholdOnPartial(
  WidgetRef ref,
  IslamicHabitTemplate habit,
  DateTime day,
) =>
    _squaresCrossOnMark(ref, habit, day, SquareState.partial);

/// The تخطّي twin of [willCompleteAllSquaresOn]: "does marking [habit] تخطّي
/// finish the day?" It can: the skipped habit leaves the day's count, so
/// three habits done of four, with the fourth then skipped, is three of
/// three. Aziz, 2026-09-22, choosing "skip a habit: fine; skip the whole
/// day: no": a day whose every habit is skipped counts nothing, earns
/// nothing, and is judged a miss (a freeze can cover it) like any other day
/// that earned no point.
bool willCrossStreakThresholdOnSkip(
  WidgetRef ref,
  IslamicHabitTemplate habit,
  DateTime day,
) =>
    _squaresCrossOnMark(ref, habit, day, SquareState.skipped);

/// WeeklyGridNotifier._crossesOnMark, reached from a screen's ref: the
/// day's own board and the Grid's loaded squares, with the habit being
/// marked right now judged as [mark].
bool _squaresCrossOnMark(
  WidgetRef ref,
  IslamicHabitTemplate habit,
  DateTime day,
  SquareState mark,
) =>
    ref.read(weeklyGridProvider.notifier)._crossesOnMark(habit, day, mark);

/// What one square is worth toward its day's streak point: a green square
/// 1, a جزئي half, anything else nothing, and a تخطّي NULL, meaning it
/// leaves the day's count entirely. Aziz, 2026-09-22: skipping a habit is
/// rest («لا تُحسب عليك»), so the other habits need their 80% without it.
double? streakCreditOf(SquareState square) => switch (square) {
      SquareState.complete || SquareState.bonus => 1,
      SquareState.partial => 0.5,
      SquareState.skipped => null,
      _ => 0,
    };

/// Whether [habitId]'s square turning [mark] takes its day to
/// [kStreakDayCompletionThreshold], judged on the day's squares
/// ([squareOf]) over [dayHabits], every square worth [streakCreditOf].
///
/// The one rule behind a مكتمل pick ([willCompleteAllSquaresOn]), a جزئي
/// pick ([willCrossStreakThresholdOnPartial]) and a تخطّي pick
/// ([willCrossStreakThresholdOnSkip]). A day with nothing left to count, a
/// day off or a day skipped whole, is never a completed day.
bool squaresCrossStreakThreshold({
  required Iterable<String> dayHabits,
  required SquareState Function(String habitId) squareOf,
  required String habitId,
  required SquareState mark,
}) {
  var total = 0;
  var credited = 0.0;
  var sawTarget = false;
  for (final id in dayHabits) {
    final isTarget = id == habitId;
    if (isTarget) sawTarget = true;
    final credit = streakCreditOf(isTarget ? mark : squareOf(id));
    if (credit == null) continue;
    total++;
    credited += credit;
  }
  if (total == 0 || !sawTarget) return false;
  return credited / total >= kStreakDayCompletionThreshold;
}
