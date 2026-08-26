// A zero that nobody vouched for must never be shown as a number.
//
// Every progression field on DashboardState is written back to Firestore as
// an ABSOLUTE value, so a failed load has always been blocked from WRITING
// (see DashboardState.loadFailed). What was never blocked was DRAWING it: a
// level 12 account with 7,564 XP and a 10-day best rendered as level 1 with
// 0 XP and no streak, at full confidence, for the whole cold-start window
// and permanently if the load failed. The two states are identical on
// screen, and the obvious reading of them, that the account was wiped, is
// the wrong one.
import 'package:flutter_test/flutter_test.dart';
import 'package:grow_daily_v2/features/dashboard/notifiers/dashboard_notifier.dart';

void main() {
  test('a freshly constructed state is not yet trustworthy', () {
    // initial() is isLoading: true, and every number on it is a placeholder
    // zero rather than anything the server said.
    expect(DashboardState.initial().statsAreReal, isFalse);
  });

  test('a load still in flight is not trustworthy', () {
    final loading = DashboardState.initial().copyWith(isLoading: true);
    expect(loading.statsAreReal, isFalse);
  });

  test('a failed load is not trustworthy even though it stopped loading', () {
    // The trap this getter exists for: isLoading goes false on the failure
    // path too, so isLoading alone would call these zeros real.
    final failed =
        DashboardState.initial().copyWith(isLoading: false, loadFailed: true);
    expect(failed.isLoading, isFalse);
    expect(failed.statsAreReal, isFalse,
        reason: 'not loading is not the same as loaded');
  });

  test('a completed load is trustworthy', () {
    final loaded = DashboardState.initial()
        .copyWith(isLoading: false, loadFailed: false, cumulativeXp: 7564);
    expect(loaded.statsAreReal, isTrue);
  });

  test('real zeros on a genuinely new account are still shown', () {
    // The getter must not become "hide zeros". A brand new account really
    // does have 0 XP and that number is correct and earned; only unloaded
    // zeros are the lie.
    final newAccount =
        DashboardState.initial().copyWith(isLoading: false, loadFailed: false);
    expect(newAccount.cumulativeXp, 0);
    expect(newAccount.statsAreReal, isTrue,
        reason: 'a loaded zero is a fact, an unloaded zero is a guess');
  });
}
