import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';
import 'nav_tabs.dart';

class _NavItem {
  final IconData icon;
  final String label;
  final NavBadge? badge;
  const _NavItem(this.icon, this.label, this.badge);
}

// The three original tabs still answer to their old named routes (see
// main.dart's onGenerateRoute), which is all the standalone fallback in
// _select below needs. Order in the bar is whatever [GameNavBar.tabs] says:
// the default reads Habits→Profile→Tasks in English and, because the bar
// mirrors for RTL locales, Tasks→Profile→Habits in Arabic. A Premium
// account can reorder that and grow it to five (see NavBarSettingsScreen);
// HomeShell passes the live layout in.
const _kLegacyRoutes = {
  NavTab.grid: '/grid',
  NavTab.profile: '/profile',
  NavTab.matrix: '/matrix',
};

class GameNavBar extends StatelessWidget {
  final int currentIndex;

  /// The tabs to draw, in order. Defaults to [kDefaultNavTabs] so a bar
  /// pumped on its own (the theme and text-scale tests, the customiser's
  /// preview) needs no provider; HomeShell always passes the account's
  /// layout.
  final List<NavTab> tabs;

  /// Marks per tab (see [NavBadge]); tabs absent from the map draw none.
  /// HomeShell passes navBadgesProvider's map; a bar on its own draws
  /// nothing, which is also what the customiser's preview wants.
  final Map<NavTab, NavBadge> badges;

  /// When set, tab taps call this instead of navigating routes — HomeShell
  /// passes its PageView animator here so taps and swipes share one page
  /// stack. When null (a bar shown standalone, which today is only tests
  /// and the customiser's preview), a tap on one of the three original
  /// tabs keeps the old pushReplacementNamed behaviour, which lands on
  /// HomeShell anyway; any other tab has no route of its own and the tap
  /// does nothing.
  final ValueChanged<int>? onSelect;

  const GameNavBar({
    super.key,
    required this.currentIndex,
    this.tabs = kDefaultNavTabs,
    this.badges = const {},
    this.onSelect,
  });

  void _select(BuildContext context, int i) {
    if (i == currentIndex) return;
    HapticFeedback.selectionClick();
    final override = onSelect;
    if (override != null) {
      override(i);
      return;
    }
    final route = _kLegacyRoutes[tabs[i]];
    if (route != null) Navigator.pushReplacementNamed(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = [
      for (final tab in tabs) _NavItem(tab.icon, tab.label(s), badges[tab]),
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
    final bar = isIOS
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
    // Press and hold anywhere on the bar to rearrange it. The Settings row
    // is the documented way in; this is the one people find by themselves,
    // because holding a thing you want to move is what every home screen
    // has taught them. A tap still wins the arena on release, so nothing
    // about selecting a tab changes; only a hold past the long-press delay
    // goes here. The customiser's own preview bar sits under an
    // IgnorePointer, so it cannot open a second copy of itself.
    return GestureDetector(
      onLongPress: () => _openCustomiser(context),
      child: bar,
    );
  }

  void _openCustomiser(BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pushNamed('/nav-bar');
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
      // No tooltips. The label is always drawn under the icon, so the
      // tooltip only repeated it, and its long-press recogniser sat deeper
      // in the tree than GameNavBar's press-and-hold, so it won the arena
      // and the customiser was unreachable that way on Android. An empty
      // `tooltip` string is not enough on this Flutter: NavigationBar wraps
      // every destination in a Tooltip regardless, and Tooltip only skips
      // its gesture handling when TooltipVisibility says it is not visible.
      child: TooltipVisibility(
        visible: false,
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: onSelect,
          destinations: [
            for (final item in items)
              NavigationDestination(
                icon: _materialIcon(context, item),
                label: item.label,
              ),
          ],
        ),
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

class _GlassNavItem extends StatefulWidget {
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
  State<_GlassNavItem> createState() => _GlassNavItemState();
}

/// Stateful for one reason: the pill and the ink have to move together.
///
/// The pill was already an AnimatedContainer, but the icon colour, the label
/// colour and the label's weight all snapped on the same tap. Switching tabs
/// therefore looked like two events — a pill that eased over 160ms and a
/// letterform that changed instantly — which reads as a glitch rather than
/// as a transition.
///
/// One controller drives all three, so there is a single source of truth for
/// "how selected is this tab right now", and nothing can drift. An explicit
/// controller rather than TweenAnimationBuilder because that one animates
/// from its tween's begin on FIRST build, so every tab would have faded in
/// on launch; `value:` seeds this one at its resting position instead.
class _GlassNavItemState extends State<_GlassNavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: GameMotion.quick,
    value: widget.selected ? 1 : 0,
  );
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);

  @override
  void didUpdateWidget(covariant _GlassNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      widget.selected ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ink, not the raw accent. This bar is a custom widget, so it never
    // read navigationBarTheme and the theme's own light-mode fix could not
    // reach it: the selected tab measured 2.24:1 on the light background,
    // on the one control that is on screen for the whole session.
    final selectedColor = context.gp.goldInk;
    final item = widget.item;
    final selected = widget.selected;
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
          onTap: widget.onTap,
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, child) {
              final t = _t.value;
              // One value, three properties. The pill's own fill is driven
              // from it too rather than from `selected`, so the wash, the
              // ink and the weight cannot come apart mid-transition.
              final color =
                  Color.lerp(widget.unselectedColor, selectedColor, t)!;
              return Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
          decoration: BoxDecoration(
            color: GameColors.gold.withValues(alpha: 0.16 * t),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _GlassBadgedIcon(item: item, color: color),
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
                // the bar to a third of the screen, and a Premium bar can hold
                // five (kNavTabsMax), which is why that cap is what it is.
                textScaler: MediaQuery.textScalerOf(context)
                    .clamp(maxScaleFactor: 1.4),
                style: TextStyle(
                  fontSize: 10,
                  // Lerped, not switched. FontWeight.lerp still lands on
                  // whole weights, but it steps through them over the same
                  // 160ms as the wash instead of jumping on the tap frame.
                  fontWeight:
                      FontWeight.lerp(FontWeight.w500, FontWeight.w700, t),
                  color: color,
                ),
              ),
              ],
            ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Material's own Badge in the app's colours, so the Android bar says the
/// same thing as the glass bar in its platform's native voice.
Widget _materialIcon(BuildContext context, _NavItem item) {
  final badge = item.badge;
  final icon = Icon(item.icon);
  if (badge == null || badge.isEmpty) return icon;
  if (badge.dot) {
    return Badge(
      smallSize: 7,
      backgroundColor: context.gp.iconXp,
      child: icon,
    );
  }
  return Badge.count(
    count: badge.count,
    backgroundColor: GameColors.gold,
    textColor: GameColors.onGold,
    child: icon,
  );
}

/// The glass bar's icon with its badge hung off the top-end corner: a gold
/// count pill, or the small blue dot the Night Review prompt card already
/// uses for "tonight is still open". Directional, so in Arabic the mark
/// sits top-left, which is where an RTL eye expects a trailing mark.
class _GlassBadgedIcon extends StatelessWidget {
  final _NavItem item;
  final Color color;
  const _GlassBadgedIcon({required this.item, required this.color});

  @override
  Widget build(BuildContext context) {
    final icon = Icon(item.icon, size: 22, color: color);
    final badge = item.badge;
    if (badge == null || badge.isEmpty) return icon;
    final Widget mark = badge.dot
        ? Semantics(
            label: S.of(context).navBadgeReviewPending,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: context.gp.iconXp,
                shape: BoxShape.circle,
              ),
            ),
          )
        : Container(
            constraints: const BoxConstraints(minWidth: 15),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: GameColors.gold,
              borderRadius: BorderRadius.circular(GameSpacing.pillRadius),
            ),
            child: Text(
              badge.count > 99 ? '99+' : '${badge.count}',
              textAlign: TextAlign.center,
              // Never scales. At 3.1x a 9pt count becomes a 28pt blob over
              // a 22pt icon; the icon and the label carry the meaning at
              // any size, and the number is read aloud regardless (it is
              // plain text inside the tab's own Semantics container).
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: GameColors.onGold,
                height: 1.2,
              ),
            ),
          );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        PositionedDirectional(
          top: badge.dot ? -2 : -6,
          end: badge.dot ? -4 : -10,
          child: mark,
        ),
      ],
    );
  }
}
