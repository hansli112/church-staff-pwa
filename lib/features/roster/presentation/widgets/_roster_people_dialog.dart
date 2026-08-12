part of 'roster_card.dart';

// ---------------------------------------------------------------------------
// _PeopleOptions – data class used by RosterCard and _RosterPeopleDialog
// ---------------------------------------------------------------------------

class _PeopleOptions {
  final List<String> options;
  final Set<String> allUserNames;
  final Map<String, String> userIdsByName;

  const _PeopleOptions({
    required this.options,
    required this.allUserNames,
    required this.userIdsByName,
  });
}

// ---------------------------------------------------------------------------
// _RosterPeopleDialog
// ---------------------------------------------------------------------------

class _RosterPeopleDialog extends StatefulWidget {
  final String title;
  final ServiceType rosterType;
  final String? initialRoleText;
  final List<String> roleOptions;
  final String? initialRole;
  final List<String> initialOrder;
  final Future<_PeopleOptions> Function(String? role) peopleLoader;
  final List<String> initialPeople;
  final Map<String, String> initialPersonIdsByName;
  final void Function(
    String role,
    List<String> people,
    List<String> order,
    Map<String, String> personIdsByName,
  )
  onSubmit;
  final String submitLabel;
  final bool roleEditable;
  final bool useBottomSheet;

  const _RosterPeopleDialog({
    required this.title,
    required this.rosterType,
    this.initialRoleText,
    required this.roleOptions,
    required this.initialRole,
    required this.initialOrder,
    required this.peopleLoader,
    required this.initialPeople,
    this.initialPersonIdsByName = const {},
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
  bool _optionsInitialized = false;
  Set<String> _allUserNames = const {};
  Map<String, String> _userIdsByName = const {};
  String? _selectedRole;
  late Future<_PeopleOptions> _peopleFuture;
  late final TextEditingController _customController;
  late final TextEditingController _roleController;
  late final ScrollController _peopleScrollController;

  @override
  void initState() {
    super.initState();
    _customController = TextEditingController();
    _roleController = TextEditingController(text: widget.initialRoleText ?? '');
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
    _peopleFuture = widget.peopleLoader(_selectedRole);
  }

  @override
  void dispose() {
    _customController.dispose();
    _roleController.dispose();
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

      if (_selectedPeople.isEmpty) {
        _selectedPeople.add('待定');
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
        final order = duty.peopleOrder.where((p) => p != trimmed).toList();
        final personIdsByName = Map<String, String>.from(duty.personIdsByName)
          ..remove(trimmed);
        changed = true;
        if (people.isEmpty) {
          return duty.copyWith(
            people: const ['待定'],
            peopleOrder: order,
            personIdsByName: personIdsByName,
          );
        }
        return duty.copyWith(
          people: people,
          peopleOrder: order,
          personIdsByName: personIdsByName,
        );
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
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              hintStyle: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.35),
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

  List<String> _buildSelectedOrder(
    List<String> options,
    List<String> selected,
  ) {
    final selectedSet = selected.where((name) => name != '待定').toSet();
    if (selectedSet.isEmpty) return const [];

    final ordered = options
        .where((name) => name != '待定' && selectedSet.contains(name))
        .toList();
    final existing = ordered.toSet();
    for (final name in selected) {
      if (name == '待定' || existing.contains(name)) continue;
      ordered.add(name);
    }
    return ordered;
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
    final result = <String>[];
    if (merged.contains('待定') || baseOptions.contains('待定')) {
      result.add('待定');
    }
    final baseOrdered =
        (widget.initialOrder.isNotEmpty ? widget.initialOrder : baseOptions)
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty && name != '待定')
            .toList();
    final baseSet = baseOrdered.toSet();
    result.addAll(baseOrdered);

    merged.remove('待定');
    final remaining = merged.where((name) => !baseSet.contains(name)).toList()
      ..sort();
    result.addAll(remaining);
    return result;
  }

  void _syncOptions(List<String> baseOptions) {
    if (!_optionsInitialized) {
      _options = _mergeOptions(baseOptions);
      _optionsInitialized = true;
      return;
    }

    final merged = _mergeOptions(baseOptions).toSet();
    _options = _options.where(merged.contains).toList();
    final existing = _options.toSet();
    final missing = merged.where((name) => !existing.contains(name)).toList()
      ..sort();
    if (missing.isNotEmpty) {
      _options = [..._options, ...missing];
    }
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
            controller: _roleController,
            decoration: const InputDecoration(labelText: '職位名稱'),
            enabled: false,
          ),
        if (canSelectRole)
          DropdownButtonFormField<String>(
            initialValue: _selectedRole,
            decoration: const InputDecoration(labelText: '服事項目'),
            items: widget.roleOptions.map((role) {
              return DropdownMenuItem(value: role, child: Text(role));
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedRole = value;
                  _peopleFuture = widget.peopleLoader(_selectedRole);
                });
              }
            },
          ),
        if (roleMissing)
          Builder(
            builder: (context) => Text(
              '請先到「服事項目設定」新增項目',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '選擇同工',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 280,
          child: FutureBuilder<_PeopleOptions>(
            future: _peopleFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('載入同工名單失敗: ${snapshot.error}'));
              }

              final data = snapshot.data;
              _syncOptions(data?.options ?? const ['待定']);
              if (_removedCustomNames.isNotEmpty) {
                _options = _options
                    .where((name) => !_removedCustomNames.contains(name))
                    .toList();
              }
              _allUserNames = data?.allUserNames ?? const {};
              _userIdsByName = {
                ...widget.initialPersonIdsByName,
                ...(data?.userIdsByName ?? const <String, String>{}),
              };
              return Scrollbar(
                controller: _peopleScrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: ReorderableListView.builder(
                  scrollController: _peopleScrollController,
                  itemCount: _options.length,
                  buildDefaultDragHandles: true,
                  onReorder: (oldIndex, newIndex) {
                    final name = _options[oldIndex];
                    if (name == '待定') {
                      return;
                    }
                    setState(() {
                      if (newIndex > oldIndex) {
                        newIndex -= 1;
                      }
                      final moved = _options.removeAt(oldIndex);
                      _options.insert(newIndex, moved);
                    });
                  },
                  itemBuilder: (context, index) {
                    final name = _options[index];
                    final checked = _selectedPeople.contains(name);
                    final isCustom =
                        name != '待定' && !_allUserNames.contains(name);
                    final canDrag = name != '待定';
                    return CheckboxListTile(
                      key: ValueKey('option-$name'),
                      title: Text(name),
                      value: checked,
                      onChanged: (_) => _toggleSelection(name),
                      secondary: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCustom)
                            IconButton(
                              tooltip: '刪除自訂項目',
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => _confirmRemoveCustomName(name),
                            ),
                          Icon(
                            Icons.drag_handle,
                            size: 18,
                            color: canDrag
                                ? Colors.grey.shade700
                                : Colors.grey.shade300,
                          ),
                        ],
                      ),
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
                      : _roleController.text.trim();
                  if (role.isEmpty) return;
                  final selected = _buildSelectedPeople(_options);
                  final order = _buildSelectedOrder(_options, selected);
                  final selectedPersonIdsByName = <String, String>{};
                  for (final name in selected) {
                    final uid = _userIdsByName[name];
                    if (uid == null || uid.trim().isEmpty) continue;
                    selectedPersonIdsByName[name] = uid;
                  }
                  widget.onSubmit(
                    role,
                    selected,
                    order,
                    selectedPersonIdsByName,
                  );
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
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(child: content),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
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
                      : _roleController.text.trim();
                  if (role.isEmpty) return;
                  final selected = _buildSelectedPeople(_options);
                  final order = _buildSelectedOrder(_options, selected);
                  final selectedPersonIdsByName = <String, String>{};
                  for (final name in selected) {
                    final uid = _userIdsByName[name];
                    if (uid == null || uid.trim().isEmpty) continue;
                    selectedPersonIdsByName[name] = uid;
                  }
                  widget.onSubmit(
                    role,
                    selected,
                    order,
                    selectedPersonIdsByName,
                  );
                  Navigator.of(context).pop();
                },
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}
