import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/service_roster.dart';
import '../providers/roster_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/widgets/settings_bottom_sheet.dart';

class RoleSettingsScreen extends StatefulWidget {
  const RoleSettingsScreen({super.key});

  @override
  State<RoleSettingsScreen> createState() => _RoleSettingsScreenState();
}

class _RoleSettingsScreenState extends State<RoleSettingsScreen> {
  late Map<ServiceType, List<String>> _editingTemplates;

  @override
  void initState() {
    super.initState();
    final provider = context.read<RosterProvider>();
    _editingTemplates = Map.fromIterables(
      provider.templates.keys,
      provider.templates.values.map((list) => List<String>.from(list)),
    );
  }

  Future<void> _promptAddRole(ServiceType type) async {
    final controller = TextEditingController();
    final name = await _showRoleNameDialog(
      title: '新增項目',
      controller: controller,
      existing: _editingTemplates[type] ?? const <String>[],
    );
    if (name == null) return;
    setState(() {
      _editingTemplates[type]?.add(name);
    });
  }

  void _removeRole(ServiceType type, int index) {
    setState(() {
      _editingTemplates[type]?.removeAt(index);
    });
  }

  Future<void> _promptEditRole(ServiceType type, int index) async {
    final current = _editingTemplates[type]?[index] ?? '';
    final controller = TextEditingController(text: current);
    final name = await _showRoleNameDialog(
      title: '編輯項目',
      controller: controller,
      existing: _editingTemplates[type] ?? const <String>[],
      currentName: current,
    );
    if (name == null) return;
    _updateRole(type, index, name);
  }

  Future<void> _confirmRemoveRole(ServiceType type, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: const Text('確定要刪除此服事項目嗎？'),
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
      _removeRole(type, index);
    }
  }

  Future<String?> _showRoleNameDialog({
    required String title,
    required TextEditingController controller,
    required List<String> existing,
    String? currentName,
  }) async {
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        String? errorText;
        String? validateValue(String value) {
          final trimmed = value.trim();
          if (trimmed.isEmpty) return '請輸入名稱';
          final isDuplicate = existing.any(
            (name) => name.trim() == trimmed && name.trim() != currentName?.trim(),
          );
          if (isDuplicate) return '名稱已存在';
          return null;
        }

        void submit(StateSetter setState) {
          final value = controller.text;
          final validation = validateValue(value);
          if (validation != null) {
            setState(() => errorText = validation);
            return;
          }
          Navigator.pop(context, value.trim());
        }

        return StatefulBuilder(
          builder: (context, setState) {
            return SettingsBottomSheet(
              title: title,
              onSubmit: () => submit(setState),
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: '服事項目名稱',
                  hintText: '例：敬拜主領',
                  hintStyle: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.35),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
                onChanged: (value) =>
                    setState(() => errorText = validateValue(value)),
                onSubmitted: (_) => submit(setState),
              ),
            );
          },
        );
      },
    );
    return result;
  }

  void _updateRole(ServiceType type, int index, String value) {
    setState(() {
      _editingTemplates[type]?[index] = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: ServiceType.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('服事項目設定'),
          bottom: TabBar(
            tabs: ServiceType.values.map((type) => Tab(text: type.label)).toList(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () async {
                await context.read<RosterProvider>().updateTemplates(_editingTemplates);
                await context.read<AuthProvider>().cleanupUserMinistries(_editingTemplates);
                if (mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
        body: TabBarView(
          children: ServiceType.values.map((type) {
            final roles = _editingTemplates[type] ?? [];
            return Column(
              children: [
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: roles.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        final item = roles.removeAt(oldIndex);
                        roles.insert(newIndex, item);
                        _editingTemplates[type] = List<String>.from(roles);
                      });
                    },
                    itemBuilder: (context, index) {
                      return ListTile(
                        key: ValueKey('role_${type.name}_${roles[index]}'),
                        title: Text(roles[index]),
                        onTap: () => _promptEditRole(type, index),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _confirmRemoveRole(type, index),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Icon(Icons.drag_handle),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('新增項目'),
                    onTap: () => _promptAddRole(type),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
