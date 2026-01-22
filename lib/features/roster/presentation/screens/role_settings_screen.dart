import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/service_roster.dart';
import '../providers/roster_provider.dart';

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

  void _addRole(ServiceType type) {
    setState(() {
      _editingTemplates[type]?.add('新職位');
    });
  }

  void _removeRole(ServiceType type, int index) {
    setState(() {
      _editingTemplates[type]?.removeAt(index);
    });
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
                if (mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
        body: TabBarView(
          children: ServiceType.values.map((type) {
            final roles = _editingTemplates[type] ?? [];
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: roles.length + 1,
              itemBuilder: (context, index) {
                if (index == roles.length) {
                  return ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('新增項目'),
                    onTap: () => _addRole(type),
                  );
                }
                return ListTile(
                  title: TextFormField(
                    initialValue: roles[index],
                    onChanged: (value) => _updateRole(type, index, value),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: UnderlineInputBorder(),
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeRole(type, index),
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
