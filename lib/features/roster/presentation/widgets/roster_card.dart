import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/service_roster.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/roster_provider.dart';
import '../../../../core/widgets/settings_bottom_sheet.dart';

class RosterCard extends StatelessWidget {
  static final DateFormat _dateFormat = DateFormat('yyyy/MM/dd (E)', 'zh_TW');

  final ServiceRoster roster;
  final bool initiallyExpanded;
  final bool isEditMode;
  final int Function(ServiceType type, String name) eventColorFor;

  const RosterCard({
    super.key,
    required this.roster,
    this.initiallyExpanded = false,
    required this.isEditMode,
    required this.eventColorFor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return RepaintBoundary(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: isEditMode ? 4.0 : 2.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isEditMode
              ? BorderSide(color: colorScheme.primary, width: 2.0)
              : BorderSide.none,
        ),
        child: ExpansionTile(
          key: PageStorageKey(roster.id),
          initiallyExpanded: initiallyExpanded,
          leading: Icon(
            isEditMode ? Icons.edit_note : Icons.event_note,
            color: isEditMode ? colorScheme.primary : Colors.blueAccent,
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
                  child: RepaintBoundary(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ...roster.specialEvents.map((event) {
                            final colorValue = eventColorFor(
                              roster.type,
                              event,
                            );
                            final color = Color(colorValue);
                            final label = Text(
                              event,
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                            if (!isEditMode) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Chip(
                                  label: label,
                                  backgroundColor: color.withOpacity(0.12),
                                  side: BorderSide(
                                    color: color.withOpacity(0.4),
                                  ),
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
                                ),
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InputChip(
                                label: label,
                                backgroundColor: color.withOpacity(0.12),
                                side: BorderSide(color: color.withOpacity(0.4)),
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
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            );
                          }),
                          if (isEditMode)
                            ActionChip(
                              label: const Text('新增事件'),
                              onPressed: () =>
                                  _showAddSpecialEventDialog(context),
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
                              labelStyle: TextStyle(
                                color: Colors.orange[800],
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          trailing: isEditMode ? const Icon(Icons.drag_handle) : null,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: RepaintBoundary(
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
                          splashColor: colorScheme.primary.withOpacity(0.08),
                          highlightColor: colorScheme.primary.withOpacity(0.04),
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
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: Colors.redAccent,
                                  ),
                                  onPressed: () => _confirmRemoveDuty(
                                    context,
                                    index,
                                    duty.role,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
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
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDutyDialog(BuildContext context) async {
    final TextEditingController roleController = TextEditingController();
    final Future<_PeopleOptions> Function(String? role) peopleLoader = (role) =>
        _loadSelectablePeople(context, roster.type, const [], role);
    final roleOptions =
        context.read<RosterProvider>().templates[roster.type] ??
        const <String>[];

    return showDialog(
      context: context,
      builder: (context) {
        return _RosterPeopleDialog(
          title: '新增服事項目',
          rosterType: roster.type,
          roleController: roleController,
          roleOptions: roleOptions,
          initialRole: roleOptions.isNotEmpty ? roleOptions.first : null,
          peopleLoader: peopleLoader,
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

    if (confirmed == true) {
      _removeDuty(context, index);
    }
  }

  Future<void> _showEditDialog(
    BuildContext context,
    int index,
    RosterEntry duty,
  ) async {
    final Future<_PeopleOptions> Function(String? role) peopleLoader = (role) =>
        _loadSelectablePeople(
          context,
          roster.type,
          duty.people,
          role ?? duty.role,
        );

    await showDialog(
      context: context,
      builder: (context) {
        return _RosterPeopleDialog(
          title: '編輯 ${duty.role}',
          rosterType: roster.type,
          roleController: TextEditingController(text: duty.role),
          roleOptions: const [],
          initialRole: duty.role,
          peopleLoader: peopleLoader,
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

  Future<void> _showAddSpecialEventDialog(BuildContext context) async {
    final provider = context.read<RosterProvider>();
    final existing = roster.specialEvents.toSet();
    final options = provider
        .eventOptionsFor(roster.type)
        .where((e) => e.name.trim().isNotEmpty)
        .toList();
    final selected = <String>{};
    final scrollController = ScrollController();

    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('新增事件'),
            content: SizedBox(
              width: double.maxFinite,
              child: options.isEmpty
                  ? const Text('尚未設定可選事件')
                  : Scrollbar(
                      controller: scrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      child: ListView(
                        controller: scrollController,
                        shrinkWrap: true,
                        children: options.map((option) {
                          final isExisting = existing.contains(option.name);
                          final dotColor = Color(option.color);
                          return CheckboxListTile(
                            value: isExisting
                                ? true
                                : selected.contains(option.name),
                            onChanged: isExisting
                                ? null
                                : (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        selected.add(option.name);
                                      } else {
                                        selected.remove(option.name);
                                      }
                                    });
                                  },
                            title: Row(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: dotColor,
                                    border: Border.all(
                                      color: dotColor.withOpacity(0.6),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(option.name)),
                              ],
                            ),
                            dense: true,
                          );
                        }).toList(),
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, selected.toList()),
                child: const Text('新增'),
              ),
            ],
          ),
        );
      },
    );
    scrollController.dispose();

    if (result == null || result.isEmpty) return;
    final events = List<String>.from(roster.specialEvents);
    for (final event in result) {
      if (!events.contains(event)) {
        events.add(event);
      }
    }
    context.read<RosterProvider>().updateRoster(
      roster.copyWith(specialEvents: events),
    );
  }

  void _removeSpecialEvent(BuildContext context, String event) {
    final events = List<String>.from(roster.specialEvents)..remove(event);
    context.read<RosterProvider>().updateRoster(
      roster.copyWith(specialEvents: events),
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
    final users = await context.read<AuthProvider>().getUsers();
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
    return _PeopleOptions(options: result, allUserNames: allUserNames);
  }
}

class _PeopleOptions {
  final List<String> options;
  final Set<String> allUserNames;

  const _PeopleOptions({required this.options, required this.allUserNames});
}

class _RosterPeopleDialog extends StatefulWidget {
  final String title;
  final ServiceType rosterType;
  final TextEditingController roleController;
  final List<String> roleOptions;
  final String? initialRole;
  final Future<_PeopleOptions> Function(String? role) peopleLoader;
  final List<String> initialPeople;
  final void Function(String role, List<String> people) onSubmit;
  final String submitLabel;
  final bool roleEditable;
  final bool useBottomSheet;

  const _RosterPeopleDialog({
    required this.title,
    required this.rosterType,
    required this.roleController,
    required this.roleOptions,
    required this.initialRole,
    required this.peopleLoader,
    required this.initialPeople,
    required this.onSubmit,
    required this.submitLabel,
    this.roleEditable = true,
    this.useBottomSheet = false,
  });

  @override
  State<_RosterPeopleDialog> createState() => _RosterPeopleDialogState();
}

class _RosterPeopleDialogState extends State<_RosterPeopleDialog> {
  late Set<String> _selectedPeople;
  late Set<String> _customNames;
  final Set<String> _removedCustomNames = {};
  List<String> _options = const ['待定'];
  Set<String> _allUserNames = const {};
  String? _selectedRole;
  late final TextEditingController _customController;
  late final ScrollController _peopleScrollController;

  @override
  void initState() {
    super.initState();
    _customController = TextEditingController();
    _peopleScrollController = ScrollController();
    _selectedPeople = widget.initialPeople
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (_selectedPeople.isEmpty) {
      _selectedPeople = {'待定'};
    }
    _customNames = widget.initialPeople
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != '待定')
        .toSet();
    _selectedRole = widget.initialRole;
  }

  @override
  void dispose() {
    _customController.dispose();
    _peopleScrollController.dispose();
    super.dispose();
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

  void _addCustomName([String? raw]) {
    final name = (raw ?? _customController.text).trim();
    if (name.isEmpty) return;
    setState(() {
      if (name == '待定') {
        _selectedPeople
          ..clear()
          ..add('待定');
      } else {
        _selectedPeople.add(name);
        _customNames.add(name);
        _selectedPeople.remove('待定');
      }
    });
    _customController.clear();
  }

  void _removeCustomName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _customNames.remove(trimmed);
      _selectedPeople.remove(trimmed);
      _removedCustomNames.add(trimmed);
      _options = _options.where((option) => option != trimmed).toList();
      if (_selectedPeople.isEmpty) {
        _selectedPeople.add('待定');
      }
    });
  }

  Future<void> _removeCustomNameAcrossRosters(String name, String role) async {
    final trimmed = name.trim();
    final roleKey = role.trim();
    if (trimmed.isEmpty || roleKey.isEmpty) return;
    final provider = context.read<RosterProvider>();
    final rosters = provider.getRostersByType(widget.rosterType);
    for (final roster in rosters) {
      var changed = false;
      final updatedDuties = roster.duties.map((duty) {
        if (duty.role.trim() != roleKey) return duty;
        if (!duty.people.contains(trimmed)) return duty;
        final people = duty.people.where((p) => p != trimmed).toList();
        changed = true;
        if (people.isEmpty) {
          return duty.copyWith(people: const ['待定']);
        }
        return duty.copyWith(people: people);
      }).toList();
      if (changed) {
        await provider.updateRoster(roster.copyWith(duties: updatedDuties));
      }
    }
  }

  Future<void> _confirmRemoveCustomName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除「$trimmed」嗎？'),
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
      final role = (_selectedRole ?? widget.initialRole ?? '').trim();
      _removeCustomName(trimmed);
      await _removeCustomNameAcrossRosters(trimmed, role);
    }
  }

  Future<void> _showCustomInputSheet() async {
    _customController.clear();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SettingsBottomSheet(
          title: '新增名單以外的人員',
          submitLabel: '加入',
          onSubmit: () {
            _addCustomName();
            Navigator.of(context).pop();
          },
          child: TextField(
            controller: _customController,
            decoration: InputDecoration(
              hintText: '例：外請講員',
              isDense: true,
              filled: true,
              fillColor: Theme.of(
                context,
              ).colorScheme.surfaceVariant.withOpacity(0.35),
              hintStyle: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withOpacity(0.35),
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (value) {
              _addCustomName(value);
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }

  List<String> _buildSelectedPeople(List<String> options) {
    final selected = options.where(_selectedPeople.contains).toList();
    if (selected.isEmpty) {
      return ['待定'];
    }
    return selected;
  }

  List<String> _mergeOptions(List<String> baseOptions) {
    final merged = <String>{};
    for (final name in baseOptions) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty) merged.add(trimmed);
    }
    for (final name in _selectedPeople) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty) merged.add(trimmed);
    }
    for (final name in _customNames) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty) merged.add(trimmed);
    }
    merged.remove('待定');
    final sorted = merged.toList()..sort();
    return ['待定', ...sorted];
  }

  @override
  Widget build(BuildContext context) {
    final canSelectRole = widget.roleEditable && widget.roleOptions.isNotEmpty;
    final roleMissing = widget.roleEditable && widget.roleOptions.isEmpty;
    final content = Column(
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
              return DropdownMenuItem(value: role, child: Text(role));
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
          child: FutureBuilder<_PeopleOptions>(
            future: widget.peopleLoader(_selectedRole),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('載入同工名單失敗: ${snapshot.error}'));
              }

              final data = snapshot.data;
              _options = _mergeOptions(data?.options ?? const ['待定']);
              if (_removedCustomNames.isNotEmpty) {
                _options = _options
                    .where((name) => !_removedCustomNames.contains(name))
                    .toList();
              }
              _allUserNames = data?.allUserNames ?? const {};
              return Scrollbar(
                controller: _peopleScrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: ListView.builder(
                  controller: _peopleScrollController,
                  itemCount: _options.length,
                  itemBuilder: (context, index) {
                    final name = _options[index];
                    final checked = _selectedPeople.contains(name);
                    final isCustom =
                        name != '待定' && !_allUserNames.contains(name);
                    return CheckboxListTile(
                      title: Text(name),
                      value: checked,
                      onChanged: (_) => _toggleSelection(name),
                      secondary: isCustom
                          ? IconButton(
                              tooltip: '刪除自訂項目',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => _confirmRemoveCustomName(name),
                            )
                          : null,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    );
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _showCustomInputSheet,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新增名單以外的人員'),
          ),
        ),
      ],
    );

    final actions = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
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

    if (widget.useBottomSheet) {
      final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
      final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(child: content),
              ),
              const SizedBox(height: 12),
              actions,
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(width: double.maxFinite, child: content),
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
