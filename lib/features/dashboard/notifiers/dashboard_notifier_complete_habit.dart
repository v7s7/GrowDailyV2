part of 'dashboard_notifier.dart';

extension DashboardNotifierCompleteHabit on DashboardNotifier {

  // ── Actions ──────────────────────────────────────────────────

  /// Completes a habit for today — the single canonical reward path for
  /// "a habit was done today", called from both Today's habit list and
  /// Grid's square tap (see [markCompleteFromHabit] on `WeeklyGridNotifier`
  /// for the visual-only mirror the other screen uses).
  ///
  /// Returns whether this call just finished a *single-tap*
  /// (`frequencyTarget == 1`) habit. This is narrower than "did it
  /// succeed" — Today's own button and the notification action handler
  /// use it to decide whether *their* completion should also paint
  /// today's Grid square green, which only makes sense for single-tap
  /// habits: a multi-tap (`frequencyTarget > 1`, e.g. "3x this week")
  /// habit finishing one tap from Today shouldn't turn the square fully
  /// green, since a single square can't cleanly represent "2 of 3 this
  /// week". Grid's own square tap (grid_screen.dart) doesn't read this
  /// return value at all — it already knows the user just painted that
  /// exact square, for any frequencyTarget, so it mirrors unconditionally
  /// once its own pre-check confirms the completion isn't a no-op. Also
  /// returns `false` if the habit was already done today (no new
  /// completion registered at all).
  ///
  /// [allHabitsDoneAfter] answers "once this completion lands, will today's
  /// scheduled habits be at or above [kStreakDayCompletionThreshold]?" —
  /// the caller computes this (see [willCompleteAllHabitsToday]) because
  /// only it has today's full habit list; this method only ever sees one
  /// habit at a time. That answer is what decides whether *today* just
  /// earned its once-per-day streak point (see
  /// [DashboardState.streakEarnedToday] for the full reasoning) — with,
  /// say, 5 scheduled habits, completing your 1st through 3rd doesn't
  /// bump the streak, but your 4th (4/5 = 80%) does.
  Future<bool> completeHabit({
    required String habitId,
    required int xpReward,
    required int goldReward,
    required int frequencyTarget,
    required bool allHabitsDoneAfter,
    String? category,
    String? habitName,
  }) async {
    final current = state.completions[habitId] ?? 0;
    if (current >= frequencyTarget) return false;

    final newCompletions = Map<String, int>.from(state.completions)
      ..[habitId] = current + 1;

    // ── Per-habit streak bump ────────────────────────────────
    //
    // Fires once per habit per day — `current == 0` means this is the
    // first completion of *this specific habit* today. Unlike the
    // app-wide streak bump below (which needs *every* habit done), this
    // per-habit one only cares about this one habit, so it still fires on
    // habit 1 of 3. A weekly habit tapped 3 separate days still bumps 3
    // times; nothing here double-counts a same-day multi-tap because
    // current is already > 0 by the second tap.
    final newHabitStreakCounts = {...state.habitStreakCounts};
    final newHabitLongestStreaks = {...state.habitLongestStreaks};
    final newHabitTotalCompletions = {...state.habitTotalCompletions};
    final newHabitLastCompletedDate = {...state.habitLastCompletedDate};
    // Set only when this completion just crossed one of
    // GameConstants.habitStreakBonuses' thresholds — see below.
    HabitMilestoneEvent? newHabitMilestoneEvent;
    int habitMilestoneBonusXp = 0;
    if (current == 0) {
      final lastKey = state.habitLastCompletedDate[habitId];
      final last = lastKey == null ? null : DateTime.tryParse(lastKey);
      final gap = last == null
          ? null
          : DateTime.now().effectiveDay.difference(DashboardNotifier._dateOnly(last)).inDays;
      final prevStreak = state.habitStreakCounts[habitId] ?? 0;
      // Only a same-day-yesterday completion continues the streak; a gap of
      // 0 (shouldn't happen given the `current == 0` guard, but defensive),
      // 2+, or no prior completion at all all restart it at 1.
      final newHabitStreak = gap == 1 ? prevStreak + 1 : 1;
      newHabitStreakCounts[habitId] = newHabitStreak;
      final prevLongest = state.habitLongestStreaks[habitId] ?? 0;
      newHabitLongestStreaks[habitId] =
          newHabitStreak > prevLongest ? newHabitStreak : prevLongest;
      newHabitTotalCompletions[habitId] =
          (state.habitTotalCompletions[habitId] ?? 0) + 1;
      newHabitLastCompletedDate[habitId] = DashboardNotifier._todayKey;

      // ── Per-habit milestone ──────────────────────────────────
      final habitBonus = GameConstants.habitStreakBonuses[newHabitStreak];
      if (habitBonus != null) {
        habitMilestoneBonusXp = habitBonus;
        newHabitMilestoneEvent = HabitMilestoneEvent(
          habitId: habitId,
          habitName: habitName ?? habitId,
          milestone: newHabitStreak,
          bonusXp: habitBonus,
        );
      }
    }

    // ── Surprise bonus ───────────────────────────────────────────
    //
    // A small, independent chance on *every* completion (not gated to the
    // day's first, unlike the streak logic above — this rewards the single
    // action, not "did something today"). Always additive on top of the
    // normal reward, capped at half again its size — see
    // GameConstants.surpriseBonusChance for the reasoning.
    final rolledBonus = _random.nextDouble() < GameConstants.surpriseBonusChance;
    final surpriseBonusXp = rolledBonus
        ? (xpReward * GameConstants.surpriseBonusMultiplier).ceil()
        : 0;
    final surpriseBonusGold = rolledBonus
        ? (goldReward * GameConstants.surpriseBonusMultiplier).ceil()
        : 0;

    // ── Same-day-undo snapshot ───────────────────────────────────
    //
    // Only meaningful on the tap that actually changed the per-habit
    // fields above (current == 0) — a later same-day tap on a multi-tap
    // habit leaves them untouched, so it leaves whatever snapshot the
    // day's first tap already recorded in place. uncompleteHabit's
    // .remove() wipes the whole day's taps at once regardless of how many
    // there were, so that first-tap snapshot is still the right one to
    // reverse against — see uncompleteHabit's doc comment.
    if (current == 0) {
      _lastHabitCompletion[habitId] = _HabitCompletionSnapshot(
        hadPrior: state.habitLastCompletedDate.containsKey(habitId),
        prevStreak: state.habitStreakCounts[habitId] ?? 0,
        prevLongest: state.habitLongestStreaks[habitId] ?? 0,
        prevTotal: state.habitTotalCompletions[habitId] ?? 0,
        prevLastCompletedDate: state.habitLastCompletedDate[habitId],
        bonusXp: habitMilestoneBonusXp + surpriseBonusXp,
        bonusGold: surpriseBonusGold,
      );
    }

    // Only single-tap habits are synced with the Grid in this phase — see
    // the doc comment above.
    final isGridSyncable = frequencyTarget == 1;

    // ── App-wide streak bump ─────────────────────────────────────
    //
    // See [DashboardState.streakEarnedToday] for the full reasoning; in
    // short, this only fires the instant today's habits go from "not all
    // done" to "all done" (never on the 1st of N, only the Nth), it can
    // only ever fire once per calendar day, and once it fires it stays
    // earned for the rest of the day even if a new habit gets added later.
    final justReachedAllDone =
        allHabitsDoneAfter && !state.streakEarnedToday;
    final newStreakEarnedToday = state.streakEarnedToday || justReachedAllDone;
    // A real, freshly-earned streak day supersedes any stale "restore your
    // old streak with a freeze" offer still sitting around from a past
    // loss — see DashboardState.previousStreak's doc comment. Without
    // this, someone who ignores the comeback card and just starts
    // completing habits again would keep the offer dangling indefinitely,
    // and using it later would clobber the real progress they've since
    // rebuilt.
    final clearsPendingComeback = justReachedAllDone && state.previousStreak > 0;
    final bump = justReachedAllDone
        ? _computeStreakBump()
        : (
            streak: state.streak,
            longestStreak: state.longestStreak,
            milestone: null,
            milestoneBonusXp: 0,
          );
    final newStreak = bump.streak;
    final newLongest = bump.longestStreak;
    final newMilestone = bump.milestone;
    final milestoneBonusXp = bump.milestoneBonusXp;

    final result = XpCalculator.applyXpGain(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpGained:
          xpReward + milestoneBonusXp + habitMilestoneBonusXp + surpriseBonusXp,
    );
    final newGold = state.gold + goldReward + surpriseBonusGold;
    final newTotal = state.totalCompletions + 1;

    final newCategoryCompletions = {...state.categoryCompletions};
    if (category != null) {
      newCategoryCompletions[category] =
          (newCategoryCompletions[category] ?? 0) + 1;
    }

    // Every completion counts toward the heatmap and the lifetime
    // green-squares total — regardless of isGridSyncable. isGridSyncable
    // only answers "can this mirror onto a *specific Grid square's
    // color*" (a single square can't cleanly represent "2 of 3 this
    // week" for a multi-tap habit — see the doc comment above); it was
    // never meant to also gate whether the day *happened* at all. Gating
    // this increment on it too was a real bug: a habit tracked purely
    // through Today (never touching its Grid square directly) with a
    // frequencyTarget > 1 silently never showed up on the Monthly
    // Heatmap, on any day, ever — "I did my habits but the heatmap is
    // blank" with no obvious cause. Forward-only: this only ever touches
    // today's dateKey, never rewrites or backfills earlier days. The
    // guard above (`current >= frequencyTarget`) already makes this at
    // most a one-time bump per habit per day, same as everything else in
    // this method.
    final newTotalGreenSquares = state.totalGreenSquares + 1;
    final newDailyGreenCounts = {...state.dailyGreenCounts};
    newDailyGreenCounts[DashboardNotifier._todayKey] =
        (newDailyGreenCounts[DashboardNotifier._todayKey] ?? 0) + 1;

    // ── Achievement check ────────────────────────────────────
    final newly = AchievementCatalog.locked(state.unlockedAchievements)
        .where((a) => switch (a.trigger) {
              AchievementTrigger.streak => newStreak >= a.threshold,
              AchievementTrigger.level =>
                result.newLevel >= a.threshold,
              AchievementTrigger.totalCompletions =>
                newTotal >= a.threshold,
              AchievementTrigger.habitMastery => a.targetCategory != null &&
                  (newCategoryCompletions[a.targetCategory] ?? 0) >=
                      a.threshold,
              AchievementTrigger.greenSquares =>
                newTotalGreenSquares >= a.threshold,
              _ => false,
            })
        .toList();

    final newUnlockedIds = [
      ...state.unlockedAchievements,
      ...newly.map((a) => a.id),
    ];

    // XP + gold bonus from achievements
    int bonusXp = newly.fold(0, (s, a) => s + a.xpReward);
    int bonusGold = newly.fold(0, (s, a) => s + a.goldReward);
    final bonusResult = bonusXp > 0
        ? XpCalculator.applyXpGain(
            currentLevel: result.newLevel,
            currentLevelXp: result.newCurrentLevelXp,
            cumulativeXp: result.newCumulativeXp,
            xpGained: bonusXp,
          )
        : (
            newLevel: result.newLevel,
            newCurrentLevelXp: result.newCurrentLevelXp,
            newCumulativeXp: result.newCumulativeXp,
          );

    AnalyticsService.instance.track('habit_completed', props: {
      'habitId': habitId,
      'streak': newStreak,
      'allHabitsDoneAfter': allHabitsDoneAfter,
      'streakJustEarned': justReachedAllDone,
      'milestone': newMilestone,
    });

    final didLevelUp = bonusResult.newLevel > state.level;

    // ── Milestone Event Log ────────────────────────────────────
    //
    // Every meaningful thing that just happened, collected once here and
    // appended to the same Firestore batch below (see _milestonesRef's doc
    // comment in dashboard_notifier.dart for why this rides the existing
    // batch rather than the standalone logMilestoneEvent() helper).
    // Deliberately narrow — only events with no other home already
    // (level-up, streak thresholds, perfect day/week, achievement
    // unlocks). totalCompletions/greenSquares round numbers are NOT
    // separately thresholded here: they already have their own Achievement
    // family (completions_50/500/2000/5000, green_1/100/500/2000 — see
    // AchievementCatalog), whose unlock is itself logged as
    // achievementUnlocked just below, so a second independent check on the
    // same numbers would both duplicate that detection and double-
    // celebrate the same moment.
    final nowInstant = DateTime.now();
    final milestoneEvents = <MilestoneEvent>[
      if (didLevelUp)
        MilestoneEvent(
          id: '',
          type: MilestoneType.levelUp,
          occurredAt: nowInstant,
          data: {'level': bonusResult.newLevel},
        ),
      if (newMilestone != null)
        MilestoneEvent(
          id: '',
          type: MilestoneType.streakMilestone,
          occurredAt: nowInstant,
          data: {'days': newMilestone},
        ),
      if (justReachedAllDone)
        MilestoneEvent(
          id: '',
          type: MilestoneType.perfectDay,
          occurredAt: nowInstant,
        ),
      // A streak that just landed on an exact multiple of 7 means the 7
      // calendar days ending today were each a qualifying day in a row (any
      // gap would have reset the streak below 7 first) — the same "streak
      // count is the unit of celebration" logic GameConstants.streakBonuses
      // already uses, just also flagged as a week boundary for Journey
      // Page / Monthly Story to call out by name. Reuses newStreak rather
      // than re-deriving "were the last 7 calendar days each perfect" from
      // scratch, which nothing in DashboardState tracks directly.
      if (justReachedAllDone && newStreak > 0 && newStreak % 7 == 0)
        MilestoneEvent(
          id: '',
          type: MilestoneType.perfectWeek,
          occurredAt: nowInstant,
          data: {'weekNumber': newStreak ~/ 7},
        ),
      for (final a in newly)
        MilestoneEvent(
          id: '',
          type: MilestoneType.achievementUnlocked,
          occurredAt: nowInstant,
          // Only what MilestoneEvent actually exposes a getter for
          // (achievementId/achievementTier) — this used to also write
          // a.familyId, which nothing ever read back out (no
          // MilestoneEvent.familyId getter exists), just a stranded field
          // in every unlock's Firestore doc.
          data: {
            'achievementId': a.id,
            'tier': a.tier.name,
          },
        ),
    ];

    state = state.copyWith(
      level: bonusResult.newLevel,
      currentLevelXp: bonusResult.newCurrentLevelXp,
      cumulativeXp: bonusResult.newCumulativeXp,
      gold: newGold + bonusGold,
      streak: newStreak,
      longestStreak: newLongest,
      streakEarnedToday: newStreakEarnedToday,
      previousStreak: clearsPendingComeback ? 0 : null,
      totalCompletions: newTotal,
      completions: newCompletions,
      unlockedAchievements: newUnlockedIds,
      newlyUnlocked: newly,
      didJustLevelUp: didLevelUp,
      // The exact completion that finished today's whole list — same
      // justReachedAllDone moment that earns the streak point, so this can
      // fire at most once per day and never from a backfilled past square.
      perfectDayCelebration: justReachedAllDone,
      lastCompletedId: habitId,
      setMilestone: newMilestone,
      categoryCompletions: newCategoryCompletions,
      totalGreenSquares: newTotalGreenSquares,
      dailyGreenCounts: newDailyGreenCounts,
      habitStreakCounts: newHabitStreakCounts,
      habitLongestStreaks: newHabitLongestStreaks,
      habitTotalCompletions: newHabitTotalCompletions,
      habitLastCompletedDate: newHabitLastCompletedDate,
      setHabitMilestone: newHabitMilestoneEvent,
      lastCompletionBonusXp: surpriseBonusXp,
      lastCompletionBonusGold: surpriseBonusGold,
    );

    _fireCompletionNotifications(
      habitId: habitName ?? habitId,
      xpEarned: xpReward +
          milestoneBonusXp +
          habitMilestoneBonusXp +
          surpriseBonusXp,
      goldEarned: goldReward + surpriseBonusGold,
      didLevelUp: didLevelUp,
      newLevel: bonusResult.newLevel,
      newlyUnlocked: newly,
    );

    if (_uid == null) {
      await _saveGuestDaily(newCompletions, streakEarnedToday: newStreakEarnedToday);
      // lastActiveDate means "the last calendar day that itself qualified
      // for the streak point" (see _loadGuestToday's gap-check doc comment)
      // — NOT "the last day anything happened," which is what let a streak
      // coast indefinitely on partial-completion days that never actually
      // hit kStreakDayCompletionThreshold. Only ever advanced here when
      // today has genuinely qualified (just now, or earlier today — either
      // way newStreakEarnedToday is already true); a non-qualifying day
      // leaves it untouched, exactly like uncompleteHabit already does.
      await _saveGuestState(
        lastActiveDate:
            newStreakEarnedToday ? DateTime.now().effectiveDay : null,
      );
      return isGridSyncable;
    }

    try {
      // .effectiveDay, not the raw instant — everything downstream that
      // reads dates back (habitStreak, completeHabit's per-habit gap,
      // _loadToday/_loadGuestToday's app-wide gap) assumes day-cutoff
      // alignment. See DateTimeGameExt.effectiveDay's doc comment.
      final now = DateTime.now().effectiveDay;
      final batch = FirebaseFirestore.instance.batch();

      batch.set(
        _dailyRef,
        {
          'habitCompletions': newCompletions,
          'date': Timestamp.fromDate(now),
          'streakEarnedToday': newStreakEarnedToday,
        },
        SetOptions(merge: true),
      );

      batch.set(
        _userRef,
        {
          'level': bonusResult.newLevel,
          'currentLevelXp': bonusResult.newCurrentLevelXp,
          'cumulativeXp': bonusResult.newCumulativeXp,
          'gold': newGold + bonusGold,
          'currentStreak': newStreak,
          'longestStreak': newLongest,
          if (clearsPendingComeback) 'previousStreak': 0,
          'totalHabitCompletions': newTotal,
          'unlockedAchievements': newUnlockedIds,
          'categoryCompletions': newCategoryCompletions,
          // Same "only on a genuinely qualifying day" rule as the guest
          // branch above — see that comment. Previously unconditional,
          // which was the actual bug: any single completion refreshed this
          // regardless of whether today ever reached the threshold, so the
          // streak could coast forever on partial days without ever
          // tripping the gap-check below.
          if (newStreakEarnedToday) 'lastActiveDate': Timestamp.fromDate(now),
          'habitStreakCounts': newHabitStreakCounts,
          'habitLongestStreaks': newHabitLongestStreaks,
          'habitTotalCompletions': newHabitTotalCompletions,
          'habitLastCompletedDate': newHabitLastCompletedDate,
          // Same fields Grid's own applyGridSquareChange writes — no new
          // schema, just a second writer here. Unconditional (every
          // completion, not just isGridSyncable ones — see the doc
          // comment above newTotalGreenSquares) so a multi-tap habit
          // tracked only through Today still shows up on the heatmap.
          //
          // A nested map, NOT a dotted 'dailyGreenCounts.$_todayKey' key:
          // dot notation is only a field *path* in update() — inside
          // set(merge: true) it's a literal field name, so the dotted
          // form was creating junk top-level fields named
          // "dailyGreenCounts.2026-07-17" that the loader (which reads
          // the real map) never saw. That was the whole "heatmap is
          // empty after every restart" bug; _load's one-time repair
          // folds the stranded junk fields back in. merge: true merges
          // maps per-leaf-field, so this increments just today's entry
          // without touching other days.
          'totalGreenSquares': FieldValue.increment(1),
          'dailyGreenCounts': {DashboardNotifier._todayKey: FieldValue.increment(1)},
        },
        SetOptions(merge: true),
      );

      // Auto-id per entry — an append-only log, never merged/overwritten,
      // so there's no meaningful key to set() against the way _dailyRef/
      // _userRef use their fixed doc ids above.
      for (final e in milestoneEvents) {
        batch.set(_milestonesRef.doc(), e.toFirestore());
      }

      // ── Deliberately NOT awaited ──────────────────────────────────────
      // Firestore resolves a commit only once the BACKEND acknowledges it.
      // Offline — or on a weak connection — that future simply never
      // completes. The write is already queued durably and the local cache
      // already reflects it, so nothing here actually needs to wait.
      //
      // Awaiting it meant this whole method never returned, and Grid paints
      // the square only *after* awaiting this call (see _handleSquareTap ->
      // markCompleteFromHabit). So tapping yellow -> green with no signal
      // left the square yellow, fired no confetti and never synced the room,
      // while XP, the streak and Today's checkbox had all already moved from
      // the in-memory state update above — the completion visibly half
      // happened. A second tap papered over it by taking the
      // already-rewarded repair branch, which is why it read as flaky rather
      // than broken.
      //
      // Same fire-and-forget posture as every other Firestore write in this
      // app (see WeeklyGridNotifier._persistSquare), with the failure still
      // recorded rather than swallowed.
      unawaited(batch.commit().catchError(
          (Object e, StackTrace st) =>
              _recordWriteFailure('completeHabit', e, st)));
    } catch (e, st) {
      await _recordWriteFailure('completeHabit', e, st);
    }
    return isGridSyncable;
  }
}
