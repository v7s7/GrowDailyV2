import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set by a screen that wants HomeShell to animate its PageView to a given
/// tab (0=Grid, 1=Profile, 2=Matrix - matches GameNavBar's route order),
/// then reset back to null once handled - see HomeShell's own ref.listen.
/// Lives in its own file (rather than inside home_shell.dart) purely so
/// sibling pages inside that same PageView (GridScreen, MatrixScreen) can
/// import just the provider without importing the shell that contains them
/// - Dart allows the circular alternative fine, but this avoids it.
///
/// A plain StateProvider since there's only ever one thing to communicate
/// (which page to jump to), not a queue of them.
final requestedHomeTabProvider = StateProvider<int?>((ref) => null);
