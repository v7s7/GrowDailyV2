import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/home_tab_provider.dart';
import '../../core/theme/game_theme.dart' show GameMotion;
import '../../features/grid/screens/grid_screen.dart';
import '../../features/matrix/screens/matrix_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import 'game_nav_bar.dart';

/// The app's three peer tabs — Grid, Profile, Matrix — in one swipeable
/// PageView under a single [GameNavBar], instead of three separate routes
/// that pushReplacementNamed'd each other. Swiping between tabs is the
/// whole point (tap-only bottom nav reads as web-ish; horizontal swipe is
/// the native-feel win), but taps still work exactly as before through the
/// bar, now animating the same PageView instead of swapping routes.
///
/// Page order matches GameNavBar's route order (grid, profile, matrix) so
/// [initialIndex] and the bar's currentIndex speak the same language, and
/// PageView follows the ambient text direction — in Arabic the pages run
/// right-to-left, mirroring the bar exactly like before.
///
/// The old '/grid' / '/profile' / '/matrix' routes all resolve to this
/// shell at the matching page (see main.dart's onGenerateRoute), so every
/// existing pushReplacementNamed call site anywhere in the app keeps
/// working unchanged. The tab screens themselves no longer carry their own
/// GameNavBar — the shell owns the one bar.
///
/// Also listens for [requestedHomeTabProvider]: GetStartedChecklistCard's
/// "other domain" row (e.g. "Add your first task" while looking at Grid)
/// can't reach across sibling pages of this same PageView directly, so it
/// just requests a tab switch here instead of trying to poke Matrix's
/// private state from outside - the checklist re-appears on the new tab
/// with its own, screen-owned "add" action already wired.
class HomeShell extends ConsumerStatefulWidget {
  final int initialIndex;
  const HomeShell({super.key, this.initialIndex = 0});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTabSelected(int i) {
    _controller.animateToPage(
      i,
      duration: GameMotion.relaxed,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // See requestedHomeTabProvider's doc comment. ref.listen (not read/
    // watch) since this is a one-shot side effect, not something the build
    // method's own output depends on - and it's safe to call unconditionally
    // on every build the way ConsumerStatefulWidget's build allows.
    ref.listen<int?>(requestedHomeTabProvider, (previous, next) {
      if (next == null) return;
      HapticFeedback.selectionClick();
      if (ref.read(requestedHomeTabInstantProvider)) {
        // See requestedHomeTabInstantProvider's doc comment — the caller is
        // a route that's mid-pop back onto this shell, so jump straight
        // there instead of racing an animated page-turn against that route's
        // own pop transition.
        _controller.jumpToPage(next);
        ref.read(requestedHomeTabInstantProvider.notifier).state = false;
      } else {
        _controller.animateToPage(
          next,
          duration: GameMotion.relaxed,
          curve: Curves.easeOutCubic,
        );
      }
      ref.read(requestedHomeTabProvider.notifier).state = null;
    });
    return Scaffold(
      // The shell owns the one nav bar; each page keeps its own Scaffold
      // (FABs, app bars, backgrounds) minus the bar it used to carry.
      bottomNavigationBar: GameNavBar(
        currentIndex: _index,
        onSelect: _onTabSelected,
      ),
      body: PageView(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        children: const [
          GridScreen(),
          ProfileScreen(),
          MatrixScreen(),
        ],
      ),
    );
  }
}

