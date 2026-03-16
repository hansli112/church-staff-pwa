import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../roster/domain/entities/service_roster.dart';
import '../providers/group_settings_provider.dart';
import '../providers/auth_provider.dart';

class GroupSettingsScreen extends StatefulWidget {
  const GroupSettingsScreen({super.key});

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  late Map<ServiceType, List<String>> _editingTemplates;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _editingTemplates = {
      ServiceType.sundayService: [],
      ServiceType.youth: [],
      ServiceType.children: [],
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.watch<GroupSettingsProvider>();
    if (!_initialized && !provider.isLoading) {
      _editingTemplates = Map.fromIterables(
        provider.templates.keys,
        provider.templates.values.map((list) => List<String>.from(list)),
      );
      _initialized = true;
    }
  }

  Future<void> _promptAddGroup(ServiceType type) async {
    final controller = TextEditingController();
    final name = await _showGroupNameDialog(
      title: '新增小組',
      controller: controller,
      existing: _editingTemplates[type] ?? const <String>[],
    );
    if (name == null) return;
    setState(() {
      _editingTemplates[type]?.add(name);
    });
  }

  void _removeGroup(ServiceType type, int index) {
    setState(() {
      _editingTemplates[type]?.removeAt(index);
    });
  }

  Future<void> _promptEditGroup(ServiceType type, int index) async {
    final current = _editingTemplates[type]?[index] ?? '';
    final controller = TextEditingController(text: current);
    final name = await _showGroupNameDialog(
      title: '編輯小組',
      controller: controller,
      existing: _editingTemplates[type] ?? const <String>[],
      currentName: current,
    );
    if (name == null) return;
    _updateGroup(type, index, name);
  }

  Future<void> _confirmRemoveGroup(ServiceType type, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: const Text('確定要刪除此小組嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _removeGroup(type, index);
    }
  }

  Future<String?> _showGroupNameDialog({
    required String title,
    required TextEditingController controller,
    required List<String> existing,
    String? currentName,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) {
        String? errorText;
        String? validateValue(String value) {
          final trimmed = value.trim();
          if (trimmed.isEmpty) return '請輸入名稱';
          final isDuplicate = existing.any(
            (name) =>
                name.trim() == trimmed && name.trim() != currentName?.trim(),
          );
          if (isDuplicate) return '名稱已存在';
          return null;
        }

        void submit() {
          final value = controller.text;
          final validation = validateValue(value);
          if (validation != null) {
            setState(() => errorText = validation);
            return;
          }
          Navigator.pop(context, value.trim());
        }

        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '小組名稱',
                border: const OutlineInputBorder(),
                errorText: errorText,
              ),
              onChanged: (value) =>
                  setState(() => errorText = validateValue(value)),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(onPressed: submit, child: const Text('儲存')),
            ],
          ),
        );
      },
    );
  }

  void _updateGroup(ServiceType type, int index, String value) {
    setState(() {
      _editingTemplates[type]?[index] = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GroupSettingsProvider>();
    if (!_initialized && provider.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('小組設定')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_initialized && provider.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('小組設定')),
        body: Center(child: Text(provider.error!)),
      );
    }

    return DefaultTabController(
      length: ServiceType.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('小組設定'),
          bottom: TabBar(
            tabs: ServiceType.values
                .map((type) => Tab(text: type.label))
                .toList(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () async {
                final settingsProvider = context.read<GroupSettingsProvider>();
                final authProvider = context.read<AuthProvider>();
                await settingsProvider.updateTemplates(_editingTemplates);
                await authProvider.cleanupUserGroups(_editingTemplates);
                if (!context.mounted) return;
                Navigator.pop(context);
              },
            ),
          ],
        ),
        body: TabBarView(
          children: ServiceType.values.map((type) {
            final groups = _editingTemplates[type] ?? [];
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: groups.length + 1,
              itemBuilder: (context, index) {
                if (index == groups.length) {
                  return ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('新增小組'),
                    onTap: () => _promptAddGroup(type),
                  );
                }
                return ListTile(
                  title: Text(groups[index]),
                  onTap: () => _promptEditGroup(type, index),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmRemoveGroup(type, index),
                  ),
                );
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
