import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/service_roster.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/roster_provider.dart';

class RosterCard extends StatelessWidget {
  final ServiceRoster roster;
  final bool initiallyExpanded;

  const RosterCard({
    super.key, 
    required this.roster,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd (E)', 'zh_TW');
    final isEditMode = context.watch<RosterProvider>().isEditMode;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: isEditMode ? 4.0 : 2.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isEditMode 
          ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2.0)
          : BorderSide.none,
      ),
      child: ExpansionTile(
        key: PageStorageKey(roster.id),
        initiallyExpanded: initiallyExpanded,
        leading: Icon(
          isEditMode ? Icons.edit_note : Icons.event_note, 
          color: isEditMode ? Theme.of(context).colorScheme.primary : Colors.blueAccent,
        ),
        title: Text(
          dateFormat.format(roster.date),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(roster.serviceName),
        trailing: isEditMode ? const Icon(Icons.drag_handle) : null,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: roster.duties.asMap().entries.map((entry) {
                final int index = entry.key;
                final RosterEntry duty = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: InkWell(
                    onTap: isEditMode ? () => _showEditDialog(context, index, duty) : null,
                    borderRadius: BorderRadius.circular(8),
                    splashColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                    highlightColor: Theme.of(context).colorScheme.primary.withOpacity(0.04),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text(
                            duty.role,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            duty.people.join('、'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isEditMode)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                            onPressed: () => _confirmRemoveDuty(context, index, duty.role),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList()..addAll(isEditMode ? [
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('新增服事項目'),
                    onPressed: () => _showAddDutyDialog(context),
                  ),
                )
              ] : []),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDutyDialog(BuildContext context) async {
    final TextEditingController roleController = TextEditingController();
    final Future<List<String>> peopleFuture =
        _loadSelectablePeople(context, roster.type, const []);
    final roleOptions =
        context.read<RosterProvider>().templates[roster.type] ?? const <String>[];
    
    return showDialog(
      context: context,
      builder: (context) {
        return _RosterPeopleDialog(
          title: '新增服事項目',
          roleController: roleController,
          roleOptions: roleOptions,
          initialRole: roleOptions.isNotEmpty ? roleOptions.first : null,
          peopleFuture: peopleFuture,
          initialPeople: const ['待定'],
          onSubmit: (role, people) => _addDuty(context, role, people),
          submitLabel: '新增',
        );
      },
    );
  }

  void _addDuty(BuildContext context, String role, List<String> people) {
    final newDuties = List<RosterEntry>.from(roster.duties);
    newDuties.add(RosterEntry(role: role, people: people));
    
    final newRoster = roster.copyWith(duties: newDuties);
    context.read<RosterProvider>().updateRoster(newRoster);
  }

  void _removeDuty(BuildContext context, int index) {
    final newDuties = List<RosterEntry>.from(roster.duties);
    newDuties.removeAt(index);
    
    final newRoster = roster.copyWith(duties: newDuties);
    context.read<RosterProvider>().updateRoster(newRoster);
  }

  Future<void> _confirmRemoveDuty(BuildContext context, int index, String role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除「$role」嗎？'),
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
      _removeDuty(context, index);
    }
  }

  Future<void> _showEditDialog(BuildContext context, int index, RosterEntry duty) async {
    final Future<List<String>> peopleFuture =
        _loadSelectablePeople(context, roster.type, duty.people);

    await showDialog(
      context: context,
      builder: (context) {
        return _RosterPeopleDialog(
          title: '編輯 ${duty.role}',
          roleController: TextEditingController(text: duty.role),
          roleOptions: const [],
          initialRole: duty.role,
          peopleFuture: peopleFuture,
          initialPeople: duty.people.isEmpty ? const ['待定'] : duty.people,
          onSubmit: (role, people) => _updateDuty(context, index, people),
          submitLabel: '儲存',
          roleEditable: false,
        );
      },
    );
  }

  void _updateDuty(BuildContext context, int index, List<String> newPeople) {
    final newDuties = List<RosterEntry>.from(roster.duties);
    newDuties[index] = newDuties[index].copyWith(people: newPeople);
    
    final newRoster = roster.copyWith(duties: newDuties);
    context.read<RosterProvider>().updateRoster(newRoster);
  }

  Future<List<String>> _loadSelectablePeople(
    BuildContext context,
    ServiceType rosterType,
    List<String> extras,
  ) async {
    final users = await context.read<AuthProvider>().getUsers();
    final names = users
        .where((u) => u.zones.any((zone) => zone.serviceType == rosterType))
        .map((u) => u.name.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    names.sort();
    final Set<String> merged = {...names, ...extras.map((e) => e.trim()).where((e) => e.isNotEmpty)};
    final List<String> result = ['待定'];
    result.addAll(merged.where((name) => name != '待定'));
    return result;
  }
}

class _RosterPeopleDialog extends StatefulWidget {
  final String title;
  final TextEditingController roleController;
  final List<String> roleOptions;
  final String? initialRole;
  final Future<List<String>> peopleFuture;
  final List<String> initialPeople;
  final void Function(String role, List<String> people) onSubmit;
  final String submitLabel;
  final bool roleEditable;

  const _RosterPeopleDialog({
    required this.title,
    required this.roleController,
    required this.roleOptions,
    required this.initialRole,
    required this.peopleFuture,
    required this.initialPeople,
    required this.onSubmit,
    required this.submitLabel,
    this.roleEditable = true,
  });

  @override
  State<_RosterPeopleDialog> createState() => _RosterPeopleDialogState();
}

class _RosterPeopleDialogState extends State<_RosterPeopleDialog> {
  late Set<String> _selectedPeople;
  List<String> _options = const ['待定'];
  String? _selectedRole;

  @override
  void initState() {
    super.initState();
    _selectedPeople = widget.initialPeople.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (_selectedPeople.isEmpty) {
      _selectedPeople = {'待定'};
    }
    _selectedRole = widget.initialRole;
  }

  void _toggleSelection(String name) {
    setState(() {
      if (_selectedPeople.contains(name)) {
        _selectedPeople.remove(name);
      } else {
        _selectedPeople.add(name);
      }

      if (name == '待定' && _selectedPeople.contains('待定')) {
        _selectedPeople
          ..clear()
          ..add('待定');
      } else if (_selectedPeople.length > 1 && _selectedPeople.contains('待定')) {
        _selectedPeople.remove('待定');
      }
    });
  }

  List<String> _buildSelectedPeople(List<String> options) {
    final selected = options.where(_selectedPeople.contains).toList();
    if (selected.isEmpty) {
      return ['待定'];
    }
    return selected;
  }

  @override
  Widget build(BuildContext context) {
    final canSelectRole = widget.roleEditable && widget.roleOptions.isNotEmpty;
    final roleMissing = widget.roleEditable && widget.roleOptions.isEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.roleEditable)
              TextField(
                controller: widget.roleController,
                decoration: const InputDecoration(labelText: '職位名稱'),
                enabled: false,
              ),
            if (canSelectRole)
              DropdownButtonFormField<String>(
                value: _selectedRole,
                decoration: const InputDecoration(labelText: '服事項目'),
                items: widget.roleOptions.map((role) {
                  return DropdownMenuItem(
                    value: role,
                    child: Text(role),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedRole = value);
                  }
                },
              ),
            if (roleMissing)
              const Text(
                '請先到「服事項目設定」新增項目',
                style: TextStyle(color: Colors.redAccent),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '選擇同工',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 280,
              child: FutureBuilder<List<String>>(
                future: widget.peopleFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('載入同工名單失敗: ${snapshot.error}'));
                  }

                  _options = snapshot.data ?? const ['待定'];
                  return ListView.builder(
                    itemCount: _options.length,
                    itemBuilder: (context, index) {
                      final name = _options[index];
                      final checked = _selectedPeople.contains(name);
                      return CheckboxListTile(
                        title: Text(name),
                        value: checked,
                        onChanged: (_) => _toggleSelection(name),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: roleMissing
              ? null
              : () {
            final role = widget.roleEditable
                ? (_selectedRole ?? '').trim()
                : widget.roleController.text.trim();
            if (role.isEmpty) return;
            final selected = _buildSelectedPeople(_options);
            widget.onSubmit(role, selected);
            Navigator.of(context).pop();
          },
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}
