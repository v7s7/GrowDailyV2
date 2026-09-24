part of 'dashboard_notifier.dart';

extension DashboardNotifierStreakFromPartial on DashboardNotifier {
  /// Retroactively earns [day]'s streak point when a جزئي mark — not a full
  /// completion — is what crosses [kStreakDayCompletionThreshold].
  ///
  /// [completeHabit]'s own app-wide streak bump only ever runs from a real
  /// completion landing, because only [willCompleteAllHabitsToday]/
  /// [willCompleteAllSquaresOn] ask the question and both are wired to that
  /// one call site. That is exactly right for a day that finishes on its
  /// last GREEN square. It silently missed the day that finishes on its
  /// last YELLOW one instead: mark three of four habits complete, then the
  /// fourth جزئي, and the day is genuinely 87.5%
  /// ([willCrossStreakThresholdOnPartial] already credits that) — but
  /// nothing ever re-asked the question, because a جزئي never calls
  /// completeHabit. Reported live (Aziz, 2026-09-21): "i am already above
  /// 80% with the 0.5 habit."
  ///
  /// A تخطّي can be that last mark too, since a skipped habit leaves the
  /// day's count (Aziz, 2026-09-22), so the palette also calls this after
  /// [willCrossStreakThresholdOnSkip]. Nothing else about it differs.
  ///
  /// Callers must already have confirmed [willCrossStreakThresholdOnPartial]
  /// for this exact day — that predicate, not this method, is what keeps a
  /// day made entirely of جزئي squares from ever earning anything (see its
  /// own doc comment). This method trusts that guard and just pays the same
  /// thing [completeHabit] would have paid at that exact moment: the streak
  /// bump, any streak milestone (and its bonus XP), any achievement that
  /// bump newly crosses, and the same celebration. Confirmed with Aziz
  /// (2026-09-21): this should feel identical to finishing the day on a
  /// green square, not a quieter version of it.
  ///
  /// Deliberately narrower than completeHabit everywhere else: no habit is
  /// finishing, so none of its per-habit machinery runs here — no XP/gold
  /// slice, no per-habit streak, no totalCompletions/greenSquares bump, no
  /// yearly-strip mirror write. The جزئي square itself was already paid its
  /// own flat rate by `WeeklyGridNotifier.setSquare` before this ever runs.
  Future<void> earnStreakFromPartialCredit({DateTime? day}) async {
    // Same refusals as completeHabit's, for the same reason: everything
    // below is written as an ABSOLUTE value computed from `state`.
    if (_uid != null && state.loadFailed) return;
    if (_uid != null && state.isLoading) return;

    final markDay = (day ?? _clock().effectiveDay).startOfDay;
    final dayKey = markDay.toDateKey();
    final isGraceDay = dayKey != _todayKeyNow;
    if (isGraceDay && !markDay.isOpenDayAt(_clock())) return;

    var dayStreakEarnedBefore = state.streakEarnedToday;
    if (isGraceDay) {
      final stored = await _readStoredDay(markDay);
      dayStreakEarnedBefore = stored.streakEarned;
    }
    // Already earned by something else (a completion landed first, or this
    // fired twice) — nothing left to pay.
    if (dayStreakEarnedBefore) return;

    final bump = _computeStreakBump();
    final newStreak = bump.streak;
    final newLongest = bump.longestStreak;
    final newMilestone = bump.milestone;
    final milestoneBonusXp = bump.milestoneBonusXp;

    // Same comeback rule as completeHabit's justReachedAllDone branch — see
    // its doc comment for why an already-armed freeze must not be
    // auto-spent by a day simply reaching its threshold.
    final clearsPendingComeback =
        state.previousStreak > 0 && state.streakFreezes <= 0;
    final comebackBonusXp =
        clearsPendingComeback ? DashboardNotifier.comebackBonusXp : 0;

    final result = XpCalculator.applyXpGain(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpGained: milestoneBonusXp + comebackBonusXp,
    );

    final unlocks = _resolveUnlocks(
      unlockedIds: state.unlockedAchievements,
      level: result.newLevel,
      currentLevelXp: result.newCurrentLevelXp,
      cumulativeXp: result.newCumulativeXp,
      streak: newStreak,
      totalCompletions: state.totalCompletions,
      greenSquares: state.totalGreenSquares,
      categoryCompletions: state.categoryCompletions,
      levelGrantPaidThrough: state.levelGrantPaidThrough,
    );
    final newly = unlocks.newly;
    final newGold = state.gold + unlocks.bonusGold;
    final newLevel = unlocks.level;
    final newCurrentLevelXp = unlocks.currentLevelXp;
    final newCumulativeXp = unlocks.cumulativeXp;
    final didLevelUp = newLevel > state.level;

    AnalyticsService.instance.track('streak_earned_from_partial', props: {
      'streak': newStreak,
      'milestone': newMilestone,
    });
    if (clearsPendingComeback) {
      AnalyticsService.instance
          .track('comeback_bonus_claimed', props: {'route': 'partial'});
    }

    final nowInstant = DateTime.now();
    final milestoneEvents = <MilestoneEvent>[
      if (didLevelUp)
        MilestoneEvent(
          id: '',
          type: MilestoneType.levelUp,
          occurredAt: nowInstant,
          data: {'level': newLevel},
        ),
      if (newMilestone != null)
        MilestoneEvent(
          id: '',
          type: MilestoneType.streakMilestone,
          occurredAt: nowInstant,
          data: {'days': newMilestone},
        ),
      MilestoneEvent(
        id: '',
        type: MilestoneType.perfectDay,
        occurredAt: nowInstant,
      ),
      if (newStreak > 0 && newStreak % 7 == 0)
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
          data: {'achievementId': a.id, 'tier': a.tier.name},
        ),
    ];

    state = state.copyWith(
      level: newLevel,
      currentLevelXp: newCurrentLevelXp,
      cumulativeXp: newCumulativeXp,
      gold: newGold,
      streak: newStreak,
      longestStreak: newLongest,
      previousStreak: clearsPendingComeback ? 0 : null,
      unlockedAchievements: unlocks.unlockedIds,
      newlyUnlocked: newly,
      didJustLevelUp: didLevelUp,
      setMilestone: newMilestone,
      streakEarnedToday: isGraceDay ? null : true,
      // Moves with the stored lastActiveDay below, same as completeHabit.
      lastStreakDay: !_lastActiveIsAfter(dayKey) ? markDay : null,
      perfectDayCelebration: isGraceDay ? false : true,
      levelGrantPaidThrough: unlocks.levelGrantPaidThrough,
    );

    if (_uid == null) {
      await _saveGuestDaily(
        state.completions,
        streakEarnedToday: true,
        dayKey: dayKey,
      );
      await _saveGuestState(
        lastActiveDate: !_lastActiveIsAfter(dayKey) ? markDay : null,
      );
      return;
    }

    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.set(
        _dailyRefFor(markDay),
        {
          'streakEarnedToday': true,
          'date': Timestamp.fromDate(markDay),
        },
        SetOptions(merge: true),
      );
      batch.set(
        _userRef,
        {
          'level': newLevel,
          'levelGrantPaidThrough': unlocks.levelGrantPaidThrough,
          'currentLevelXp': newCurrentLevelXp,
          'cumulativeXp': newCumulativeXp,
          'gold': newGold,
          'currentStreak': newStreak,
          'longestStreak': newLongest,
          if (clearsPendingComeback) 'previousStreak': 0,
          if (newly.isNotEmpty)
            'unlockedAchievements':
                FieldValue.arrayUnion(newly.map((a) => a.id).toList()),
          if (!_lastActiveIsAfter(dayKey))
            'lastActiveDate': Timestamp.fromDate(markDay),
          if (!_lastActiveIsAfter(dayKey)) 'lastActiveDay': dayKey,
        },
        SetOptions(merge: true),
      );
      for (final e in milestoneEvents) {
        batch.set(_milestonesRef.doc(), e.toFirestore());
      }
      // Fire-and-forget, same posture as completeHabit's own commit — see
      // its doc comment for why awaiting it would be wrong here too.
      unawaited(batch.commit().catchError((Object e, StackTrace st) =>
          _recordWriteFailure('earnStreakFromPartialCredit', e, st)));
    } catch (e, st) {
      await _recordWriteFailure('earnStreakFromPartialCredit', e, st);
    }
  }
}
