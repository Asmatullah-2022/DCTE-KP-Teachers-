import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../routing/app_router.dart';

/// Bottom navigation shell: Home, Curriculum, Updates, Search, More.
class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _tabs = [
    (Routes.home, Icons.home_outlined, Icons.home, 'Home'),
    (Routes.curriculum, Icons.menu_book_outlined, Icons.menu_book, 'Curriculum'),
    (Routes.notifications, Icons.notifications_outlined, Icons.notifications, 'Updates'),
    (Routes.search, Icons.search_outlined, Icons.search, 'Search'),
    (Routes.settings, Icons.more_horiz, Icons.more_horiz, 'More'),
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    for (var i = 0; i < _tabs.length; i++) {
      if (location == _tabs[i].$1 || (i == 0 && location == '/')) return i;
      if (i != 0 && location.startsWith(_tabs[i].$1)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final index = _currentIndex(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_tabs[i].$1),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(icon: Icon(tab.$2), selectedIcon: Icon(tab.$3), label: tab.$4),
        ],
      ),
    );
  }
}
