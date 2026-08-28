import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/services/app_version_service.dart';
import '../../../../core/services/push_notification_service.dart';
import '../../../../core/utils/error_messages.dart';
import '../../domain/entities/user.dart';
import '../providers/session_provider.dart';
import 'user_management_screen.dart' deferred as user_management_screen;
import 'group_settings_screen.dart' deferred as group_settings_screen;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.updateService = const AppUpdateService(),
  });

  /// 注入點只是為了測試 —— 正式環境永遠是預設那個。
  final AppUpdateService updateService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const AppVersionService _appVersionService = AppVersionService();

  String? _statusUserId;
  bool _isPushEnabled = false;
  bool _isPushLoading = false;
  bool _isCheckingUpdate = false;
  late final Future<AppVersionInfo?> _versionInfoFuture = _appVersionService
      .fetchVersionInfo();

  /// 「檢查更新」。
  ///
  /// 找到新版的話 `web/app_update.js` 會把頁面重載，所以那條路徑上這裡什麼都
  /// 不用收尾 —— 連 setState 都不必，widget 馬上就不在了。
  Future<void> _checkForUpdate() async {
    setState(() => _isCheckingUpdate = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await widget.updateService.checkForUpdate();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result == AppUpdateResult.updating ? '找到新版本，正在更新…' : '已經是最新版本',
          ),
        ),
      );
    } catch (error, st) {
      log('檢查更新失敗', error: error, stackTrace: st);
      if (!mounted) return;
      // 這個按鈕存在的理由就是使用者已經不相信畫面上的版本了，失敗要說出來，
      // 不能讓它看起來像「檢查過了，沒事」。
      messenger.showSnackBar(
        SnackBar(content: Text('檢查更新失敗：${mapErrorToUserMessage(error)}')),
      );
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

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
    } catch (error, st) {
      log('載入畫面失敗', error: error, stackTrace: st);
      if (context.mounted) {
        if (dialogShown) {
          Navigator.of(context, rootNavigator: true).pop();
          dialogShown = false;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入失敗：${mapErrorToUserMessage(error)}')),
        );
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
    final userId = context.read<SessionProvider>().currentUser?.id;
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
    final userId = context.read<SessionProvider>().currentUser?.id;
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
          PushToggleFailureReason.permissionDenied =>
            '通知權限未開啟，請到 iPhone 設定允許此 App 通知。',
          PushToggleFailureReason.tokenUnavailable =>
            '目前裝置無法取得推播識別碼，請重新開啟 App 後再試。',
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
    } catch (error, st) {
      log('更新通知設定失敗', error: error, stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('更新通知設定失敗：${mapErrorToUserMessage(error)}')),
      );
    } finally {
      if (mounted) {
        setState(() => _isPushLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final user = session.currentUser;

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
                    _avatarLetter(user.name),
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
                // 角色是身分，group 是編輯權限 —— 兩種不同的東西，所以用不同
                // 的底色，而不是排成一串看起來同質的標籤。
                //
                // 管理員不列 group：他隱含全部，逐項列出反而像是「被指定了這
                // 幾項」，看起來比實際權限還小。Wrap 是為了窄螢幕會換行而不是
                // 擠成一行溢出。
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    Chip(
                      label: Text(user.role.label),
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                    ),
                    if (!user.isAdmin)
                      for (final group in UserGroup.values)
                        if (user.groups.contains(group))
                          Chip(
                            label: Text(group.label),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                          ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Admin Actions
          if (session.isAdmin) ...[
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

              if (confirm != true) return;
              await session.logout();
              // 登出失敗時 session 會被保留（避免假登出），所以錯誤要在這裡
              // 講清楚，否則使用者以為登出成功、畫面卻沒有變化。
              final logoutError = session.error;
              if (logoutError == null) return;
              session.clearError();
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(logoutError)));
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8),
            child: FutureBuilder<AppVersionInfo?>(
              future: _versionInfoFuture,
              builder: (context, snapshot) {
                final info = snapshot.data;
                // 頁尾的版本資訊。刻意都用同一個灰色小字：這裡是註腳，不是
                // 功能入口 —— 平常載入與切回前景都會自己檢查更新，按鈕只是給
                // 「我看起來還是舊版」的人一個不必被叫去滑掉 App 的出口。
                // 一顆正常的 TextButton（主色、按鈕級字級）會比它上面那行還
                // 搶眼，看起來像有什麼事該做。
                final captionStyle = Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600);

                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 這是「這台裝置正在跑的版本」，不是伺服器的 ——
                    // version.json 跟著 bundle 一起進快取（見 AppVersionService）。
                    if (info != null)
                      Text(
                        '更新於 ${_buildVersionDateText(info)}',
                        style: captionStyle,
                      ),
                    if (info != null && widget.updateService.isSupported)
                      Text('　·　', style: captionStyle),
                    if (widget.updateService.isSupported)
                      InkWell(
                        onTap: _isCheckingUpdate ? null : _checkForUpdate,
                        // 字級小，靠 padding 把可點範圍撐到手指按得到。
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 4,
                          ),
                          child: Text(
                            _isCheckingUpdate ? '檢查中…' : '檢查更新',
                            // 顏色跟旁邊一樣，只用底線表示按得下去。
                            style: captionStyle?.copyWith(
                              decoration: _isCheckingUpdate
                                  ? null
                                  : TextDecoration.underline,
                              decorationColor: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 空字串直接取 [0] 會 RangeError（Firestore 上的 name 不保證非空）。
  String _avatarLetter(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed[0];
  }

  String _buildVersionDateText(AppVersionInfo? info) {
    return DateFormat('yyyy/MM/dd HH:mm').format(info!.generatedAt);
  }
}
