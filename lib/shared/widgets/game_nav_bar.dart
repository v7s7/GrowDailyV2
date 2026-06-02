import 'package:flutter/material.dart';

class GameNavBar extends StatelessWidget {
  final int currentIndex;
  const GameNavBar({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: (i) {
        if (i == currentIndex) return;
        Navigator.pushReplacementNamed(
          context,
          i == 0 ? '/' : '/matrix',
        );
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
    );
  }
}
