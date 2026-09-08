import 'package:flutter/material.dart';

/// One notice at a time.
///
/// [ScaffoldMessenger] QUEUES by default: every bar waits out the one before
/// it, and its own duration only starts once it reaches the front. So a few
/// quick actions in a row — tapping several squares, correcting a mark, then
/// pausing a habit — stack into a train of notices that keeps the bottom of
/// the screen occupied long after the action that caused any of them, which
/// reads as a popup that simply will not go away.
///
/// Replacing rather than queueing also keeps the message HONEST: the bar on
/// screen always describes the last thing that happened, and an Undo action
/// always belongs to it. A queued bar offering "Undo" for something two taps
/// ago is worse than no bar at all.
///
/// ── And every bar leaves on its own ──────────────────────────────────────
///
/// Flutter 3.41 added `SnackBar.persist` and defaulted it to `action != null`,
/// which silently reversed what a bar with an Undo does: it now stays put
/// until the action is tapped or it is swiped away, and its `duration` is
/// ignored entirely. Worse, the one timer ScaffoldMessenger arms fires, sees
/// `persist`, and returns WITHOUT clearing itself, so no second timer is ever
/// armed. The bar is pinned to the bottom of the screen for the rest of the
/// session, and because the messenger sits above the Navigator it rides along
/// on top of every screen opened next: a "شلنا العلامة" from the Grid was
/// still sitting over Room Detail minutes later.
///
/// So every SnackBar in this app that carries an action passes
/// `persist: false`, which restores the promise its duration is making.
/// test/shared/snackbar_auto_dismiss_test.dart fails if a new one forgets.
extension AppSnackBar on ScaffoldMessengerState {
  /// Dismisses whatever is on screen, then shows [bar].
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showOne(
    SnackBar bar,
  ) {
    hideCurrentSnackBar();
    return showSnackBar(bar);
  }
}
