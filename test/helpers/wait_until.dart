// Waiting for async work in a test, without inventing a flake.
//
// Several tests here drive real providers against real Hive storage, so they
// have to wait for a load that genuinely takes time. The way that was written
// looked reasonable and was not:
//
//     final deadline = DateTime.now().add(const Duration(seconds: 10));
//     while (container.read(dashboardProvider).isLoading &&
//         DateTime.now().isBefore(deadline)) {
//       await Future<void>.delayed(const Duration(milliseconds: 20));
//     }
//     return container;                      // <- and if it never loaded?
//
// Two separate problems, and the second is the one that cost a day.
//
// A WALL-CLOCK BUDGET IS A GUESS ABOUT THE MACHINE. Ten seconds is generous
// on an idle laptop and not generous at all when the suite is running many
// isolates and a simulator is compiling in the background. That is exactly
// the condition under which undo_restore_guest_test failed and then passed
// again on a quiet machine, which is the signature of a load-sensitive
// deadline rather than a logic bug.
//
// GIVING UP SILENTLY TURNS A TIMEOUT INTO A LIE. When the loop above expired
// it returned the container anyway, still loading, and the test carried on
// asserting against a half-built state. The failure then surfaced somewhere
// else entirely, as a wrong XP delta, with nothing pointing at the real
// cause. Proven, not guessed: setting that deadline to zero reproduces the
// same test failing the same way.
//
// So this helper does the two things that loop did not. It fails LOUDLY and
// says what it was waiting for, and it carries a budget big enough that only
// a genuine hang can exhaust it.
import 'package:flutter_test/flutter_test.dart';

/// Polls [ready] until it is true, then returns.
///
/// Fails the test, naming [describe], if [timeout] passes first. Never
/// returns having given up: a caller can rely on [ready] being true after
/// this, which is the whole point.
///
/// Thirty seconds rather than ten. Nothing here should ever take that long,
/// so it is not a budget anyone is meant to spend, it is the point past which
/// something is genuinely wrong and the test should say so instead of
/// limping onward.
Future<void> waitUntil(
  bool Function() ready, {
  required String describe,
  Duration timeout = const Duration(seconds: 30),
  Duration poll = const Duration(milliseconds: 10),
}) async {
  if (ready()) return;
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(poll);
    if (ready()) return;
  }
  fail(
    'Timed out after ${timeout.inSeconds}s waiting for: $describe.\n'
    'This is a real hang or a genuinely slow machine, not a flake to retry: '
    'the previous version of this wait gave up silently and let the test '
    'assert against a half-loaded state, which is why failures used to '
    'surface as unrelated wrong numbers.',
  );
}
