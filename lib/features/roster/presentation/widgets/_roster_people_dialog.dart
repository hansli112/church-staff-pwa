part of 'roster_card.dart';

// ---------------------------------------------------------------------------
// _PeopleOptions – data class used by RosterCard and _RosterPeopleDialog
// ---------------------------------------------------------------------------

/// 選人視窗送出的一項服事。
///
/// [ranking] 只在有人拖過順序時才有值：候選名單裡名單上的同工由前到後，要
/// 存成這個服事項目的同工排序。沒拖過就是 null，不必寫排序。
typedef _PeopleSelection = ({
  String role,
  List<String> people,
  StaffRanking? ranking,
  Map<String, String> personIdsByName,
});

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

  /// 候選名單，已經照同工排序排好（見 [RosterProvider.staffOrderFor]）。
  final Future<_PeopleOptions> Function(String? role) peopleLoader;
  final List<String> initialPeople;
  final Map<String, String> initialPersonIdsByName;

  final void Function(_PeopleSelection selection) onSubmit;
  final String submitLabel;
  final bool roleEditable;
  final bool useBottomSheet;

  /// 有值時，視窗裡會多一顆「與其他日期交換」。編輯既有服事項目才給 ——
  /// 還不存在的項目沒有東西可以拿去換。
  final VoidCallback? onSwap;

  const _RosterPeopleDialog({
    required this.title,
    required this.rosterType,
    this.initialRoleText,
    required this.roleOptions,
    required this.initialRole,
    required this.peopleLoader,
    required this.initialPeople,
    this.initialPersonIdsByName = const {},
    required this.onSubmit,
    required this.submitLabel,
    this.roleEditable = true,
    this.useBottomSheet = false,
    this.onSwap,
  });

  @override
  State<_RosterPeopleDialog> createState() => _RosterPeopleDialogState();
}

class _RosterPeopleDialogState extends State<_RosterPeopleDialog> {
  late Set<String> _selectedPeople;
  late Set<String> _customNames;
  final Set<String> _removedCustomNames = {};
  List<String> _options = const [placeholderPerson];
  bool _optionsInitialized = false;

  /// 拖過順序了嗎。拖曳改的是這個服事項目在每一週的順序，不只這一天。
  bool _orderChanged = false;
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
      _selectedPeople = {placeholderPerson};
    }
    _customNames = widget.initialPeople
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != placeholderPerson)
        .toSet();
    _selectedRole = widget.initialRole;
    _peopleFuture = widget.peopleLoader(_selectedRole);
    _initialSelection = Set<String>.from(_selectedPeople);
  }

  /// 進場時勾了誰。按「與其他日期交換」會關掉這張視窗，關掉之前要拿它比對
  /// 有沒有還沒存的改動。
  late final Set<String> _initialSelection;

  /// 勾選或順序跟進場時不一樣了嗎。
  bool get _hasUnsavedChanges {
    // 名單還沒載進來時 _options 只有一個「待定」，這時候算出來的勾選一定跟
    // 進場時不一樣，會誤判成「改過」而多跳一次確認。
    if (!_optionsInitialized) return false;
    final selected = _buildSelectedPeople(_options);
    // 「沒有人」在 _buildSelectedPeople 會被補成 ['待定']，而 _initialSelection
    // 是原始勾選（可能是空的），兩邊都先把佔位符拿掉才比得準。
    final selectedSet = selected.where((n) => n != placeholderPerson).toSet();
    final initialSet = _initialSelection
        .where((n) => n != placeholderPerson)
        .toSet();
    if (!setEquals(selectedSet, initialSet)) return true;
    return _orderChanged;
  }

  /// 未存的改動要被丟掉時先問一聲。交換會重寫這一項的人，帶不過去。
  Future<bool> _confirmDiscardChanges() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('尚未儲存'),
        content: const Text('這裡改的人員還沒儲存，去交換會丟掉這些改動。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('留在這裡'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('丟掉並交換'),
          ),
        ],
      ),
    );
    return discard == true;
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

      if (name == placeholderPerson &&
          _selectedPeople.contains(placeholderPerson)) {
        _selectedPeople
          ..clear()
          ..add(placeholderPerson);
      } else if (_selectedPeople.length > 1 &&
          _selectedPeople.contains(placeholderPerson)) {
        _selectedPeople.remove(placeholderPerson);
      }

      if (_selectedPeople.isEmpty) {
        _selectedPeople.add(placeholderPerson);
      }
    });
  }

  void _addCustomName([String? raw]) {
    final name = (raw ?? _customController.text).trim();
    if (name.isEmpty) return;
    setState(() {
      if (name == placeholderPerson) {
        _selectedPeople
          ..clear()
          ..add(placeholderPerson);
      } else {
        _selectedPeople.add(name);
        _customNames.add(name);
        _selectedPeople.remove(placeholderPerson);
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
        _selectedPeople.add(placeholderPerson);
      }
    });
  }

  Future<void> _removeCustomNameAcrossRosters(String name, String role) async {
    final trimmed = name.trim();
    final roleKey = role.trim();
    if (trimmed.isEmpty || roleKey.isEmpty) return;
    final provider = context.read<RosterProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final updates = <ServiceRoster>[];
    for (final roster in provider.getRostersByType(widget.rosterType)) {
      var changed = false;
      final updatedDuties = roster.duties.map((duty) {
        if (duty.role.trim() != roleKey) return duty;
        if (!duty.people.contains(trimmed)) return duty;
        final people = duty.people.where((p) => p != trimmed).toList();
        final personIdsByName = Map<String, String>.from(duty.personIdsByName)
          ..remove(trimmed);
        changed = true;
        if (people.isEmpty) {
          return duty.copyWith(
            people: const [placeholderPerson],
            personIdsByName: personIdsByName,
          );
        }
        return duty.copyWith(people: people, personIdsByName: personIdsByName);
      }).toList();
      if (changed) updates.add(roster.copyWith(duties: updatedDuties));
    }
    // 一次送出而不是逐筆 await：逐筆的話中間一筆失敗，後面幾天就默默沒改。
    // updateRosters 會把成功的先寫回畫面，再把失敗的報上來。
    try {
      await provider.updateRosters(updates);
    } catch (e) {
      showWriteFailure(messenger, '刪除', e);
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
      return [placeholderPerson];
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
    final result = <String>[];
    if (merged.contains(placeholderPerson) ||
        baseOptions.contains(placeholderPerson)) {
      result.add(placeholderPerson);
    }
    final baseOrdered = baseOptions
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty && name != placeholderPerson)
        .toList();
    final baseSet = baseOrdered.toSet();
    result.addAll(baseOrdered);

    merged.remove(placeholderPerson);
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

  bool _isRankable(String name) =>
      name != placeholderPerson && _allUserNames.contains(name);

  void _submit() {
    final role = widget.roleEditable
        ? (_selectedRole ?? '').trim()
        : _roleController.text.trim();
    if (role.isEmpty) return;
    final selected = _buildSelectedPeople(_options);
    final selectedPersonIdsByName = <String, String>{};
    for (final name in selected) {
      final uid = _userIdsByName[name];
      if (uid == null || uid.trim().isEmpty) continue;
      selectedPersonIdsByName[name] = uid;
    }
    widget.onSubmit((
      role: role,
      people: selected,
      // 只收名單上的同工：外請講員這類名字寫進固定排序的話，之後新加入的
      // 同工都會排在他們後面。他們本來就拖不動（見 onReorder）。
      ranking: _orderChanged
          ? StaffRanking(role, _options.where(_allUserNames.contains).toList())
          : null,
      personIdsByName: selectedPersonIdsByName,
    ));
    Navigator.of(context).pop();
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
                  // 換了服事項目就換了一份排序，前一項拖過的順序不能帶過來。
                  _optionsInitialized = false;
                  _orderChanged = false;
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
        // 換班的入口。原本是服事列上的一顆 ⇄，但那顆佔掉的 44px 讓名字欄只
        // 剩 142px，三個名字就被擠成兩行 —— 名字才是這個畫面天天在看的東西。
        if (widget.onSwap != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                if (_hasUnsavedChanges && !await _confirmDiscardChanges()) {
                  return;
                }
                if (!mounted) return;
                // 先關掉這張 sheet：兩張疊著的話，換完回來的還是舊資料。
                Navigator.of(this.context).pop();
                widget.onSwap!();
              },
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('與其他日期交換'),
            ),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '選擇同工（拖曳排序會套用到每一週）',
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
              _syncOptions(data?.options ?? const [placeholderPerson]);
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
                    // 待定與名單外的人不進固定排序，拖了也存不起來，乾脆
                    // 不給拖 —— 否則畫面上排好的位置存完就跳回去。
                    if (!_isRankable(name)) return;
                    setState(() {
                      if (newIndex > oldIndex) {
                        newIndex -= 1;
                      }
                      final moved = _options.removeAt(oldIndex);
                      _options.insert(newIndex, moved);
                      _orderChanged = true;
                    });
                  },
                  itemBuilder: (context, index) {
                    final name = _options[index];
                    final checked = _selectedPeople.contains(name);
                    final isCustom =
                        name != placeholderPerson &&
                        !_allUserNames.contains(name);
                    final canDrag = _isRankable(name);
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
          onPressed: roleMissing ? null : _submit,
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
          onPressed: roleMissing ? null : _submit,
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}
