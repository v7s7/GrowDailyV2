import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

// "Today" is retired from bottom-nav (Grid is the app's home screen and
// already covers day-to-day habit completion) — three peer tabs now,
// not four. Order here is logical/code order; the nav bar itself mirrors
// for RTL locales same as before, so this reads Grid→Profile→Matrix in
// English and Matrix→Profile→Grid in Arabic.
const _kRoutes = ['/grid', '/profile', '/matrix'];

class GameNavBar extends StatelessWidget {
  final int currentIndex;

  /// When set, tab taps call this instead of navigating routes — HomeShell
  /// passes its PageView animator here so taps and swipes share one page
  /// stack. When null (any screen still using the bar standalone, e.g.
  /// Today), taps keep the original pushReplacementNamed behavior, which
  /// now lands on HomeShell anyway.
  final ValueChanged<int>? onSelect;

  const GameNavBar({super.key, required this.currentIndex, this.onSelect});

  void _select(BuildContext context, int i) {
    if (i == currentIndex) return;
    HapticFeedback.selectionClick();
    final override = onSelect;
    if (override != null) {
      override(i);
      return;
    }
    Navigator.pushReplacementNamed(context, _kRoutes[i]);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = [
      _NavItem(Icons.grid_view_rounded, s.navGrid),
      _NavItem(Icons.person_rounded, s.navProfile),
      _NavItem(Icons.view_quilt_rounded, s.navMatrix),
    ];

    // `defaultTargetPlatform` (rather than `dart:io`'s `Platform`) so this
    // stays safe to evaluate on web builds too — it just won't report iOS
    // there.
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;

    // The floating voice-note player used to live here, docked above
    // whichever of these two bars was on screen. It's now a single
    // GlobalVoiceNotePlayerOverlay mounted once in main.dart's
    // MaterialApp.builder instead — see that widget's doc comment for why:
    // a modal sheet or pushed route sits in the same Navigator as this bar
    // and paints over the whole screen (bar included), so anything docked
    // in here would go invisible the moment one opened even though
    // playback kept going. Nothing else about this bar changes.
    return isIOS
        ? _GlassNavBar(
            currentIndex: currentIndex,
            items: items,
            onSelect: (i) => _select(context, i),
          )
        : _MaterialNavBar(
            currentIndex: currentIndex,
            items: items,
            onSelect: (i) => _select(context, i),
          );
  }
}

/// The "normal" nav bar — Material 3's `NavigationBar`, themed in
/// [GameTheme]. Used on Android and anywhere else that isn't iOS.
class _MaterialNavBar extends StatelessWidget {
  final int currentIndex;
  final List<_NavItem> items;
  final ValueChanged<int> onSelect;

  const _MaterialNavBar({
    required this.currentIndex,
    required this.items,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: gp.divider, width: 0.5)),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: onSelect,
        destinations: [
          for (final item in items)
            NavigationDestination(icon: Icon(item.icon), label: item.label),
        ],
      ),
    );
  }
}

/// The "new iOS style" nav bar — a floating, frosted-glass pill inset from
/// the screen edges, in the spirit of iOS's recent Liquid-Glass redesign.
class _GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final List<_NavItem> items;
  final ValueChanged<int> onSelect;

  const _GlassNavBar({
    required this.currentIndex,
    required this.items,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Was a hardcoded 0xFF17251F, which is the DEFAULT preset's elevated
    // surface — so the nav bar stayed emerald-green under all eleven presets
    // while every other surface changed around it. Nobody noticed because
    // most presets are close enough to the default in the dark; the custom
    // preset, which can put the app in plum or navy, made it obvious.
    // In LIGHT mode this used gp.surfaceHigh, which is #FFFFFF in all eleven
    // presets and in both custom ones. Every other light token shifts hue with
    // the theme (bg, surface, highlight, border all do), but the "high"
    // surface is pinned to pure white on purpose, because that is what an
    // elevated card should be. The nav bar is not a card. Reading that token
    // made the bar the one surface in the app that could not take the theme:
    // pick plum, pick navy, and the bar stayed white.
    //
    // gp.surface instead, which is the same tone the cards on the page behind
    // it already use: #F5EFE3 by default, #F0E3F5 in a plum custom theme,
    // #E3E8F5 in navy. Dark mode keeps surfaceHigh, which was already themed
    // (#17251F emerald, #171F25 plum) and correct.
    final glassColor = dark ? context.gp.surfaceHigh : context.gp.surface;
    // Both of these were hardcoded white and black54, so even once the fill
    // above followed the theme they would still have sat on top of it in
    // neutral grey. The rim in particular was 85 percent white, which is a
    // bright ring around a tinted bar rather than an edge of it.
    final borderColor =
        dark ? Colors.white.withOpacity(0.08) : context.gp.border;
    // textPrimary at 0.70, not textSec, and the number is measured. On the
    // newly tinted fills above, textSec lands between 4.00 and 4.46 to 1
    // across the thirteen presets, which is under the 4.5 AA needs for a 10pt
    // label. Compositing textPrimary at 0.70 gives 5.28 at worst and still
    // reads as clearly secondary next to the selected tab, which carries the
    // accent colour, a heavier weight and a filled pill of its own.
    final unselectedColor = context.gp.textPrimary.withOpacity(0.70);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              // Fixed, and it has to stay fixed.
              //
              // The overflow this box used to produce at the largest
              // accessibility text size (a 22pt icon, a 2pt gap and a 10pt
              // label against 48pt of content space, overflowing by 23) is
              // fixed by capping the LABEL's scale in _GlassNavItem below,
              // not by relaxing this.
              //
              // Relaxing it was tried and was worse: `constraints:
              // BoxConstraints(minHeight: 60)` has no maximum, and
              // Scaffold.bottomNavigationBar hands down loose constraints, so
              // the Container took the whole screen height and the app came
              // up as a blank page with a full-height nav bar. Caught on a
              // device, not by the test, because a test that pumps this bar
              // in an otherwise empty Scaffold has nothing for it to crowd
              // out. See nav_bar_text_scale_test.dart, which now asserts the
              // height directly.
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: glassColor.withOpacity(0.68),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: borderColor, width: 0.75),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(dark ? 0.45 : 0.14),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    _GlassNavItem(
                      item: items[i],
                      selected: i == currentIndex,
                      unselectedColor: unselectedColor,
                      onTap: () => onSelect(i),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavItem extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final Color unselectedColor;
  final VoidCallback onTap;

  const _GlassNavItem({
    required this.item,
    required this.selected,
    required this.unselectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? GameColors.gold : unselectedColor;
    return Expanded(
      // The label is already on screen as text, so `container: true` is what
      // matters here: without it the icon and the word announced as two
      // separate nodes, and neither said which tab was current. `selected`
      // is what makes VoiceOver read "Habits, selected" rather than leaving
      // someone to guess where they are.
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
          duration: GameMotion.quick,
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
          decoration: BoxDecoration(
            color: selected ? GameColors.gold.withOpacity(0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Capped at 1.4x, measured rather than picked: the item has
                // 48pt of content space (60 less its own 6pt margins), and a
                // 22pt icon plus a 2pt gap leaves 24 for the label. At 1.6x
                // the label rendered 24.5 and the row overflowed by exactly
                // half a pixel; 1.4x lands near 19 and leaves real slack for a
                // font whose metrics differ.
                //
                // Capping at all is the right trade here and nowhere else: the
                // icon above carries the meaning at any size, and the Semantics
                // wrapper reads the label aloud regardless, so nothing is lost
                // to somebody who actually needs the larger type. Three tabs of
                // 31pt text would either ellipsis into nothing readable or push
                // the bar to a third of the screen.
                textScaler: MediaQuery.textScalerOf(context)
                    .clamp(maxScaleFactor: 1.4),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
