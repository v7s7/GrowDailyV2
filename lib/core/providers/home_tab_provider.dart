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

/// Set alongside [requestedHomeTabProvider] when the request is arriving
/// from a route that's itself mid-pop back onto this shell (AppGuideScreen's
/// lesson rows, currently) rather than from a CTA that lives on one of the
/// shell's own three pages. In that case the PageView's own animateToPage
/// would be running underneath that route's pop transition at the same
/// time — two animations racing each other reads as a glitchy double-shift
/// instead of one smooth motion. This says "just land on it, no page-turn
/// animation," so the only motion visible is the pop transition itself,
/// revealing the destination tab already settled. Reset by HomeShell's
/// listener right after reading it, same one-shot pattern as
/// [requestedHomeTabProvider] itself.
final requestedHomeTabInstantProvider = StateProvider<bool>((ref) => false);

/// Set alongside [requestedHomeTabProvider] (tab 2) when something outside
/// the Matrix tab wants it to land straight in the Add Task sheet the
/// moment it's on screen, rather than just showing the board — currently
/// only the Matrix home-screen widget's "+" button, via a
/// `growdaily://matrix/add` deep link (see main.dart's AppLinks wiring and
/// matrix_notifier.dart's isMatrixQuickAddLink). MatrixScreen consumes and
/// resets this exactly once, same one-shot pattern as
/// [requestedHomeTabProvider] itself — see MatrixScreen's own ref.listen.
final requestedMatrixQuickAddProvider = StateProvider<bool>((ref) => false);
