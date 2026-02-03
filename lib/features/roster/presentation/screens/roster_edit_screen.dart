import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/service_roster.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/domain/entities/user.dart';
import '../providers/roster_provider.dart';
import '../widgets/roster_card.dart';
import '../../../../core/widgets/settings_bottom_sheet.dart';
import 'event_settings_screen.dart' deferred as event_settings_screen;
import 'role_settings_screen.dart' deferred as role_settings_screen;

class RosterEditScreen extends StatefulWidget {
  final VoidCallback onExit;
  final TabController? tabController;
  final List<ServiceType> allowedTypes;

  const RosterEditScreen({
    super.key,
    required this.onExit,
    required this.tabController,
    required this.allowedTypes,
  });

  @override
  State<RosterEditScreen> createState() => _RosterEditScreenState();
}

class _RosterEditScreenState extends State<RosterEditScreen> {
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();

      if (!authProvider.isAdmin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('沒有權限進入編輯模式')),
        );
        widget.onExit();
        return;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final allowedTypes = widget.allowedTypes;
    final now = DateTime.now();
    final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    final isLastMonthOfQuarter = now.month == (quarterStartMonth + 2);
    final titleText = isLastMonthOfQuarter ? '編輯本季/下季服事表' : '編輯本季服事表';

    final appBar = AppBar(
      title: Text(titleText),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.event),
          tooltip: '事件選項設定',
          onPressed: () => _loadAndPush(
            context,
            event_settings_screen.loadLibrary,
            () => event_settings_screen.EventSettingsScreen(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: '服事項目設定',
          onPressed: () => _loadAndPush(
            context,
            role_settings_screen.loadLibrary,
            () => role_settings_screen.RoleSettingsScreen(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.view_list),
          tooltip: '切換至檢視模式',
          onPressed: widget.onExit,
        ),
      ],
      bottom: allowedTypes.isEmpty
          ? null
          : TabBar(
              controller: widget.tabController,
              tabs: allowedTypes.map((type) => Tab(text: type.label)).toList(),
              indicatorSize: TabBarIndicatorSize.label,
              // 讓切換時的動畫更平滑
              splashFactory: NoSplash.splashFactory,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
    );

    if (allowedTypes.isEmpty) {
      return Scaffold(
        appBar: appBar,
        body: const Center(child: Text('尚未設定可檢視的牧區')),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: Consumer<RosterProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(child: Text(provider.error!));
          }

          // TabBarView 預設支援左右滑動
          return TabBarView(
            // 結合 BouncingScrollPhysics 產生彈性，同時保持分頁吸附感
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            controller: widget.tabController,
            children: allowedTypes.map((type) {
              return _RosterList(
                key: PageStorageKey(type.toString()),
                type: type,
                rosters: provider.getRostersByType(type),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _RosterList extends StatefulWidget {
  final ServiceType type;
  final List<ServiceRoster> rosters;

  const _RosterList({super.key, required this.type, required this.rosters});

  @override
  State<_RosterList> createState() => _RosterListState();
}

// 使用 AutomaticKeepAliveClientMixin 來保持滑動位置
class _RosterListState extends State<_RosterList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // 告訴 Flutter 保持這個頁面的狀態

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必須呼叫 super.build
    final isEditMode = context.watch<RosterProvider>().isEditMode;

    if (widget.rosters.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('此類別目前沒有服事資訊'),
            if (isEditMode) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showImportJsonDialog(context),
                icon: const Icon(Icons.data_object),
                label: const Text('JSON 匯入'),
              ),
            ],
          ],
        ),
      );
    }

    final showImport = isEditMode;
    return ListView.builder(
      padding: const EdgeInsets.only(top: 12, bottom: 20),
      itemCount: widget.rosters.length + (showImport ? 1 : 0),
      itemBuilder: (context, index) {
        if (showImport && index == 0) {
          return _buildImportCard(context);
        }
        final rosterIndex = index - (showImport ? 1 : 0);
        final roster = widget.rosters[rosterIndex];
        return RosterCard(
          key: ValueKey(roster.id),
          roster: roster,
          initiallyExpanded: rosterIndex == 0,
        );
      },
    );
  }

  Widget _buildImportCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'JSON 匯入',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '貼上陣列格式，依日期批次填入服事表',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => _showImportJsonDialog(context),
              icon: const Icon(Icons.upload_file),
              label: const Text('匯入'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showImportJsonDialog(BuildContext context) async {
    final controller = TextEditingController();
    String? errorText;
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SettingsBottomSheet(
              title: 'JSON 匯入（${widget.type.label}）',
              submitLabel: '匯入',
              submitChild: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('匯入'),
              onSubmit: isSubmitting
                  ? null
                  : () async {
                      setState(() {
                        errorText = null;
                        isSubmitting = true;
                      });
                      final result = await _applyJsonImport(
                        context,
                        controller.text,
                      );
                      if (!mounted) return;
                      if (result.error != null) {
                        setState(() {
                          errorText = result.error;
                          isSubmitting = false;
                        });
                        return;
                      }
                      Navigator.of(context).pop();
                      if (result.missingDates.isNotEmpty ||
                          result.notInRosterNames.isNotEmpty ||
                          result.roleMismatchNames.isNotEmpty ||
                          result.otherNames.isNotEmpty) {
                        await _showImportSummaryDialog(
                          context,
                          result,
                        );
                      } else {
                        final message = _buildResultMessage(result);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(message)),
                        );
                      }
                    },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    maxLines: 12,
                    decoration: InputDecoration(
                      hintText:
                          '[\n  {\n    "date": "2026-01-04",\n    "duties": [\n      {"people": ["芳伶"], "role": "敬拜主領"}\n    ]\n  }\n]',
                      hintStyle: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.35),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 160),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.redAccent),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          errorText!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    '格式需為 JSON 陣列，每筆含 date 與 duties',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _buildResultMessage(_JsonImportResult result) {
    if (result.updated == 0) {
      return '找不到可更新的日期';
    }
    if (result.missingDates.isEmpty &&
        result.notInRosterNames.isEmpty &&
        result.roleMismatchNames.isEmpty &&
        result.otherNames.isEmpty) {
      return '已更新 ${result.updated} 筆服事表';
    }
    final missingPreview = result.missingDates.take(3).join(', ');
    final missingSuffix = result.missingDates.length > 3 ? '...' : '';
    final notInListPreview = result.notInRosterNames.take(3).join('、');
    final notInListSuffix = result.notInRosterNames.length > 3 ? '...' : '';
    final mismatchPreview = result.roleMismatchNames.take(3).join('、');
    final mismatchSuffix = result.roleMismatchNames.length > 3 ? '...' : '';
    final otherPreview = result.otherNames.take(3).join('、');
    final otherSuffix = result.otherNames.length > 3 ? '...' : '';
    final parts = <String>[];
    if (result.missingDates.isNotEmpty) {
      parts.add(
        '${result.missingDates.length} 筆日期找不到：$missingPreview$missingSuffix',
      );
    }
    if (result.notInRosterNames.isNotEmpty) {
      parts.add(
        '${result.notInRosterNames.length} 位不在名單：$notInListPreview$notInListSuffix',
      );
    }
    if (result.roleMismatchNames.isNotEmpty) {
      parts.add(
        '${result.roleMismatchNames.length} 位未勾選該服事：$mismatchPreview$mismatchSuffix',
      );
    }
    if (result.otherNames.isNotEmpty) {
      parts.add('${result.otherNames.length} 位其它：$otherPreview$otherSuffix');
    }
    return '已更新 ${result.updated} 筆，${parts.join('；')}';
  }

  String _buildResultDetails(_JsonImportResult result) {
    final buffer = StringBuffer();
    buffer.writeln('已更新 ${result.updated} 筆服事表');
    if (result.missingDates.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('找不到的日期：');
      for (final date in result.missingDates) {
        buffer.writeln('- $date');
      }
    }
    if (result.notInRosterNames.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('不在名單：');
      for (final name in result.notInRosterNames) {
        buffer.writeln('- $name');
      }
    }
    if (result.roleMismatchNames.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('未勾選該服事：');
      for (final name in result.roleMismatchNames) {
        final roles = result.roleMismatchDetails[name];
        if (roles == null || roles.isEmpty) {
          buffer.writeln('- $name');
        } else {
          buffer.writeln('- $name：${roles.join('、')}');
        }
      }
    }
    if (result.otherNames.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('其它：');
      for (final name in result.otherNames) {
        buffer.writeln('- $name');
      }
    }
    return buffer.toString().trim();
  }

  Future<void> _showImportSummaryDialog(
    BuildContext context,
    _JsonImportResult result,
  ) async {
    final details = _buildResultDetails(result);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('匯入完成（含未匹配）'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(details),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('關閉'),
            ),
          ],
        );
      },
    );
  }

  Future<_JsonImportResult> _applyJsonImport(
    BuildContext context,
    String raw,
  ) async {
    if (raw.trim().isEmpty) {
      return const _JsonImportResult(error: '請貼上 JSON 內容');
    }

    final List<String> candidateNames;
    final Map<String, Set<String>> allowedByRole;
    try {
      final users = await context.read<AuthProvider>().getUsers();
      candidateNames = [
        ...users
            .map((u) => u.name.trim())
            .where((name) => name.isNotEmpty),
      ];
      allowedByRole = _buildAllowedByRole(users);
    } catch (_) {
      return const _JsonImportResult(error: '無法載入同工名單');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      return const _JsonImportResult(error: 'JSON 格式錯誤');
    }

    if (decoded is! List) {
      return const _JsonImportResult(error: 'JSON 最外層需為陣列');
    }

    final Map<String, List<RosterEntry>> importMap = {};
    final List<String> duplicateDates = [];
    final List<String> notInRosterNames = [];
    final List<String> roleMismatchNames = [];
    final Map<String, Set<String>> roleMismatchDetails = {};
    final List<String> otherNames = [];
    for (var i = 0; i < decoded.length; i++) {
      final item = decoded[i];
      if (item is! Map) {
        return _JsonImportResult(error: '第 ${i + 1} 筆不是物件');
      }
      final dateValue = item['date'];
      if (dateValue is! String) {
        return _JsonImportResult(error: '第 ${i + 1} 筆缺少 date');
      }
      final parsedDate = _parseDateKey(dateValue);
      if (parsedDate == null) {
        return _JsonImportResult(error: '第 ${i + 1} 筆 date 格式錯誤');
      }
      final dutiesValue = item['duties'];
      if (dutiesValue is! List) {
        return _JsonImportResult(error: '第 ${i + 1} 筆 duties 格式錯誤');
      }
      final duties = <RosterEntry>[];
      for (var j = 0; j < dutiesValue.length; j++) {
        final duty = dutiesValue[j];
        if (duty is! Map) {
          return _JsonImportResult(error: '第 ${i + 1} 筆 duties 第 ${j + 1} 筆不是物件');
        }
        final roleValue = duty['role'];
        if (roleValue is! String || roleValue.trim().isEmpty) {
          return _JsonImportResult(error: '第 ${i + 1} 筆 duties 第 ${j + 1} 筆 role 缺失');
        }
        final peopleValue = duty['people'];
        if (peopleValue is! List) {
          return _JsonImportResult(error: '第 ${i + 1} 筆 duties 第 ${j + 1} 筆 people 格式錯誤');
        }
        final people = peopleValue
            .whereType<String>()
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .map((name) {
              final result = _resolvePersonName(
                name,
                candidateNames,
                roleValue.trim(),
                allowedByRole,
              );
              switch (result.status) {
                case _NameMatchStatus.matched:
                  return result.name;
                case _NameMatchStatus.roleMismatch:
                  roleMismatchNames.add(result.name);
                  _addRoleMismatch(
                    roleMismatchDetails,
                    result.name,
                    roleValue.trim(),
                  );
                  return null;
                case _NameMatchStatus.notInList:
                  notInRosterNames.add(name);
                  return null;
                case _NameMatchStatus.other:
                  otherNames.add(name);
                  return null;
              }
            })
            .whereType<String>()
            .toList();
        duties.add(
          RosterEntry(
            role: roleValue.trim(),
            people: people.isEmpty ? const ['待定'] : people,
            peopleOrder: people.isEmpty ? const [] : List<String>.from(people),
          ),
        );
      }
      if (duties.isEmpty) {
        return _JsonImportResult(error: '第 ${i + 1} 筆 duties 不可為空');
      }
      if (importMap.containsKey(parsedDate)) {
        duplicateDates.add(parsedDate);
      }
      importMap[parsedDate] = duties;
    }

    if (duplicateDates.isNotEmpty) {
      return _JsonImportResult(error: '重複日期：${duplicateDates.join(', ')}');
    }

    final rosterByDate = <String, ServiceRoster>{
      for (final roster in widget.rosters) _dateKey(roster.date): roster,
    };
    final updates = <ServiceRoster>[];
    final missingDates = <String>[];

    for (final entry in importMap.entries) {
      final roster = rosterByDate[entry.key];
      if (roster == null) {
        missingDates.add(entry.key);
        continue;
      }
      updates.add(roster.copyWith(duties: entry.value));
    }

    if (updates.isEmpty) {
      return _JsonImportResult(
        updated: 0,
        missingDates: missingDates,
        notInRosterNames: _uniqueNames(notInRosterNames),
        roleMismatchNames: _uniqueNames(roleMismatchNames),
        roleMismatchDetails: _normalizeRoleMismatch(roleMismatchDetails),
        otherNames: _uniqueNames(otherNames),
      );
    }

    final provider = context.read<RosterProvider>();
    for (final roster in updates) {
      await provider.updateRoster(roster);
    }

    return _JsonImportResult(
      updated: updates.length,
      missingDates: missingDates,
      notInRosterNames: _uniqueNames(notInRosterNames),
      roleMismatchNames: _uniqueNames(roleMismatchNames),
      roleMismatchDetails: _normalizeRoleMismatch(roleMismatchDetails),
      otherNames: _uniqueNames(otherNames),
    );
  }

  String _dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String? _parseDateKey(String raw) {
    try {
      final parsed = DateTime.parse(raw);
      return _dateKey(DateTime(parsed.year, parsed.month, parsed.day));
    } catch (_) {
      return null;
    }
  }

  _NameMatchResult _resolvePersonName(
    String raw,
    List<String> userNames,
    String role,
    Map<String, Set<String>> allowedByRole,
  ) {
    final name = raw.trim();
    if (name.isEmpty || name == '待定') {
      return const _NameMatchResult.matched('待定');
    }
    if (userNames.contains(name)) {
      return _isAllowedForRole(name, role, allowedByRole)
          ? _NameMatchResult.matched(name)
          : _NameMatchResult.roleMismatch(name);
    }
    final matches = userNames
        .where((full) => full.length > name.length && full.endsWith(name))
        .toList();
    if (matches.length == 1) {
      final full = matches.first;
      return _isAllowedForRole(full, role, allowedByRole)
          ? _NameMatchResult.matched(full)
          : _NameMatchResult.roleMismatch(full);
    }
    if (matches.length > 1) {
      return _NameMatchResult.other(name);
    }
    return _NameMatchResult.notInList(name);
  }

  List<String> _uniqueNames(List<String> names) {
    final seen = <String>{};
    final result = <String>[];
    for (final name in names) {
      final trimmed = name.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) continue;
      seen.add(trimmed);
      result.add(trimmed);
    }
    return result;
  }

  void _addRoleMismatch(
    Map<String, Set<String>> bucket,
    String name,
    String role,
  ) {
    final trimmedName = name.trim();
    final trimmedRole = role.trim();
    if (trimmedName.isEmpty || trimmedRole.isEmpty) return;
    bucket.putIfAbsent(trimmedName, () => <String>{});
    bucket[trimmedName]!.add(trimmedRole);
  }

  Map<String, List<String>> _normalizeRoleMismatch(
    Map<String, Set<String>> raw,
  ) {
    if (raw.isEmpty) return const {};
    final result = <String, List<String>>{};
    for (final entry in raw.entries) {
      final roles = entry.value.toList()..sort();
      result[entry.key] = roles;
    }
    return result;
  }

  Map<String, Set<String>> _buildAllowedByRole(List<User> users) {
    final Map<String, Set<String>> allowed = {};
    for (final user in users) {
      final userName = user.name.trim();
      if (userName.isEmpty) continue;
      for (final zone in user.zones) {
        if (zone.serviceType != widget.type) continue;
        for (final ministry in zone.ministries) {
          final role = ministry.trim();
          if (role.isEmpty) continue;
          allowed.putIfAbsent(role, () => {});
          allowed[role]!.add(userName);
        }
      }
    }

    return allowed;
  }

  bool _isAllowedForRole(
    String name,
    String role,
    Map<String, Set<String>> allowedByRole,
  ) {
    final normalizedRole = role.trim();
    if (normalizedRole.isEmpty) return false;
    final allowed = allowedByRole[normalizedRole];
    if (allowed == null || allowed.isEmpty) return false;
    return allowed.contains(name);
  }
}

class _JsonImportResult {
  final int updated;
  final List<String> missingDates;
  final List<String> notInRosterNames;
  final List<String> roleMismatchNames;
  final Map<String, List<String>> roleMismatchDetails;
  final List<String> otherNames;
  final String? error;

  const _JsonImportResult({
    this.updated = 0,
    this.missingDates = const [],
    this.notInRosterNames = const [],
    this.roleMismatchNames = const [],
    this.roleMismatchDetails = const {},
    this.otherNames = const [],
    this.error,
  });
}

enum _NameMatchStatus { matched, notInList, roleMismatch, other }

class _NameMatchResult {
  final _NameMatchStatus status;
  final String name;

  const _NameMatchResult(this.status, this.name);

  const _NameMatchResult.matched(this.name)
      : status = _NameMatchStatus.matched;

  const _NameMatchResult.notInList(this.name)
      : status = _NameMatchStatus.notInList;

  const _NameMatchResult.roleMismatch(this.name)
      : status = _NameMatchStatus.roleMismatch;

  const _NameMatchResult.other(this.name) : status = _NameMatchStatus.other;
}
