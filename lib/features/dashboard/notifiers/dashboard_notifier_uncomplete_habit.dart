part of 'dashboard_notifier.dart';

/// The value to write for [habitId] into a SPARSE map that is persisted with
/// `SetOptions(merge: true)`.
///
/// Returns the new value when the habit still has one, and an explicit
/// [FieldValue.delete] when it does not.
///
/// This exists because merge semantics are the opposite of the obvious
/// reading: merging a nested map updates the keys PRESENT in the written
/// data and leaves every other key untouched. So "copy the map, remove the
/// key, write the map" removes nothing at all on the server. Every sparse
/// per-habit map in this file (completions, total completions, streak
/// counts, longest streaks, last completed date) drops its key at zero and
/// so must go through here.
///
/// Returns the WRAPPED map, `{habitId: value}`, and not the bare value, so a
/// call site physically cannot write the delta as the field itself. An earlier
/// version returned the bare value and left the wrapping to five call sites;
/// they were written unwrapped, so `'habitCompletions': FieldValue.delete()`
/// removed the entire field rather than one key. That wiped a whole day of
/// completions and an account's entire habitTotalCompletions map, and the next
/// load threw on `as Map` and set DashboardState.loadFailed, which blocks
/// every reward write. The API now makes that mistake unrepresentable.
///
/// Nested map rather than a dotted key on purpose: inside `set(merge: true)`
/// a dotted string is a literal field name, not a path. The file's other
/// writes already comment on that.
Map<String, Object> habitCompletionDelta<T extends Object>(
  String habitId,
  Map<String, T>? updated,
) =>
    {habitId: updated?[habitId] ?? FieldValue.delete()};

extension DashboardNotifierUncompleteHabit on DashboardNotifier {

  /// Reverses a same-day completion made via [completeHabit] — the "I
  /// completed this by mistake" correction available from Grid's
  /// long-press editor on a synced, completed-today square, and from
  /// quit-habit's affirm→slip mis-tap correction.
  ///
  /// Operates on today by default, and on [day] when one is given — which is
  /// only ever yesterday, still inside its grace window (see
  /// DateTimeGameExt.isOpenDay). An undo has to reach exactly as far back as
  /// a completion can, or a mark made during the grace could not be taken
  /// back by the person who made it.
  ///
  /// Reverses what's safe to reverse: the base XP/gold the caller passes
  /// in, plus — via [_lastHabitCompletion], when a same-session record of
  /// this exact completion exists — the surprise-bonus/per-habit-milestone
  /// XP/Gold it awarded, and the `habitStreakCounts` /
  /// `habitLongestStreaks` / `habitTotalCompletions` /
  /// `habitLastCompletedDate` bump for this one habit. Also always
  /// reverses `completions[habitId]` (back to not-done so Today un-checks
  /// it too), `categoryCompletions`, `totalCompletions`, and the
  /// `totalGreenSquares`/`dailyGreenCounts` counters this phase added for
  /// synced completions. Today's spent cap allowance
  /// (`earnedXpToday`/`earnedGoldToday`) is refunded alongside them, sized
  /// from what the undo actually removed — see the earn-counter note in the
  /// body for why that size and not the nominal reward.
  ///
  /// Without a snapshot (the app was fully restarted between the
  /// completion and the undo, so [_lastHabitCompletion] lost it) the
  /// per-habit streak fields and their bonus are left untouched rather
  /// than guessed at — guessing wrong would silently corrupt a real streak
  /// count (e.g. resetting a 6-day streak to 1 because "completed again
  /// today" looks identical to "completed for the first time"), which is
  /// worse than occasionally leaving a few stray XP/gold uncorrected.
  ///
  /// Leaves behind an [UndoneCompletion] receipt whenever it takes the day's
  /// LAST completion of this habit away, so the same habit-day being marked
  /// done again later is recognised as putting a mistake right rather than as
  /// backfilling a day that never happened. See that class for why the app
  /// could not tell those apart before, and
  /// [DashboardNotifier.restoreUndoneCompletion] for the redemption. A
  /// multi-tap habit dropping from 8/8 to 7/8 writes nothing: the day is still
  /// done, so there is no completion to put back.
  ///
  /// Deliberately does **not** touch `unlockedAchievements` — nothing in
  /// this app ever revokes an unlocked achievement, the same way a real
  /// trophy doesn't get taken back once earned — or
  /// `streak`/`longestStreak`/`streakEarnedToday`/its milestone bonus:
  /// once today has been credited as a full 100% day, undoing one habit
  /// again is left alone rather than un-crediting it. This is the same
  /// one-way, conservative bias [DashboardState.streakEarnedToday]
  /// documents for the "add a new habit after 100%" case — today's
  /// *whole-day* credit only ever moves forward, even though this one
  /// habit's own reward and per-habit streak now reverse precisely.
  /// [frequencyTarget] is the habit's per-day count, and exists so the
  /// refund is the same size as the debit: completeHabit paid this tap only
  /// its slice of the day (see XpCalculator.rewardSliceForTap), so giving
  /// back a whole day's xpReward here would mint XP on every undo of a
  /// counted habit. Defaults to 1, which makes the slice the whole reward
  /// and leaves every pre-existing caller behaving exactly as before.
  /// [clearWholeDay] takes the habit's whole day off in one call rather than
  /// one tap at a time, and exists for the Grid's counted square: tapping a
  /// full square is meant to empty it (design/Grid.dc.html), and looping this
  /// method N times to get there would decrement habitTotalCompletions N
  /// times against the single bump completeHabit made on the day's first tap.
  /// The refund is everything the day was actually paid, so a 2-of-4 day
  /// gives back two slices and a 4-of-4 day gives back the whole reward.
  Future<void> uncompleteHabit({
    required String habitId,
    required int xpReward,
    required int goldReward,
    int frequencyTarget = 1,
    bool clearWholeDay = false,
    String? category,
    DateTime? day,
  }) async {
    // See completeHabit's guard: this method writes level, currentLevelXp,
    // cumulativeXp, gold, totalHabitCompletions and categoryCompletions as
    // absolute values from `state` too, so it must decline for the same
    // reason. In practice a failed load leaves `completions` empty and the
    // `current <= 0` check below already turns most calls away — this makes
    // that an explicit rule rather than a side effect of the zeros lining up.
    if (_uid != null && state.loadFailed) return;

    // Which day is being corrected — see completeHabit's [day] for the whole
    // reasoning. Null is today; a non-null day is only ever yesterday inside
    // its grace window, so an undo can reach exactly as far back as a
    // completion can.
    final markDay = (day ?? _clock().effectiveDay).startOfDay;
    final isGraceDay = markDay.toDateKey() != _todayKeyNow;
    if (isGraceDay && !markDay.isOpenDayAt(_clock())) return;

    // Today's counts are in `state`; a grace day's are read off the day, the
    // same split completeHabit makes and for the same reason: an undo on
    // another day must not touch the board on screen.
    Map<String, int> dayCompletions = state.completions;
    var dayPaid = _paidToday;
    if (isGraceDay) {
      final stored = await _readStoredDay(markDay);
      dayCompletions = stored.completions;
      dayPaid = stored.paid;
    }

    final current = dayCompletions[habitId] ?? 0;
    if (current <= 0) return;

    // Decrement by one, not remove.
    //
    // This method refunds exactly ONE xpReward and decrements the lifetime
    // counters by one, so clearing the whole day's count for the habit was a
    // mismatch: a multi-tap habit (drink water 8x) sitting at 8/8 gave back
    // one reward while eight completions vanished — and every re-tap could
    // then be paid again, netting XP on each lap. Taking one off makes the
    // refund and the debit the same size, and 8/8 → 7/8 is also what a
    // person means by undoing one tap.
    //
    // The key is dropped entirely at zero so the map stays sparse, which is
    // what isCompleted's `?? 0` fallback and the Firestore writes below
    // both assume.
    // Whether this undo takes the habit's whole day off. The day's first-tap
    // fields — the [_lastHabitCompletion] snapshot, the per-habit streak, and
    // the lifetime completion counter — were each written ONCE, on the tap that
    // started the day (completeHabit's `current == 0` branch), so they may only
    // be reversed when the day is actually emptied. A one-tap undo of a counted
    // habit that still has taps left (4/4 → 3/4) must leave them exactly as they
    // are. Before habits could be counted `current` was never above 1, so this
    // was unconditionally true and the distinction did not exist.
    final emptiesDay = clearWholeDay || current <= 1;
    final newCompletions = Map<String, int>.from(dayCompletions);
    if (emptiesDay) {
      newCompletions.remove(habitId);
    } else {
      newCompletions[habitId] = current - 1;
    }

    // Consumed only when the day empties. Peeking-without-removing on a partial
    // undo keeps the day's first-tap snapshot in place for the eventual clear,
    // and — crucially — stops a one-tap undo restoring the pre-first-tap streak
    // and clawing back every tap's accumulated bonus against a single slice.
    final snapshot = emptiesDay ? _lastHabitCompletion.remove(habitId) : null;

    Map<String, int>? newHabitStreakCounts;
    Map<String, int>? newHabitLongestStreaks;
    Map<String, String>? newHabitLastCompletedDate;
    if (snapshot != null) {
      newHabitStreakCounts = {...state.habitStreakCounts};
      newHabitLongestStreaks = {...state.habitLongestStreaks};
      newHabitLastCompletedDate = {...state.habitLastCompletedDate};
      if (snapshot.hadPrior) {
        newHabitStreakCounts[habitId] = snapshot.prevStreak;
        newHabitLongestStreaks[habitId] = snapshot.prevLongest;
        final prevDate = snapshot.prevLastCompletedDate;
        if (prevDate != null) {
          newHabitLastCompletedDate[habitId] = prevDate;
        } else {
          newHabitLastCompletedDate.remove(habitId);
        }
      } else {
        newHabitStreakCounts.remove(habitId);
        newHabitLongestStreaks.remove(habitId);
        newHabitLastCompletedDate.remove(habitId);
      }
    }

    // completeHabit bumps this lifetime counter once per day, on the first tap
    // (`current == 0`), so it may only be decremented when the day is emptied —
    // exactly like the counter, not once per undone tap. Gating on [emptiesDay]
    // is what keeps a counted habit's one-tap undo (4/4 → 3/4, first tap's +1
    // still standing) from dropping the counter, and two such undos from
    // dropping it twice against a single +1. When the day does empty this is
    // always safe to correct, even across a restart, without the same-session
    // snapshot the streak fields need: the early-return above already confirmed
    // a real completion is being reversed. This is also the *only* signal
    // add_habit_sheet/grid_screen read to decide hard-delete vs. archive when a
    // habit is removed, so a stale value here would make a truly never-completed
    // habit refuse to hard-delete and silently soft-archive instead.
    final newHabitTotalCompletions = {...state.habitTotalCompletions};
    if (emptiesDay) {
      final rawHabitTotal = (newHabitTotalCompletions[habitId] ?? 0) - 1;
      if (rawHabitTotal <= 0) {
        newHabitTotalCompletions.remove(habitId);
      } else {
        newHabitTotalCompletions[habitId] = rawHabitTotal;
      }
    }

    // The slice this exact tap was paid — tapIndex is the count BEFORE the
    // tap, and the tap being undone is the one that took the habit from
    // current - 1 to current. The stored bonus is refunded whole because
    // completeHabit already sized it against the slice.
    final xpSlice = clearWholeDay
        ? XpCalculator.rewardPaidSoFar(
            total: xpReward, target: frequencyTarget, done: current)
        : XpCalculator.rewardSliceForTap(
            total: xpReward, target: frequencyTarget, tapIndex: current - 1);
    final goldSlice = clearWholeDay
        ? XpCalculator.rewardPaidSoFar(
            total: goldReward, target: frequencyTarget, done: current)
        : XpCalculator.rewardSliceForTap(
            total: goldReward, target: frequencyTarget, tapIndex: current - 1);
    // ── Exact reversal ───────────────────────────────────────────
    //
    // The ledger on the day (habitPaidXp/habitPaidGold, see _paidToday) says
    // what this habit was ACTUALLY paid: capped slices, surprise bonuses and
    // the per-habit milestone, as they landed. Emptying the day gives back
    // exactly that. A one-tap undo of a counted habit gives back that tap's
    // nominal slice, never more than the ledger still holds. The nominal
    // arithmetic above survives only as the fallback for a day recorded by
    // a build older than the ledger.
    //
    // Two defects this closes, both seen on 2026-09-07: a completion the
    // daily ceiling had clamped was undone at its full nominal price, so the
    // account lost XP and gold it was never paid; and after a restart the
    // in-memory snapshot was gone, so the undo left every bonus behind.
    final nominalXp = xpSlice + (snapshot?.bonusXp ?? 0);
    final nominalGold = goldSlice + (snapshot?.bonusGold ?? 0);
    final recorded = dayPaid[habitId];
    final int totalXpReward;
    final int totalGoldReward;
    if (recorded == null) {
      totalXpReward = nominalXp;
      totalGoldReward = nominalGold;
    } else if (emptiesDay) {
      totalXpReward = recorded.xp;
      totalGoldReward = recorded.gold;
    } else {
      totalXpReward = nominalXp < recorded.xp ? nominalXp : recorded.xp;
      totalGoldReward =
          nominalGold < recorded.gold ? nominalGold : recorded.gold;
    }

    // ── What the reversal can actually take back ─────────────────
    //
    // Computed HERE, above the receipt, because the receipt has to be sized
    // from what the undo REMOVED rather than from what the completion was
    // owed, and those two numbers are not always the same.
    //
    // Both currencies floor at zero: XpCalculator.applyXpDelta clamps
    // newCumulativeXp, and the gold subtraction clamps just below. So an
    // account that has already SPENT what this completion paid gives back
    // less than the completion was nominally worth, and the shortfall is
    // real rather than an accounting artifact: it is gold sitting in a
    // purchased accessory, not gold the user still holds.
    //
    // Sizing the receipt from `totalGoldReward` instead made the shop free.
    // Earn gold, spend every coin, undo the completion (which took nothing,
    // because there was nothing left to take), then re-tick the habit to
    // redeem the receipt: the full amount was paid out a second time and the
    // purchase was kept. Same shape for XP on a young account whose
    // cumulative total is smaller than the reward being reversed.
    final xpResult = XpCalculator.applyXpDelta(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpDelta: -totalXpReward,
    );
    final rawGold = state.gold - totalGoldReward;
    final newGold = rawGold < 0 ? 0 : rawGold;
    final removedXp = state.cumulativeXp - xpResult.newCumulativeXp;
    final removedGold = state.gold - newGold;

    // What the ledger still holds for this habit after the undo: nothing
    // once the day empties, the remainder otherwise. Kept in the same two
    // places the completion wrote it (today's mirror, the day document).
    final ({int xp, int gold})? remainingPaid =
        emptiesDay || recorded == null
            ? null
            : (
                xp: recorded.xp - removedXp < 0 ? 0 : recorded.xp - removedXp,
                gold: recorded.gold - removedGold < 0
                    ? 0
                    : recorded.gold - removedGold,
              );
    if (!isGraceDay) {
      if (remainingPaid == null) {
        _paidToday.remove(habitId);
      } else {
        _paidToday[habitId] = remainingPaid;
      }
    }

    // ── The receipt ──────────────────────────────────────────────
    //
    // Only when this undo empties the day for this habit. A multi-tap habit
    // going 8/8 to 7/8 is still a done day, so there is nothing to restore
    // and a receipt would hand out a second reward for a completion that was
    // never given back.
    //
    // The streak numbers are read from `state`, which is still pre-reversal
    // here, and are therefore exactly what the completion being undone
    // produced — this method only ever runs against today, so the values in
    // state belong to today's completion and to no other. That is the half
    // the redemption cannot recompute later, and the reason the receipt
    // carries it at all.
    // Read once, and used for every date in this method: the receipt, the
    // heatmap rollup, the history mirror and the green counter all mean the
    // SAME day, and four independent reads of a getter named "today" is how a
    // method that runs across a day boundary ends up writing half its fields
    // to one day and half to the next.
    final dayKey = markDay.toDateKey();
    // Whether the day being emptied had actually reached its target —
    // declared here (rather than beside the counters below that read it)
    // because the receipt has to carry it too: an unfinished counted day
    // never paid the lifetime counters, so its receipt must not hand them
    // out on redemption. See UndoneCompletion.finishedDay.
    final hadFinishedDay = current >= frequencyTarget;
    final receipt = newCompletions.containsKey(habitId)
        ? null
        : UndoneCompletion(
            habitId: habitId,
            dateKey: dayKey,
            category: category,
            xp: removedXp,
            gold: removedGold,
            streakAtCompletion: state.habitStreakCounts[habitId] ?? 0,
            longestAtCompletion: state.habitLongestStreaks[habitId] ?? 0,
            undoneOnKey: dayKey,
            finishedDay: hadFinishedDay,
          );
    final newUndoneCompletions = receipt == null
        ? null
        : {...state.undoneCompletions, receipt.key: receipt};

    // ── The daily earn counter ──────────────────────────────────
    //
    // Give today's cap allowance back too. completeHabit spends
    // earnedXpToday/earnedGoldToday on every payout, and a same-day redo
    // spends it AGAIN (its receipt redemption reuses the normal reward
    // arithmetic), so leaving the counter untouched here made every
    // complete→undo→redo lap inflate it by one full reward: the summary
    // card's "XP اليوم" read 60 on a day that actually held 40, and honest
    // corrections burned real cap room until genuine completions started
    // being clamped early.
    //
    // Sized from [removedXp]/[removedGold] — what this undo actually took
    // out of the account — not from the nominal reward, so an undo whose
    // clawback was floored (the XP already spent case above) frees no room
    // it did not reclaim. The clawback can also EXCEED what the completion
    // put into the counter (milestone bonuses are paid past the clamp and
    // never banked against it), and freeing that much is safe for the same
    // reason the clamp exempts them: the XP leaving the account is real and
    // once-per-lifetime, so no lap can mint from it. Clamped at zero, and
    // read through earnedXpOn so an undo landing after the cutoff sees the
    // fresh day's zero rather than yesterday's spend.
    final rawEarnedXp = state.earnedXpOn(dayKey) - removedXp;
    final newEarnedXpToday = rawEarnedXp < 0 ? 0 : rawEarnedXp;
    final rawEarnedGold = state.earnedGoldOn(dayKey) - removedGold;
    final newEarnedGoldToday = rawEarnedGold < 0 ? 0 : rawEarnedGold;

    // ── The day-counters ────────────────────────────────────────
    //
    // Mirrors completeHabit, which now bumps these four only on the tap that
    // FINISHES the habit's day (see its own note). So there is a day to give
    // back only if the day was actually finished — a habit sitting at 2 of 4
    // never earned a completion, a category count or a green square, and
    // taking one off for it would quietly bill the user for a day they were
    // never paid.
    //
    // Always true for an ordinary once-a-day habit, whose single tap both
    // starts and finishes its day. (Declared above, next to the receipt
    // that also records it.)

    final newCategoryCompletions = {...state.categoryCompletions};
    if (category != null && hadFinishedDay) {
      final rawCategory = (newCategoryCompletions[category] ?? 0) - 1;
      newCategoryCompletions[category] = rawCategory < 0 ? 0 : rawCategory;
    }
    final rawTotal = state.totalCompletions - (hadFinishedDay ? 1 : 0);
    final newTotal = rawTotal < 0 ? 0 : rawTotal;

    final rawTotalGreen = state.totalGreenSquares - (hadFinishedDay ? 1 : 0);
    final newTotalGreenSquares = rawTotalGreen < 0 ? 0 : rawTotalGreen;
    final newDailyGreenCounts = {...state.dailyGreenCounts};
    if (hadFinishedDay) {
      final rawDay = (newDailyGreenCounts[dayKey] ?? 0) - 1;
      newDailyGreenCounts[dayKey] = rawDay < 0 ? 0 : rawDay;
    }

    // The banked-day receipt is handed back with the counters: only an undo
    // that actually decremented them (hadFinishedDay) un-banks, so a later
    // genuine re-finish banks exactly once. See
    // DashboardState.dayCountedHabitIds.
    final newDayCounted = hadFinishedDay
        ? ({...state.dayCountedHabitIds}..remove(habitId))
        : state.dayCountedHabitIds;

    state = state.copyWith(
      level: xpResult.newLevel,
      currentLevelXp: xpResult.newCurrentLevelXp,
      cumulativeXp: xpResult.newCumulativeXp,
      gold: newGold,
      // TODAY's cap slot only, mirroring completeHabit: a grace day's ledger
      // lives on that day's own document, so refunding into this slot would
      // hand today allowance it never spent.
      earnedDayKey: isGraceDay ? null : dayKey,
      earnedXpToday: isGraceDay ? null : newEarnedXpToday,
      earnedGoldToday: isGraceDay ? null : newEarnedGoldToday,
      totalCompletions: newTotal,
      // The board on screen is today's, so a correction to another day must
      // not touch it — same split completeHabit makes.
      completions: isGraceDay ? null : newCompletions,
      categoryCompletions: newCategoryCompletions,
      totalGreenSquares: newTotalGreenSquares,
      dailyGreenCounts: newDailyGreenCounts,
      habitStreakCounts: newHabitStreakCounts,
      habitLongestStreaks: newHabitLongestStreaks,
      habitTotalCompletions: newHabitTotalCompletions,
      habitLastCompletedDate: newHabitLastCompletedDate,
      dayCountedHabitIds: isGraceDay ? null : newDayCounted,
      undoneCompletions: newUndoneCompletions,
    );

    if (_uid == null) {
      await _saveGuestDaily(
        newCompletions,
        dayCounted: hadFinishedDay ? newDayCounted.toList() : null,
        dayKey: dayKey,
        dayEarnedXp: isGraceDay ? newEarnedXpToday : null,
        dayEarnedGold: isGraceDay ? newEarnedGoldToday : null,
        habitPaidXp: {habitId: remainingPaid?.xp},
        habitPaidGold: {habitId: remainingPaid?.gold},
      );
      // No lastActiveDate here — undoing isn't "new activity" and
      // shouldn't disturb the streak-gap-detection logic that field feeds.
      await _saveGuestState();
      return;
    }

    try {
      final batch = FirebaseFirestore.instance.batch();

      batch.set(
        _dailyRefFor(markDay),
        // A DELTA for this one habit, not the whole map.
        //
        // SetOptions(merge: true) merges a nested map key by key, so a key
        // that is ABSENT from the data being written is left exactly as it
        // was on the server. Removing the key from a local copy and writing
        // that copy therefore deletes nothing: the completion survives in
        // Firestore, dayMark's rule 2 keeps reading it as complete forever,
        // and _loadToday rehydrates state.completions from it on the next
        // launch, so the undo silently reverts.
        //
        // It only bites when ANOTHER habit is still completed that day. Undo
        // the day's only completion and newCompletions is empty, the empty
        // map is itself the leaf, the field is written whole, and it clears.
        // Which is why every obvious manual test passed.
        //
        // The mirror write ten lines below always did this correctly with
        // FieldValue.delete(); this one did not.
        {
          'habitCompletions': habitCompletionDelta(habitId, newCompletions),
          // The paid ledger, see _paidToday: cleared with the day, trimmed
          // with a one-tap undo. Nested maps, merged key by key.
          'habitPaidXp': {
            habitId: remainingPaid == null
                ? FieldValue.delete()
                : remainingPaid.xp,
          },
          'habitPaidGold': {
            habitId: remainingPaid == null
                ? FieldValue.delete()
                : remainingPaid.gold,
          },
          // The grace day's own cap ledger, refunded where it is kept — see
          // _allowedOn. Absolute, like the completion side.
          if (isGraceDay) ...{
            'dayEarnedXp': newEarnedXpToday,
            'dayEarnedGold': newEarnedGoldToday,
          },
          // Hand the banked-day receipt back — see
          // DashboardState.dayCountedHabitIds. arrayRemove, mirroring
          // completeHabit's arrayUnion, so other habits' receipts survive.
          if (hadFinishedDay) 'dayCounted': FieldValue.arrayRemove([habitId]),
        },
        SetOptions(merge: true),
      );

      // Writer 2 of 3 for the yearly strip's mirror (see habitHistoryRef).
      // Uses newCompletions (already decremented above): absence means zero.
      // Deleted when the undo empties the day; otherwise the day still has taps
      // but is no longer full, so the mirror drops from complete back to
      // partial — matching completeHabit, which now records partial for a
      // non-finishing tap. Without the else a 4/4 day undone to 3/4 would keep
      // its 'complete' mark and settle as a fully-done day. The else is only
      // reachable for a counted habit; a single-tap habit always empties here.
      if (!newCompletions.containsKey(habitId)) {
        batch.set(
          habitHistoryRef(habitId),
          {
            'days': {dayKey: FieldValue.delete()},
          },
          SetOptions(merge: true),
        );
      } else {
        batch.set(
          habitHistoryRef(habitId),
          {
            'days': {dayKey: markToStored(SquareState.partial)},
          },
          SetOptions(merge: true),
        );
      }

      batch.set(
        _userRef,
        {
          'level': xpResult.newLevel,
          'currentLevelXp': xpResult.newCurrentLevelXp,
          'cumulativeXp': xpResult.newCumulativeXp,
          'gold': newGold,
          // The refunded cap allowance, mirroring completeHabit's own write
          // of this trio — see the earn-counter note above the copyWith.
          if (!isGraceDay) ...{
            'earnedDayKey': dayKey,
            'earnedXpToday': newEarnedXpToday,
            'earnedGoldToday': newEarnedGoldToday,
          },
          'totalHabitCompletions': newTotal,
          'categoryCompletions': newCategoryCompletions,
          // Atomic increments, matching completeHabit's own writes to
          // these same two fields — both Grid's applyGridSquareChange and
          // this method can touch them, so an absolute local value would
          // risk a lost update. Nested map, not a dotted key — see
          // completeHabit's identical write for why (dot notation is a
          // literal field name inside set(merge: true), not a path).
          // Gated on hadFinishedDay, same as the local counters above: an
          // unfinished day never earned a green square, so there is none to
          // take back.
          'totalGreenSquares': FieldValue.increment(hadFinishedDay ? -1 : 0),
          'dailyGreenCounts': {
            dayKey: FieldValue.increment(hadFinishedDay ? -1 : 0),
          },
          // Deltas, for the same merge reason as habitCompletions above.
          // Every one of these four drops the habit's key at zero, and every
          // one of them was written as a whole map, so none of the removals
          // ever reached the server. habitTotalCompletions matters most: it
          // is the ONLY signal the removal flow reads to decide hard delete
          // versus archive, so a stale entry made a never-completed habit
          // refuse to hard-delete and silently soft-archive instead.
          'habitTotalCompletions': habitCompletionDelta(habitId, newHabitTotalCompletions),
          // One nested key, so merge adds this receipt without rewriting the
          // ones already outstanding — same reason every other sparse map in
          // this write is a delta rather than the whole map.
          if (receipt != null)
            'undoneCompletions': {receipt.key: receipt.toJson()},
          if (snapshot != null) ...{
            'habitStreakCounts': habitCompletionDelta(habitId, newHabitStreakCounts),
            'habitLongestStreaks': habitCompletionDelta(habitId, newHabitLongestStreaks),
            'habitLastCompletedDate': habitCompletionDelta(habitId, newHabitLastCompletedDate),
          },
        },
        SetOptions(merge: true),
      );

      // Not awaited, for the same reason completeHabit's commit isn't — see
      // the long comment there. The undo path has the mirror-image symptom:
      // Grid clears the green square only after awaiting this, so offline a
      // tap on a completed square refunded the XP but left the square green.
      unawaited(batch.commit().catchError(
          (Object e, StackTrace st) =>
              _recordWriteFailure('uncompleteHabit', e, st)));
    } catch (e, st) {
      await _recordWriteFailure('uncompleteHabit', e, st);
    }
  }

  /// Puts back a completion this app itself undid, on a day that has since
  /// stopped being today.
  ///
  /// The redemption half of [UndoneCompletion] — read that class first. In
  /// short: the anti-backdating rule (see WeeklyGridNotifier.setSquare) keeps
  /// every past day out of the reward system, which is right, and which also
  /// meant an un-tick made by mistake could never be put right once the day
  /// rolled over. A receipt is proof this exact habit-day was genuinely
  /// completed and genuinely given back, so redeeming one is not a backfill
  /// and is the one past-day case allowed to pay.
  ///
  /// It cannot be farmed. A receipt is only ever created by [uncompleteHabit]
  /// reversing a real completion, it names one habit and one date, it pays
  /// back exactly what that undo took and not a freshly computed reward, and
  /// it is deleted the moment it is used.
  ///
  /// Restores one completion, not a whole day of them: a multi-tap habit only
  /// leaves a receipt on the undo that empties its day, so 8/8 undone eight
  /// times and then re-painted comes back as 1. That matches what the square
  /// itself can say, and erring low is the right direction for anything that
  /// hands out XP. Writing that 1 flat rather than incrementing is safe for
  /// the same reason: a LIVE receipt can only ever describe a day whose count
  /// for this habit is zero, since [uncompleteHabit] only writes one when it
  /// empties the day and [completeHabit] spends it the moment anything is put
  /// back on that day.
  ///
  /// Deliberately does not touch `dailyGreenCounts` (the caller's own
  /// past-day green delta owns that field — see [recordPastDayGreenDelta] —
  /// and both moving it would double-count the day on the heatmap), the
  /// app-wide streak (a past day was never able to earn one), the habit
  /// history mirror (the square paint that triggers this already writes it,
  /// as painted, so writing 'complete' here would race a `bonus` square down
  /// to plain green), or `unlockedAchievements` (the undo never revoked one,
  /// so a counter climbing back to a level it already passed cannot unlock
  /// anything new).
  ///
  /// Returns whether a receipt was found and redeemed.
  Future<bool> restoreUndoneCompletion({
    required String habitId,
    required DateTime day,
  }) async {
    // Same two guards completeHabit carries, for the same reason: every field
    // below is written back as an ABSOLUTE value computed from `state`, so a
    // failed or still-arriving load would persist zeros over the real account.
    if (_uid != null && (state.loadFailed || state.isLoading)) return false;

    final dateKey = day.toDateKey();
    final receipt = state.undoneFor(habitId, dateKey);
    if (receipt == null) return false;

    final xpResult = XpCalculator.applyXpDelta(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpDelta: receipt.xp,
    );
    final newGold = state.gold + receipt.gold;
    // The redemption pays exactly what the receipt holds, so that is what
    // the day's paid ledger records for a later undo (see _paidToday).
    if (dateKey == _todayKeyNow) {
      _paidToday[habitId] = (xp: receipt.xp, gold: receipt.gold);
    }
    // The lifetime counters mirror what the undo actually decremented:
    // uncompleteHabit only takes them back for a FINISHED day, so a receipt
    // minted from an unfinished counted day (its finishedDay is false)
    // restores XP, gold and the streak link but none of the counters —
    // handing those out would mint completions the account was never paid.
    final countsDay = receipt.finishedDay;
    final newTotal = state.totalCompletions + (countsDay ? 1 : 0);

    final newCategoryCompletions = {...state.categoryCompletions};
    final category = receipt.category;
    if (category != null && countsDay) {
      newCategoryCompletions[category] =
          (newCategoryCompletions[category] ?? 0) + 1;
    }

    final newHabitTotalCompletions = {...state.habitTotalCompletions};
    if (countsDay) {
      newHabitTotalCompletions[habitId] =
          (newHabitTotalCompletions[habitId] ?? 0) + 1;
    }

    // ── Re-linking the streak ────────────────────────────────────
    //
    // The one thing repainting a square could never do on its own, and the
    // reason a corrected day still read as a miss: the chain is driven by
    // habitLastCompletedDate, which only a same-day completion ever writes.
    // See restoredHabitStreak for the rule, including when it declines to
    // answer and leaves the counters alone.
    final lastKey = state.habitLastCompletedDate[habitId];
    final relink = restoredHabitStreak(
      restoredDay: day,
      streakAtCompletion: receipt.streakAtCompletion,
      currentStreak: state.habitStreakCounts[habitId] ?? 0,
      currentLastCompleted: lastKey == null ? null : DateTime.tryParse(lastKey),
    );
    Map<String, int>? newHabitStreakCounts;
    Map<String, int>? newHabitLongestStreaks;
    Map<String, String>? newHabitLastCompletedDate;
    if (relink != null) {
      newHabitStreakCounts = {...state.habitStreakCounts}
        ..[habitId] = relink.streak;
      newHabitLongestStreaks = {...state.habitLongestStreaks};
      newHabitLongestStreaks[habitId] = max(
        max(state.habitLongestStreaks[habitId] ?? 0,
            receipt.longestAtCompletion),
        relink.streak,
      );
      newHabitLastCompletedDate = {...state.habitLastCompletedDate}
        ..[habitId] = relink.lastCompleted.toDateKey();
    }

    final newUndone = {...state.undoneCompletions}..remove(receipt.key);

    state = state.copyWith(
      level: xpResult.newLevel,
      currentLevelXp: xpResult.newCurrentLevelXp,
      cumulativeXp: xpResult.newCumulativeXp,
      gold: newGold,
      totalCompletions: newTotal,
      categoryCompletions: newCategoryCompletions,
      totalGreenSquares: state.totalGreenSquares + (countsDay ? 1 : 0),
      habitTotalCompletions: newHabitTotalCompletions,
      habitStreakCounts: newHabitStreakCounts,
      habitLongestStreaks: newHabitLongestStreaks,
      habitLastCompletedDate: newHabitLastCompletedDate,
      undoneCompletions: newUndone,
    );

    if (_uid == null) {
      // The day's own completion count, restored on the day it belongs to.
      // Not _saveGuestDaily, which only ever writes today. Through
      // updateDailyMap so this cannot race the square write landing for the
      // same day — see that method's comment.
      await LocalStoreService.updateDailyMap(dateKey, (stored) {
        final completions = Map<String, dynamic>.from(
            (stored['habitCompletions'] as Map?)?.cast<String, dynamic>() ??
                {});
        completions[habitId] = 1;
        stored['habitCompletions'] = completions;
        for (final (field, value) in [
          ('habitPaidXp', receipt.xp),
          ('habitPaidGold', receipt.gold),
        ]) {
          final m = Map<String, dynamic>.from(
              (stored[field] as Map?)?.cast<String, dynamic>() ?? {});
          m[habitId] = value;
          stored[field] = m;
        }
      });
      await _saveGuestState();
      return true;
    }

    try {
      final batch = FirebaseFirestore.instance.batch();

      // The completion itself, back on the day it happened, so a restored day
      // is indistinguishable from one that was never touched: dayMark's rule 2
      // and the room resync both read this field directly.
      batch.set(
        _userRef.collection('daily').doc(dateKey),
        {
          'habitCompletions': {habitId: 1},
          'habitPaidXp': {habitId: receipt.xp},
          'habitPaidGold': {habitId: receipt.gold},
        },
        SetOptions(merge: true),
      );

      batch.set(
        _userRef,
        {
          'level': xpResult.newLevel,
          'currentLevelXp': xpResult.newCurrentLevelXp,
          'cumulativeXp': xpResult.newCumulativeXp,
          'gold': newGold,
          'totalHabitCompletions': newTotal,
          'categoryCompletions': newCategoryCompletions,
          // Atomic, mirroring uncompleteHabit's own decrement of this field:
          // Grid's applyGridSquareChange writes it too, so an absolute value
          // computed locally could lose an update.
          'totalGreenSquares': FieldValue.increment(countsDay ? 1 : 0),
          'habitTotalCompletions':
              habitCompletionDelta(habitId, newHabitTotalCompletions),
          if (relink != null) ...{
            'habitStreakCounts':
                habitCompletionDelta(habitId, newHabitStreakCounts),
            'habitLongestStreaks':
                habitCompletionDelta(habitId, newHabitLongestStreaks),
            'habitLastCompletedDate':
                habitCompletionDelta(habitId, newHabitLastCompletedDate),
          },
          // Spent. One nested key deleted, so the other outstanding receipts
          // survive the merge.
          'undoneCompletions': {receipt.key: FieldValue.delete()},
        },
        SetOptions(merge: true),
      );

      unawaited(batch.commit().catchError((Object e, StackTrace st) =>
          _recordWriteFailure('restoreUndoneCompletion', e, st)));
    } catch (e, st) {
      await _recordWriteFailure('restoreUndoneCompletion', e, st);
    }
    return true;
  }
}
