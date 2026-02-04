import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../roster/domain/entities/service_roster.dart';
import '../../../roster/presentation/providers/roster_provider.dart';
import '../../../calendar/presentation/screens/calendar_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rosterProvider = context.read<RosterProvider>();
      if (rosterProvider.rosters.isEmpty && !rosterProvider.isLoading) {
        rosterProvider.fetchInitialData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _displayName(
      context.watch<AuthProvider>().currentUser?.name,
    );
    final fullName = context.watch<AuthProvider>().currentUser?.name ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('教會同工中心'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '歡迎回來，$displayName！',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildFeatureCard(
              context,
              icon: Icons.notifications_active,
              title: '最新公告',
              description: '查看教會本週重要事項',
              color: Colors.orangeAccent,
            ),
            const SizedBox(height: 16),
            _buildFeatureCard(
              context,
              icon: Icons.calendar_month,
              title: '行事曆',
              description: '教會年度活動一覽',
              color: Colors.purpleAccent,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CalendarScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            _buildSeasonServiceSection(context, fullName: fullName),
          ],
        ),
      ),
    );
  }

  String _displayName(String? fullName) {
    final name = fullName?.trim() ?? '';
    if (name.isEmpty) return '同工';

    final parts = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final hasLatin = RegExp(r'[A-Za-z]').hasMatch(name);
    if (parts.length > 1) {
      return hasLatin ? parts.first : parts.last;
    }

    if (RegExp(r'[\u4E00-\u9FFF]').hasMatch(name)) {
      return name.length > 1 ? name.substring(1) : name;
    }

    return name;
  }

  Widget _buildSeasonServiceSection(
    BuildContext context, {
    required String fullName,
  }) {
    return Consumer<RosterProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return _buildSectionCard(
            title: '本季服事',
            icon: Icons.volunteer_activism,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (provider.error != null) {
          return _buildSectionCard(
            title: '本季服事',
            icon: Icons.volunteer_activism,
            child: Text(provider.error!),
          );
        }

        final assignments = _seasonAssignments(
          rosters: provider.rosters,
          userName: fullName,
        );
        if (assignments.isEmpty) {
          final emptyText = fullName.trim().isEmpty ? '尚未登入同工資料' : '本季尚無排到服事';
          return _buildSectionCard(
            title: '本季服事',
            icon: Icons.volunteer_activism,
            child: Text(emptyText),
          );
        }

        return _buildSectionCard(
          title: '本季服事',
          icon: Icons.volunteer_activism,
          child: SizedBox(
            height: _seasonListHeight(assignments.length),
            child: Scrollbar(
              child: ListView.separated(
                itemCount: assignments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final assignment = assignments[index];
                  final dateText = DateFormat(
                    'MM/dd (E)',
                    'zh_TW',
                  ).format(assignment.roster.date);
                  final roleText = assignment.roles.join('、');
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          dateText,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              assignment.roster.serviceName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(roleText),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  double _seasonListHeight(int itemCount) {
    const maxVisibleItems = 3;
    const rowHeight = 48.0;
    const separatorHeight = 8.0;
    final visibleCount = itemCount < maxVisibleItems
        ? itemCount
        : maxVisibleItems;
    if (visibleCount <= 0) return 0;
    return (visibleCount * rowHeight) + ((visibleCount - 1) * separatorHeight);
  }

  List<_UserServiceAssignment> _seasonAssignments({
    required List<ServiceRoster> rosters,
    required String userName,
  }) {
    final normalizedName = _normalizeName(userName);
    if (normalizedName.isEmpty) return [];

    final List<_UserServiceAssignment> results = [];
    final now = DateTime.now();
    final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    final quarterStart = DateTime(now.year, quarterStartMonth, 1);
    final quarterEnd = DateTime(now.year, quarterStartMonth + 3, 0);
    final sorted = List<ServiceRoster>.from(rosters)
      ..sort((a, b) => a.date.compareTo(b.date));

    for (final roster in sorted) {
      if (roster.date.isBefore(quarterStart) ||
          roster.date.isAfter(quarterEnd)) {
        continue;
      }
      final roles = roster.duties
          .where(
            (duty) => duty.people.any(
              (person) => _normalizeName(person) == normalizedName,
            ),
          )
          .map((duty) => duty.role)
          .toList();
      if (roles.isEmpty) continue;
      results.add(_UserServiceAssignment(roster: roster, roles: roles));
    }

    return results;
  }

  String _normalizeName(String name) {
    return name.trim().toLowerCase();
  }

  Widget _buildSectionCard({
    required String title,
    required Widget child,
    IconData? icon,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(description),
        onTap:
            onTap ??
            () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('此功能即將推出！')));
            },
      ),
    );
  }
}

class _UserServiceAssignment {
  final ServiceRoster roster;
  final List<String> roles;

  const _UserServiceAssignment({required this.roster, required this.roles});
}
