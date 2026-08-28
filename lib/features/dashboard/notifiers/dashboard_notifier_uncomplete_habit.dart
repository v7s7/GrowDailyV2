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
  /// quit-habit's affirm→slip mis-tap correction. Always operates on
  /// *today* (there's no "edit yesterday's completion" concept anywhere in
  /// this app).
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
  /// synced completions.
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
  }) async {
    // See completeHabit's guard: this method writes level, currentLevelXp,
    // cumulativeXp, gold, totalHabitCompletions and categoryCompletions as
    // absolute values from `state` too, so it must decline for the same
    // reason. In practice a failed load leaves `completions` empty and the
    // `current <= 0` check below already turns most calls away — this makes
    // that an explicit rule rather than a side effect of the zeros lining up.
    if (_uid != null && state.loadFailed) return;

    final current = state.completions[habitId] ?? 0;
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
    final newCompletions = Map<String, int>.from(state.completions);
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
    final totalXpReward = xpSlice + (snapshot?.bonusXp ?? 0);
    final totalGoldReward = goldSlice + (snapshot?.bonusGold ?? 0);

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
    final dayKey = DashboardNotifier._todayKey;
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
      totalCompletions: newTotal,
      completions: newCompletions,
      categoryCompletions: newCategoryCompletions,
      totalGreenSquares: newTotalGreenSquares,
      dailyGreenCounts: newDailyGreenCounts,
      habitStreakCounts: newHabitStreakCounts,
      habitLongestStreaks: newHabitLongestStreaks,
      habitTotalCompletions: newHabitTotalCompletions,
      habitLastCompletedDate: newHabitLastCompletedDate,
      dayCountedHabitIds: newDayCounted,
      undoneCompletions: newUndoneCompletions,
    );

    if (_uid == null) {
      await _saveGuestDaily(
        newCompletions,
        dayCounted: hadFinishedDay ? newDayCounted.toList() : null,
      );
      // No lastActiveDate here — undoing isn't "new activity" and
      // shouldn't disturb the streak-gap-detection logic that field feeds.
      await _saveGuestState();
      return;
    }

    try {
      final batch = FirebaseFirestore.instance.batch();

      batch.set(
        _dailyRef,
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

  /// Fires local notifications for a habit completion — a habit-completed
  /// ping, plus a level-up / achievement-unlocked ping if either happened in
  /// the same action. These are on-device local notifications (no push
  /// server), so they show even if the in-app celebration overlay was
  /// dismissed or the app is backgrounded.
  void _fireCompletionNotifications({
    required String habitId,
    required int xpEarned,
    required int goldEarned,
    required bool didLevelUp,
    required int newLevel,
    required List<AchievementModel> newlyUnlocked,
  }) {
    NotificationService.instance.showHabitCompleted(
      habitName: habitId,
      xpEarned: xpEarned,
      goldEarned: goldEarned,
    );
    if (didLevelUp) {
      NotificationService.instance.showLevelUp(newLevel);
    }
    // One notification for the whole batch — a single completion can cross
    // three thresholds at once, and this used to deal one push per medal on
    // top of the habit-completed and level-up ones already going out.
    NotificationService.instance.showAchievementsUnlocked([
      for (final a in newlyUnlocked)
        a.localName(NotificationService.instance.isArabic),
    ]);
  }
}
