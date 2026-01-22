import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/service_roster.dart';
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
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _showEditDialog(context, index, duty),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                              onPressed: () => _removeDuty(context, index),
                            ),
                          ],
                        ),
                    ],
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
    final TextEditingController nameController = TextEditingController(text: '待定');
    
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新增服事項目'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: roleController,
                decoration: const InputDecoration(labelText: '職位名稱 (如: 領會)'),
                autofocus: true,
              ),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '人員姓名 (第一位)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (roleController.text.isNotEmpty) {
                  _addDuty(context, roleController.text, [nameController.text]);
                }
                Navigator.of(context).pop();
              },
              child: const Text('新增'),
            ),
          ],
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

  Future<void> _showEditDialog(BuildContext context, int index, RosterEntry duty) async {
    // 建立一個可變的 List 來操作狀態
    List<String> editingPeople = List.from(duty.people);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('編輯 ${duty.role}'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: editingPeople.length + 1,
                  itemBuilder: (context, pIndex) {
                    if (pIndex == editingPeople.length) {
                      return ListTile(
                        leading: const Icon(Icons.add),
                        title: const Text('新增人員'),
                        onTap: () {
                          setState(() {
                            editingPeople.add('待定');
                          });
                        },
                      );
                    }
                    return ListTile(
                      title: TextFormField(
                        initialValue: editingPeople[pIndex],
                        decoration: InputDecoration(
                          labelText: '人員 ${pIndex + 1}',
                        ),
                        onChanged: (val) {
                          editingPeople[pIndex] = val;
                        },
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            editingPeople.removeAt(pIndex);
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    // 過濾掉空白的輸入
                    final finalPeople = editingPeople.where((s) => s.trim().isNotEmpty).toList();
                    _updateDuty(context, index, finalPeople.isEmpty ? ['待定'] : finalPeople);
                    Navigator.of(context).pop();
                  },
                  child: const Text('儲存'),
                ),
              ],
            );
          },
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
}