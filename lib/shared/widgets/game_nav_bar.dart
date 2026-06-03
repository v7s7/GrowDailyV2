import 'package:flutter/material.dart';

import '../../core/theme/game_theme.dart';

class GameNavBar extends StatelessWidget {
  final int currentIndex;
  const GameNavBar({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final gp = context.gp;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: gp.divider, width: 0.5)),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) {
          if (i == currentIndex) return;
          Navigator.pushReplacementNamed(
              context, i == 0 ? '/dashboard' : '/matrix');
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Matrix',
          ),
        ],
      ),
    );
  }
}
