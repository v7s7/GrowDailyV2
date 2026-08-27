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
      // `.stale` is deliberately dropped rather than written back here, and
      // only here: _saveGuestState puts this map back WHOLE from state on the
      // next save, so the swept keys leave the store on their own. The
      // signed-in path has to delete them by hand because its writes are
      // per-key merges that never rewrite the map entire.
      final undone = _readUndoneCompletions(
        saved['undoneCompletions'],
        DateTime.now().effectiveDay,
      );

      int streak = (saved['currentStreak'] as int?) ?? 0;
      int streakFreezes = (saved['streakFreezes'] as int?) ?? 1;
      // Persisted, not re-derived — see DashboardState.previousStreak's doc
      // comment for why this can no longer be a fresh-every-load local.
      int previousStreak = (saved['previousStreak'] as int?) ?? 0;
      bool didUseStreakFreeze = false;
      DateTime? pendingStreakGapFrom;
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
        final gapDays = today.difference(lastDay).inDays;
        // Recorded, not judged. Whether those days were MISSED or merely
        // days this person had nothing scheduled cannot be answered
        // without the habit list, which this loader does not have - see
        // DashboardState.pendingStreakGapFrom and resolveStreakGap.
        if (gapDays > 1) pendingStreakGapFrom = lastDay;
      }

      if (!mounted) return;
      final earnedDayKey = (saved['earnedDayKey'] as String?) ?? '';
      final earnedXpToday = (saved['earnedXpToday'] as int?) ?? 0;
      final earnedGoldToday = (saved['earnedGoldToday'] as int?) ?? 0;
      final rewardedTasksDayKey = (saved['rewardedTasksDayKey'] as String?) ?? '';
      final rewardedTasksToday = (saved['rewardedTasksToday'] as int?) ?? 0;
      final freezeCapacity = (saved['freezeCapacity'] as int?) ?? 0;
      // Seeded to the account's CURRENT level when absent, never to 1: a
      // level-60 account would otherwise collect all twelve grants
      // retroactively on the first launch after this shipped.
      final storedGrantMark = (saved['levelGrantPaidThrough'] as int?) ?? 0;

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
        pendingStreakGapFrom: pendingStreakGapFrom,
        previousStreak: previousStreak,
        isLoading: false,
        intentionsSetToday: intentionsSetToday,
        totalGreenSquares: (saved['totalGreenSquares'] as int?) ?? 0,
        streakEarnedToday: streakEarnedToday,
        dailyGreenCounts: dailyGreenCounts,
        earnedDayKey: earnedDayKey,
        earnedXpToday: earnedXpToday,
        earnedGoldToday: earnedGoldToday,
        rewardedTasksDayKey: rewardedTasksDayKey,
        rewardedTasksToday: rewardedTasksToday,
        freezeCapacity: freezeCapacity,
        levelGrantPaidThrough:
            storedGrantMark < 1 ? (saved['level'] as int?) ?? 1 : storedGrantMark,
        categoryCompletions: categoryCompletions,
        habitStreakCounts: habitStreakCounts,
        habitLongestStreaks: habitLongestStreaks,
        habitTotalCompletions: habitTotalCompletions,
        habitLastCompletedDate: habitLastCompletedDate,
        undoneCompletions: undone.kept,
      );
    } catch (_) {
      if (mounted) state = DashboardState.initial().copyWith(isLoading: false);
      return;
    }
    // Outside the try on purpose — a failure in here must not be caught by
    // the handler above and mistaken for "the load failed", which would
    // wipe the state that just loaded correctly.
    await _reconcileAchievements();
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
        'earnedDayKey': state.earnedDayKey,
        'earnedXpToday': state.earnedXpToday,
        'earnedGoldToday': state.earnedGoldToday,
        'rewardedTasksDayKey': state.rewardedTasksDayKey,
        'rewardedTasksToday': state.rewardedTasksToday,
        'freezeCapacity': state.freezeCapacity,
        'levelGrantPaidThrough': state.levelGrantPaidThrough,
        'categoryCompletions': state.categoryCompletions,
        'habitStreakCounts': state.habitStreakCounts,
        'habitLongestStreaks': state.habitLongestStreaks,
        'habitTotalCompletions': state.habitTotalCompletions,
        'habitLastCompletedDate': state.habitLastCompletedDate,
        // Written whole rather than as a delta, which is safe here and is not
        // in the signed-in path: putSettingsMap is a plain overwrite of the
        // one key, so the map that goes in is exactly the map that comes back.
        'undoneCompletions': {
          for (final entry in state.undoneCompletions.entries)
            entry.key: entry.value.toJson(),
        },
        if (lastActiveDate != null)
          'lastActiveDate': lastActiveDate.toIso8601String(),
      },
    );
  }

  /// A per-habit int map read from a document, degrading to empty on anything
  /// that is not a map of numbers.
  ///
  /// Every one of these fields used to be read with `as Map?`, which throws on
  /// a field that is PRESENT but the wrong shape, and a throw anywhere in the
  /// load fails the whole thing: the account renders at level 1 with zero XP
  /// and gold, and DashboardState.loadFailed then refuses every reward write
  /// until it parses again. One malformed field should cost that field, not
  /// the account.
  ///
  /// Per ENTRY, not just per field: a single junk value inside an otherwise
  /// good map drops that habit rather than the whole map.
  static Map<String, int> _asIntMap(Object? raw) {
    if (raw is! Map) return {};
    final out = <String, int>{};
    raw.forEach((key, value) {
      if (value is num) out[key.toString()] = value.toInt();
    });
    return out;
  }

  /// The stored [UndoneCompletion] receipts, split into the ones still worth
  /// keeping and the keys that should be swept out of storage.
  ///
  /// Two things get swept: anything malformed (same degrade-don't-throw
  /// posture as [_asIntMap] — one bad entry must not cost the whole load), and
  /// anything undone longer ago than [kUndoneCompletionRetentionDays]. Without
  /// the sweep this map would only ever grow on an account that undoes marks
  /// and never corrects them.
  static ({Map<String, UndoneCompletion> kept, List<String> stale})
      _readUndoneCompletions(Object? raw, DateTime today) {
    final kept = <String, UndoneCompletion>{};
    final stale = <String>[];
    if (raw is! Map) return (kept: kept, stale: stale);
    raw.forEach((key, value) {
      final mapKey = key.toString();
      final record = UndoneCompletion.fromJson(value);
      if (record == null) {
        stale.add(mapKey);
        return;
      }
      final undoneOn = DateTime.tryParse(record.undoneOnKey);
      if (undoneOn != null &&
          daysBetweenDates(undoneOn, today) > kUndoneCompletionRetentionDays) {
        stale.add(mapKey);
        return;
      }
      kept[mapKey] = record;
    });
    return (kept: kept, stale: stale);
  }

  /// The string-valued counterpart, for habitLastCompletedDate.
  static Map<String, String> _asStringMap(Object? raw) {
    if (raw is! Map) return {};
    final out = <String, String>{};
    raw.forEach((key, value) {
      if (value is String) out[key.toString()] = value;
    });
    return out;
  }

  Future<void> _saveGuestDaily(
    Map<String, int> completions, {
    bool? streakEarnedToday,
    Map<String, int>? completedAtMinutes,
    Map<String, int>? habitTargets,
  }) async {
    // Inside updateDailyMap, so this read and write cannot interleave with
    // the grid's write to the same day. That interleaving is what let a
    // square corrected to red keep its completion, see that method's comment.
    await LocalStoreService.updateDailyMap(DashboardNotifier._todayKey, (day) {
      // completedAtMinutes is merged by hand, because the local store writes
      // the map whole. Without this the guest path would keep only the newest
      // stamp per day while the signed-in path (which gets Firestore's deep
      // merge for free) kept them all, and the two stores would disagree
      // about the same day.
      final mergedMinutes = <String, int>{
        ...?(day['completedAtMinutes'] as Map?)?.map(
          (key, value) => MapEntry('$key', (value as num).toInt()),
        ),
        ...?completedAtMinutes,
      };
      day['habitCompletions'] = completions;
      // What the day ASKED of each counted habit, recorded on the day itself so
      // history stays self-describing: see dayMark, which reads it back to tell
      // a finished counted day from a part-done one. Merged rather than
      // overwritten, because one call only ever knows about the habit it just
      // completed.
      if (habitTargets != null && habitTargets.isNotEmpty) {
        day['habitTargets'] = <String, int>{
          ...?(day['habitTargets'] as Map?)?.map(
            (key, value) => MapEntry('$key', (value as num).toInt()),
          ),
          ...habitTargets,
        };
      }
      day['date'] = DateTime.now().effectiveDay.toIso8601String();
      if (streakEarnedToday != null) day['streakEarnedToday'] = streakEarnedToday;
      if (mergedMinutes.isNotEmpty) day['completedAtMinutes'] = mergedMinutes;
    });
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
      // The two reads are deliberately NOT combined with Future.wait any
      // more. Today's daily doc legitimately does not exist yet on the first
      // launch of a new calendar day, and the mobile Firestore SDK fails a
      // default-source get() of a document that is neither reachable on the
      // server nor in the local cache ("Failed to get document because the
      // client is offline"). Under Future.wait that one expected, harmless
      // failure rejected the whole call and threw away a perfectly good user
      // document along with it — landing in the catch below, which is the
      // dangerous state (see DashboardState.loadFailed). The user doc is the
      // one that must survive; a missing daily doc just means "nothing done
      // yet today", which is exactly what the null path already handles.
      final userSnap = await _userRef.get();
      final dailySnap = await _dailyRef.get().then<DocumentSnapshot<Map<String, dynamic>>?>(
            (s) => s,
            onError: (_) => null,
          );

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
      DateTime? pendingStreakGapFrom;
      List<String> unlockedAchievements = [];
      Map<String, int> completions = {};
      bool intentionsSetToday = false;
      bool streakEarnedToday = false;
      int totalGreenSquares = 0;
      Map<String, int> dailyGreenCounts = {};
      String earnedDayKey = '';
      int earnedXpToday = 0;
      int earnedGoldToday = 0;
      String rewardedTasksDayKey = '';
      int rewardedTasksToday = 0;
      int freezeCapacity = 0;
      int storedGrantMark = 0;
      Map<String, int> categoryCompletions = {};
      Map<String, int> habitStreakCounts = {};
      Map<String, int> habitLongestStreaks = {};
      Map<String, int> habitTotalCompletions = {};
      Map<String, String> habitLastCompletedDate = {};
      Map<String, UndoneCompletion> undoneCompletions = {};
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
        // The daily earn ceiling's running total. Read plainly, and a
        // missing or malformed field simply reads as a fresh allowance,
        // which is the safe direction to fail in: a load that THREW here
        // would set loadFailed and refuse every reward write for the rest of
        // the session, which is far worse than one uncapped day.
        earnedDayKey = (d['earnedDayKey'] as String?) ?? '';
        earnedXpToday = (d['earnedXpToday'] as num?)?.toInt() ?? 0;
        earnedGoldToday = (d['earnedGoldToday'] as num?)?.toInt() ?? 0;
        rewardedTasksDayKey = (d['rewardedTasksDayKey'] as String?) ?? '';
        rewardedTasksToday = (d['rewardedTasksToday'] as num?)?.toInt() ?? 0;
        // Floored on read by freezeCapacityOrDefault, so a legacy document
        // with no such field simply keeps the original three slots.
        freezeCapacity = (d['freezeCapacity'] as num?)?.toInt() ?? 0;
        // num, not int: a stored double under `as int?` throws, and a throw
        // here lands in the catch that flags loadFailed for the session.
        storedGrantMark =
            (d['levelGrantPaidThrough'] as num?)?.toInt() ?? 0;
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
        final rawCategoryCompletions = _asIntMap(d['categoryCompletions']);
        categoryCompletions = rawCategoryCompletions;
        final rawHabitStreakCounts = _asIntMap(d['habitStreakCounts']);
        habitStreakCounts = rawHabitStreakCounts;
        final rawHabitLongestStreaks = _asIntMap(d['habitLongestStreaks']);
        habitLongestStreaks = rawHabitLongestStreaks;
        // `as Map?` throws on a field that is present but NOT a map, and a
        // throw here fails the whole load: the account renders as level 1
        // with zero XP, zero gold and no streak, and every reward write is
        // refused until it parses again.
        //
        // That is far too much blast radius for one bad field. A wrong shape
        // degrades to empty, exactly as an absent field already does, so a
        // single corrupt entry costs its own map and nothing else. Written
        // after a bad write set this field to a bare int and locked the
        // account out of its own progression.
        final rawHabitTotalCompletions =
            _asIntMap(d['habitTotalCompletions']);
        habitTotalCompletions = rawHabitTotalCompletions;
        habitLastCompletedDate = _asStringMap(d['habitLastCompletedDate']);

        final undone = _readUndoneCompletions(
          d['undoneCompletions'],
          DateTime.now().effectiveDay,
        );
        undoneCompletions = undone.kept;
        if (undone.stale.isNotEmpty) {
          // Same shape as the junk dailyGreenCounts repair above: a nested map
          // with FieldValue.delete() per key, so merge removes exactly those
          // entries and leaves every live one alone. Fire and forget, since a
          // sweep that misses this launch simply runs again on the next one.
          _userRef.set({
            'undoneCompletions': {
              for (final key in undone.stale) key: FieldValue.delete(),
            },
          }, SetOptions(merge: true)).ignore();
        }

        // See _loadGuestToday's identical comment: this is the last day
        // that itself earned the streak point, not the last day any
        // activity happened — completeHabit only advances it on a
        // genuinely qualifying (>=kStreakDayCompletionThreshold) day, and
        // applyGridSquareChange no longer touches it at all (see that
        // method's doc comment).
        // A CALENDAR DAY, not an instant.
        //
        // This used to read only 'lastActiveDate', a Timestamp written from
        // the local midnight of the qualifying day. An instant is a point in
        // time, so reading it back in a different zone hands you a different
        // calendar day: local midnight on 2026-08-23 in Bahrain is 21:00 the
        // previous day in UTC, which reads back as 2026-08-22 anywhere west
        // of it. The fabricated one day gap then reaches the gap check below,
        // which spends a streak freeze or writes currentStreak 0, within about
        // a second of opening the app and before the person can touch
        // anything.
        //
        // Someone who completed everything in Bahrain on Monday and opened the
        // app in London on Tuesday lost the streak. So did anyone in Europe,
        // North America, the Levant or Morocco on the day the clocks went
        // back. Guests were never affected: their path stores an offset free
        // string already.
        //
        // 'lastActiveDay' is that same string, written alongside the
        // Timestamp since this fix. The Timestamp is still read as a fallback
        // for accounts last written by an older build, and it is still wrong
        // in exactly the old way, which is the best that can be done for a
        // value that never recorded which day it meant.
        final lastActiveKey = d['lastActiveDay'] as String?;
        final lastActiveTs = d['lastActiveDate'] as Timestamp?;
        final lastDay = lastActiveKey != null
            ? DateTime.tryParse(lastActiveKey)
            : (lastActiveTs == null
                ? null
                : DashboardNotifier._dateOnly(lastActiveTs.toDate()));
        if (lastDay != null) {
          final today = DateTime.now().effectiveDay;
          final gapDays = today.difference(lastDay).inDays;
          // Recorded, not judged - see the guest branch above and
          // DashboardState.pendingStreakGapFrom.
          if (gapDays > 1) pendingStreakGapFrom = lastDay;
        }

        // Grants back to ONE, not all the way to the bank cap. Topping to
        // three for free made the only repeatable gold sink in the app
        // unreachable: at 100 gold a freeze with a cap of 3, a player who
        // breaks fewer than one streak a week never had a slot to buy, so
        // total lifetime gold spending was the 3,710 accessory catalogue,
        // once, and nothing after it. Refilling to one keeps the safety net
        // exactly as it was (nobody is ever left with zero protection) while
        // putting slots two and three back behind real gold.
        if (level >= 5 &&
            streakFreezes < 1 &&
            lastFreezeGrantWeek != DashboardNotifier._weekKey) {
          streakFreezes += 1;
          _userRef.set({
            'streakFreezes': streakFreezes,
            'lastFreezeGrantWeek': DashboardNotifier._weekKey,
          }, SetOptions(merge: true)).ignore();
        }
      }

      if (dailySnap != null && dailySnap.exists) {
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
          pendingStreakGapFrom: pendingStreakGapFrom,
          isLoading: false,
          previousStreak: previousStreak,
          intentionsSetToday: intentionsSetToday,
          totalGreenSquares: totalGreenSquares,
          streakEarnedToday: streakEarnedToday,
          dailyGreenCounts: dailyGreenCounts,
          earnedDayKey: earnedDayKey,
          earnedXpToday: earnedXpToday,
          earnedGoldToday: earnedGoldToday,
          rewardedTasksDayKey: rewardedTasksDayKey,
          rewardedTasksToday: rewardedTasksToday,
          freezeCapacity: freezeCapacity,
          levelGrantPaidThrough:
              storedGrantMark < 1 ? level : storedGrantMark,
          categoryCompletions: categoryCompletions,
          habitStreakCounts: habitStreakCounts,
          habitLongestStreaks: habitLongestStreaks,
          habitTotalCompletions: habitTotalCompletions,
          habitLastCompletedDate: habitLastCompletedDate,
          undoneCompletions: undoneCompletions,
          accountCreatedAt: accountCreatedAt,
        );
      }
    } catch (e, st) {
      // Logged, not swallowed. This catch used to be `catch (_)`, so a single
      // malformed field bricked the whole account into the zeros state with
      // nothing on screen or in the console to say why, and finding it cost a
      // full device session.
      debugPrint('[dash] load failed: $e\n$st');
      // state is still DashboardState.initial() here — level 1, 0 XP, 0 gold,
      // no streak, no achievements — and none of that came from the server.
      // Flag it so the writers that persist progression as absolute values —
      // completeHabit, applyGridSquareChange and uncompleteHabit — refuse to
      // put those zeros back over the real document. The remaining writers
      // are turned away by their own preconditions instead: spendGold and
      // buyStreakFreeze can't pass an affordability check against 0 gold,
      // useStreakFreeze needs a freeze it no longer appears to have, and
      // acknowledgeComeback needs a flag the failed load never set. See
      // DashboardState.loadFailed.
      if (mounted) state = state.copyWith(isLoading: false, loadFailed: true);
      return;
    }
    // Outside the try for the same reason as _loadGuestToday's — see there.
    // Unreachable after the catch, which returns: a failed load has nothing
    // trustworthy to reconcile against, and _reconcileAchievements' own
    // loadFailed guard would turn it away anyway.
    await _reconcileAchievements();
  }

  // ── Achievement reconciliation ───────────────────────────────

  /// How many backfilled medals get a celebration sheet on load. See the
  /// `newlyUnlocked` write in [_reconcileAchievements].
  static const int _maxBackfillCelebrations = 3;

  /// Awards anything this account already qualifies for but never got.
  ///
  /// Until this existed, `unlockedAchievements` was only ever appended to
  /// from inside completeHabit and applyGridSquareChange — the two moments a
  /// counter moves *through this app*. Every other way a counter can change
  /// left the medal permanently stranded:
  ///
  ///  * the Quran-category fix in IslamicHabitCatalog.fromJson (see its own
  ///    comment) restored `categoryCompletions['quran']` for habits whose
  ///    category had been collapsed to 'faith' — the count came back, but
  ///    the quran_25/100/... tiers it had already passed did not;
  ///  * a Firestore restore, a field edited by hand, or signing in on a
  ///    device that had been progressing offline;
  ///  * any threshold added to the catalog *below* where an existing user
  ///    already sits, which would otherwise only unlock on their next tap.
  ///
  /// Runs once per load, after state is populated. Rewards are granted
  /// exactly as a live unlock would grant them, and the results are surfaced
  /// through `newlyUnlocked` so they're celebrated rather than appearing
  /// silently in the list — earning four medals at once on the load right
  /// after a data fix is a good moment, not a bug.
  Future<void> _reconcileAchievements() async {
    // Nothing to reconcile against: after a failed load `state` is the
    // all-zeros initial value, which qualifies for nothing anyway, but the
    // write below would still stamp a bad document. Same refusal, same
    // reason as completeHabit's — see DashboardState.loadFailed.
    if (!mounted || state.loadFailed) return;

    final unlocks = _resolveUnlocks(
      unlockedIds: state.unlockedAchievements,
      level: state.level,
      currentLevelXp: state.currentLevelXp,
      cumulativeXp: state.cumulativeXp,
      streak: state.streak,
      totalCompletions: state.totalCompletions,
      greenSquares: state.totalGreenSquares,
      categoryCompletions: state.categoryCompletions,
      levelGrantPaidThrough: state.levelGrantPaidThrough,
    );
    // The grant clause is what makes this a real backstop: a level raised by
    // a path that resolves no medal still owes its gold, and without this it
    // was dropped on the floor.
    if (unlocks.newly.isEmpty &&
        unlocks.levelGrantPaidThrough == state.levelGrantPaidThrough) {
      return;
    }

    state = state.copyWith(
      level: unlocks.level,
      levelGrantPaidThrough: unlocks.levelGrantPaidThrough,
      currentLevelXp: unlocks.currentLevelXp,
      cumulativeXp: unlocks.cumulativeXp,
      gold: state.gold + unlocks.bonusGold,
      unlockedAchievements: unlocks.unlockedIds,
      // Every medal is awarded, but only the first few are *celebrated*.
      // registerDashboardReactions shows one modal sheet per entry, awaiting
      // each before the next, so handing it a full backfill would greet
      // someone with six sheets to dismiss one at a time on cold start —
      // exactly the kind of thing that turns a reward into an interruption.
      // The uncelebrated ones are still unlocked and still on the
      // achievements screen; they just don't each demand a tap.
      //
      // Deliberately no local notifications from this path either (unlike
      // completeHabit's), for the same reason: a burst of pushes for medals
      // earned weeks ago is noise, not news.
      newlyUnlocked: unlocks.newly.take(_maxBackfillCelebrations).toList(),
    );

    if (_uid == null) {
      await _saveGuestState();
      return;
    }
    try {
      await _userRef.set({
        'level': state.level,
        'levelGrantPaidThrough': state.levelGrantPaidThrough,
        'currentLevelXp': state.currentLevelXp,
        'cumulativeXp': state.cumulativeXp,
        'gold': state.gold,
        // arrayUnion of only what this sweep awarded — see completeHabit's
        // identical write. It matters most here: this runs on every load,
        // including one that raced a write from another device.
        // Guarded now, and it has to be: this method used to return early
        // whenever `newly` was empty, which proved it non-empty before this
        // line could run. The grant clause above made an empty sweep
        // reachable, and an unguarded empty arrayUnion is a pointless write
        // on every cold start. Both sibling call sites already guard it.
        if (unlocks.newly.isNotEmpty)
          'unlockedAchievements':
              FieldValue.arrayUnion(unlocks.newly.map((a) => a.id).toList()),
      }, SetOptions(merge: true));
    } catch (e, st) {
      await _recordWriteFailure('reconcileAchievements', e, st);
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
