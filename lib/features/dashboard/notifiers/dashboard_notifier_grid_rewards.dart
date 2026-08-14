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

    if (xpDelta != 0) {
      final result = XpCalculator.applyXpDelta(
        currentLevel: state.level,
        currentLevelXp: state.currentLevelXp,
        cumulativeXp: state.cumulativeXp,
        xpDelta: xpDelta,
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
    final newly = AchievementCatalog.locked(state.unlockedAchievements)
        .where((a) => switch (a.trigger) {
              AchievementTrigger.level => newLevel >= a.threshold,
              AchievementTrigger.greenSquares =>
                newTotalGreen >= a.threshold,
              _ => false,
            })
        .toList();

    final newUnlockedIds = [
      ...state.unlockedAchievements,
      ...newly.map((a) => a.id),
    ];

    int bonusXp = newly.fold(0, (s, a) => s + a.xpReward);
    int bonusGold = newly.fold(0, (s, a) => s + a.goldReward);
    if (bonusXp > 0) {
      final bonusResult = XpCalculator.applyXpGain(
        currentLevel: newLevel,
        currentLevelXp: newCurrentLevelXp,
        cumulativeXp: newCumulativeXp,
        xpGained: bonusXp,
      );
      newLevel = bonusResult.newLevel;
      newCurrentLevelXp = bonusResult.newCurrentLevelXp;
      newCumulativeXp = bonusResult.newCumulativeXp;
    }
    final newGold = state.gold + bonusGold;
    final didLevelUp = newLevel > state.level;

    state = state.copyWith(
      level: newLevel,
      currentLevelXp: newCurrentLevelXp,
      cumulativeXp: newCumulativeXp,
      gold: newGold,
      totalGreenSquares: newTotalGreen,
      dailyGreenCounts: newDailyGreenCounts,
      unlockedAchievements: newUnlockedIds,
      newlyUnlocked: newly,
      didJustLevelUp: didLevelUp,
    );

    if (didLevelUp) NotificationService.instance.showLevelUp(newLevel);
    for (final a in newly) {
      NotificationService.instance.showAchievementUnlocked(a.name);
    }

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
        'currentLevelXp': newCurrentLevelXp,
        'cumulativeXp': newCumulativeXp,
        'gold': newGold,
        'unlockedAchievements': newUnlockedIds,
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
        state.streakFreezes >= DashboardNotifier.maxStreakFreezes) {
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

  /// Sets the stored display name (see [DashboardState.displayName]).
  /// No-ops on an empty/whitespace name — same "don't let an edit blank
  /// this out" guard MatrixNotifier.rename uses for task titles. Same
  /// optimistic-update + rollback-on-failed-write shape as [spendGold].
  Future<bool> setDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
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
  Future<void> useStreakFreeze() async {
    if (state.streakFreezes <= 0 || state.previousStreak <= 0) return;
    final newFreezes = state.streakFreezes - 1;
    final restoredStreak = state.previousStreak;
    final newLongest = restoredStreak > state.longestStreak
        ? restoredStreak
        : state.longestStreak;

    state = state.copyWith(
      streak: restoredStreak,
      longestStreak: newLongest,
      streakFreezes: newFreezes,
      previousStreak: 0,
    );

    if (_uid == null) {
      // This was previously missing entirely — the restore only ever
      // updated in-memory state and guests would see their streak silently
      // revert to lost on next launch. Same guest-save-on-mutation pattern
      // every other method in this class already follows.
      await _saveGuestState();
      return;
    }
    _userRef.set({
      'currentStreak': restoredStreak,
      'longestStreak': newLongest,
      'streakFreezes': newFreezes,
      'previousStreak': 0,
      'lastActiveDate': Timestamp.fromDate(DateTime.now().effectiveDay),
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
    AnalyticsService.instance.track('comeback_bonus_claimed');
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
      final existing = await LocalStoreService.getDailyMap(DashboardNotifier._todayKey);
      await LocalStoreService.putDailyMap(DashboardNotifier._todayKey, {
        ...existing,
        'intentionsSet': true,
        'priorities': priorities,
        'intentionAnchor': anchor,
        'intentionAction': intention,
        'date': DateTime.now().effectiveDay.toIso8601String(),
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

  /// Generic XP/Gold award used by Focus Timer sessions and Weekly Challenges.
  Future<void> awardBonus({required int xp, required int gold}) async {
    final result = XpCalculator.applyXpGain(
      currentLevel: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      xpGained: xp,
    );
    final newGold = state.gold + gold;
    state = state.copyWith(
      level: result.newLevel,
      currentLevelXp: result.newCurrentLevelXp,
      cumulativeXp: result.newCumulativeXp,
      gold: newGold,
      didJustLevelUp: result.newLevel > state.level,
    );
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
        'level': result.newLevel,
        'currentLevelXp': result.newCurrentLevelXp,
        'cumulativeXp': result.newCumulativeXp,
        'gold': newGold,
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
