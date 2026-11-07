import 'package:flutter/material.dart';

/// One destination in an [AppTabBar].
@immutable
class AppTabDestination {
  /// Creates a destination.
  const new({required this.icon, required this.label});

  /// Icon shown for the destination.
  final IconData icon;

  /// Text label, also used as the accessibility label.
  final String label;
}

/// Bottom tab bar with a solid surface.
class AppTabBar extends StatelessWidget {
  /// Creates a tab bar.
  const new({
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  /// Tabs to show, in order. Needs at least two.
  final List<AppTabDestination> destinations;

  /// Index of the selected tab.
  final int currentIndex;

  /// Called with the index of the tapped tab.
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onSelected,
      destinations: [
        for (final d in destinations)
          NavigationDestination(icon: Icon(d.icon), label: d.label),
      ],
    );
  }
}
