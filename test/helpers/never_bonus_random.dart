// The surprise bonus, taken out of the way of tests that assert exact numbers.
//
// [DashboardNotifier.completeHabit] rolls an independent chance on EVERY
// completion (GameConstants.surpriseBonusChance, currently 0.15) and, when it
// hits, pays half the tap's slice again on top of the normal reward. That
// bonus is real progression: it lands in cumulativeXp and gold, it is recorded
// on the same-day-undo snapshot, and from there it is refunded by
// uncompleteHabit and written onto the UndoneCompletion receipt.
//
// So any test that calls completeHabit and then asserts a LITERAL reward
// number is really asserting "and the coin came up tails", and fails roughly
// one run in seven for no reason anyone can see. It is a nasty flake to read,
// because nothing about it correlates with anything: it moves around the
// suite, it survives running the file alone, and the number it produces (10
// XP becoming 15, 5 gold becoming 8) looks exactly like a double-award bug.
// undo_restore_guest_test's receipt test was chased as a load/ordering
// problem twice before the coin was noticed.
//
// Inject this wherever a test drives completeHabit and pins a number:
//
//     dashboardProvider.overrideWith(
//       (ref) => DashboardNotifier(null, random: NeverBonusRandom()),
//     )
//
// A test that wants to prove the bonus itself works should inject the
// opposite (nextDouble() => 0) rather than hoping for it.
import 'dart:math';

/// A [Random] that always rolls the highest possible value, so every
/// `nextDouble() < chance` gate in the app stays shut.
///
/// `nextDouble` returns 1 rather than something just under it: real
/// `Random.nextDouble` never reaches 1, which is precisely what makes 1 a
/// value no chance gate can ever let through, whatever the chance is set to.
class NeverBonusRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 1;

  @override
  int nextInt(int max) => 0;
}
