import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/push_notification_service.dart';
import '../providers/auth_provider.dart';
import 'user_management_screen.dart' deferred as user_management_screen;
import 'group_settings_screen.dart' deferred as group_settings_screen;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _statusUserId;
  bool _isPushEnabled = false;
  bool _isPushLoading = false;

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
      Navigator.push(context, MaterialPageRoute(builder: (_) => builder()));
    } catch (error) {
      if (context.mounted) {
        if (dialogShown) {
          Navigator.of(context, rootNavigator: true).pop();
          dialogShown = false;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('載入失敗: $error')));
      }
    } finally {
      if (dialogShown && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.read<AuthProvider>().currentUser?.id;
    if (_statusUserId == userId) return;
    _statusUserId = userId;
    _refreshPushStatus();
  }

  Future<void> _refreshPushStatus() async {
    final userId = _statusUserId;
    if (userId == null) return;
    setState(() => _isPushLoading = true);
    try {
      final pushService = context.read<PushNotificationService>();
      final enabled = await pushService.isNotificationEnabledForUser(userId);
      if (!mounted || _statusUserId != userId) return;
      setState(() => _isPushEnabled = enabled);
    } catch (_) {
      if (!mounted || _statusUserId != userId) return;
      setState(() => _isPushEnabled = false);
    } finally {
      if (mounted && _statusUserId == userId) {
        setState(() => _isPushLoading = false);
      }
    }
  }

  Future<void> _togglePush(bool value) async {
    final userId = context.read<AuthProvider>().currentUser?.id;
    if (userId == null) return;
    setState(() => _isPushLoading = true);
    try {
      final pushService = context.read<PushNotificationService>();
      final result = await pushService.setNotificationEnabled(
        userId: userId,
        enabled: value,
      );
      final enabled = result.enabled;
      if (!mounted) return;
      setState(() => _isPushEnabled = enabled);
      if (value && !enabled) {
        final reasonMessage = switch (result.failureReason) {
          PushToggleFailureReason.missingVapidKey => '系統設定缺少推播金鑰，請聯絡管理員。',
          PushToggleFailureReason.permissionDenied => '通知權限未開啟，請到 iPhone 設定允許此 App 通知。',
          PushToggleFailureReason.tokenUnavailable => '目前裝置無法取得推播識別碼，請重新開啟 App 後再試。',
          PushToggleFailureReason.saveTokenFailed => '已取得識別碼，但儲存失敗，請稍後再試。',
          PushToggleFailureReason.savePreferenceFailed => '通知偏好儲存失敗，請稍後再試。',
          PushToggleFailureReason.notInitialized => '推播服務尚未初始化完成，請重整後再試。',
          PushToggleFailureReason.notWeb => '目前環境不支援網頁推播。',
          null => '通知未啟用，請確認瀏覽器通知權限設定。',
        };
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(reasonMessage)));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新通知設定失敗: $error')));
    } finally {
      if (mounted) {
        setState(() => _isPushLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;

    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(title: const Text('個人中心')),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Chip(
                  label: Text(user.role.label),
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
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

          SwitchListTile(
            secondary: const Icon(Icons.notifications_active),
            title: const Text('服事提醒'),
            subtitle: const Text('每週一晚間發送提醒'),
            value: _isPushEnabled,
            onChanged: _isPushLoading ? null : _togglePush,
          ),

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
                      child: const Text(
                        '登出',
                        style: TextStyle(color: Colors.red),
                      ),
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
