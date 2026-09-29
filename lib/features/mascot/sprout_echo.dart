import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'sprout.dart';

/// What a second body needs to stand in for the Grid's sprout somewhere
/// else, while the one that thinks stays where it is.
///
/// Doum's mind is [DayCardSprout] on the board's edge (SproutLedge): his
/// talking limit, the praise he said lately, his greeting, his laugh. When
/// the board's edge scrolls away he waits above the bottom bar instead
/// (SproutBottomPeek), and that body must be the same Doum, not a second
/// one with its own opinions: it shows the pose the mind shows, makes the
/// moves the mind makes, and a tap on it tickles the mind. The mind stays
/// mounted the whole time (a SliverToBoxAdapter's child is never disposed by
/// scrolling), so this only carries what the body shows, never a decision.
///
/// The mind moves through [moves] and the stand-in through [echoMoves],
/// both owned here rather than by either widget, so they live as long as the
/// Grid does. Two controllers, not one: the mind hops from inside its own
/// build (a square turned green rebuilt it), where only its own body, below
/// it, may be told; the stand-in is somewhere else in the tree, so it hears
/// the same move a frame later.
class SproutEcho extends ChangeNotifier {
  SproutEcho() {
    moves.addListener(_relay);
  }

  /// The moves the mind makes: a hop, a celebration.
  final SproutController moves = SproutController();

  /// The same moves, for the stand-in, a frame behind.
  final SproutController echoMoves = SproutController();
  bool _relayQueued = false;

  void _relay() {
    if (_relayQueued || _disposed) return;
    _relayQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _relayQueued = false;
      if (!_disposed) echoMoves.repeat(moves);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  SproutPose _pose = SproutPose.frontWave;
  SproutPose _mood = SproutPose.frontWave;
  SproutPose? _pending;
  SproutPose? _pendingMood;
  VoidCallback? _tickle;
  Object? _owner;

  /// The pose the mind shows right now (a frame behind it: see [report]).
  SproutPose get pose => _pose;

  /// The pose his mood gives him (see dayCardMoodFor), whatever he shows for
  /// a moment on top of it (a laugh): where he stands and whether he is
  /// asleep go by this one, so a laugh never moves him.
  SproutPose get mood => _mood;

  /// Whether a mind is listening: without one there is nobody to stand in
  /// for, and a body must not be shown.
  bool get hasMind => _tickle != null;

  /// A tap on the stand-in: the mind laughs, and says so.
  void tickle() => _tickle?.call();

  /// Called by the mind when it mounts (from its initState, mid-build).
  void attach(Object owner, VoidCallback tickle) {
    _owner = owner;
    _tickle = tickle;
    _notifyLater();
  }

  /// Called by the mind when it goes (from its dispose, while the tree is
  /// locked). A mind that was already replaced (a new one attached before
  /// the old one was disposed) changes nothing.
  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _tickle = null;
    _notifyLater();
  }

  /// The mind reports the pose it is about to show. It does so from its
  /// build, and a listener told mid-build would be marked dirty from inside
  /// someone else's build (the framework's assertion), so the news waits for
  /// the end of the frame: the stand-in shows a new pose one frame late,
  /// which no one can see. Repeated reports inside one frame keep the last.
  void report(SproutPose pose, {required SproutPose mood}) {
    if (_pending == null &&
        _pendingMood == null &&
        pose == _pose &&
        mood == _mood) {
      return;
    }
    _pending = pose;
    _pendingMood = mood;
    _notifyLater();
  }

  bool _disposed = false;
  bool _notifyQueued = false;

  /// Every change here is made from inside a build or a dispose, where a
  /// listener must not be told (it would be marked dirty mid-build, or
  /// while the tree is locked): the news goes out once, after the frame.
  void _notifyLater() {
    if (_notifyQueued || _disposed) return;
    _notifyQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyQueued = false;
      if (_disposed) return;
      final next = _pending;
      final nextMood = _pendingMood;
      _pending = null;
      _pendingMood = null;
      if (next != null) _pose = next;
      if (nextMood != null) _mood = nextMood;
      notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    moves.removeListener(_relay);
    moves.dispose();
    echoMoves.dispose();
    super.dispose();
  }
}
