import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/event_option.dart';
import '../../domain/entities/service_roster.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import '../../../auth/presentation/providers/user_admin_provider.dart';
import '../providers/roster_provider.dart';
import '../../../../core/widgets/settings_bottom_sheet.dart';

part '_roster_people_dialog.dart';
part '_special_event_dialog.dart';

class RosterCard extends StatelessWidget {
  static final _dateFormat = DateFormat('yyyy/MM/dd (E)', 'zh_TW');

  final ServiceRoster roster;
  final bool initiallyExpanded;

  const RosterCard({
    super.key,
    required this.roster,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final rosterProvider = context.watch<RosterProvider>();
    final isEditMode = rosterProvider.isEditMode;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: isEditMode ? 4.0 : 2.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isEditMode
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2.0,
              )
            : BorderSide.none,
      ),
      child: ExpansionTile(
        key: PageStorageKey(roster.id),
        initiallyExpanded: initiallyExpanded,
        leading: Icon(
          isEditMode ? Icons.edit_note : Icons.event_note,
          color: isEditMode
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.primary,
        ),
        title: Text(
          _dateFormat.format(roster.date),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(roster.serviceName),
            if (roster.specialEvents.isNotEmpty || isEditMode)
              const SizedBox(width: 8),
            if (roster.specialEvents.isNotEmpty || isEditMode)
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    ...roster.specialEvents.map((event) {
                      final colorValue = roster.customEventColors[event] ??
                          rosterProvider.eventColorFor(
                            roster.type,
                            event,
                          );
                      final color = Color(colorValue);
                      final label = Text(
                        event,
                        style: TextStyle(
                          color: color,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                      if (!isEditMode) {
                        return Chip(
                          label: label,
                          backgroundColor: color.withValues(alpha: 0.12),
                          side: BorderSide(color: color.withValues(alpha: 0.4)),
                          padding: EdgeInsets.zero,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 0,
                          ),
                          visualDensity: const VisualDensity(
                            horizontal: -2,
                            vertical: -3,
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        );
                      }
                      return InputChip(
                        label: label,
                        backgroundColor: color.withValues(alpha: 0.12),
                        side: BorderSide(color: color.withValues(alpha: 0.4)),
                        onDeleted: () =>
                            _confirmRemoveSpecialEvent(context, event),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        visualDensity: const VisualDensity(
                          horizontal: -2,
                          vertical: -3,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }),
                    if (isEditMode)
                      ActionChip(
                        label: const Text('新增事件'),
                        onPressed: () => _showAddSpecialEventDialog(context),
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        visualDensity: const VisualDensity(
                          horizontal: -2,
                          vertical: -3,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        labelStyle: TextStyle(
                          color: Colors.orange[800],
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        trailing: isEditMode ? const Icon(Icons.drag_handle) : null,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                ...roster.duties.asMap().entries.map((entry) {
                  final int index = entry.key;
                  final RosterEntry duty = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: InkWell(
                      onTap: isEditMode
                          ? () => _showEditDialog(context, index, duty)
                          : null,
                      borderRadius: BorderRadius.circular(8),
                      splashColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.08),
                      highlightColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.04),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 88,
                            child: Text(
                              duty.role,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[700],
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
                              tooltip: '刪除服事項目',
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              icon: Icon(
                                Icons.delete_outline,
                                size: 20,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              onPressed: () =>
                                  _confirmRemoveDuty(context, index, duty.role),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                if (isEditMode) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('新增服事項目'),
                      onPressed: () => _showAddDutyDialog(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDutyDialog(BuildContext context) async {
    Future<_PeopleOptions> peopleLoader(String? role) =>
        _loadSelectablePeople(context, roster.type, const [], role);
    final roleOptions =
        context.read<RosterProvider>().templates[roster.type] ??
        const <String>[];

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return _RosterPeopleDialog(
          title: '新增服事項目',
          rosterType: roster.type,
          roleOptions: roleOptions,
          initialRole: roleOptions.isNotEmpty ? roleOptions.first : null,
          initialOrder: const [],
          peopleLoader: peopleLoader,
          initialPeople: const ['待定'],
          initialPersonIdsByName: const {},
          onSubmit: (role, people, order, personIdsByName) =>
              _addDuty(context, role, people, order, personIdsByName),
          submitLabel: '新增',
          useBottomSheet: true,
        );
      },
    );
  }

  void _addDuty(
    BuildContext context,
    String role,
    List<String> people,
    List<String> peopleOrder,
    Map<String, String> personIdsByName,
  ) {
    final newDuties = List<RosterEntry>.from(roster.duties);
    newDuties.add(
      RosterEntry(
        role: role,
        people: people,
        peopleOrder: peopleOrder,
        personIdsByName: personIdsByName,
      ),
    );

    final newRoster = roster.copyWith(duties: newDuties);
    context.read<RosterProvider>().updateRoster(newRoster);
  }

  void _removeDuty(BuildContext context, int index) {
    final newDuties = List<RosterEntry>.from(roster.duties);
    newDuties.removeAt(index);

    final newRoster = roster.copyWith(duties: newDuties);
    context.read<RosterProvider>().updateRoster(newRoster);
  }

  Future<void> _confirmRemoveDuty(
    BuildContext context,
    int index,
    String role,
  ) async {
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

    if (!context.mounted) return;
    if (confirmed == true) {
      _removeDuty(context, index);
    }
  }

  Future<void> _showEditDialog(
    BuildContext context,
    int index,
    RosterEntry duty,
  ) async {
    Future<_PeopleOptions> peopleLoader(String? role) => _loadSelectablePeople(
      context,
      roster.type,
      duty.people,
      role ?? duty.role,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return _RosterPeopleDialog(
          title: '編輯 ${duty.role}',
          rosterType: roster.type,
          initialRoleText: duty.role,
          roleOptions: const [],
          initialRole: duty.role,
          initialOrder: duty.peopleOrder,
          peopleLoader: peopleLoader,
          initialPeople: duty.people.isEmpty ? const ['待定'] : duty.people,
          initialPersonIdsByName: duty.personIdsByName,
          onSubmit: (role, people, order, personIdsByName) =>
              _updateDuty(context, index, people, order, personIdsByName),
          submitLabel: '儲存',
          roleEditable: false,
          useBottomSheet: true,
        );
      },
    );
  }

  void _updateDuty(
    BuildContext context,
    int index,
    List<String> newPeople,
    List<String> peopleOrder,
    Map<String, String> personIdsByName,
  ) {
    final newDuties = List<RosterEntry>.from(roster.duties);
    newDuties[index] = newDuties[index].copyWith(
      people: newPeople,
      peopleOrder: peopleOrder,
      personIdsByName: personIdsByName,
    );

    final newRoster = roster.copyWith(duties: newDuties);
    context.read<RosterProvider>().updateRoster(newRoster);
  }

  Future<void> _showAddSpecialEventDialog(BuildContext context) async {
    final provider = context.read<RosterProvider>();
    final existing = roster.specialEvents.toSet();
    final options = provider
        .eventOptionsFor(roster.type)
        .where((e) => e.name.trim().isNotEmpty)
        .toList();

    final result = await showDialog<_SpecialEventDialogResult>(
      context: context,
      builder: (context) => _SpecialEventDialog(
        options: options,
        existing: existing,
      ),
    );

    if (!context.mounted) return;
    if (result == null || result.events.isEmpty) return;
    final events = List<String>.from(roster.specialEvents);
    for (final event in result.events) {
      if (!events.contains(event)) {
        events.add(event);
      }
    }
    final mergedColors = {
      ...roster.customEventColors,
      ...result.customColors,
    };
    context.read<RosterProvider>().updateRoster(
      roster.copyWith(specialEvents: events, customEventColors: mergedColors),
    );
  }

  void _removeSpecialEvent(BuildContext context, String event) {
    final events = List<String>.from(roster.specialEvents)..remove(event);
    final colors = Map<String, int>.from(roster.customEventColors)
      ..remove(event);
    context.read<RosterProvider>().updateRoster(
      roster.copyWith(specialEvents: events, customEventColors: colors),
    );
  }

  Future<void> _confirmRemoveSpecialEvent(
    BuildContext context,
    String event,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除「$event」嗎？'),
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

    if (!context.mounted) return;
    if (confirmed == true) {
      _removeSpecialEvent(context, event);
    }
  }

  Future<_PeopleOptions> _loadSelectablePeople(
    BuildContext context,
    ServiceType rosterType,
    List<String> extras,
    String? role,
  ) async {
    final provider = context.read<RosterProvider>();
    final users = await context.read<UserAdminProvider>().getUsers();
    final roleKey = role?.trim();
    final allUserNames = users
        .map((u) => u.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final extrasSet = extras
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final rosterPeople = roleKey == null || roleKey.isEmpty
        ? <String>{}
        : provider
              .getRostersByType(rosterType)
              .expand((roster) => roster.duties)
              .where((duty) => duty.role.trim() == roleKey)
              .expand((duty) => duty.people)
              .map((name) => name.trim())
              .where((name) => name.isNotEmpty && name != '待定')
              .toSet();
    final names = users
        .where(
          (u) => u.zones.any(
            (zone) =>
                zone.serviceType == rosterType &&
                (roleKey != null && roleKey.isNotEmpty
                    ? zone.ministries.contains(roleKey)
                    : false),
          ),
        )
        .map((u) => u.name.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    names.sort();
    final Set<String> merged = {...names, ...rosterPeople, ...extrasSet};
    final List<String> result = ['待定'];
    result.addAll(merged.where((name) => name != '待定'));
    final userIdsByName = <String, String>{};
    for (final user in users) {
      final name = user.name.trim();
      final uid = user.id.trim();
      if (name.isEmpty || uid.isEmpty) continue;
      userIdsByName.putIfAbsent(name, () => uid);
    }
    return _PeopleOptions(
      options: result,
      allUserNames: allUserNames,
      userIdsByName: userIdsByName,
    );
  }
}
