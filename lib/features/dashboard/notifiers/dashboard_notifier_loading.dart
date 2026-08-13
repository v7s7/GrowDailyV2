part of 'dashboard_notifier.dart';

extension DashboardNotifierLoading on DashboardNotifier {

  // ── Load ─────────────────────────────────────────────────────


  Future<void> _loadGuestToday() async {
    try {
      final saved = await LocalStoreService.getSettingsMap(
        LocalStoreService.guestDashboardKey,
      );
      final daily = await LocalStoreService.getDailyMap(DashboardNotifier._todayKey);
      final rawCompletions =
          (daily['habitCompletions'] as Map?)?.cast<String, dynamic>() ?? {};
      final completions = rawCompletions.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );
      final streakEarnedToday = (daily['streakEarnedToday'] as bool?) ?? false;
      final intentionsSetToday = (daily['intentionsSet'] as bool?) ?? false;
      final rawGreenCounts =
          (saved['dailyGreenCounts'] as Map?)?.cast<String, dynamic>() ?? {};
      final dailyGreenCounts = rawGreenCounts.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );
      final rawCategoryCompletions =
          (saved['categoryCompletions'] as Map?)?.cast<String, dynamic>() ??
              {};
      final categoryCompletions = rawCategoryCompletions.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );
      final rawHabitStreakCounts =
          (saved['habitStreakCounts'] as Map?)?.cast<String, dynamic>() ??
              {};
      final habitStreakCounts = rawHabitStreakCounts.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );
      final rawHabitLongestStreaks =
          (saved['habitLongestStreaks'] as Map?)?.cast<String, dynamic>() ??
              {};
      final habitLongestStreaks = rawHabitLongestStreaks.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );
      final rawHabitTotalCompletions =
          (saved['habitTotalCompletions'] as Map?)?.cast<String, dynamic>() ??
              {};
      final habitTotalCompletions = rawHabitTotalCompletions.map(
        (key, value) => MapEntry(key, (value as num).toInt()),
      );
      final habitLastCompletedDate = (saved['habitLastCompletedDate'] as Map?)
              ?.cast<String, dynamic>()
              .map((key, value) => MapEntry(key, value as String)) ??
          {};

      int streak = (saved['currentStreak'] as int?) ?? 0;
      int streakFreezes = (saved['streakFreezes'] as int?) ?? 1;
      // Persisted, not re-derived — see DashboardState.previousStreak's doc
      // comment for why this can no longer be a fresh-every-load local.
      int previousStreak = (saved['previousStreak'] as int?) ?? 0;
      bool didUseStreakFreeze = false;
      // The last calendar day that itself earned the streak point (see
      // completeHabit's lastActiveDate write) — not the last day *any*
      // activity happened. That distinction matters here: gapDays below
      // is what decides whether a day genuinely fell short of
      // kStreakDayCompletionThreshold, which only holds if this field
      // never advances on a partial (non-qualifying) day. It used to
      // advance on any single habit completion, which meant this whole
      // gap-check almost never actually fired — a streak could coast
      // indefinitely as long as *something* got tapped occasionally,
      // regardless of whether any day since actually qualified.
      final lastActive = DateTime.tryParse(saved['lastActiveDate'] as String? ?? '');

      if (lastActive != null) {
        final today = DateTime.now().effectiveDay;
        final lastDay = DashboardNotifier._dateOnly(lastActive);
        final yesterday = today.subtract(const Duration(days: 1));
        final gapDays = today.difference(lastDay).inDays;
        if (gapDays > 1) {
          if (gapDays == 2 && streak > 0 && streakFreezes > 0) {
            streakFreezes -= 1;
            didUseStreakFreeze = true;
            saved['streakFreezes'] = streakFreezes;
            saved['lastActiveDate'] = yesterday.toIso8601String();
            await LocalStoreService.putSettingsMap(
              LocalStoreService.guestDashboardKey,
              saved,
            );
          } else {
            if (streak > 0) {
              previousStreak = streak;
              saved['previousStreak'] = previousStreak;
            }
            streak = 0;
            saved['currentStreak'] = 0;
            await LocalStoreService.putSettingsMap(
              LocalStoreService.guestDashboardKey,
              saved,
            );
          }
        }
      }

      if (!mounted) return;
      state = DashboardState(
        displayName: (saved['displayName'] as String?) ?? '',
        level: (saved['level'] as int?) ?? 1,
        currentLevelXp: (saved['currentLevelXp'] as int?) ?? 0,
        cumulativeXp: (saved['cumulativeXp'] as int?) ?? 0,
        gold: (saved['gold'] as int?) ?? 0,
        streak: streak,
        longestStreak: (saved['longestStreak'] as int?) ?? 0,
        totalCompletions: (saved['totalHabitCompletions'] as int?) ?? 0,
        streakFreezes: streakFreezes,
        completions: completions,
        unlockedAchievements:
            List<String>.from(saved['unlockedAchievements'] as List? ?? []),
        didUseStreakFreeze: didUseStreakFreeze,
        previousStreak: previousStreak,
        isLoading: false,
        intentionsSetToday: intentionsSetToday,
        totalGreenSquares: (saved['totalGreenSquares'] as int?) ?? 0,
        streakEarnedToday: streakEarnedToday,
        dailyGreenCounts: dailyGreenCounts,
        categoryCompletions: categoryCompletions,
        habitStreakCounts: habitStreakCounts,
        habitLongestStreaks: habitLongestStreaks,
        habitTotalCompletions: habitTotalCompletions,
        habitLastCompletedDate: habitLastCompletedDate,
      );
    } catch (_) {
      if (mounted) state = DashboardState.initial().copyWith(isLoading: false);
    }
  }

  Future<void> _saveGuestState({DateTime? lastActiveDate}) async {
    final saved = await LocalStoreService.getSettingsMap(
      LocalStoreService.guestDashboardKey,
    );
    await LocalStoreService.putSettingsMap(
      LocalStoreService.guestDashboardKey,
      {
        ...saved,
        'displayName': state.displayName,
        'level': state.level,
        'currentLevelXp': state.currentLevelXp,
        'cumulativeXp': state.cumulativeXp,
        'gold': state.gold,
        'currentStreak': state.streak,
        'longestStreak': state.longestStreak,
        'totalHabitCompletions': state.totalCompletions,
        'streakFreezes': state.streakFreezes,
        'previousStreak': state.previousStreak,
        'unlockedAchievements': state.unlockedAchievements,
        'totalGreenSquares': state.totalGreenSquares,
        'dailyGreenCounts': state.dailyGreenCounts,
        'categoryCompletions': state.categoryCompletions,
        'habitStreakCounts': state.habitStreakCounts,
        'habitLongestStreaks': state.habitLongestStreaks,
        'habitTotalCompletions': state.habitTotalCompletions,
        'habitLastCompletedDate': state.habitLastCompletedDate,
        if (lastActiveDate != null)
          'lastActiveDate': lastActiveDate.toIso8601String(),
      },
    );
  }

  Future<void> _saveGuestDaily(
    Map<String, int> completions, {
    bool? streakEarnedToday,
  }) async {
    final existing = await LocalStoreService.getDailyMap(DashboardNotifier._todayKey);
    await LocalStoreService.putDailyMap(
      DashboardNotifier._todayKey,
      {
        ...existing,
        'habitCompletions': completions,
        'date': DateTime.now().effectiveDay.toIso8601String(),
        if (streakEarnedToday != null) 'streakEarnedToday': streakEarnedToday,
      },
    );
  }

  // Fields left over from the old GrowDaily v1 schema (this project reused
  // an existing Firebase database) — confirmed by a full search of this
  // codebase that nothing anywhere reads any of these anymore. Kept as an
  // explicit, named list rather than just deleting-and-forgetting so it's
  // obvious later *why* a user doc briefly gets an extra merge-write on
  // load: 'streak'/'name' in particular used to sit right next to the
  // still-live 'currentStreak'/'displayName' and are exactly the kind of
  // near-duplicate that misleads whoever reads this data next. See
  // _scrubLegacyV1Fields below for how this list gets used.
  static const _legacyV1Keys = [
    'name', 'streak', 'totalPoints', 'availablePoints', 'lastStreakDate',
    'plan', 'todoTasks', 'taskRepeats', 'completedTasks',
    'dailyPointsEarned', 'dailySubmissions', 'eisenhowerColors',
    'eisenhowerTasks', 'gym', 'gymPoints', 'quran', 'quranPoints', 'study',
    'hydration', 'waterPoints', 'waterSubmissions', 'showerPoints',
    'phonePoints', 'masaa_athkar', 'masaa_athkarPoints', 'sabah_athkar',
    'sabah_athkarPoints',
  ];

  /// One-time cleanup, called from [_loadToday] right after reading the
  /// user doc. Self-healing rather than a bulk migration script: every
  /// signed-in user's next normal app open checks their own doc for any
  /// of [_legacyV1Keys] and — only if at least one is actually still
  /// present — fires a single merge-write deleting just those keys.
  /// Nothing to do (and nothing written) once a doc's already been
  /// cleaned, so this naturally stops costing anything after the first
  /// successful run per user. Fire-and-forget like every other background
  /// write in this method (streak-freeze grants, streak reset) — a v1
  /// field lingering one extra app open because this particular write
  /// failed isn't worth blocking the load over.
  void _scrubLegacyV1Fields(Map<String, dynamic> d) {
    final present = _legacyV1Keys.where(d.containsKey);
    if (present.isEmpty) return;
    _userRef.set({
      for (final key in present) key: FieldValue.delete(),
    }, SetOptions(merge: true)).ignore();
  }

  Future<void> _loadToday() async {
    if (_uid == null) return;
    try {
      final results = await Future.wait([_userRef.get(), _dailyRef.get()]);
      final userSnap = results[0];
      final dailySnap = results[1];

      String displayName = '';
      int level = 1,
          currentLevelXp = 0,
          cumulativeXp = 0,
          gold = 0,
          streak = 0,
          longestStreak = 0,
          totalCompletions = 0,
          streakFreezes = 1,
          previousStreak = 0;
      bool didUseStreakFreeze = false;
      List<String> unlockedAchievements = [];
      Map<String, int> completions = {};
      bool intentionsSetToday = false;
      bool streakEarnedToday = false;
      int totalGreenSquares = 0;
      Map<String, int> dailyGreenCounts = {};
      Map<String, int> categoryCompletions = {};
      Map<String, int> habitStreakCounts = {};
      Map<String, int> habitLongestStreaks = {};
      Map<String, int> habitTotalCompletions = {};
      Map<String, String> habitLastCompletedDate = {};
      DateTime? accountCreatedAt;

      if (userSnap.exists) {
        final d = userSnap.data()!;
        _scrubLegacyV1Fields(d);
        displayName = (d['displayName'] as String?) ?? '';
        level = (d['level'] as int?) ?? 1;
        currentLevelXp = (d['currentLevelXp'] as int?) ?? 0;
        cumulativeXp = (d['cumulativeXp'] as int?) ?? 0;
        gold = (d['gold'] as int?) ?? 0;
        streak = (d['currentStreak'] as int?) ?? 0;
        longestStreak = (d['longestStreak'] as int?) ?? 0;
        totalCompletions = (d['totalHabitCompletions'] as int?) ?? 0;
        streakFreezes = (d['streakFreezes'] as int?) ?? 1;
        accountCreatedAt = (d['createdAt'] as Timestamp?)?.toDate();
        // Persisted, not re-derived — see DashboardState.previousStreak's
        // doc comment for why this can no longer be a fresh-every-load
        // local.
        previousStreak = (d['previousStreak'] as int?) ?? 0;
        final lastFreezeGrantWeek = d['lastFreezeGrantWeek'] as String?;
        unlockedAchievements =
            List<String>.from(d['unlockedAchievements'] as List? ?? []);
        totalGreenSquares = (d['totalGreenSquares'] as int?) ?? 0;
        final rawGreenCounts =
            (d['dailyGreenCounts'] as Map?)?.cast<String, dynamic>() ?? {};
        dailyGreenCounts = rawGreenCounts.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
        // ── One-time repair of the dotted-key heatmap bug ─────────
        // dailyGreenCounts increments used to be written as
        // 'dailyGreenCounts.<dateKey>' string keys inside set(merge:
        // true) — but dot notation is only a field *path* in update();
        // in set() it's a literal field name. So every completion landed
        // on a junk top-level field literally named
        // "dailyGreenCounts.2026-07-17" while the real map stayed empty,
        // which is why the Monthly Heatmap blanked on every restart. The
        // counts themselves are intact in those junk fields (the atomic
        // increments worked fine, just against the wrong field name) —
        // fold them back into the real map and delete the junk, healing
        // the doc in place. After one pass this finds nothing and costs
        // a single keys scan. FieldValue.delete() is valid inside
        // set(merge: true), and set()'s literal-key handling is exactly
        // what lets each delete target its dotted-name junk field.
        final junkGreenKeys =
            d.keys.where((k) => k.startsWith('dailyGreenCounts.')).toList();
        if (junkGreenKeys.isNotEmpty) {
          for (final junkKey in junkGreenKeys) {
            final dateKey = junkKey.substring('dailyGreenCounts.'.length);
            final junkCount = (d[junkKey] as num?)?.toInt() ?? 0;
            final merged = (dailyGreenCounts[dateKey] ?? 0) + junkCount;
            dailyGreenCounts[dateKey] = merged < 0 ? 0 : merged;
          }
          _userRef.set({
            'dailyGreenCounts': dailyGreenCounts,
            for (final junkKey in junkGreenKeys)
              junkKey: FieldValue.delete(),
          }, SetOptions(merge: true)).ignore();
        }
        final rawCategoryCompletions =
            (d['categoryCompletions'] as Map?)?.cast<String, dynamic>() ?? {};
        categoryCompletions = rawCategoryCompletions.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
        final rawHabitStreakCounts =
            (d['habitStreakCounts'] as Map?)?.cast<String, dynamic>() ?? {};
        habitStreakCounts = rawHabitStreakCounts.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
        final rawHabitLongestStreaks =
            (d['habitLongestStreaks'] as Map?)?.cast<String, dynamic>() ?? {};
        habitLongestStreaks = rawHabitLongestStreaks.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
        final rawHabitTotalCompletions =
            (d['habitTotalCompletions'] as Map?)?.cast<String, dynamic>() ??
                {};
        habitTotalCompletions = rawHabitTotalCompletions.map(
          (key, value) => MapEntry(key, (value as num).toInt()),
        );
        habitLastCompletedDate = (d['habitLastCompletedDate'] as Map?)
                ?.cast<String, dynamic>()
                .map((key, value) => MapEntry(key, value as String)) ??
            {};

        // See _loadGuestToday's identical comment: this is the last day
        // that itself earned the streak point, not the last day any
        // activity happened — completeHabit only advances it on a
        // genuinely qualifying (>=kStreakDayCompletionThreshold) day, and
        // applyGridSquareChange no longer touches it at all (see that
        // method's doc comment).
        final lastActiveTs = d['lastActiveDate'] as Timestamp?;
        if (lastActiveTs != null) {
          final today = DateTime.now().effectiveDay;
          final lastDay = DashboardNotifier._dateOnly(lastActiveTs.toDate());
          final yesterday = today.subtract(const Duration(days: 1));
          final gapDays = today.difference(lastDay).inDays;
          if (gapDays > 1) {
            if (gapDays == 2 && streak > 0 && streakFreezes > 0) {
              streakFreezes -= 1;
              didUseStreakFreeze = true;
              _userRef.set({
                'streakFreezes': streakFreezes,
                'lastActiveDate': Timestamp.fromDate(yesterday),
              }, SetOptions(merge: true)).ignore();
            } else {
              if (streak > 0) {
                previousStreak = streak;
              }
              streak = 0;
              _userRef.set({
                'currentStreak': 0,
                if (previousStreak > 0) 'previousStreak': previousStreak,
              }, SetOptions(merge: true)).ignore();
            }
          }
        }

        if (level >= 5 &&
            streakFreezes < DashboardNotifier.maxStreakFreezes &&
            lastFreezeGrantWeek != DashboardNotifier._weekKey) {
          streakFreezes += 1;
          _userRef.set({
            'streakFreezes': streakFreezes,
            'lastFreezeGrantWeek': DashboardNotifier._weekKey,
          }, SetOptions(merge: true)).ignore();
        }
      }

      if (dailySnap.exists) {
        final d = dailySnap.data()!;
        final raw =
            (d['habitCompletions'] as Map<String, dynamic>?) ?? {};
        completions =
            raw.map((k, v) => MapEntry(k, (v as num).toInt()));
        intentionsSetToday = (d['intentionsSet'] as bool?) ?? false;
        streakEarnedToday = (d['streakEarnedToday'] as bool?) ?? false;
      }

      if (mounted) {
        state = DashboardState(
          displayName: displayName,
          level: level,
          currentLevelXp: currentLevelXp,
          cumulativeXp: cumulativeXp,
          gold: gold,
          streak: streak,
          longestStreak: longestStreak,
          totalCompletions: totalCompletions,
          streakFreezes: streakFreezes,
          completions: completions,
          unlockedAchievements: unlockedAchievements,
          newlyUnlocked: const [],
          didUseStreakFreeze: didUseStreakFreeze,
          isLoading: false,
          previousStreak: previousStreak,
          intentionsSetToday: intentionsSetToday,
          totalGreenSquares: totalGreenSquares,
          streakEarnedToday: streakEarnedToday,
          dailyGreenCounts: dailyGreenCounts,
          categoryCompletions: categoryCompletions,
          habitStreakCounts: habitStreakCounts,
          habitLongestStreaks: habitLongestStreaks,
          habitTotalCompletions: habitTotalCompletions,
          habitLastCompletedDate: habitLastCompletedDate,
          accountCreatedAt: accountCreatedAt,
        );
      }
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  // ── Streak helper ────────────────────────────────────────────

  /// Advances the day-streak by one and reports any milestone crossed.
  /// The only caller is [completeHabit], at the exact moment today's
  /// habits first reach 100% — see [DashboardState.streakEarnedToday].
  ({int streak, int longestStreak, int? milestone, int milestoneBonusXp})
      _computeStreakBump() {
    final newStreak = state.streak + 1;
    final newLongest =
        newStreak > state.longestStreak ? newStreak : state.longestStreak;
    int? newMilestone;
    for (final m in kStreakMilestones) {
      if (newStreak == m && state.streak < m) {
        newMilestone = m;
        break;
      }
    }
    final bonus = newMilestone != null ? milestoneXpBonus(newMilestone) : 0;
    return (
      streak: newStreak,
      longestStreak: newLongest,
      milestone: newMilestone,
      milestoneBonusXp: bonus,
    );
  }
}
