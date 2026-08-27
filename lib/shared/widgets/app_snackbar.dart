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
extension AppSnackBar on ScaffoldMessengerState {
  /// Dismisses whatever is on screen, then shows [bar].
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showOne(
    SnackBar bar,
  ) {
    hideCurrentSnackBar();
    return showSnackBar(bar);
  }
}
