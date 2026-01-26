import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/user.dart';
import '../../../roster/domain/entities/service_roster.dart';
import '../providers/auth_provider.dart';
import '../providers/group_settings_provider.dart';
import 'user_editor_screen.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  late Future<List<User>> _usersFuture;
  String _nameFilter = '';

  @override
  void initState() {
    super.initState();
    _refreshUsers();
  }

  void _refreshUsers() {
    setState(() {
      _usersFuture = context.read<AuthProvider>().getUsers();
    });
  }

  Future<void> _openEditor([User? user]) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final width = size.width < 640 ? size.width - 32 : 600.0;
        final height = size.height < 720 ? size.height - 32 : 700.0;
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: width,
            height: height,
            child: UserEditorScreen(user: user, isDialog: true),
          ),
        );
      },
    );
    _refreshUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('帳號管理'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<User>>(
        future: _usersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final users = snapshot.data ?? [];
          final filter = _nameFilter.trim().toLowerCase();
          final filteredUsers = filter.isEmpty
              ? users
              : users.where((user) => user.name.toLowerCase().contains(filter)).toList();
          final groupTemplates = context.watch<GroupSettingsProvider>().templates;
          final sortedUsers = List<User>.from(filteredUsers)
            ..sort((a, b) {
              UserZoneInfo? primaryZone(User user) {
                if (user.zones.isEmpty) return null;
                final zones = List<UserZoneInfo>.from(user.zones)
                  ..sort((z1, z2) => ServiceType.values
                      .indexOf(z1.serviceType)
                      .compareTo(ServiceType.values.indexOf(z2.serviceType)));
                return zones.first;
              }

              int roleIndex(User user) {
                return UserRole.values.indexOf(user.role);
              }

              int zoneIndex(User user) {
                final zone = primaryZone(user);
                if (zone == null) return 999;
                return ServiceType.values.indexOf(zone.serviceType);
              }

              int groupIndex(User user) {
                final zone = primaryZone(user);
                if (zone == null || zone.smallGroups.isEmpty) return 999;
                final groupOrder = groupTemplates[zone.serviceType] ?? const <String>[];
                final groupName = zone.smallGroups.first;
                final index = groupOrder.indexOf(groupName);
                return index == -1 ? 999 : index;
              }

              final roleCompare = roleIndex(a).compareTo(roleIndex(b));
              if (roleCompare != 0) return roleCompare;

              final zoneCompare = zoneIndex(a).compareTo(zoneIndex(b));
              if (zoneCompare != 0) return zoneCompare;

              final groupCompare = groupIndex(a).compareTo(groupIndex(b));
              if (groupCompare != 0) return groupCompare;

              return a.name.compareTo(b.name);
            });

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: '搜尋姓名',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _nameFilter = value),
                ),
              ),
              Expanded(
                child: sortedUsers.isEmpty
                    ? const Center(child: Text('沒有符合的帳號'))
                    : ListView.builder(
                        itemCount: sortedUsers.length,
                        itemBuilder: (context, index) {
                          final user = sortedUsers[index];
                          final zoneText = user.zones.map((z) => z.serviceType.label).join(', ');

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(user.name[0]),
                              ),
                              title: Text(
                                user.username.isEmpty
                                    ? '${user.name}（無帳號）'
                                    : '${user.name} (@${user.username})',
                              ),
                              subtitle: Text(
                                '${user.role.label} ${zoneText.isNotEmpty ? ' | $zoneText' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _openEditor(user),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('確認刪除'),
                                      content: Text('確定要刪除 ${user.name} 嗎？'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('取消'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('刪除',
                                              style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true && mounted) {
                                    await context.read<AuthProvider>().deleteUser(user.id);
                                    _refreshUsers();
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
