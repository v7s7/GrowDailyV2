import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_store_service.dart';
import '../../dashboard/notifiers/dashboard_notifier.dart';
import '../../grid/notifiers/weekly_grid_notifier.dart';
import '../../habits/models/habit_model.dart';
import '../../habits/notifiers/custom_habits_notifier.dart' show habitListProvider;
import '../catalog/quick_win_catalog.dart';
import '../models/quick_win.dart';

const _kStorageKey = 'quick_wins_v1';
const _kMaxRecentlyShown = 10;

String _dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class QuickWinsState {
  final bool isLoading;
  final String? dailyWinId;
  final String? dailyDateKey;
  final bool dailyDone;
  final String? weeklyWinId;
  final String? weeklyWeekKey;
  final bool weeklyDone;
  final List<String> recentlyShownIds;

  const QuickWinsState({
    this.isLoading = true,
    this.dailyWinId,
    this.dailyDateKey,
    this.dailyDone = false,
    this.weeklyWinId,
    this.weeklyWeekKey,
    this.weeklyDone = false,
    this.recentlyShownIds = const [],
  });

  QuickWin? get dailyWin =>
      dailyWinId == null ? null : QuickWinCatalog.findById(dailyWinId!);
  QuickWin? get weeklyWin =>
      weeklyWinId == null ? null : QuickWinCatalog.findById(weeklyWinId!);

  QuickWinsState copyWith({
    bool? isLoading,
    String? dailyWinId,
    String? dailyDateKey,
    bool? dailyDone,
    String? weeklyWinId,
    String? weeklyWeekKey,
    bool? weeklyDone,
    List<String>? recentlyShownIds,
  }) =>
      QuickWinsState(
        isLoading: isLoading ?? this.isLoading,
        dailyWinId: dailyWinId ?? this.dailyWinId,
        dailyDateKey: dailyDateKey ?? this.dailyDateKey,
        dailyDone: dailyDone ?? this.dailyDone,
        weeklyWinId: weeklyWinId ?? this.weeklyWinId,
        weeklyWeekKey: weeklyWeekKey ?? this.weeklyWeekKey,
        weeklyDone: weeklyDone ?? this.weeklyDone,
        recentlyShownIds: recentlyShownIds ?? this.recentlyShownIds,
      );
}

/// Picks one [QuickWin] from [pool], weighted 70% toward categories the
/// user already has completions in ("familiar") and 30% toward categories
/// they have none in yet ("discovery") — using only
/// [DashboardState.categoryCompletions], which already exists for
/// habit-mastery achievements. No new tracking, no AI.
QuickWin _pick({
  required List<QuickWin> pool,
  required Map<String, int> categoryCompletions,
  required List<String> excludeIds,
  required Random random,
}) {
  final familiar = <HabitCategory>{};
  final discovery = <HabitCategory>{};
  for (final category in HabitCategory.values) {
    if ((categoryCompletions[category.name] ?? 0) > 0) {
      familiar.add(category);
    } else {
      discovery.add(category);
    }
  }
  // Brand-new account: nothing is "familiar" yet — don't starve the 70%
  // branch, treat every category as fair game.
  if (familiar.isEmpty) familiar.addAll(HabitCategory.values);
  // Every category has been tried at least once: "discovery" becomes "the
  // categories practiced least", so the 30% branch still means something.
  if (discovery.isEmpty) {
    final byCount = HabitCategory.values.toList()
      ..sort((a, b) => (categoryCompletions[a.name] ?? 0)
          .compareTo(categoryCompletions[b.name] ?? 0));
    discovery.addAll(byCount.take(2));
  }

  final wanted = random.nextDouble() < 0.3 ? discovery : familiar;
  var candidates = pool.where((w) => wanted.contains(w.category)).toList();
  if (candidates.isEmpty) candidates = pool;

  var fresh = candidates.where((w) => !excludeIds.contains(w.id)).toList();
  if (fresh.isEmpty) fresh = candidates;

  return fresh[random.nextInt(fresh.length)];
}

/// Local-only Quick Wins state: which daily/weekly suggestion is active,
/// whether it's done, and a short memory of recently-shown ids so the same
/// suggestion doesn't repeat every time. Deliberately mirrors
/// [FocusTimerNotifier]'s Hive-only persistence pattern (see that file) —
/// no `_uid` branching, works identically for guests and signed-in users.
///
/// The reward itself (XP/gold) is applied through
/// [DashboardNotifier.awardBonus], the same call Focus sessions and the old
/// Weekly Challenge already use, so it never touches streak, Grid squares,
/// habit completions, or category-completion counts.
class QuickWinsNotifier extends StateNotifier<QuickWinsState> {
  final Ref _ref;
  final Random _random;

  QuickWinsNotifier(this._ref, {Random? random})
      : _random = random ?? Random(),
        super(const QuickWinsState()) {
    _restore();
  }

  Map<String, int> get _categoryCompletions =>
      _ref.read(dashboardProvider).categoryCompletions;

  Future<void> _restore() async {
    final saved = await LocalStoreService.getSettingsMap(_kStorageKey);
    var next = QuickWinsState(
      dailyWinId: saved['dailyWinId'] as String?,
      dailyDateKey: saved['dailyDateKey'] as String?,
      dailyDone: (saved['dailyDone'] as bool?) ?? false,
      weeklyWinId: saved['weeklyWinId'] as String?,
      weeklyWeekKey: saved['weeklyWeekKey'] as String?,
      weeklyDone: (saved['weeklyDone'] as bool?) ?? false,
      recentlyShownIds:
          List<String>.from(saved['recentlyShownIds'] as List? ?? const []),
      isLoading: false,
    );

    next = _ensureDaily(next);
    next = _ensureWeekly(next);

    if (!mounted) return;
    state = next;
    await _persist();
  }

  List<String> _remember(List<String> recent, String id) {
    final next = [...recent, id];
    if (next.length <= _kMaxRecentlyShown) return next;
    return next.sublist(next.length - _kMaxRecentlyShown);
  }

  QuickWinsState _ensureDaily(QuickWinsState s) {
    final todayKey = _dateKey(DateTime.now());
    if (s.dailyWinId != null && s.dailyDateKey == todayKey) return s;
    final picked = _pick(
      pool: QuickWinCatalog.daily,
      categoryCompletions: _categoryCompletions,
      excludeIds: s.recentlyShownIds,
      random: _random,
    );
    return s.copyWith(
      dailyWinId: picked.id,
      dailyDateKey: todayKey,
      dailyDone: false,
      recentlyShownIds: _remember(s.recentlyShownIds, picked.id),
    );
  }

  QuickWinsState _ensureWeekly(QuickWinsState s) {
    final weekKey = _dateKey(startOfGridWeek(DateTime.now()));
    if (s.weeklyWinId != null && s.weeklyWeekKey == weekKey) return s;
    final picked = _pick(
      pool: QuickWinCatalog.weekly,
      categoryCompletions: _categoryCompletions,
      excludeIds: s.recentlyShownIds,
      random: _random,
    );
    return s.copyWith(
      weeklyWinId: picked.id,
      weeklyWeekKey: weekKey,
      weeklyDone: false,
      recentlyShownIds: _remember(s.recentlyShownIds, picked.id),
    );
  }

  Future<void> _persist() async {
    await LocalStoreService.putSettingsMap(_kStorageKey, {
      'dailyWinId': state.dailyWinId,
      'dailyDateKey': state.dailyDateKey,
      'dailyDone': state.dailyDone,
      'weeklyWinId': state.weeklyWinId,
      'weeklyWeekKey': state.weeklyWeekKey,
      'weeklyDone': state.weeklyDone,
      'recentlyShownIds': state.recentlyShownIds,
    });
  }

  // ── Actions ──────────────────────────────────────────────────

  /// Marks the Daily Quick Win done and awards its (small, XP-only) reward.
  ///
  /// TODO(quick-wins-v2): completion is guarded only by local state
  /// (`dailyDone`), not a server record — a reinstall or a second device
  /// won't know today's win was already claimed. Fine while the reward is
  /// this small; if Quick Win rewards ever grow, this needs a server-backed
  /// claim ledger like the rest of the app's economy, not just a local flag.
  Future<void> completeDaily() async {
    final win = state.dailyWin;
    if (win == null || state.dailyDone) return;
    state = state.copyWith(dailyDone: true);
    await _persist();
    await _ref
        .read(dashboardProvider.notifier)
        .awardBonus(xp: win.xpReward, gold: win.goldReward);
  }

  Future<void> swapDaily() async {
    if (state.dailyDone) return;
    final currentId = state.dailyWinId;
    final picked = _pick(
      pool: QuickWinCatalog.daily,
      categoryCompletions: _categoryCompletions,
      excludeIds: [
        ...state.recentlyShownIds,
        if (currentId != null) currentId,
      ],
      random: _random,
    );
    state = state.copyWith(
      dailyWinId: picked.id,
      recentlyShownIds: _remember(state.recentlyShownIds, picked.id),
    );
    await _persist();
  }

  /// Marks the Weekly Quick Win done/claimed. Same local-only caveat as
  /// [completeDaily] — see the TODO there.
  Future<void> completeWeekly() async {
    final win = state.weeklyWin;
    if (win == null || state.weeklyDone) return;
    state = state.copyWith(weeklyDone: true);
    await _persist();
    await _ref
        .read(dashboardProvider.notifier)
        .awardBonus(xp: win.xpReward, gold: win.goldReward);
  }

  Future<void> swapWeekly() async {
    if (state.weeklyDone) return;
    final currentId = state.weeklyWinId;
    final picked = _pick(
      pool: QuickWinCatalog.weekly,
      categoryCompletions: _categoryCompletions,
      excludeIds: [
        ...state.recentlyShownIds,
        if (currentId != null) currentId,
      ],
      random: _random,
    );
    state = state.copyWith(
      weeklyWinId: picked.id,
      recentlyShownIds: _remember(state.recentlyShownIds, picked.id),
    );
    await _persist();
  }
}

final quickWinsProvider =
    StateNotifierProvider<QuickWinsNotifier, QuickWinsState>((ref) {
  return QuickWinsNotifier(ref);
});

/// Live progress `(completedDays, targetDays)` for the current Weekly Quick
/// Win, derived from the same Grid data driving the habit squares — or null
/// if it can't be safely auto-tracked right now, in which case the UI
/// should show a manual "mark done" action instead of a progress bar.
///
/// Deliberately requires [WeeklyGridState.isCurrentWeek]: the Grid tab lets
/// a user browse past weeks, and `weeklyGridProvider`'s state reflects
/// whichever week they last viewed there, not necessarily "this week" — so
/// if they've navigated away from the current week, we don't actually know
/// today's real progress and must not display stale/wrong numbers.
final quickWinWeeklyProgressProvider = Provider<(int, int)?>((ref) {
  final win = ref.watch(quickWinsProvider).weeklyWin;
  if (win == null || win.autoTrackTarget == null) return null;
  // `custom` is a catch-all habit category covering unrelated habits, so
  // "the user has *a* custom habit" doesn't mean it's the *right* one —
  // never auto-track against it, regardless of what the catalog says.
  if (win.category == HabitCategory.custom) return null;

  final grid = ref.watch(weeklyGridProvider);
  if (!grid.isCurrentWeek) return null;

  final habitIds = ref
      .watch(habitListProvider)
      .where((h) => h.category == win.category)
      .map((h) => h.id)
      .toList();
  if (habitIds.isEmpty) return null;

  final progress = grid.greenSquares(habitIds);
  return (progress.clamp(0, win.autoTrackTarget!), win.autoTrackTarget!);
});
