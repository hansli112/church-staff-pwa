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

  void _addGroup(ServiceType type) {
    setState(() {
      _editingTemplates[type]?.add('新小組');
    });
  }

  void _removeGroup(ServiceType type, int index) {
    setState(() {
      _editingTemplates[type]?.removeAt(index);
    });
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
            tabs: ServiceType.values.map((type) => Tab(text: type.label)).toList(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () async {
                await context.read<GroupSettingsProvider>().updateTemplates(_editingTemplates);
                await context.read<AuthProvider>().cleanupUserGroups(_editingTemplates);
                if (mounted) Navigator.pop(context);
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
                    onTap: () => _addGroup(type),
                  );
                }
                return ListTile(
                  title: TextFormField(
                    initialValue: groups[index],
                    onChanged: (value) => _updateGroup(type, index, value),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: UnderlineInputBorder(),
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeGroup(type, index),
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
