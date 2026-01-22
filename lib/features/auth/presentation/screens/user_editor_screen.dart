import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/user.dart';
import '../../../roster/domain/entities/service_roster.dart';
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
                        setState(() => _selectedType = value);
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
            
            _StringListEditor(
              title: '所屬小組',
              items: _groups,
              onChanged: (newGroups) {
                _groups = newGroups;
                _notifyUpdate();
              },
            ),
            const SizedBox(height: 12),
            
            _StringListEditor(
              title: '參與服事',
              items: _ministries,
              onChanged: (newMinistries) {
                _ministries = newMinistries;
                _notifyUpdate();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StringListEditor extends StatefulWidget {
  final String title;
  final List<String> items;
  final ValueChanged<List<String>> onChanged;

  const _StringListEditor({
    required this.title,
    required this.items,
    required this.onChanged,
  });

  @override
  State<_StringListEditor> createState() => _StringListEditorState();
}

class _StringListEditorState extends State<_StringListEditor> {
  final _controller = TextEditingController();

  void _add() {
    if (_controller.text.isNotEmpty) {
      final newItems = List<String>.from(widget.items)..add(_controller.text);
      widget.onChanged(newItems);
      _controller.clear();
    }
  }

  void _remove(int index) {
    final newItems = List<String>.from(widget.items)..removeAt(index);
    widget.onChanged(newItems);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: widget.items.asMap().entries.map((entry) {
            return Chip(
              label: Text(entry.value),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () => _remove(entry.key),
            );
          }).toList(),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: '新增${widget.title}...',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _add,
            ),
          ],
        ),
      ],
    );
  }
}
