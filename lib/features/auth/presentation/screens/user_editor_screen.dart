import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/user.dart';
import '../../../roster/domain/entities/service_roster.dart';
import '../../../roster/presentation/providers/roster_provider.dart';
import '../providers/group_settings_provider.dart';
import '../providers/auth_provider.dart';

class UserEditorScreen extends StatefulWidget {
  final User? user; // If null, it's add mode

  const UserEditorScreen({super.key, this.user});

  @override
  State<UserEditorScreen> createState() => _UserEditorScreenState();
}

class _UserEditorScreenState extends State<UserEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _usernameController;
  late UserRole _selectedRole;
  late List<UserZoneInfo> _zones;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user?.name ?? '');
    _emailController = TextEditingController(text: widget.user?.email ?? '');
    _usernameController = TextEditingController(text: widget.user?.username ?? '');
    _selectedRole = widget.user?.role ?? UserRole.member;
    _zones = List.from(widget.user?.zones ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _addZone() {
    setState(() {
      _zones.add(const UserZoneInfo(serviceType: ServiceType.sundayService, smallGroups: [], ministries: []));
    });
  }

  void _removeZone(int index) {
    setState(() {
      _zones.removeAt(index);
    });
  }

  void _updateZone(int index, UserZoneInfo newZone) {
    setState(() {
      _zones[index] = newZone;
    });
  }

  Future<void> _save() async {
    if (_zones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少設定一個牧區')),
      );
      return;
    }
    if (_formKey.currentState!.validate()) {
      final authProvider = context.read<AuthProvider>();
      
      try {
        if (widget.user == null) {
          await authProvider.addUser(
            _nameController.text,
            _emailController.text,
            _usernameController.text,
            _selectedRole,
            zones: _zones,
          );
        } else {
          final updatedUser = widget.user!.copyWith(
            name: _nameController.text,
            email: _emailController.text,
            username: _usernameController.text,
            role: _selectedRole,
            zones: _zones,
          );
          await authProvider.updateUser(updatedUser);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('儲存成功')),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('錯誤: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.user == null ? '新增帳號' : '編輯帳號'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('基本資料', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '姓名',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v?.isEmpty == true ? '請輸入姓名' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        hintText: 'example@gmail.com',
                      ),
                      enabled: widget.user == null,
                      validator: (v) {
                        if (v == null || v.isEmpty) return '請輸入 Email';
                        if (!v.contains('@')) return '請輸入有效的 Email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: '顯示帳號 (ID)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v?.isEmpty == true ? '請輸入帳號 ID' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<UserRole>(
                      value: _selectedRole,
                      decoration: const InputDecoration(
                        labelText: '角色',
                        border: OutlineInputBorder(),
                      ),
                      items: UserRole.values.map((role) {
                        return DropdownMenuItem(
                          value: role,
                          child: Text(role.label),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedRole = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('牧區資料', style: Theme.of(context).textTheme.titleMedium),
                if (_zones.length < ServiceType.values.length)
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('新增牧區'),
                    onPressed: _addZone,
                  ),
              ],
            ),
            if (_zones.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: Text('尚無牧區資料', style: TextStyle(color: Colors.grey))),
              ),
            ..._zones.asMap().entries.map((entry) {
              final index = entry.key;
              final zone = entry.value;
              return _ZoneEditorCard(
                key: ValueKey('zone_$index'),
                zone: zone,
                onRemove: () => _removeZone(index),
                onUpdate: (newZone) => _updateZone(index, newZone),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _ZoneEditorCard extends StatefulWidget {
  final UserZoneInfo zone;
  final VoidCallback onRemove;
  final ValueChanged<UserZoneInfo> onUpdate;

  const _ZoneEditorCard({
    super.key,
    required this.zone,
    required this.onRemove,
    required this.onUpdate,
  });

  @override
  State<_ZoneEditorCard> createState() => _ZoneEditorCardState();
}

class _ZoneEditorCardState extends State<_ZoneEditorCard> {
  late List<String> _groups;
  late List<String> _ministries;
  late ServiceType _selectedType;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.zone.serviceType;
    _groups = List.from(widget.zone.smallGroups);
    _ministries = List.from(widget.zone.ministries);
  }

  void _notifyUpdate() {
    widget.onUpdate(widget.zone.copyWith(
      serviceType: _selectedType,
      smallGroups: _groups,
      ministries: _ministries,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final templates = context.watch<RosterProvider>().templates;
    final ministryOptions = templates[_selectedType] ?? const <String>[];
    final groupTemplates = context.watch<GroupSettingsProvider>().templates;
    final groupOptions = groupTemplates[_selectedType] ?? const <String>[];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ServiceType>(
                    value: _selectedType,
                    decoration: const InputDecoration(labelText: '牧區'),
                    items: ServiceType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        final newOptions = context.read<RosterProvider>().templates[value] ?? [];
                        final newGroupOptions =
                            context.read<GroupSettingsProvider>().templates[value] ?? [];
                        setState(() {
                          _selectedType = value;
                          _ministries = _ministries.where(newOptions.contains).toList();
                          _groups = _groups.where(newGroupOptions.contains).toList();
                        });
                        _notifyUpdate();
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            _OptionListSelector(
              title: '所屬小組',
              options: groupOptions,
              selected: _groups,
              onChanged: (newGroups) {
                _groups = newGroups;
                _notifyUpdate();
              },
              emptyText: '尚未設定小組清單',
            ),
            const SizedBox(height: 12),
            
            _OptionListSelector(
              title: '參與服事',
              options: ministryOptions,
              selected: _ministries,
              onChanged: (newMinistries) {
                _ministries = newMinistries;
                _notifyUpdate();
              },
              emptyText: '尚未設定服事項目',
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionListSelector extends StatelessWidget {
  final String title;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final String emptyText;

  const _OptionListSelector({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final sortedOptions = List<String>.from(options)..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        if (sortedOptions.isEmpty)
          Text(emptyText, style: const TextStyle(color: Colors.grey)),
        if (sortedOptions.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: sortedOptions.map((option) {
              final isSelected = selected.contains(option);
              return FilterChip(
                label: Text(option),
                selected: isSelected,
                onSelected: (value) {
                  final updated = List<String>.from(selected);
                  if (value) {
                    if (!updated.contains(option)) {
                      updated.add(option);
                    }
                  } else {
                    updated.remove(option);
                  }
                  onChanged(updated);
                },
              );
            }).toList(),
          ),
      ],
    );
  }
}
