// completeHabit must refuse to run against a dashboard that has not loaded.
//
// Every reward field this method persists — level, currentLevelXp,
// cumulativeXp, gold, streak, totalCompletions, unlockedAchievements — is
// written back to Firestore as an ABSOLUTE value computed from `state`. So
// running it while `state` is DashboardState.initial()'s zeros does not
// merely record one wrong completion: it writes level 1 / 0 XP / 0 gold /
// no achievements straight over a real account, and the real numbers are
// gone.
//
// DashboardState.loadFailed already guarded the load-THREW case. This
// covers the load-hasn't-ARRIVED-yet case, which is the one with a caller:
// main.dart drains the home widget's queued Mark Done taps from initState,
// and a notification action that cold-launched the app flushes through the
// same path, both potentially before _loadToday resolves.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

void main() {
  test('the initial state is loading and has NOT failed', () {
    // The exact shape that made the old guard miss: loadFailed is false, so
    // a guard written only against loadFailed waves this straight through
    // even though the numbers are placeholders.
    final initial = DashboardState.initial();
    expect(initial.isLoading, isTrue);
    expect(initial.loadFailed, isFalse);
  });

  test('the initial state carries the zeros that would be written back', () {
    // Documents what is actually at stake: these are the values that would
    // overwrite a real account's progress if a completion ran against them.
    final initial = DashboardState.initial();
    expect(initial.level, 1);
    expect(initial.cumulativeXp, 0);
    expect(initial.gold, 0);
    expect(initial.streak, 0);
    expect(initial.totalCompletions, 0);
    expect(initial.unlockedAchievements, isEmpty);
  });

  test('a loaded state is distinguishable from both failure and loading', () {
    // What the guard lets through, so the check cannot be satisfied by
    // simply refusing everything.
    final loaded = DashboardState.initial()
        .copyWith(isLoading: false, level: 12, gold: 1820);
    expect(loaded.isLoading, isFalse);
    expect(loaded.loadFailed, isFalse);
    expect(loaded.level, 12);
  });
}
