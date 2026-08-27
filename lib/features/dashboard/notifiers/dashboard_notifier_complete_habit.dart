part of 'dashboard_notifier.dart';

/// Minutes since local midnight, the value stamped into a daily doc's
/// `completedAtMinutes` map whenever a habit is completed.
///
/// ── Why this is recorded when nothing reads it ──────────────────────────
/// Time of completion is the one thing about a habit that cannot be
/// recovered later. Every other number in this app can be recomputed from
/// what is already stored, but a day that ended without recording WHEN can
/// never be asked again. The report it exists for (which prayer window a
/// habit actually gets done in, which a generic tracker structurally cannot
/// produce because the windows move daily and by location) is only ever as
/// good as how far back this field reaches, so every release without it is
/// a release that report can never describe.
///
/// ── Two things any reader of this map must know ─────────────────────────
/// 1. It is a SIDECAR, not a record of completion. Uncompleting a habit
///    back to zero leaves its stamp behind on purpose: clearing one key
///    nested inside a merge-written map is its own class of bug, and a
///    stale entry is harmless as long as consumers intersect with
///    `habitCompletions` first, which any "when did I do this" question
///    does anyway. Never read this map on its own.
/// 2. It is WALL CLOCK, measured from real local midnight, while the
///    document it lives on is keyed by effectiveDay, which rolls at
///    kDayCutoffHour (10am). A value below 10 * 60 therefore belongs to the
///    calendar day AFTER the document's own date: qiyam prayed at 02:00 is
///    stamped 120 on the previous day's doc, which is the night it belongs
///    to.
int minutesSinceMidnight(DateTime at) => at.hour * 60 + at.minute;

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
    int scheduledHabitCount = 0,
  }) async {
    // Refuse to record anything while the signed-in load failed. Everything
    // this method persists — level, currentLevelXp, cumulativeXp, gold,
    // streaks, totalHabitCompletions, unlockedAchievements — is written as an
    // ABSOLUTE value with SetOptions(merge: true), computed from `state`. If
    // `state` is DashboardState.initial()'s zeros because _loadToday threw
    // (offline on a fresh calendar day is the common way in), completing a
    // habit would persist level 1 / streak 1 / gold-of-one-reward / no
    // achievements straight over the account's real document, and the real
    // numbers are then gone for good. Declining the completion is recoverable
    // — the person taps again after the next successful load; overwriting is
    // not. See DashboardState.loadFailed.
    //
    // Guests are deliberately not covered: they have no server document to
    // destroy, and _loadGuestToday owns its own failure path.
    if (_uid != null && state.loadFailed) return false;

    // And refuse while the first load simply hasn't ARRIVED yet, for the
    // identical reason. DashboardState.initial() is isLoading: true with
    // loadFailed: false, so the guard above does not cover the cold-start
    // window at all — and that window has a caller: main.dart drains the
    // home widget's queued Mark Done taps from initState
    // (_processPendingWidgetCompletions), and a notification action that
    // cold-launched the app flushes through the same path the moment
    // NotificationService.onAction is assigned. Both can land before
    // _loadToday resolves, and every field this method persists would then
    // be computed from zeros and written back as an ABSOLUTE value.
    //
    // Returning false rather than queueing: this method cannot know whether
    // its caller can retry. The widget path is careful not to drain its
    // queue until the load lands (see _processPendingWidgetCompletions), so
    // nothing is lost there; this is the backstop for every other caller.
    if (_uid != null && state.isLoading) return false;

    final current = state.completions[habitId] ?? 0;
    if (current >= frequencyTarget) return false;

    final newCompletions = Map<String, int>.from(state.completions)
      ..[habitId] = current + 1;

    // ── This tap's share of the day ──────────────────────────────
    //
    // xpReward/goldReward are the price of the DAY, not of one tap. A habit
    // counted 4 times a day is not worth 4 days' XP for the same habit, so
    // the day's price is split across its taps and this tap takes its slice
    // (see XpCalculator.rewardSliceForTap for why the slices are uneven and
    // why that is the point). frequencyTarget is already the per-day count:
    // every caller passes IslamicHabitTemplate.effectiveDailyTarget, which
    // is frequencyTarget for a daily habit and 1 for a weekly one.
    //
    // At a target of 1 both slices ARE xpReward/goldReward, so every habit
    // that existed before counting did is paid to the byte what it always
    // was — that equivalence is pinned in test/core/reward_per_day_test.dart.
    // Whether this tap is the one that finishes the habit's day. Always true
    // at a target of 1, which is what every caller passed before habits could
    // be counted — so everything gated on it below behaves for an ordinary
    // habit exactly as it did when the gate did not exist.
    final finishesDay = completionAnnouncesItself(
      doneBefore: current,
      target: frequencyTarget,
    );

    final xpSlice = XpCalculator.rewardSliceForTap(
      total: xpReward,
      target: frequencyTarget,
      tapIndex: current,
    );
    final goldSlice = XpCalculator.rewardSliceForTap(
      total: goldReward,
      target: frequencyTarget,
      tapIndex: current,
    );

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
    // An outstanding receipt for this habit TODAY means this completion is
    // putting back one that was undone earlier today (see [UndoneCompletion]).
    // The reward arithmetic below needs no help for that — a same-day redo
    // recomputes it correctly — but two things do follow from it: the day's
    // original completion TIME must survive (see [minutesSinceMidnight]'s
    // sidecar note and the write below), and the receipt has to be spent here
    // so it can never be redeemed a second time by repainting the same square
    // once the day has rolled over.
    final redeemed = state.undoneFor(habitId, DashboardNotifier._todayKey);
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
      // 2+, or no prior completion at all, restarts it at 1. A gap of zero is
      // reachable and used to be destructive — see [nextHabitStreak], which
      // owns the whole rule now so it can be tested.
      final newHabitStreak =
          nextHabitStreak(gapDays: gap, previousStreak: prevStreak);
      newHabitStreakCounts[habitId] = newHabitStreak;
      final prevLongest = state.habitLongestStreaks[habitId] ?? 0;
      newHabitLongestStreaks[habitId] =
          newHabitStreak > prevLongest ? newHabitStreak : prevLongest;
      newHabitTotalCompletions[habitId] =
          (state.habitTotalCompletions[habitId] ?? 0) + 1;
      newHabitLastCompletedDate[habitId] = DashboardNotifier._todayKey;

      // ── Per-habit milestone ──────────────────────────────────
      //
      // Skipped when the streak did not actually advance — see
      // [habitStreakAdvanced] for the one case that is and why paying its
      // bonus again would be paying twice for one day.
      final habitBonus = habitStreakAdvanced(gap)
          ? GameConstants.habitStreakBonuses[newHabitStreak]
          : null;
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
    //
    // Scaled off the SLICE rather than the day's full price, for the same
    // reason the slice exists: this fires per tap, so paying it against the
    // whole day would let a habit counted 4 times a day roll four bonuses
    // that were each priced as though they were the entire day.
    final rolledBonus = _random.nextDouble() < GameConstants.surpriseBonusChance;
    final surpriseBonusXp = rolledBonus
        ? (xpSlice * GameConstants.surpriseBonusMultiplier).ceil()
        : 0;
    final surpriseBonusGold = rolledBonus
        ? (goldSlice * GameConstants.surpriseBonusMultiplier).ceil()
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
    } else {
      // A later tap of a counted habit keeps the day's first-tap snapshot —
      // those prev* fields are the ones an undo has to restore — but its own
      // surprise bonus still has to be recorded, because the bonus rolls on
      // EVERY tap while the snapshot was only ever written on the first.
      //
      // Left unaccumulated, clearing a finished day gave back the day's
      // reward plus only the first tap's bonus, stranding every later one.
      // Tap to full, clear, repeat, and each lap nets whatever those later
      // taps happened to roll — the same repeatable lap that
      // setSquareStateOnly exists to close, reopened through a different
      // door. Pinned by "clearing a finished day gives back exactly what it
      // paid" in times_per_day_economy_test.dart.
      final prior = _lastHabitCompletion[habitId];
      if (prior != null && (surpriseBonusXp > 0 || surpriseBonusGold > 0)) {
        _lastHabitCompletion[habitId] = prior.copyWithAddedBonus(
          xp: surpriseBonusXp,
          gold: surpriseBonusGold,
        );
      }
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
    // Not when a freeze is banked. previousStreak > 0 with streakFreezes > 0 is
    // the card offering a real streak RESTORE, and useStreakFreeze guards on
    // previousStreak > 0 — so zeroing it here the instant today goes all-done
    // would spend a multi-day restore the user never chose, trading it for
    // 50 XP and a day-1 streak, and the card would vanish before they could
    // pick. Leaving it armed keeps the choice open; the bonus is still paid by
    // whichever route they then take (restore or fresh start both pay it — see
    // useStreakFreeze / acknowledgeComeback), just not auto-collected here. With
    // no freeze there is nothing to protect, so continuing clears and pays it as
    // before, which is what comebackEitherWay promises for that layout.
    final clearsPendingComeback = justReachedAllDone &&
        state.previousStreak > 0 &&
        state.streakFreezes <= 0;
    // Clearing the offer used to be ALL this did, and the bonus attached to
    // it was simply forfeited: DashboardNotifier.comebackBonusXp was spent
    // in exactly one place, acknowledgeComeback, which only ever runs from
    // the card's own button. So the person who ignored the card and went
    // and finished their habits, which is the entire behaviour the card is
    // asking for, was the one person who got nothing for it, while the
    // person who tapped a button and did nothing else got 50 XP. The card
    // even promised the opposite in writing ("+50 XP comeback bonus when
    // you continue"). Continuing is the comeback, so continuing pays it.
    final comebackBonusXp =
        clearsPendingComeback ? DashboardNotifier.comebackBonusXp : 0;
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

    // ── The daily ceiling ───────────────────────────────────────
    //
    // Only the REPEATABLE half of this payout meets it. The slice and the
    // surprise bonus are both produced again every time a habit is created
    // and completed, which is the farm the cap exists to bound. The three
    // milestone bonuses are added after the clamp and are never withheld:
    // each is once-per-lifetime or once-per-episode, so capping them buys no
    // safety, and a withheld milestone is unrecoverable because the crossing
    // test that pays it (`newStreak == m && state.streak < m`) can never be
    // true for that threshold again.
    //
    // Read once into a local, like the receipt below does, because a method
    // that straddles the day cutoff must not bank against one day and
    // charge against the next.
    final earnDayKey = DashboardNotifier._todayKey;
    final capped = _allowedToday(
      xp: xpSlice + surpriseBonusXp,
      gold: goldSlice + surpriseBonusGold,
      habitCount: scheduledHabitCount,
    );

    final result = XpCalculator.applyXpGain(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpGained: capped.xp +
          milestoneBonusXp +
          habitMilestoneBonusXp +
          comebackBonusXp,
    );
    final newGold = state.gold + capped.gold;
    // ── The day-counters ────────────────────────────────────────
    //
    // A completion is a habit-DAY, not a tap. These four feed the lifetime
    // stats on Profile, the Monthly Heatmap, and the achievement thresholds
    // (completions_50/500/2000/5000 and green_1/100/500/2000), and every one
    // of them means "days", so a habit counted four times a day must not
    // advance them four times as fast. Left per-tap it was the same class of
    // leak as paying XP per tap: pick a bigger number, unlock medals sooner.
    //
    // The comment that used to sit here claimed the guard above already made
    // this "at most a one-time bump per habit per day". That was true only
    // because effectiveDailyTarget could never exceed 1 — daily habits were
    // pinned to 1 by the editor and weekly ones resolve to 1 — so the claim
    // was correct by accident and stopped being correct the moment the
    // stepper could set it. Gating on finishesDay makes it true on purpose.
    final newTotal = state.totalCompletions + (finishesDay ? 1 : 0);

    final newCategoryCompletions = {...state.categoryCompletions};
    if (category != null && finishesDay) {
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
    // Green squares are literally squares, and a counted habit turns exactly
    // one square green per day — on the tap that fills it. Counting the
    // part-done taps too would put more green squares in the heatmap than
    // the board has squares to show.
    final newTotalGreenSquares = state.totalGreenSquares + (finishesDay ? 1 : 0);
    final newDailyGreenCounts = {...state.dailyGreenCounts};
    if (finishesDay) {
      newDailyGreenCounts[DashboardNotifier._todayKey] =
          (newDailyGreenCounts[DashboardNotifier._todayKey] ?? 0) + 1;
    }

    // ── Achievement check ────────────────────────────────────
    // See _resolveUnlocks for why this resolves to a fixed point instead of
    // testing once against `result.newLevel` the way it used to.
    final unlocks = _resolveUnlocks(
      unlockedIds: state.unlockedAchievements,
      level: result.newLevel,
      currentLevelXp: result.newCurrentLevelXp,
      cumulativeXp: result.newCumulativeXp,
      streak: newStreak,
      totalCompletions: newTotal,
      greenSquares: newTotalGreenSquares,
      categoryCompletions: newCategoryCompletions,
      levelGrantPaidThrough: state.levelGrantPaidThrough,
    );
    final newly = unlocks.newly;
    final newUnlockedIds = unlocks.unlockedIds;
    final bonusGold = unlocks.bonusGold;
    final bonusResult = (
      newLevel: unlocks.level,
      newCurrentLevelXp: unlocks.currentLevelXp,
      newCumulativeXp: unlocks.cumulativeXp,
    );

    AnalyticsService.instance.track('habit_completed', props: {
      'habitId': habitId,
      'streak': newStreak,
      'allHabitsDoneAfter': allHabitsDoneAfter,
      'streakJustEarned': justReachedAllDone,
      'milestone': newMilestone,
    });
    // Same event the card's button fires, so the funnel counts a comeback
    // once however it was finished. 'route' is the only way to tell the two
    // apart afterwards, and worth knowing: if almost nobody ever arrives
    // here by 'continue', the card is doing the work and the bonus is
    // really a tap reward, which would be worth redesigning rather than
    // quietly paying for.
    if (clearsPendingComeback) {
      AnalyticsService.instance
          .track('comeback_bonus_claimed', props: {'route': 'continue'});
    }

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
      levelGrantPaidThrough: unlocks.levelGrantPaidThrough,
      currentLevelXp: bonusResult.newCurrentLevelXp,
      cumulativeXp: bonusResult.newCumulativeXp,
      gold: newGold + bonusGold,
      earnedDayKey: earnDayKey,
      earnedXpToday: capped.newXpToday,
      earnedGoldToday: capped.newGoldToday,
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
      // Spent, so repainting this same square after the day rolls over can
      // never redeem it a second time.
      undoneCompletions: redeemed == null
          ? null
          : ({...state.undoneCompletions}..remove(redeemed.key)),
      setHabitMilestone: newHabitMilestoneEvent,
      lastCompletionBonusXp: surpriseBonusXp,
      lastCompletionBonusGold: surpriseBonusGold,
    );

    // ── Only the tap that finishes the day announces itself ──────
    //
    // The reward banner is an EVENT — "this is done, here is what it paid" —
    // and a habit counted N times a day would otherwise fire N of them. Four
    // a day is wrong even when the habit is a happy one, and it is worse than
    // wrong when it is not: the app does not know whether this habit is
    // drinking water or taking medicine, and it must not congratulate someone
    // four times a day for taking medicine. Neutral is the only safe default,
    // because it is the only one that is never insulting.
    //
    // Nothing is taken away from the cheerful case either. The finishing tap
    // fires exactly the banner the habit fired when it was once a day, so a
    // water habit still gets its celebration — one a day, the same one it
    // always had. What the intermediate taps get instead is the square
    // filling and its count going up, which is a statement of fact and reads
    // as progress without claiming anything about how the person should feel.
    //
    // At frequencyTarget 1 this is unconditionally true, so no habit that
    // existed before counting did notices any of it.
    if (finishesDay) {
      _fireCompletionNotifications(
        habitId: habitName ?? habitId,
        // The slice, not the day's price: this is the number the person is
        // shown, and showing them "+10 XP" on each of four taps that together
        // paid 10 would be telling them they earned 40.
        // The CAPPED figures, not the nominal ones. This is the number the
        // person is shown, and a banner that celebrates XP the ceiling just
        // withheld is the app lying about their balance.
        xpEarned: capped.xp + milestoneBonusXp + habitMilestoneBonusXp,
        goldEarned: capped.gold,
        didLevelUp: didLevelUp,
        newLevel: bonusResult.newLevel,
        newlyUnlocked: newly,
      );
    }

    if (_uid == null) {
      await _saveGuestDaily(
        newCompletions,
        streakEarnedToday: newStreakEarnedToday,
        // Only for a habit that is counted more than once a day: at a target
        // of 1 the absence of an entry already means 1, and writing it for
        // every habit would grow every day document for nothing.
        habitTargets:
            frequencyTarget > 1 ? {habitId: frequencyTarget} : null,
        // Not restamped when a receipt is being redeemed. Uncompleting leaves
        // the original stamp behind on purpose (see [minutesSinceMidnight]),
        // so the fajr adhkar that were really done at fajr keep saying so
        // instead of being rewritten to whenever the mis-tap was corrected.
        completedAtMinutes: redeemed != null
            ? null
            : {habitId: minutesSinceMidnight(DateTime.now())},
      );
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
          // What this day asked of this habit, stamped on the day itself so a
          // report reading it back years later can tell a finished counted day
          // from a part-done one without guessing from today's settings — see
          // dayMark. Only written above a target of 1, where absence already
          // means 1. Nested map, so merge updates this habit's entry and leaves
          // the other habits' alone.
          if (frequencyTarget > 1)
            'habitTargets': {habitId: frequencyTarget},
          'date': Timestamp.fromDate(now),
          'streakEarnedToday': newStreakEarnedToday,
          // A nested map merged key by key, not written whole:
          // SetOptions(merge: true) deep-merges maps, so two habits
          // completed from two devices cannot erase each other the way a
          // wholesale write of this field would. See
          // [minutesSinceMidnight] for what this is for and the two things
          // any reader of it must know.
          // Not restamped when a receipt is being redeemed — see the guest
          // branch above for why the original time has to survive a
          // correction.
          if (redeemed == null)
            'completedAtMinutes': {
              habitId: minutesSinceMidnight(DateTime.now()),
            },
        },
        SetOptions(merge: true),
      );

      batch.set(
        _userRef,
        {
          'level': bonusResult.newLevel,
          // Rides the SAME write map as 'level', so the mark and the level
          // it marks can never land apart.
          'levelGrantPaidThrough': unlocks.levelGrantPaidThrough,
          'currentLevelXp': bonusResult.newCurrentLevelXp,
          'cumulativeXp': bonusResult.newCumulativeXp,
          'gold': newGold + bonusGold,
          // Absolute, like every figure around it. A counter that only ever
          // grows within one day and resets by stamp does not need
          // increment's merge semantics, and an absolute write is what makes
          // a stale device converge instead of double-counting.
          'earnedDayKey': earnDayKey,
          'earnedXpToday': capped.newXpToday,
          'earnedGoldToday': capped.newGoldToday,
          'currentStreak': newStreak,
          'longestStreak': newLongest,
          if (clearsPendingComeback) 'previousStreak': 0,
          'totalHabitCompletions': newTotal,
          // arrayUnion of just what was earned right now, not the whole
          // locally-computed list. `unlockedAchievements` is a set that only
          // ever grows, and writing it wholesale makes it last-writer-wins:
          // two devices each earning a different medal offline, or one device
          // running on a stale read, silently erased the other's. arrayUnion
          // merges server-side instead, so a medal can never be un-earned by
          // a sync. Omitted entirely when nothing was earned, so the common
          // completion doesn't touch the field at all.
          if (newly.isNotEmpty)
            'unlockedAchievements':
                FieldValue.arrayUnion(newly.map((a) => a.id).toList()),
          'categoryCompletions': newCategoryCompletions,
          // Same "only on a genuinely qualifying day" rule as the guest
          // branch above — see that comment. Previously unconditional,
          // which was the actual bug: any single completion refreshed this
          // regardless of whether today ever reached the threshold, so the
          // streak could coast forever on partial days without ever
          // tripping the gap-check below.
          if (newStreakEarnedToday) 'lastActiveDate': Timestamp.fromDate(now),
          // The offset free twin of the line above, and the one the streak
          // gap check actually reads. See dashboard_notifier_loading's
          // lastActiveDay branch for why a Timestamp cannot carry a calendar
          // day across a timezone change. The Timestamp stays because
          // UserAccount still reads it, and because an account written by an
          // older build has only that.
          if (newStreakEarnedToday) 'lastActiveDay': DashboardNotifier._todayKey,
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
          // Gated exactly as the local counters above are: one green
          // square per habit-day, credited on the tap that fills it.
          'totalGreenSquares': FieldValue.increment(finishesDay ? 1 : 0),
          'dailyGreenCounts': {
            DashboardNotifier._todayKey: FieldValue.increment(finishesDay ? 1 : 0),
          },
          // One nested key deleted, so the receipts outstanding on other
          // habit-days survive the merge.
          if (redeemed != null)
            'undoneCompletions': {redeemed.key: FieldValue.delete()},
        },
        SetOptions(merge: true),
      );

      // Writer 1 of 3 for the per-habit yearly strip's mirror — see
      // habitHistoryRef. Presence-based and idempotent: completing twice
      // writes the same 1.
      batch.set(
        habitHistoryRef(habitId),
        {
          // The mirror stores the six-state mark now (see habit_day_marks.dart).
          // complete ONLY when this tap finishes the day — every other
          // day-writer in this method is gated on finishesDay, and this one was
          // not. For a counted habit that made tap 1 of 4 stamp the day
          // 'complete' in the mirror, so a day stopped at 2 of 4 settled as
          // fully done: withLiveToday's overlay hides it while it is still
          // today, but once the day settles the mirror is authoritative and the
          // yearly strip and period reports show a green, fully-credited day the
          // reward system itself refused to count. partial is the honest mark
          // for a part-done day. A day already painted bonus is flattened to
          // this write's mark, accepted rather than paid for with a read: on the
          // finishing tap green stays green so nothing moves; only the rare
          // bonus flourish is lost.
          'days': {
            DashboardNotifier._todayKey: markToStored(
                finishesDay ? SquareState.complete : SquareState.partial),
          },
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
