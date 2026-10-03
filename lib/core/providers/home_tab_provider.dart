import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'nav_layout_provider.dart' show NavTab;

/// Set by a screen that wants HomeShell to show a given tab, then reset
/// back to null once handled - see HomeShell's own ref.listen.
///
/// By IDENTITY, not by page index. The bar is customisable (see
/// navLayoutProvider), so "Tasks" can be page 2, page 4, or not in the bar
/// at all; a caller only knows which screen it wants, and HomeShell is the
/// one that knows where, or whether, that screen sits in the bar. A tab
/// that is not in the bar is pushed on top of the shell as a route instead,
/// so every caller here still lands on the screen it asked for.
///
/// Lives in its own file (rather than inside home_shell.dart) purely so
/// sibling pages inside that same PageView (GridScreen, MatrixScreen) can
/// import just the provider without importing the shell that contains them
/// - Dart allows the circular alternative fine, but this avoids it.
///
/// A plain StateProvider since there's only ever one thing to communicate
/// (which tab to show), not a queue of them.
///
/// Can be set before HomeShell exists: a Lock Screen control or widget that
/// cold-starts the app asks from main.dart's _openFromOutside while the
/// sign-in gate is still up. HomeShell reads a waiting request when it is
/// built (its initState), because its listener only hears changes made
/// after it registers.
final requestedHomeTabProvider = StateProvider<NavTab?>((ref) => null);

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
///
/// Also set by main.dart's _openFromOutside for links from outside the app
/// (Lock Screen controls and widgets, the Matrix widget's "+"): the app is
/// coming up from the Lock Screen or the background, and whatever was open
/// on top is being closed in the same moment.
final requestedHomeTabInstantProvider = StateProvider<bool>((ref) => false);

/// Set alongside [requestedHomeTabProvider] (NavTab.matrix) when something outside
/// the Matrix tab wants it to land straight in the Add Task sheet the
/// moment it's on screen, rather than just showing the board: the Matrix
/// home-screen widget's "+" button (a `growdaily://matrix/add` deep link,
/// matrix_notifier.dart's isMatrixQuickAddLink) and the Lock Screen's Add
/// Task control (`/open?tab=matrix&add=1`, deep_links.dart's
/// openTabLinkWantsAdd), both through main.dart's _openFromOutside.
/// MatrixScreen._openQuickAdd consumes and resets this exactly once, as the
/// sheet opens, which is after the launch curtain has lifted: a request
/// made under the curtain stays set until then.
final requestedMatrixQuickAddProvider = StateProvider<bool>((ref) => false);

/// Set alongside [requestedHomeTabProvider] (NavTab.settings) when a link
/// from outside the app wants one page INSIDE Settings, not Settings itself.
/// Today that is only the prayer widget («حدّد موقعك» and its Lock Screen
/// faces), which asks for [kSettingsPagePrayerLocation]: since Settings
/// became five rows that each open their own page (2026-09-28), the place
/// sits two taps below Settings, and the widget should land on it.
///
/// SettingsScreen consumes and resets it, the same one-shot pattern as
/// [requestedMatrixQuickAddProvider]: read in its initState (Settings built
/// after the request, the usual case) and heard by its ref.listen (Settings
/// already open as a bar tab). Pushing from there, rather than from
/// main.dart, is what leaves Settings under the page for the back button,
/// wherever HomeShell decided Settings belongs.
final requestedSettingsPageProvider = StateProvider<String?>((ref) => null);

/// The one page id [requestedSettingsPageProvider] knows. Same spelling as
/// the `page=` of the prayer widget's link (see openTabLinkPage).
const String kSettingsPagePrayerLocation = 'prayer-location';
