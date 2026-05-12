import 'package:flutter/material.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/roster/presentation/screens/roster_screen.dart';
import '../../features/auth/presentation/screens/profile_screen.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;

  // Lazy tabs: only build a tab the first time the user visits it. Otherwise
  // every tab's initState fires on app launch (Profile's push status query,
  // Roster's roster fetch, etc.) — wasted work and Firestore reads when the
  // user only opens the dashboard.
  final Set<int> _visitedIndices = {0};

  static const List<Widget> _screens = [
    DashboardScreen(),
    RosterScreen(),
    ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _visitedIndices.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: List<Widget>.generate(_screens.length, (i) {
          // Once visited, the screen stays in the tree so its state survives
          // tab switches.
          return _visitedIndices.contains(i)
              ? _screens[i]
              : const SizedBox.shrink();
        }),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首頁',
          ),
          NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: '服事表',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}