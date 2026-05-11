part of 'roster_card.dart';

// ---------------------------------------------------------------------------
// _SpecialEventDialogResult
// ---------------------------------------------------------------------------

class _SpecialEventDialogResult {
  final List<String> events;
  final Map<String, int> customColors;
  const _SpecialEventDialogResult(this.events, this.customColors);
}

// ---------------------------------------------------------------------------
// _SpecialEventDialog
// ---------------------------------------------------------------------------

class _SpecialEventDialog extends StatefulWidget {
  final List<EventOption> options;
  final Set<String> existing;

  const _SpecialEventDialog({
    required this.options,
    required this.existing,
  });

  @override
  State<_SpecialEventDialog> createState() => _SpecialEventDialogState();
}

class _SpecialEventDialogState extends State<_SpecialEventDialog> {
  late final Set<String> _selected;
  late final Set<String> _customEvents;
  final Map<String, int> _customEventColors = {};
  static const int _defaultCustomColor = 0xFFF39C12;
  int _pendingCustomColor = _defaultCustomColor;
  late final TextEditingController _customController;
  late final ScrollController _scrollController;

  static const _colorPalette = [
    0xFFF39C12,
    0xFF27AE60,
    0xFF3498DB,
    0xFF9B59B6,
    0xFFE74C3C,
    0xFF7F8C8D,
  ];

  @override
  void initState() {
    super.initState();
    _selected = {};
    _customEvents = {};
    _customController = TextEditingController();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _customController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addCustomEvent([String? raw]) {
    final name = (raw ?? _customController.text).trim();
    if (name.isEmpty) return;
    if (widget.options.any((o) => o.name == name)) return;
    setState(() {
      _customEvents.add(name);
      _selected.add(name);
      _customEventColors[name] = _pendingCustomColor;
    });
    _customController.clear();
    _pendingCustomColor = _defaultCustomColor;
  }

  void _removeCustomEvent(String name) {
    setState(() {
      _customEvents.remove(name);
      _selected.remove(name);
      _customEventColors.remove(name);
    });
  }

  Future<void> _confirmRemoveCustomEvent(String name) async {
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
    if (!mounted) return;
    if (confirmed == true) {
      _removeCustomEvent(trimmed);
    }
  }

  Future<void> _showCustomInputSheet() async {
    _customController.clear();
    _pendingCustomColor = _defaultCustomColor;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SettingsBottomSheet(
              title: '新增選項以外的事件',
              submitLabel: '加入',
              onSubmit: () {
                _addCustomEvent();
                Navigator.of(sheetContext).pop();
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _customController,
                    decoration: InputDecoration(
                      hintText: '例：特別奉獻',
                      isDense: true,
                      filled: true,
                      fillColor: Theme.of(
                        sheetContext,
                      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      hintStyle: TextStyle(
                        color: Theme.of(
                          sheetContext,
                        ).colorScheme.onSurface.withValues(alpha: 0.35),
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (value) {
                      _addCustomEvent(value);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '標籤顏色',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 0,
                    runSpacing: 0,
                    children: _colorPalette.map((colorValue) {
                      final isSelected = _pendingCustomColor == colorValue;
                      return InkWell(
                        onTap: () {
                          setSheetState(() {
                            _pendingCustomColor = colorValue;
                          });
                        },
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.all(11),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(colorValue),
                              border: isSelected
                                  ? Border.all(
                                      color: Colors.black54,
                                      width: 2,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEventTile({
    required String name,
    required Color dotColor,
    required bool isExisting,
    required bool isSelected,
    required ValueChanged<bool?> onChanged,
    VoidCallback? onRemove,
  }) {
    return CheckboxListTile(
      value: isExisting || isSelected,
      onChanged: isExisting ? null : onChanged,
      title: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              border: Border.all(color: dotColor.withValues(alpha: 0.8)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(name)),
        ],
      ),
      controlAffinity: ListTileControlAffinity.leading,
      secondary: onRemove != null
          ? IconButton(
              tooltip: '刪除自訂項目',
              constraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 48,
              ),
              icon: const Icon(Icons.close, size: 18),
              onPressed: onRemove,
            )
          : null,
      dense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selected.isNotEmpty;

    return AlertDialog(
      title: const Text('新增事件'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.options.isNotEmpty || _customEvents.isNotEmpty)
              Flexible(
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: ListView(
                    controller: _scrollController,
                    shrinkWrap: true,
                    children: [
                      ...widget.options.map((option) {
                        final isExisting =
                            widget.existing.contains(option.name);
                        return _buildEventTile(
                          name: option.name,
                          dotColor: Color(option.color),
                          isExisting: isExisting,
                          isSelected: _selected.contains(option.name),
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selected.add(option.name);
                              } else {
                                _selected.remove(option.name);
                              }
                            });
                          },
                        );
                      }),
                      ..._customEvents.map((name) {
                        final customColor = Color(
                          _customEventColors[name] ?? _defaultCustomColor,
                        );
                        return _buildEventTile(
                          name: name,
                          dotColor: customColor,
                          isExisting: false,
                          isSelected: _selected.contains(name),
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                _selected.add(name);
                              } else {
                                _selected.remove(name);
                              }
                            });
                          },
                          onRemove: () => _confirmRemoveCustomEvent(name),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _showCustomInputSheet,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新增選項以外的事件'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: hasSelection
              ? () {
                  final selectedList = _selected.toList();
                  final filteredColors = Map<String, int>.fromEntries(
                    _customEventColors.entries.where(
                      (e) => selectedList.contains(e.key),
                    ),
                  );
                  Navigator.pop(
                    context,
                    _SpecialEventDialogResult(selectedList, filteredColors),
                  );
                }
              : null,
          child: const Text('新增'),
        ),
      ],
    );
  }
}
