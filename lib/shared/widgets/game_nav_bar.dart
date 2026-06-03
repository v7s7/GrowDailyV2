import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/game_theme.dart';

class GameNavBar extends StatelessWidget {
  final int currentIndex;
  const GameNavBar({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    final s = S.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: gp.divider, width: 0.5)),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          if (i == currentIndex) return;
          HapticFeedback.selectionClick();
          Navigator.pushReplacementNamed(
            context,
            switch (i) {
              0 => '/dashboard',
              1 => '/focus',
              2 => '/matrix',
              _ => '/profile',
            },
          );
        },
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.home_rounded), label: s.navDashboard),
          NavigationDestination(
              icon: const Icon(Icons.center_focus_strong_rounded),
              label: s.navFocus),
          NavigationDestination(
              icon: const Icon(Icons.grid_view_rounded), label: s.navGoals),
          NavigationDestination(
              icon: const Icon(Icons.person_rounded), label: s.navProfile),
        ],
      ),
    );
  }
}
