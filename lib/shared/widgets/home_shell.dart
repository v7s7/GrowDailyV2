import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/home_spotlight_provider.dart';
import '../../core/theme/game_theme.dart';
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
/// Also owns the one-time nav spotlight (see homeSpotlightSeenProvider's
/// doc comment): a brief dim-and-glow moment the first time this shell
/// shows on a device, pointing at the real, live nav bar instead of a
/// slide mock, since that's the concrete thing people actually navigate
/// with afterward.
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
  late bool _showSpotlight;

  @override
  void initState() {
    super.initState();
    // Safe to read synchronously here (not watch — this never needs to
    // rebuild in response to the provider itself changing, only via the
    // explicit setState in _dismissSpotlight below): the persisted value
    // is seeded into the ProviderScope before runApp ever fires (see
    // main.dart), so it's already correct by the time this widget exists,
    // no async gap to wait out.
    _showSpotlight = !ref.read(homeSpotlightSeenProvider);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTabSelected(int i) {
    // Tapping a tab while the spotlight is up is someone acting on the
    // guidance in real time — the best possible outcome, not something to
    // block behind an explicit "Got it" first. Dismiss it as a side effect
    // rather than making it a second thing they have to clear.
    if (_showSpotlight) _dismissSpotlight();
    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _dismissSpotlight() {
    if (!_showSpotlight) return;
    HapticFeedback.selectionClick();
    setState(() => _showSpotlight = false);
    markHomeSpotlightSeen(ref);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The shell owns the one nav bar; each page keeps its own Scaffold
      // (FABs, app bars, backgrounds) minus the bar it used to carry.
      bottomNavigationBar: _NavBarWithGlow(
        active: _showSpotlight,
        child: GameNavBar(
          currentIndex: _index,
          onSelect: _onTabSelected,
        ),
      ),
      body: Stack(
        children: [
          PageView(
            controller: _controller,
            // Blocks swiping between tabs while the spotlight is up, so it
            // can't be brushed past by accident — same reasoning as the
            // scrim's tap-to-dismiss below, just covering the drag case a
            // plain tap-catcher wouldn't.
            physics: _showSpotlight
                ? const NeverScrollableScrollPhysics()
                : null,
            onPageChanged: (i) => setState(() => _index = i),
            children: const [
              GridScreen(),
              ProfileScreen(),
              MatrixScreen(),
            ],
          ),
          if (_showSpotlight)
            _HomeSpotlightOverlay(onDismiss: _dismissSpotlight),
        ],
      ),
    );
  }
}

/// Wraps the real nav bar with a soft, pulsing gold glow while the
/// spotlight is active — a shadow rather than a traced border on purpose:
/// GameNavBar renders as two genuinely different shapes (a full-width
/// rectangle on Android, a floating inset pill on iOS), and a soft blurred
/// glow reads as "look here" cleanly around either one without needing to
/// know which shape is on screen. No-op wrapper (returns [child] untouched)
/// once the spotlight is dismissed.
class _NavBarWithGlow extends StatelessWidget {
  final bool active;
  final Widget child;
  const _NavBarWithGlow({required this.active, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: GameColors.gold.withOpacity(0.55),
                    blurRadius: 28,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(duration: 750.ms, begin: 0.35),
        ),
        child,
      ],
    );
  }
}

/// The dim-and-explain layer itself: a full-body scrim (tap anywhere to
/// dismiss) with a short card anchored to the bottom, right above the real
/// nav bar it's pointing at — proximity does the pointing, so this needs no
/// GlobalKey/RenderBox measuring of the bar's exact on-screen rect (which
/// would also have to account for the two different bar shapes above).
class _HomeSpotlightOverlay extends StatelessWidget {
  final VoidCallback onDismiss;
  const _HomeSpotlightOverlay({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(color: Colors.black.withOpacity(0.55))
                  .animate()
                  .fadeIn(duration: 300.ms),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: GestureDetector(
                  // Swallows the tap so pressing the card's own text can't
                  // also register as the scrim's dismiss-on-tap-anywhere —
                  // "Got it" below is the one deliberate dismiss action;
                  // everywhere else is the quick "never mind, I get it".
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                    decoration: BoxDecoration(
                      color: gp.surfaceHigh,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: GameColors.gold.withOpacity(0.4)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.explore_rounded,
                            size: 26, color: GameColors.gold),
                        const SizedBox(height: 10),
                        Text(
                          s.homeSpotlightBody,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                            color: gp.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: onDismiss,
                            style: FilledButton.styleFrom(
                              backgroundColor: GameColors.gold,
                              foregroundColor: Colors.black,
                              minimumSize: const Size(double.infinity, 46),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              s.homeSpotlightGotIt,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                      .animate(delay: 150.ms)
                      .fadeIn(duration: 350.ms)
                      .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
