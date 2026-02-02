import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'user_management_screen.dart' deferred as user_management_screen;
import 'group_settings_screen.dart' deferred as group_settings_screen;

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _loadAndPush(
    BuildContext context,
    Future<void> Function() loadLibrary,
    Widget Function() builder,
  ) async {
    var dialogShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await loadLibrary();
      if (!context.mounted) return;
      if (dialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => builder()),
      );
    } catch (error) {
      if (context.mounted) {
        if (dialogShown) {
          Navigator.of(context, rootNavigator: true).pop();
          dialogShown = false;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入失敗: $error')),
        );
      }
    } finally {
      if (dialogShown && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;

    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('個人中心'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // User Info Header
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  child: Text(
                    user.name[0],
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  user.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  '@${user.username}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                const SizedBox(height: 8),
                Chip(
                  label: Text(user.role.label),
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Admin Actions
          if (authProvider.isAdmin) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.manage_accounts),
              title: const Text('帳號管理'),
              subtitle: const Text('新增、刪除或修改同工權限'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _loadAndPush(
                context,
                user_management_screen.loadLibrary,
                () => user_management_screen.UserManagementScreen(),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.groups),
              title: const Text('小組管理'),
              subtitle: const Text('設定各牧區小組清單'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _loadAndPush(
                context,
                group_settings_screen.loadLibrary,
                () => group_settings_screen.GroupSettingsScreen(),
              ),
            ),
          ],

          const Divider(),
          
          // Logout Button
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('登出', style: TextStyle(color: Colors.red)),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('登出確認'),
                  content: const Text('確定要登出嗎？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('登出', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await authProvider.logout();
              }
            },
          ),
        ],
      ),
    );
  }
}
