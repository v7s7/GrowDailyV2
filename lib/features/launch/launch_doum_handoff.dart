import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the hand-off from the launch curtain to the sign-in screen stands.
enum DoumHandoffPhase {
  /// No hand-off: the curtain lifts as it always has.
  none,

  /// The very first open's scene is playing (LaunchScene.firstOpen), and a
  /// sign-in screen under it may catch Doum when the curtain lifts. That
  /// screen keeps its own Doum hidden meanwhile.
  expected,

  /// He is on his way: the curtain draws him moving from its middle into
  /// the sign-in screen's head while its ground fades.
  flying,

  /// He arrived. The sign-in screen's Doum takes over in the same place and
  /// the same pose, then turns round into his language's look.
  landed,
}

/// Doum's hand-off from the launch curtain to the sign-in screen (Aziz,
/// 2026-10-01, the canvas "Doum picks the language": "he stays when the
/// curtain lifts").
///
/// On the very first open the curtain's Doum does not fade with it: he
/// flies into the head of the sign-in screen, where the app icon used to
/// be, and that screen's Doum carries on from there. The two never meet in
/// code: the sign-in screen registers where he should land ([stand], the
/// box his feet stand at the bottom centre of, and [height], the size he
/// stands there at) and the curtain decides whether to fly.
///
/// Only ever a nicety: whenever anything is missing (no sign-in screen
/// under the curtain, a tap that skipped the curtain, Reduce Motion) the
/// curtain lifts as it always has and the phase goes back to [none], which
/// the sign-in screen reads as "pop in as usual".
class LaunchDoumHandoff extends ChangeNotifier {
  DoumHandoffPhase _phase = DoumHandoffPhase.none;
  DoumHandoffPhase get phase => _phase;

  GlobalKey? _stand;
  double _height = 0;

  /// The sign-in screen's landing box, while that screen is built.
  GlobalKey? get stand => _stand;

  /// The height [stand]'s Doum is drawn at (Sprout's reference height).
  double get height => _height;

  /// Whether a sign-in screen is built and laid out to land on.
  bool get canLand {
    final box = _stand?.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize && box.attached;
  }

  void register(GlobalKey stand, double height) {
    _stand = stand;
    _height = height;
  }

  void unregister(GlobalKey stand) {
    if (_stand == stand) _stand = null;
  }

  void expect() => _set(DoumHandoffPhase.expected);
  void fly() => _set(DoumHandoffPhase.flying);
  void land() => _set(DoumHandoffPhase.landed);

  /// The sign-in screen has taken him over: the hand-off is spent, so a
  /// later sign-in screen (after a sign-out) pops its Doum in as usual.
  void done() {
    if (_phase == DoumHandoffPhase.landed) _set(DoumHandoffPhase.none);
  }

  /// The curtain went without him flying, or went away mid-flight.
  void cancel() {
    if (_phase == DoumHandoffPhase.expected ||
        _phase == DoumHandoffPhase.flying) {
      _set(DoumHandoffPhase.none);
    }
  }

  void _set(DoumHandoffPhase phase) {
    if (_phase == phase) return;
    _phase = phase;
    notifyListeners();
  }
}

final launchDoumHandoffProvider =
    ChangeNotifierProvider<LaunchDoumHandoff>((ref) => LaunchDoumHandoff());
