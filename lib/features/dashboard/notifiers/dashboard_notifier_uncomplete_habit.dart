part of 'dashboard_notifier.dart';

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
  Future<void> uncompleteHabit({
    required String habitId,
    required int xpReward,
    required int goldReward,
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
    final newCompletions = Map<String, int>.from(state.completions);
    if (current <= 1) {
      newCompletions.remove(habitId);
    } else {
      newCompletions[habitId] = current - 1;
    }

    final snapshot = _lastHabitCompletion.remove(habitId);

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

    // Unlike the streak/date fields above — left untouched with no
    // same-session snapshot on purpose, to avoid guessing at streak
    // continuity — this lifetime counter is always safe to correct even
    // across an app restart: the early-return at the top of this function
    // already confirmed this undo is reversing exactly one real completion
    // (completeHabit only ever bumps this by 1, on the day's first tap;
    // uncompleteHabit's .remove() above always reverses that whole day's
    // taps at once), so it can simply drop by one, floored at zero, with
    // no history required. This is also the *only* signal
    // add_habit_sheet/grid_screen read to decide hard-delete vs. archive
    // when a habit is removed — leaving this stale (the old behavior,
    // gated behind `snapshot != null` same as the fields above) is what let
    // an already-undone, truly never-completed habit refuse to hard-delete:
    // it would silently soft-archive instead, looking stuck in Grid.
    final newHabitTotalCompletions = {...state.habitTotalCompletions};
    final rawHabitTotal = (newHabitTotalCompletions[habitId] ?? 0) - 1;
    if (rawHabitTotal <= 0) {
      newHabitTotalCompletions.remove(habitId);
    } else {
      newHabitTotalCompletions[habitId] = rawHabitTotal;
    }

    final totalXpReward = xpReward + (snapshot?.bonusXp ?? 0);
    final totalGoldReward = goldReward + (snapshot?.bonusGold ?? 0);

    final xpResult = XpCalculator.applyXpDelta(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpDelta: -totalXpReward,
    );
    final rawGold = state.gold - totalGoldReward;
    final newGold = rawGold < 0 ? 0 : rawGold;

    final newCategoryCompletions = {...state.categoryCompletions};
    if (category != null) {
      final rawCategory = (newCategoryCompletions[category] ?? 0) - 1;
      newCategoryCompletions[category] = rawCategory < 0 ? 0 : rawCategory;
    }
    final rawTotal = state.totalCompletions - 1;
    final newTotal = rawTotal < 0 ? 0 : rawTotal;

    final rawTotalGreen = state.totalGreenSquares - 1;
    final newTotalGreenSquares = rawTotalGreen < 0 ? 0 : rawTotalGreen;
    final newDailyGreenCounts = {...state.dailyGreenCounts};
    final rawDay = (newDailyGreenCounts[DashboardNotifier._todayKey] ?? 0) - 1;
    newDailyGreenCounts[DashboardNotifier._todayKey] = rawDay < 0 ? 0 : rawDay;

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
    );

    if (_uid == null) {
      await _saveGuestDaily(newCompletions);
      // No lastActiveDate here — undoing isn't "new activity" and
      // shouldn't disturb the streak-gap-detection logic that field feeds.
      await _saveGuestState();
      return;
    }

    try {
      final batch = FirebaseFirestore.instance.batch();

      batch.set(
        _dailyRef,
        {'habitCompletions': newCompletions},
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
          // Atomic increments, matching completeHabit's own writes to
          // these same two fields — both Grid's applyGridSquareChange and
          // this method can touch them, so an absolute local value would
          // risk a lost update. Nested map, not a dotted key — see
          // completeHabit's identical write for why (dot notation is a
          // literal field name inside set(merge: true), not a path).
          'totalGreenSquares': FieldValue.increment(-1),
          'dailyGreenCounts': {DashboardNotifier._todayKey: FieldValue.increment(-1)},
          'habitTotalCompletions': newHabitTotalCompletions,
          if (snapshot != null) ...{
            'habitStreakCounts': newHabitStreakCounts,
            'habitLongestStreaks': newHabitLongestStreaks,
            'habitLastCompletedDate': newHabitLastCompletedDate,
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
