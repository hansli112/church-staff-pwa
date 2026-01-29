import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/event_option.dart';
import '../../domain/entities/service_roster.dart';
import '../providers/roster_provider.dart';

class EventSettingsScreen extends StatefulWidget {
  const EventSettingsScreen({super.key});

  @override
  State<EventSettingsScreen> createState() => _EventSettingsScreenState();
}

class _EventSettingsScreenState extends State<EventSettingsScreen> {
  late Map<ServiceType, List<EventOption>> _editingOptions;
  final List<int> _palette = const [
    0xFFF39C12, // amber
    0xFF27AE60, // green
    0xFF3498DB, // blue
    0xFF9B59B6, // purple
    0xFFE74C3C, // red
    0xFF7F8C8D, // gray
  ];

  @override
  void initState() {
    super.initState();
    final provider = context.read<RosterProvider>();
    _editingOptions = Map.fromEntries(
      provider.eventOptionsByType.entries.map(
        (entry) => MapEntry(entry.key, List<EventOption>.from(entry.value)),
      ),
    );
    for (final type in ServiceType.values) {
      _editingOptions.putIfAbsent(type, () => <EventOption>[]);
    }
  }

  Future<void> _promptAddEvent(ServiceType type) async {
    final controller = TextEditingController();
    final result = await _showEventDialog(
      title: '新增事件',
      controller: controller,
      existing: _editingOptions[type] ?? const <EventOption>[],
      initialColor: 0xFFF39C12,
    );
    if (result == null) return;
    setState(() => _editingOptions[type]?.add(result));
  }

  Future<void> _promptEditEvent(ServiceType type, int index) async {
    final current = _editingOptions[type]?[index];
    if (current == null) return;
    final controller = TextEditingController(text: current.name);
    final result = await _showEventDialog(
      title: '編輯事件',
      controller: controller,
      existing: _editingOptions[type] ?? const <EventOption>[],
      currentName: current.name,
      initialColor: current.color,
    );
    if (result == null) return;
    setState(() => _editingOptions[type]?[index] = result);
  }

  Future<void> _confirmRemoveEvent(ServiceType type, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: const Text('確定要刪除此事件嗎？'),
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
      setState(() => _editingOptions[type]?.removeAt(index));
    }
  }

  Future<EventOption?> _showEventDialog({
    required String title,
    required TextEditingController controller,
    required List<EventOption> existing,
    String? currentName,
    required int initialColor,
  }) {
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    return showModalBottomSheet<EventOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        String? errorText;
        int selectedColor = initialColor;
        String? validateValue(String value) {
          final trimmed = value.trim();
          if (trimmed.isEmpty) return '請輸入名稱';
          final isDuplicate = existing.any(
            (name) =>
                name.name.trim() == trimmed &&
                name.name.trim() != currentName?.trim(),
          );
          if (isDuplicate) return '名稱已存在';
          return null;
        }

        void submit(StateSetter setState) {
          final value = controller.text;
          final validation = validateValue(value);
          if (validation != null) {
            setState(() => errorText = validation);
            return;
          }
          Navigator.pop(
            context,
            EventOption(name: value.trim(), color: selectedColor),
          );
        }

        return StatefulBuilder(
          builder: (context, setState) {
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
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      fit: FlexFit.loose,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                labelText: '事件名稱',
                                hintText: '例：聖餐主日',
                                hintStyle: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.35),
                                ),
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.always,
                                border: const OutlineInputBorder(),
                                errorText: errorText,
                              ),
                              onChanged: (value) =>
                                  setState(() => errorText = validateValue(value)),
                              onSubmitted: (_) => submit(setState),
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '標籤顏色',
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _palette.map((colorValue) {
                                final isSelected = selectedColor == colorValue;
                                return InkWell(
                                  onTap: () =>
                                      setState(() => selectedColor = colorValue),
                                  borderRadius: BorderRadius.circular(999),
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Color(colorValue),
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.black54
                                            : Colors.white,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => submit(setState),
                          child: const Text('儲存'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: ServiceType.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('事件選項設定'),
          bottom: TabBar(
            tabs: ServiceType.values
                .map((type) => Tab(text: type.label))
                .toList(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: () async {
                await context.read<RosterProvider>().updateEventOptions(
                  _editingOptions,
                );
                if (mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
        body: TabBarView(
          children: ServiceType.values.map((type) {
            final options = _editingOptions[type] ?? const <EventOption>[];
            return Column(
              children: [
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: options.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        final item = options.removeAt(oldIndex);
                        options.insert(newIndex, item);
                        _editingOptions[type] = List<EventOption>.from(options);
                      });
                    },
                    itemBuilder: (context, index) {
                      return ListTile(
                        key: ValueKey(
                          'event_${type.name}_${index}_${options[index].name}',
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                        horizontalTitleGap: 12,
                        minLeadingWidth: 24,
                        leading: SizedBox(
                          width: 24,
                          child: Center(
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(options[index].color),
                                border: Border.all(
                                  color: Color(
                                    options[index].color,
                                  ).withOpacity(0.6),
                                ),
                              ),
                            ),
                          ),
                        ),
                        title: Text(options[index].name),
                        onTap: () => _promptEditEvent(type, index),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _confirmRemoveEvent(type, index),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: const SizedBox(
                                width: 24,
                                child: Center(
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('新增事件'),
                    onTap: () => _promptAddEvent(type),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
