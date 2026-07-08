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

const _kRoutes = ['/grid', '/dashboard', '/focus', '/profile'];

class GameNavBar extends StatelessWidget {
  final int currentIndex;
  const GameNavBar({super.key, required this.currentIndex});

  void _select(BuildContext context, int i) {
    if (i == currentIndex) return;
    HapticFeedback.selectionClick();
    Navigator.pushReplacementNamed(context, _kRoutes[i]);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = [
      _NavItem(Icons.grid_view_rounded, s.navGrid),
      _NavItem(Icons.checklist_rounded, s.navToday),
      _NavItem(Icons.center_focus_strong_rounded, s.navFocus),
      _NavItem(Icons.person_rounded, s.navProfile),
    ];

    // `defaultTargetPlatform` (rather than `dart:io`'s `Platform`) so this
    // stays safe to evaluate on web builds too — it just won't report iOS
    // there.
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;

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
    final glassColor = dark ? const Color(0xFF17251F) : Colors.white;
    final borderColor =
        dark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.85);
    final unselectedColor = dark ? Colors.white70 : Colors.black54;

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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
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
    );
  }
}
