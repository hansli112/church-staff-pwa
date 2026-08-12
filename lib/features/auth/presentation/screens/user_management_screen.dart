import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/user.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import '../providers/user_admin_provider.dart';
import '../providers/group_settings_provider.dart';
import 'user_editor_screen.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  // itemBuilder 會跑很多次，常數配置一次就好。
  static const _cardRadius = BorderRadius.all(Radius.circular(12));
  static const _cardMargin = EdgeInsets.symmetric(horizontal: 16, vertical: 8);

  late Future<List<User>> _usersFuture;
  String _nameFilter = '';
  List<_UserListItemData> _sortedUsers = const [];

  // GroupSettingsProvider.templates 刻意回傳同一份 reference，
  // 所以用 identical() 就能判斷要不要重排，不必逐項比對。
  Map<ServiceType, List<String>>? _lastTemplates;

  final ScrollController _scrollController = ScrollController();
  double _restoreOffset = 0;
  bool _pendingRestore = false;
  List<User> _lastUsers = const [];
  bool _isRefreshing = false;
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    _refreshUsers();
  }

  void _refreshUsers() {
    if (_scrollController.hasClients) {
      _restoreOffset = _scrollController.offset;
      _pendingRestore = true;
    }
    // 管理畫面 pull-to-refresh / initial load 一律拉最新，避開 cache。
    final future = context.read<UserAdminProvider>().getUsers(
      forceRefresh: true,
    );
    setState(() {
      _usersFuture = future;
      _isRefreshing = true;
    });
    future
        .then((users) {
          if (!mounted) return;
          // 資料回來才排序，用一次性的 context.read 取 templates。
          final templates = context.read<GroupSettingsProvider>().templates;
          setState(() {
            _lastUsers = users;
            _sortedUsers = _buildSortedUsers(users, templates);
            _lastTemplates = templates;
            _isRefreshing = false;
            _hasLoaded = true;
          });
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() {
            _isRefreshing = false;
          });
        });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
    // context.select 仍負責在 templates 變動時觸發 rebuild；
    // 這裡用 reference 比較決定要不要重排。
    final groupTemplates = context
        .select<GroupSettingsProvider, Map<ServiceType, List<String>>>(
          (provider) => provider.templates,
        );

    // Re-sort only when the templates reference differs AND we have data.
    if (!identical(groupTemplates, _lastTemplates) && _lastUsers.isNotEmpty) {
      _sortedUsers = _buildSortedUsers(_lastUsers, groupTemplates);
      _lastTemplates = groupTemplates;
    }

    // BorderSide 吃 theme，只能留在 build，但至少提到 itemBuilder 外面。
    final cardBorderSide = BorderSide(
      color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('帳號管理')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<User>>(
        future: _usersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !_hasLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          // _sortedUsers is up-to-date: either from _refreshUsers callback
          // or the reference-check block in build().
          final filter = _nameFilter.trim().toLowerCase();
          final filteredUsers = filter.isEmpty
              ? _sortedUsers
              : _sortedUsers
                    .where((item) => item.nameLower.contains(filter))
                    .toList();

          // KEPT: scroll-position restore (0c178a5 fix)
          if (_pendingRestore && _scrollController.hasClients) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || !_scrollController.hasClients) return;
              final maxOffset = _scrollController.position.maxScrollExtent;
              if (maxOffset <= 0 && _restoreOffset > 0) {
                return;
              }
              final target = _restoreOffset > maxOffset
                  ? maxOffset
                  : _restoreOffset;
              if (target >= 0) {
                _scrollController.jumpTo(target);
              }
              _pendingRestore = false;
            });
          }

          return Column(
            children: [
              if (_isRefreshing) const LinearProgressIndicator(minHeight: 2),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: '搜尋姓名',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _nameFilter = value;
                      // reset scroll position on new search
                    });
                    if (_scrollController.hasClients) {
                      _scrollController.jumpTo(0);
                    }
                  },
                ),
              ),
              Expanded(
                child: filteredUsers.isEmpty
                    ? const Center(child: Text('沒有符合的帳號'))
                    : ListView.builder(
                        key: const PageStorageKey('user_management_list'),
                        controller: _scrollController,
                        itemExtent: 88,
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, index) {
                          final data = filteredUsers[index];

                          return RepaintBoundary(
                            child: Card(
                              margin: _cardMargin,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: _cardRadius,
                                side: cardBorderSide,
                              ),
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person, size: 18),
                                ),
                                title: Text(
                                  data.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  data.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => _openEditor(data.user),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () async {
                                    final authProvider = context
                                        .read<UserAdminProvider>();
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('確認刪除'),
                                        content: Text(
                                          '確定要刪除 ${data.user.name} 嗎？',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('取消'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text(
                                              '刪除',
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm != true) return;
                                    await authProvider.deleteUser(data.user.id);
                                    if (!context.mounted) return;
                                    _refreshUsers();
                                  },
                                ),
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

class _UserListItemData {
  final User user;
  final String displayName;
  final String subtitle;
  final String initial;
  final String nameLower;
  final int roleOrder;
  final int zoneOrder;
  final int groupOrder;

  const _UserListItemData({
    required this.user,
    required this.displayName,
    required this.subtitle,
    required this.initial,
    required this.nameLower,
    required this.roleOrder,
    required this.zoneOrder,
    required this.groupOrder,
  });
}

List<_UserListItemData> _buildSortedUsers(
  List<User> users,
  Map<ServiceType, List<String>> groupTemplates,
) {
  final result = <_UserListItemData>[];
  for (final user in users) {
    UserZoneInfo? primaryZone;
    var minIndex = 999;
    for (final zone in user.zones) {
      final idx = ServiceType.values.indexOf(zone.serviceType);
      if (idx < minIndex) {
        minIndex = idx;
        primaryZone = zone;
      }
    }
    final zoneOrder = primaryZone == null ? 999 : minIndex;
    final roleOrder = UserRole.values.indexOf(user.role);
    var groupOrder = 999;
    if (primaryZone != null && primaryZone.smallGroups.isNotEmpty) {
      final groupOrderList =
          groupTemplates[primaryZone.serviceType] ?? const <String>[];
      final groupName = primaryZone.smallGroups.first;
      final idx = groupOrderList.indexOf(groupName);
      if (idx != -1) {
        groupOrder = idx;
      }
    }
    final zoneText = user.zones.map((z) => z.serviceType.label).join(', ');
    final displayName = user.username.isEmpty ? '${user.name}（無帳號）' : user.name;
    final subtitle =
        '${user.role.label}${zoneText.isNotEmpty ? ' | $zoneText' : ''}';
    result.add(
      _UserListItemData(
        user: user,
        displayName: displayName,
        subtitle: subtitle,
        initial: user.name.isEmpty ? '?' : user.name[0],
        nameLower: user.name.toLowerCase(),
        roleOrder: roleOrder,
        zoneOrder: zoneOrder,
        groupOrder: groupOrder,
      ),
    );
  }

  result.sort((a, b) {
    if (a.roleOrder != b.roleOrder) return a.roleOrder - b.roleOrder;
    if (a.zoneOrder != b.zoneOrder) return a.zoneOrder - b.zoneOrder;
    if (a.groupOrder != b.groupOrder) return a.groupOrder - b.groupOrder;
    return a.user.name.compareTo(b.user.name);
  });

  return result;
}
