import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/text_warmup.dart';
import '../../features/roster/presentation/providers/roster_provider.dart';
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
    // 服事表資料一到就把會顯示的字串預熱掉，讓字型與排版快取在使用者開始捲
    // 之前就備妥。provider 有快取，資料沒變時 identity 不變，不會重複觸發。
    final warmupStrings = context.select<RosterProvider, List<String>>(
      (provider) => provider.displayStrings,
    );

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: List<Widget>.generate(_screens.length, (i) {
              // Once visited, the screen stays in the tree so its state
              // survives tab switches.
              return _visitedIndices.contains(i)
                  ? _screens[i]
                  : const SizedBox.shrink();
            }),
          ),
          TextWarmup(strings: warmupStrings),
        ],
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
