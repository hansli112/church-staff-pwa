import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/event_option.dart';
import '../providers/roster_provider.dart';

class EventSettingsScreen extends StatefulWidget {
  const EventSettingsScreen({super.key});

  @override
  State<EventSettingsScreen> createState() => _EventSettingsScreenState();
}

class _EventSettingsScreenState extends State<EventSettingsScreen> {
  late List<EventOption> _editingOptions;
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
    _editingOptions = List<EventOption>.from(provider.eventOptions);
  }

  Future<void> _promptAddEvent() async {
    final controller = TextEditingController();
    final result = await _showEventDialog(
      title: '新增事件',
      controller: controller,
      existing: _editingOptions,
      initialColor: 0xFFF39C12,
    );
    if (result == null) return;
    setState(() => _editingOptions.add(result));
  }

  Future<void> _promptEditEvent(int index) async {
    final current = _editingOptions[index];
    final controller = TextEditingController(text: current.name);
    final result = await _showEventDialog(
      title: '編輯事件',
      controller: controller,
      existing: _editingOptions,
      currentName: current.name,
      initialColor: current.color,
    );
    if (result == null) return;
    setState(() => _editingOptions[index] = result);
  }

  Future<void> _confirmRemoveEvent(int index) async {
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
      setState(() => _editingOptions.removeAt(index));
    }
  }

  Future<EventOption?> _showEventDialog({
    required String title,
    required TextEditingController controller,
    required List<EventOption> existing,
    String? currentName,
    required int initialColor,
  }) {
    return showDialog<EventOption>(
      context: context,
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

        void submit() {
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
          builder: (context, setState) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '事件名稱',
                    border: const OutlineInputBorder(),
                    errorText: errorText,
                  ),
                  onChanged: (value) =>
                      setState(() => errorText = validateValue(value)),
                  onSubmitted: (_) => submit(),
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
                      onTap: () => setState(() => selectedColor = colorValue),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(colorValue),
                          border: Border.all(
                            color: isSelected ? Colors.black54 : Colors.white,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              TextButton(onPressed: submit, child: const Text('儲存')),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('事件選項設定'),
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
      body: Column(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _editingOptions.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) {
                    newIndex -= 1;
                  }
                  final item = _editingOptions.removeAt(oldIndex);
                  _editingOptions.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                return ListTile(
                  key: ValueKey(
                    'event_${index}_${_editingOptions[index].name}',
                  ),
                  title: Text(_editingOptions[index].name),
                  onTap: () => _promptEditEvent(index),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(_editingOptions[index].color),
                          border: Border.all(
                            color: Color(
                              _editingOptions[index].color,
                            ).withOpacity(0.6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmRemoveEvent(index),
                      ),
                      const Icon(Icons.drag_handle),
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
              onTap: _promptAddEvent,
            ),
          ),
        ],
      ),
    );
  }
}
