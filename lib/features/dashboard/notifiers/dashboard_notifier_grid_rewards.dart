part of 'dashboard_notifier.dart';

extension DashboardNotifierGridRewards on DashboardNotifier {

  /// Applies the progression fallout of a single Victory Grid square
  /// changing color: fixed XP per the color (see [SquareState.xpValue]), a
  /// lifetime green-square counter that drives grid achievements, and a
  /// daily rollup for the monthly heatmap.
  ///
  /// Deliberately does **not** touch the streak. Streak means a full,
  /// 100%-of-today's-habits day (see [DashboardState.streakEarnedToday]),
  /// and that's only knowable from the real habit list, which this
  /// habit-agnostic, color-only method never sees — a lone bonus-colored
  /// square, a partial mark, or a multi-tap habit's Grid-only progress
  /// isn't "today done", so none of those should hand out the day's streak
  /// point on their own. The one case that legitimately *should* streak —
  /// finishing a real single-tap habit's square to `complete` — is already
  /// special-cased at the call site to go through [completeHabit] instead
  /// (see grid_screen.dart's `_handleSquareTap`/`_handlePaletteTap`), so by
  /// the time a color change reaches here, it was never going to be the
  /// day's 100% moment.
  Future<void> applyGridSquareChange({
    required int xpDelta,
    required int greenDelta,
    required String dateKey,
  }) async {
    // Same refusal as completeHabit's, for the same reason and with the same
    // stakes — see the long comment there. This path needed it just as much:
    // the batch below writes level, currentLevelXp, cumulativeXp, gold and
    // unlockedAchievements as ABSOLUTE values computed from `state`, and
    // WeeklyGridNotifier.setSquare routes every *non-green* square tap
    // straight here without passing through completeHabit's guard at all. So
    // a single tap landing on a partial colour after a failed load was enough
    // to flatten the real account document — the one tap that guard was
    // written to prevent, arriving through the door it doesn't cover.
    if (_uid != null && state.loadFailed) return;

    var newLevel = state.level;
    var newCurrentLevelXp = state.currentLevelXp;
    var newCumulativeXp = state.cumulativeXp;

    // Only a POSITIVE delta meets the daily ceiling. A negative one is a
    // square being cleared, i.e. a reversal, and clamping a reversal would
    // let a user keep XP by taking a colour back off once the day was full.
    // Gold is untouched here: this path pays gold only through achievement
    // unlocks, which are exempt by design.
    final gridCap = xpDelta > 0
        ? _allowedToday(xp: xpDelta, gold: 0, habitCount: 0)
        : (xp: xpDelta, gold: 0, newXpToday: -1, newGoldToday: -1);
    final cappedXpDelta = gridCap.xp;

    if (cappedXpDelta != 0) {
      final result = XpCalculator.applyXpDelta(
        currentLevel: state.level,
        currentLevelXp: state.currentLevelXp,
        cumulativeXp: state.cumulativeXp,
        xpDelta: cappedXpDelta,
      );
      newLevel = result.newLevel;
      newCurrentLevelXp = result.newCurrentLevelXp;
      newCumulativeXp = result.newCumulativeXp;
    }

    final rawTotalGreen = state.totalGreenSquares + greenDelta;
    final newTotalGreen = rawTotalGreen < 0 ? 0 : rawTotalGreen;
    final newDailyGreenCounts = {...state.dailyGreenCounts};
    if (greenDelta != 0) {
      final rawDay = (newDailyGreenCounts[dateKey] ?? 0) + greenDelta;
      newDailyGreenCounts[dateKey] = rawDay < 0 ? 0 : rawDay;
    }

    // ── Achievement check ────────────────────────────────────
    //
    // Full stats, not just the two counters this method moves. The check
    // here used to test `level` and `greenSquares` only, so anything else
    // already sitting past its threshold — a total-completions or Quran
    // mastery tier — was invisible on this path and stayed locked until a
    // habit completion happened to re-check it. Passing the unchanged
    // counters through alongside the changed ones costs nothing and closes
    // that hole.
    final unlocks = _resolveUnlocks(
      unlockedIds: state.unlockedAchievements,
      level: newLevel,
      currentLevelXp: newCurrentLevelXp,
      cumulativeXp: newCumulativeXp,
      streak: state.streak,
      totalCompletions: state.totalCompletions,
      greenSquares: newTotalGreen,
      categoryCompletions: state.categoryCompletions,
      levelGrantPaidThrough: state.levelGrantPaidThrough,
    );
    final newly = unlocks.newly;
    final newUnlockedIds = unlocks.unlockedIds;
    newLevel = unlocks.level;
    final newGrantMark = unlocks.levelGrantPaidThrough;
    newCurrentLevelXp = unlocks.currentLevelXp;
    newCumulativeXp = unlocks.cumulativeXp;
    final newGold = state.gold + unlocks.bonusGold;
    final didLevelUp = newLevel > state.level;

    state = state.copyWith(
      level: newLevel,
      currentLevelXp: newCurrentLevelXp,
      cumulativeXp: newCumulativeXp,
      gold: newGold,
      earnedDayKey: xpDelta > 0 ? DashboardNotifier._todayKey : null,
      earnedXpToday: xpDelta > 0 ? gridCap.newXpToday : null,
      totalGreenSquares: newTotalGreen,
      dailyGreenCounts: newDailyGreenCounts,
      unlockedAchievements: newUnlockedIds,
      newlyUnlocked: newly,
      didJustLevelUp: didLevelUp,
    );

    if (didLevelUp) NotificationService.instance.showLevelUp(newLevel);
    // One notification for the batch — see _fireCompletionNotifications.
    NotificationService.instance.showAchievementsUnlocked([
      for (final a in newly)
        a.localName(NotificationService.instance.isArabic),
    ]);

    if (_uid == null) {
      await _saveGuestState();
      return;
    }

    try {
      final batch = FirebaseFirestore.instance.batch();

      // No 'lastActiveDate' write here, on purpose — this method's own
      // doc comment above already says it "deliberately does not touch
      // the streak," but it used to write lastActiveDate anyway, which
      // (once that field started gating streak decay) quietly broke that
      // promise: backfilling a past day, or marking today's square a
      // non-green color, refreshed it exactly like a genuine qualifying
      // day would and let the streak keep coasting through this path too.
      // The guest branch above never had this bug (_saveGuestState() is
      // called with no lastActiveDate argument) — this brings the
      // signed-in path in line with it.
      final userUpdate = <String, dynamic>{
        'level': newLevel,
        'levelGrantPaidThrough': newGrantMark,
        'currentLevelXp': newCurrentLevelXp,
        'cumulativeXp': newCumulativeXp,
        'gold': newGold,
        if (xpDelta > 0) ...{
          'earnedDayKey': DashboardNotifier._todayKey,
          'earnedXpToday': gridCap.newXpToday,
        },
        // arrayUnion of only what was just earned — see completeHabit's
        // identical write for why this must never be a wholesale overwrite.
        if (newly.isNotEmpty)
          'unlockedAchievements':
              FieldValue.arrayUnion(newly.map((a) => a.id).toList()),
      };
      if (greenDelta != 0) {
        userUpdate['totalGreenSquares'] = FieldValue.increment(greenDelta);
        // Nested map, not a dotted key — see completeHabit's identical
        // write for why (dot notation is a literal field name inside
        // set(merge: true), not a path).
        userUpdate['dailyGreenCounts'] = {
          dateKey: FieldValue.increment(greenDelta),
        };
      }
      batch.set(_userRef, userUpdate, SetOptions(merge: true));

      // Not awaited — same reason as completeHabit's commit (see the long
      // comment there). This one is called straight from WeeklyGridNotifier.
      // setSquare on every square tap, so blocking it on a backend round
      // trip stalls the most frequent interaction in the app.
      unawaited(batch.commit().catchError(
          (Object e, StackTrace st) =>
              _recordWriteFailure('applyGridSquareChange', e, st)));
    } catch (e, st) {
      await _recordWriteFailure('applyGridSquareChange', e, st);
    }
  }

  /// Keeps the heatmap's day rollup honest when a *past* day's square is
  /// backfilled. WeeklyGridNotifier.setSquare intentionally never calls
  /// [applyGridSquareChange] for a non-today day — that guard exists so
  /// navigating to an old week and coloring squares green can't farm real
  /// XP, gold, streak, or achievement progress for a day that wasn't
  /// actually lived through. But the Monthly Heatmap (see
  /// MonthlyHeatmapScreen) reads *only* from [dailyGreenCounts], so
  /// skipping that field too meant a backfilled square colored correctly
  /// on the Grid itself but silently never showed up on the heatmap — the
  /// exact "doesn't save the previous days" gap. This method updates
  /// *only* dailyGreenCounts, nothing else: no XP, no gold, no streak, no
  /// totalGreenSquares, no achievement checks. It's deliberately the
  /// narrowest possible fix, so the anti-farming guard everywhere else
  /// stays exactly as strict as it already was.
  void recordPastDayGreenDelta(String dateKey, int greenDelta) {
    if (greenDelta == 0) return;
    final newDailyGreenCounts = {...state.dailyGreenCounts};
    final raw = (newDailyGreenCounts[dateKey] ?? 0) + greenDelta;
    newDailyGreenCounts[dateKey] = raw < 0 ? 0 : raw;
    state = state.copyWith(dailyGreenCounts: newDailyGreenCounts);

    if (_uid == null) {
      _saveGuestState().ignore();
      return;
    }
    // Nested map, not a dotted key — see completeHabit's identical write
    // for why (dot notation is a literal field name inside
    // set(merge: true), not a path).
    _userRef.set(
      {
        'dailyGreenCounts': {dateKey: FieldValue.increment(greenDelta)},
      },
      SetOptions(merge: true),
    ).ignore();
  }

  /// Buys one more BANK SLOT, permanently raising how many freezes this
  /// account may hold. Returns whether it persisted.
  ///
  /// Same rollback rule as [buyStreakFreeze] below and for the same reason:
  /// a failed write that still showed success cost the player gold and gave
  /// nothing back. Capacity is written as an ABSOLUTE value rather than an
  /// increment, so a retry after a write whose result was never seen lands
  /// on the same number instead of buying the slot twice.
  ///
  /// Both the price and the level gate come from one map, so they cannot
  /// disagree. A slot that is not in it simply cannot be bought.
  Future<bool> buyFreezeSlot(int slot) async {
    if (_uid != null && (state.loadFailed || state.isLoading)) return false;
    final offer = DashboardNotifier.freezeSlots[slot];
    if (offer == null) return false;
    // Slots are bought in order: this is the NEXT one or nothing. Without
    // it, someone at capacity 3 could buy slot 5 and skip slot 4's price.
    if (slot != state.freezeCapacityOrDefault + 1) return false;
    if (state.level < offer.level) return false;
    if (state.gold < offer.cost) return false;

    final previousGold = state.gold;
    final previousCapacity = state.freezeCapacity;
    final newGold = previousGold - offer.cost;
    state = state.copyWith(gold: newGold, freezeCapacity: slot);
    try {
      if (_uid == null) {
        await _saveGuestState();
      } else {
        await _userRef.set({
          'gold': newGold,
          'freezeCapacity': slot,
        }, SetOptions(merge: true));
      }
    } catch (_) {
      state = state.copyWith(
        gold: previousGold,
        freezeCapacity: previousCapacity,
      );
      return false;
    }
    AnalyticsService.instance.track('freeze_slot_bought', props: {'slot': slot});
    return true;
  }

  /// Spends gold for an extra streak freeze. Returns whether the purchase
  /// actually persisted — previously this always returned `true` once the
  /// affordability check passed, even if the Firestore write below failed,
  /// which showed the player a success toast for a purchase that silently
  /// never saved (they'd lose the gold and the freeze on next launch, with
  /// no error and nothing to point to why). Now a failed write rolls the
  /// optimistic gold/freeze deduction back and reports failure so the UI can
  /// tell the user to retry instead of celebrating a purchase that didn't
  /// happen.
  Future<bool> buyStreakFreeze() async {
    if (state.gold < DashboardNotifier.streakFreezeCost ||
        state.streakFreezes >= state.freezeCapacityOrDefault) {
      return false;
    }
    final previousGold = state.gold;
    final previousFreezes = state.streakFreezes;
    final newGold = previousGold - DashboardNotifier.streakFreezeCost;
    final newFreezes = previousFreezes + 1;
    state = state.copyWith(gold: newGold, streakFreezes: newFreezes);
    if (_uid == null) {
      try {
        await _saveGuestState();
      } catch (_) {
        state = state.copyWith(gold: previousGold, streakFreezes: previousFreezes);
        return false;
      }
      AnalyticsService.instance.track('streak_freeze_bought');
      return true;
    }
    try {
      await _userRef.set({
        'gold': newGold,
        'streakFreezes': newFreezes,
      }, SetOptions(merge: true));
    } catch (_) {
      state = state.copyWith(gold: previousGold, streakFreezes: previousFreezes);
      return false;
    }
    AnalyticsService.instance.track('streak_freeze_bought');
    return true;
  }

  /// Generic gold spend for purchases outside the dashboard's own gold sinks
  /// (currently just the character closet's accessory shop) — same
  /// optimistic-update + rollback-on-failed-write pattern as
  /// [buyStreakFreeze], minus the second field that one also touches.
  /// Returns whether the spend actually persisted; callers should only apply
  /// their own side effect (unlocking the item) once this returns true, so a
  /// failed write can't grant an item the player didn't actually pay for.
  Future<bool> spendGold(int amount) async {
    if (amount <= 0 || state.gold < amount) return false;
    final previousGold = state.gold;
    final newGold = previousGold - amount;
    state = state.copyWith(gold: newGold);
    if (_uid == null) {
      try {
        await _saveGuestState();
      } catch (_) {
        state = state.copyWith(gold: previousGold);
        return false;
      }
      return true;
    }
    try {
      await _userRef.set({'gold': newGold}, SetOptions(merge: true));
    } catch (_) {
      state = state.copyWith(gold: previousGold);
      return false;
    }
    return true;
  }

  /// Puts gold back after a purchase that debited the balance and then
  /// failed to deliver the thing it bought.
  ///
  /// Deliberately NOT a general "grant gold" API — the only caller is the
  /// rollback path in CharacterNotifier.buyAccessory, where [spendGold]
  /// has already succeeded (so the money is really gone from the server)
  /// but the ownership write did not land. Without this, a failed write
  /// costs up to 700 gold and hands over nothing.
  ///
  /// Best effort: if this write also fails the balance stays optimistic
  /// locally and the next load corrects it. That is the right trade — the
  /// alternative is quietly keeping money for an item the user never got.
  Future<void> refundGold(int amount) async {
    if (amount <= 0) return;
    state = state.copyWith(gold: state.gold + amount);
    if (_uid == null) {
      try {
        await _saveGuestState();
      } catch (_) {}
      return;
    }
    try {
      await _userRef.set({'gold': state.gold}, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Sets the stored display name (see [DashboardState.displayName]).
  /// No-ops on an empty/whitespace name — same "don't let an edit blank
  /// this out" guard MatrixNotifier.rename uses for task titles. Same
  /// optimistic-update + rollback-on-failed-write shape as [spendGold].
  Future<bool> setDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    // This name is shown to strangers on every room leaderboard, so it is
    // user-generated content under App Review guideline 1.2 and gets the
    // same filter room names get. Guarded HERE rather than in the edit
    // sheet because this is the one write point every caller goes through
    // — a check in the UI is a check the next new caller can forget.
    if (isObjectionable(trimmed)) return false;
    final clamped = trimmed.length > DashboardNotifier.maxDisplayNameLength
        ? trimmed.substring(0, DashboardNotifier.maxDisplayNameLength)
        : trimmed;

    final previous = state.displayName;
    state = state.copyWith(displayName: clamped);
    if (_uid == null) {
      try {
        await _saveGuestState();
      } catch (_) {
        state = state.copyWith(displayName: previous);
        return false;
      }
      return true;
    }
    try {
      await _userRef.set({'displayName': clamped}, SetOptions(merge: true));
    } catch (_) {
      state = state.copyWith(displayName: previous);
      return false;
    }
    return true;
  }

  /// Spend a streak freeze to restore the streak that was lost on a missed day.
  /// Judges a streak gap the loader recorded but could not decide, now
  /// that the habit schedule is available.
  ///
  /// The rule the old inline check got wrong: a day that asked for NOTHING
  /// cannot break a streak. willCompleteAllHabitsToday refuses to earn a
  /// point on a day with no scheduled habits, deliberately - "a day with
  /// nothing scheduled isn't a completed day, it's a day off" - so
  /// lastActiveDate never advances across rest days, and counting raw
  /// calendar days read every one of them as a miss. Someone training
  /// Sat/Mon/Wed burned a streak freeze on their first Sunday and lost the
  /// streak on the next one; a 3x-a-week habit could not hold a streak at
  /// all.
  ///
  /// So this counts only the days that actually OWED something. Zero owed
  /// days means there was never a gap: the streak stands and
  /// lastActiveDate moves up so the same question is not re-asked every
  /// launch. One owed day spends a freeze if there is one, exactly as
  /// before. More than one ends the streak, keeping it in previousStreak
  /// where the manual restore can still reach it.
  ///
  /// [habits] should be everything that has EVER been scheduled, not just
  /// what is active now (allHabitsEverProvider) - a habit paused since the
  /// gap still demanded those days at the time.
  Future<void> resolveStreakGap(
    Iterable<IslamicHabitTemplate> habits,
  ) async {
    final from = state.pendingStreakGapFrom;
    if (from == null) return;
    final today = DateTime.now().effectiveDay;

    // Strictly between: the last earning day is settled, and today is
    // still in progress and must never be judged as missed.
    var owedDays = 0;
    for (var d = from.add(const Duration(days: 1));
        d.isBefore(today);
        d = d.add(const Duration(days: 1))) {
      if (habits.any((h) => h.isScheduledFor(d))) owedDays++;
    }

    if (owedDays == 0) {
      // Every day in the gap was a rest day. Nothing was missed, so
      // nothing is spent and nothing is lost; close the gap by moving the
      // marker to yesterday, the same way the freeze path always has.
      final yesterday = today.subtract(const Duration(days: 1));
      state = state.copyWith(clearPendingStreakGap: true);
      if (_uid == null) {
        await _saveGuestState(lastActiveDate: yesterday);
      } else {
        // BOTH fields, not just the Timestamp. The loader prefers the
        // 'lastActiveDay' string whenever it exists (see
        // dashboard_notifier_loading.dart), and completeHabit is that
        // string's only other writer — so a gap closed here while the doc
        // still carried an old string was re-detected on the very next
        // refresh, re-spending freezes / re-breaking the streak that this
        // write just settled.
        _userRef.set({
          'lastActiveDate': Timestamp.fromDate(yesterday),
          'lastActiveDay': yesterday.toDateKey(),
        }, SetOptions(merge: true)).ignore();
      }
      return;
    }

    // Spends as many freezes as the gap actually owes, all or nothing.
    //
    // This is what makes capacity above three worth paying for. Before it, a
    // bank of five protected exactly as much as a bank of one: gaps resolve
    // only at app open, and this branch fired only on owedDays == 1 and spent
    // a single freeze, so a two-day gap ended the streak however full the
    // bank was. Selling slots 4 and 5 against that would have been selling
    // nothing.
    //
    // Strictly more protection than before, never less. A bank that cannot
    // cover the whole gap spends NOTHING and falls through to the unchanged
    // streak-loss branch below, so no freeze is ever burned on a gap it
    // cannot actually close.
    if (state.streak > 0 && state.streakFreezes >= owedDays) {
      final yesterday = today.subtract(const Duration(days: 1));
      final newFreezes = state.streakFreezes - owedDays;
      state = state.copyWith(
        streakFreezes: newFreezes,
        didUseStreakFreeze: true,
        clearPendingStreakGap: true,
      );
      if (_uid == null) {
        await _saveGuestState(lastActiveDate: yesterday);
      } else {
        _userRef.set({
          'streakFreezes': newFreezes,
          'lastActiveDate': Timestamp.fromDate(yesterday),
          // Same both-fields rule as the rest-day branch above: leaving the
          // stale 'lastActiveDay' string in place made the loader re-detect
          // this exact gap on the next app resume and drain the remaining
          // freezes (or break the streak) for days already paid for.
          'lastActiveDay': yesterday.toDateKey(),
        }, SetOptions(merge: true)).ignore();
      }
      return;
    }

    final lost = state.streak;
    state = state.copyWith(
      streak: 0,
      previousStreak: lost > 0 ? lost : state.previousStreak,
      clearPendingStreakGap: true,
    );
    if (_uid == null) {
      await _saveGuestState();
    } else {
      _userRef.set({
        'currentStreak': 0,
        if (lost > 0) 'previousStreak': lost,
      }, SetOptions(merge: true)).ignore();
    }
  }

  Future<void> useStreakFreeze() async {
    if (state.streakFreezes <= 0 || state.previousStreak <= 0) return;
    final newFreezes = state.streakFreezes - 1;
    // Never restore DOWN. Since completeHabit stopped clearing a pending
    // comeback while a freeze is banked, the offer can stay armed while the
    // user rebuilds a fresh streak past the lost one — and taking the offer
    // then would have paid a freeze to replace the larger live streak with
    // the smaller stored one. The restore is a floor, not an assignment.
    final restoredStreak = state.previousStreak > state.streak
        ? state.previousStreak
        : state.streak;
    final newLongest = restoredStreak > state.longestStreak
        ? restoredStreak
        : state.longestStreak;

    // The comeback bonus the card advertises above BOTH layouts. Restoring the
    // streak is one of the three routes the card promises pays "either way"
    // (see ComebackCard), but this path used to grant no XP at all — so the one
    // action the restore layout LEADS with silently forfeited the +50 it was
    // showing, while the fresh-start button (acknowledgeComeback) and finishing
    // today's habits (completeHabit's clearsPendingComeback) both paid it, and
    // spending the freeze also closed off those routes by zeroing
    // previousStreak. Granting it here makes the payout match the promise.
    final result = XpCalculator.applyXpGain(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpGained: DashboardNotifier.comebackBonusXp,
    );
    AnalyticsService.instance
        .track('comeback_bonus_claimed', props: {'route': 'restore'});

    state = state.copyWith(
      streak: restoredStreak,
      longestStreak: newLongest,
      streakFreezes: newFreezes,
      previousStreak: 0,
      level: result.newLevel,
      currentLevelXp: result.newCurrentLevelXp,
      cumulativeXp: result.newCumulativeXp,
      didJustLevelUp: result.newLevel > state.level,
    );

    // YESTERDAY, not today. lastActiveDate means "the last day that itself
    // earned the streak point" (see the loader's gap check), and spending a
    // freeze restores the streak as it stood - it does not retroactively
    // declare that today's habits were done. Stamping today handed out a
    // day nobody earned: tomorrow's gap check would see a one-day gap and
    // wave it through even if today went completely untouched. The
    // automatic freeze in the loader has always written yesterday for
    // exactly this reason; this is the manual path catching up.
    //
    // …unless today's streak point WAS already earned: completeHabit then
    // stamped the marker to today, and writing yesterday over it would
    // rewind the record and make tomorrow's gap check bill a freeze for a
    // fully-finished today. The marker only ever moves forward.
    final today = DateTime.now().effectiveDay;
    final marker = state.streakEarnedToday
        ? today
        : today.subtract(const Duration(days: 1));

    if (_uid == null) {
      // This was previously missing entirely — the restore only ever
      // updated in-memory state and guests would see their streak silently
      // revert to lost on next launch. Same guest-save-on-mutation pattern
      // every other method in this class already follows.
      //
      // lastActiveDate passed explicitly here too: without it the guest
      // branch wrote no date at all, so a restored guest streak kept
      // whatever stale date it had and could break again on next launch.
      await _saveGuestState(lastActiveDate: marker);
      return;
    }
    _userRef.set({
      'currentStreak': restoredStreak,
      'longestStreak': newLongest,
      'streakFreezes': newFreezes,
      'previousStreak': 0,
      'level': result.newLevel,
      'currentLevelXp': result.newCurrentLevelXp,
      'cumulativeXp': result.newCumulativeXp,
      'lastActiveDate': Timestamp.fromDate(marker),
      // The string twin the loader actually prefers — see the gap-closer
      // branches in resolveStreakGap for why omitting it re-broke the
      // streak this restore just paid for.
      'lastActiveDay': marker.toDateKey(),
    }, SetOptions(merge: true)).ignore();
  }

  /// Dismiss the "you're back" card and grant the comeback XP bonus.
  Future<void> acknowledgeComeback() async {
    if (!state.showComebackBonus) return;
    final result = XpCalculator.applyXpGain(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpGained: DashboardNotifier.comebackBonusXp,
    );
    AnalyticsService.instance
        .track('comeback_bonus_claimed', props: {'route': 'card'});
    state = state.copyWith(
      previousStreak: 0,
      level: result.newLevel,
      currentLevelXp: result.newCurrentLevelXp,
      cumulativeXp: result.newCumulativeXp,
      didJustLevelUp: result.newLevel > state.level,
    );
    if (_uid == null) {
      await _saveGuestState();
      return;
    }
    try {
      await _userRef.set({
        'level': result.newLevel,
        'currentLevelXp': result.newCurrentLevelXp,
        'cumulativeXp': result.newCumulativeXp,
        'previousStreak': 0,
      }, SetOptions(merge: true));
    } catch (e, st) {
      await _recordWriteFailure('acknowledgeComeback', e, st);
    }
  }

  void acknowledgeMilestone() {
    state = state.copyWith(clearMilestone: true);
  }

  void acknowledgeHabitMilestone() {
    state = state.copyWith(clearHabitMilestone: true);
  }

  Future<void> setIntentionsDone({
    required List<String> priorities,
    required String anchor,
    required String intention,
  }) async {
    state = state.copyWith(intentionsSetToday: true);
    if (_uid == null) {
      // Persist for guests too, so the prompt shows once per day — not on
      // every cold start.
      await LocalStoreService.updateDailyMap(DashboardNotifier._todayKey, (day) {
        day['intentionsSet'] = true;
        day['priorities'] = priorities;
        day['intentionAnchor'] = anchor;
        day['intentionAction'] = intention;
        day['date'] = DateTime.now().effectiveDay.toIso8601String();
      });
      return;
    }
    _dailyRef.set({
      'intentionsSet': true,
      'priorities': priorities,
      'intentionAnchor': anchor,
      'intentionAction': intention,
    }, SetOptions(merge: true)).ignore();
  }

  /// Generic XP/Gold award — every lump-sum reward in the app comes through
  /// here: Focus Timer sessions, Weekly Challenges, Matrix task completion,
  /// Quick Wins, and Rooms' team/podium bonuses.
  ///
  /// Callers are responsible for paying only once. They all do, and all
  /// differently, matched to what they can rely on: MatrixNotifier.toggle
  /// gates on the task's persisted `rewarded` flag, QuickWinsNotifier on its
  /// `dailyDone`/`weeklyDone` flags (local-only — see the TODO there), and
  /// RoomsController's two bonuses on a Firestore transaction that flips the
  /// claim flag before paying. This method itself is deliberately dumb about
  /// that; it cannot tell a legitimate second award from a duplicate.
  /// Reserves one of today's Matrix task payouts, see
  /// [kDailyRewardedTaskCap]. Returns false once the day's allowance is gone.
  ///
  /// Synchronous on purpose. The caller decides in the same event-loop turn
  /// whether to set the task's one-way `rewarded` flag, and an await between
  /// the check and the increment would let two quick taps both pass.
  ///
  /// A false answer means the caller must NOT mark the task rewarded. That
  /// flag is one-way and lives on the task, so burning it on a payout that
  /// never happened loses the reward for good; declining instead leaves the
  /// task free to pay on a later day.
  bool claimTaskReward() {
    if (_uid != null && (state.loadFailed || state.isLoading)) return false;
    final dayKey = DashboardNotifier._todayKey;
    final used = state.rewardedTasksOn(dayKey);
    if (used >= kDailyRewardedTaskCap) return false;
    state = state.copyWith(
      rewardedTasksDayKey: dayKey,
      rewardedTasksToday: used + 1,
    );
    if (_uid == null) {
      _saveGuestState().ignore();
    } else {
      _userRef.set({
        'rewardedTasksDayKey': dayKey,
        'rewardedTasksToday': used + 1,
      }, SetOptions(merge: true)).ignore();
    }
    return true;
  }

  /// [countsTowardDailyCap] is true for anything a user can repeat at will,
  /// which is the default because a new caller is far more likely to be
  /// farmable than not, and the safe failure is to cap something that did not
  /// need it. Pass false only for a genuinely once-per-episode claim whose
  /// caller flips a one-way claim flag before paying: a room podium prize or
  /// a weekly challenge cannot be ground out, and silently withholding one
  /// would strand a reward that no later sweep can re-offer.
  Future<void> awardBonus({
    required int xp,
    required int gold,
    bool countsTowardDailyCap = true,
  }) async {
    // Same refusal as completeHabit's and applyGridSquareChange's, and it
    // was missing here. This method writes level, currentLevelXp,
    // cumulativeXp and gold as ABSOLUTE values computed from `state`, and
    // after a failed load `state` is DashboardState.initial() — level 1, 0
    // XP, 0 gold — none of which came from the server. Unlike the writers
    // _loadToday's catch comment lists as "turned away by their own
    // preconditions" (spendGold can't pass an affordability check against 0
    // gold, useStreakFreeze needs a freeze it no longer appears to have),
    // this one has no precondition at all: finishing a Focus session or
    // tapping a Quick Win after a failed load was enough to write `gold: 0 +
    // reward` straight over the real balance.
    if (_uid != null && state.loadFailed) return;

    final capped = countsTowardDailyCap
        ? _allowedToday(xp: xp, gold: gold, habitCount: 0)
        : (xp: xp, gold: gold, newXpToday: -1, newGoldToday: -1);

    final result = XpCalculator.applyXpGain(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpGained: capped.xp,
    );

    // Lump-sum XP raises the level like any other XP, so it can cross a
    // level-achievement threshold — and this path used to be the one XP
    // source that never checked. A Focus session or a room prize that took
    // someone to level 25 left "نص السلّم" locked, with nothing to notice it
    // until an unrelated habit completion happened to re-run the check.
    // (The post-load sweep now also catches it, but a medal earned at 8pm
    // should not first appear at next launch.)
    final unlocks = _resolveUnlocks(
      unlockedIds: state.unlockedAchievements,
      level: result.newLevel,
      currentLevelXp: result.newCurrentLevelXp,
      cumulativeXp: result.newCumulativeXp,
      streak: state.streak,
      totalCompletions: state.totalCompletions,
      greenSquares: state.totalGreenSquares,
      categoryCompletions: state.categoryCompletions,
      levelGrantPaidThrough: state.levelGrantPaidThrough,
    );
    final newGold = state.gold + capped.gold + unlocks.bonusGold;

    state = state.copyWith(
      level: unlocks.level,
      levelGrantPaidThrough: unlocks.levelGrantPaidThrough,
      currentLevelXp: unlocks.currentLevelXp,
      cumulativeXp: unlocks.cumulativeXp,
      gold: newGold,
      unlockedAchievements: unlocks.unlockedIds,
      newlyUnlocked: unlocks.newly,
      didJustLevelUp: unlocks.level > state.level,
      earnedDayKey: countsTowardDailyCap ? DashboardNotifier._todayKey : null,
      earnedXpToday: countsTowardDailyCap ? capped.newXpToday : null,
      earnedGoldToday: countsTowardDailyCap ? capped.newGoldToday : null,
    );

    NotificationService.instance.showAchievementsUnlocked([
      for (final a in unlocks.newly)
        a.localName(NotificationService.instance.isArabic),
    ]);

    if (_uid == null) {
      // Guests reach this from the Focus timer and Weekly Challenges — it
      // was returning here without persisting, so the XP/gold shown on
      // screen silently vanished on next launch. Save it like every other
      // guest-facing mutation does.
      await _saveGuestState();
      return;
    }
    try {
      await _userRef.set({
        'level': unlocks.level,
        'levelGrantPaidThrough': unlocks.levelGrantPaidThrough,
        'currentLevelXp': unlocks.currentLevelXp,
        'cumulativeXp': unlocks.cumulativeXp,
        'gold': newGold,
        if (countsTowardDailyCap) ...{
          'earnedDayKey': DashboardNotifier._todayKey,
          'earnedXpToday': capped.newXpToday,
          'earnedGoldToday': capped.newGoldToday,
        },
        // arrayUnion, not the whole computed list — see the same call in
        // completeHabit for why a set that only ever grows must never be
        // written wholesale.
        if (unlocks.newly.isNotEmpty)
          'unlockedAchievements':
              FieldValue.arrayUnion(unlocks.newly.map((a) => a.id).toList()),
      }, SetOptions(merge: true));
    } catch (e, st) {
      await _recordWriteFailure('awardBonus', e, st);
    }
  }

  void acknowledgeAchievements() {
    if (state.newlyUnlocked.isEmpty) return;
    state = state.copyWith(newlyUnlocked: []);
  }

  /// Re-reads gold/XP/level/streak/achievements/dailyGreenCounts from
  /// Firestore/local storage. [_loadToday]/[_loadGuestToday] only ever run
  /// once, at construction — every other change flows through this app's
  /// own optimistic-update methods, so nothing normally calls this again.
  /// It's what picks up a change made *outside* that path, e.g. a field
  /// like `gold` edited by hand in the Firebase console while testing —
  /// without it, the app just keeps showing whatever it last loaded until
  /// a full restart. Called on app resume — see main.dart.
  ///
  /// This also matters for the day-cutoff feature (see
  /// DateTimeGameExt.effectiveDay): if the app is simply left open and
  /// backgrounded across the cutoff hour, `state` would otherwise keep
  /// showing yesterday's `_todayKey` document — streakEarnedToday,
  /// intentionsSetToday, completions — until a full restart. Routing
  /// guests through [_loadGuestToday] here too (previously this only ever
  /// called the signed-in path, silently no-op-ing for guests) means an
  /// app-resume after the cutoff correctly picks up the new day for both.
  Future<void> refresh() => _uid != null ? _loadToday() : _loadGuestToday();
}
