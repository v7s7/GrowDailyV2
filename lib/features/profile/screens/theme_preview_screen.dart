import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/game_theme.dart';
import '../../../core/theme/theme_preset.dart';
import '../../dashboard/screens/dashboard_screen.dart';
import '../../focus/screens/focus_screen.dart';
import '../../grid/screens/grid_screen.dart';
import 'profile_screen.dart';

/// A read-only walkthrough of the real app in a not-yet-applied theme
/// preset — reached from the Appearance sheet's "Preview" action on any
/// preset, including locked/premium ones. Shows the actual Grid/Today/
/// Focus/Profile screens (so the preview is honest, not a mockup): swipe
/// between them, but nothing inside responds to a tap. Closing (the X, the
/// system back gesture, or the iOS edge-swipe) always restores whatever
/// preset was actually applied before entering and never persists
/// anything, so this can never leave the app stuck on a preset the user
/// was only trying out — including one they haven't bought.
class ThemePreviewScreen extends ConsumerStatefulWidget {
  final ThemePreset preset;
  const ThemePreviewScreen({super.key, required this.preset});

  @override
  ConsumerState<ThemePreviewScreen> createState() =>
      _ThemePreviewScreenState();
}

class _ThemePreviewScreenState extends ConsumerState<ThemePreviewScreen> {
  late final String _originalPresetId;
  late final PageController _pageController;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _originalPresetId = ref.read(themePresetProvider);
    _pageController = PageController();
    // Swap the live palette *before* the first frame — every screen below
    // is a fresh widget instance built inside this route, not one already
    // on screen elsewhere, so it simply renders in the previewed colors
    // from its very first build. No app-wide rebuild needed, and — unlike
    // ThemePresetNotifier.set() — this never touches themePresetProvider's
    // state or Hive, so it's purely visual and fully reversible.
    GameColors.applyPreset(widget.preset);
  }

  @override
  void dispose() {
    // Restore exactly what was actually applied. Backgrounding or killing
    // the app mid-preview can't strand it here, since nothing above was
    // ever persisted in the first place.
    GameColors.applyPreset(ThemePresets.byId(_originalPresetId));
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    final name = s.isAr ? widget.preset.nameAr : widget.preset.nameEn;

    return Scaffold(
      backgroundColor: gp.bg,
      body: Stack(
        children: [
          // The PageView itself keeps its own drag/swipe gesture; only each
          // page's *content* is wrapped in IgnorePointer, so swiping still
          // works but nothing inside a page — habit checkboxes, the add
          // FAB, the screen's own embedded nav bar, anything — responds to
          // a tap.
          PageView(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _pageIndex = i),
            children: const [
              IgnorePointer(child: GridScreen()),
              IgnorePointer(child: DashboardScreen()),
              IgnorePointer(child: FocusScreen()),
              IgnorePointer(child: ProfileScreen()),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: gp.surfaceHigh,
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(color: gp.border, width: 0.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.18),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.visibility_rounded,
                                    size: 16, color: GameColors.gold),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    s.previewingTheme(name),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: gp.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // The one live control in the whole screen — every
                        // other pixel here is look-only.
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: gp.surfaceHigh,
                              shape: BoxShape.circle,
                              border: Border.all(color: gp.border, width: 0.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.18),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: Icon(Icons.close_rounded,
                                size: 20, color: gp.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Page dots — purely informational, not interactive
                    // (swipe is the only way to move between pages here).
                    IgnorePointer(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(4, (i) {
                          final active = i == _pageIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: active ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: active
                                  ? GameColors.gold
                                  : gp.textTert.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
