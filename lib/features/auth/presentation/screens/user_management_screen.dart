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
  List<_UserListItemData> _sortedUsers = const [];
  int _usersSignature = 0;
  int _templatesSignature = 0;
  static const int _pageSize = 60;
  int _visibleCount = _pageSize;
  final ScrollController _scrollController = ScrollController();
  bool _loadingMore = false;
  double _restoreOffset = 0;
  bool _pendingRestore = false;
  List<User> _lastUsers = const [];
  bool _isRefreshing = false;
  bool _hasLoaded = false;

  @override
  void initState() {
    super.initState();
    _refreshUsers();
    _scrollController.addListener(_onScroll);
  }

  void _refreshUsers() {
    if (_scrollController.hasClients) {
      _restoreOffset = _scrollController.offset;
      _pendingRestore = true;
    }
    final future = context.read<AuthProvider>().getUsers();
    setState(() {
      _usersFuture = future;
      _visibleCount = _visibleCount < _pageSize ? _pageSize : _visibleCount;
      _isRefreshing = true;
    });
    future
        .then((users) {
          if (!mounted) return;
          setState(() {
            _lastUsers = users;
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

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  void _loadMore() {
    setState(() {
      _loadingMore = true;
      _visibleCount = (_visibleCount + _pageSize);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupTemplates = context
        .select<GroupSettingsProvider, Map<ServiceType, List<String>>>(
          (provider) => provider.templates,
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

          final users = snapshot.data ?? _lastUsers;
          _ensureSortedUsers(users, groupTemplates);
          final filter = _nameFilter.trim().toLowerCase();
          final filteredUsers = filter.isEmpty
              ? _sortedUsers
              : _sortedUsers
                    .where((item) => item.nameLower.contains(filter))
                    .toList();
          if (_visibleCount > filteredUsers.length) {
            _visibleCount = filteredUsers.length;
          } else if (filteredUsers.length < _pageSize) {
            _visibleCount = filteredUsers.length;
          }
          if (_pendingRestore && filteredUsers.isNotEmpty) {
            final indexAtOffset = (_restoreOffset / 88).floor();
            final minNeeded = (indexAtOffset + _pageSize);
            if (_visibleCount < minNeeded) {
              _visibleCount = minNeeded > filteredUsers.length
                  ? filteredUsers.length
                  : minNeeded;
            }
          }
          final visibleUsers = filteredUsers.take(_visibleCount).toList();

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
                      _visibleCount = _pageSize;
                    });
                    if (_scrollController.hasClients) {
                      _scrollController.jumpTo(0);
                    }
                  },
                ),
              ),
              Expanded(
                child: visibleUsers.isEmpty
                    ? const Center(child: Text('沒有符合的帳號'))
                    : ListView.builder(
                        key: const PageStorageKey('user_management_list'),
                        controller: _scrollController,
                        itemExtent: 88,
                        itemCount: visibleUsers.length + 1,
                        itemBuilder: (context, index) {
                          if (index == visibleUsers.length) {
                            if (visibleUsers.length >= filteredUsers.length) {
                              return const SizedBox.shrink();
                            }
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }
                          final data = visibleUsers[index];

                          return RepaintBoundary(
                            child: Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: Theme.of(
                                    context,
                                  ).dividerColor.withValues(alpha: 0.6),
                                ),
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
                                        .read<AuthProvider>();
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

  void _ensureSortedUsers(
    List<User> users,
    Map<ServiceType, List<String>> groupTemplates,
  ) {
    final usersSignature = _usersSignatureFor(users);
    final templatesSignature = _templatesSignatureFor(groupTemplates);
    if (usersSignature == _usersSignature &&
        templatesSignature == _templatesSignature) {
      return;
    }
    _usersSignature = usersSignature;
    _templatesSignature = templatesSignature;
    _sortedUsers = _buildSortedUsers(users, groupTemplates);
  }

  int _usersSignatureFor(List<User> users) {
    var hash = 17;
    for (final user in users) {
      var zonesHash = 17;
      for (final zone in user.zones) {
        zonesHash = Object.hash(
          zonesHash,
          zone.serviceType.index,
          Object.hashAll(zone.smallGroups),
        );
      }
      final userHash = Object.hash(
        user.id,
        user.name,
        user.username,
        user.role.index,
        zonesHash,
      );
      hash = Object.hash(hash, userHash);
    }
    return hash;
  }

  int _templatesSignatureFor(Map<ServiceType, List<String>> templates) {
    var hash = 17;
    final entries = templates.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));
    for (final entry in entries) {
      hash = Object.hash(hash, entry.key.index, Object.hashAll(entry.value));
    }
    return hash;
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
