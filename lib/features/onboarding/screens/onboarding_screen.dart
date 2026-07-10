import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/onboarding_provider.dart';
import '../../../core/theme/game_theme.dart';

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String body;
  const _OnboardingPage(this.icon, this.title, this.body);
}

/// Shown once per device, right after language + auth/guest are settled
/// (see `_AuthGate` in main.dart) and before the very first Grid screen —
/// three short pages explaining the core loop, since a brand-new user
/// otherwise lands cold on a grid of empty squares with no context for what
/// they mean. Finishing (or skipping) marks [onboardingSeenProvider] true,
/// which is what actually reveals the Grid — this screen doesn't navigate
/// anywhere itself.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next(int pageCount) {
    HapticFeedback.selectionClick();
    if (_page == pageCount - 1) {
      markOnboardingSeen(ref);
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final pages = [
      _OnboardingPage(
          Icons.grid_view_rounded, s.onboardingGridTitle, s.onboardingGridBody),
      _OnboardingPage(Icons.bolt_rounded, s.onboardingHabitsTitle,
          s.onboardingHabitsBody),
      _OnboardingPage(Icons.view_quilt_rounded, s.onboardingTasksTitle,
          s.onboardingTasksBody),
    ];
    final isLast = _page == pages.length - 1;

    return Scaffold(
      backgroundColor: gp.bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                child: Opacity(
                  opacity: isLast ? 0 : 1,
                  child: TextButton(
                    onPressed:
                        isLast ? null : () => markOnboardingSeen(ref),
                    child: Text(s.onboardingSkip,
                        style: TextStyle(color: gp.textTert, fontSize: 13)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final page = pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: GameColors.gold.withOpacity(0.12),
                            shape: BoxShape.circle,
                          ),
                          child:
                              Icon(page.icon, size: 44, color: GameColors.gold),
                        )
                            .animate(key: ValueKey('icon-$i'))
                            .fadeIn(duration: 400.ms)
                            .scale(
                              begin: const Offset(0.7, 0.7),
                              end: const Offset(1, 1),
                              curve: Curves.easeOutBack,
                              duration: 450.ms,
                            ),
                        const SizedBox(height: 28),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: gp.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        )
                            .animate(key: ValueKey('title-$i'), delay: 100.ms)
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),
                        const SizedBox(height: 12),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: gp.textSec,
                          ),
                        )
                            .animate(key: ValueKey('body-$i'), delay: 180.ms)
                            .fadeIn(duration: 400.ms)
                            .slideY(begin: 0.15, end: 0, curve: Curves.easeOut),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                pages.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? GameColors.gold
                        : gp.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: GameColors.gold,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => _next(pages.length),
                child: Text(
                  isLast ? s.onboardingGetStarted : s.onboardingNext,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
