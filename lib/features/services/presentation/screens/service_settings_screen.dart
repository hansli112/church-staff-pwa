import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/config/church_config.dart';
import '../../../../core/utils/error_messages.dart';
import '../providers/service_catalog_provider.dart';

const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

String weekdayLabel(int weekday) => '星期${_weekdayNames[weekday - 1]}';

/// 管理員設定每週固定的聚會：新增、改名、改星期、調順序、停用。
///
/// 不能刪除，只能停用：服事表、同工的牧區、服事項目樣板都用聚會 ID 對應，
/// 刪掉 ID 就對不回去了。
class ServiceSettingsScreen extends StatefulWidget {
  const ServiceSettingsScreen({super.key});

  @override
  State<ServiceSettingsScreen> createState() => _ServiceSettingsScreenState();
}

class _ServiceSettingsScreenState extends State<ServiceSettingsScreen> {
  late List<ServiceDefinition> _services;
  late final List<ServiceDefinition> _original;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _original = List.of(ChurchConfig.current.services);
    _services = List.of(_original);
  }

  bool get _hasUnsavedChanges =>
      _services.length != _original.length ||
      Iterable.generate(
        _services.length,
      ).any((i) => _services[i] != _original[i]);

  static String _newId() {
    // 字母開頭、只有英數：符合部署設定與 rules 對聚會 ID 的要求。
    final random = Random().nextInt(1 << 20).toRadixString(36);
    return 'svc${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}$random';
  }

  Future<void> _edit({int? index}) async {
    final existing = index == null ? null : _services[index];
    final result = await showDialog<ServiceDefinition>(
      context: context,
      builder: (_) => _ServiceDialog(
        initial: existing,
        otherLabels: {
          for (final (i, service) in _services.indexed)
            if (i != index) service.label,
        },
        newId: _newId,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _services.add(result);
      } else {
        _services[index] = result;
      }
    });
  }

  Future<void> _save() async {
    if (!_services.any((service) => service.enabled)) {
      _showMessage('至少要有一個聚會是開啟的。');
      return;
    }
    if (!_hasUnsavedChanges) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      // 網頁版存好會整頁重新載入，換成新的分頁；其他平台直接回上一頁。
      await context.read<ServiceCatalogProvider>().save(_services);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('已儲存聚會設定')));
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('儲存失敗：${mapErrorToUserMessage(e)}');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('還沒儲存'),
        content: const Text('剛才的變更還沒儲存。要儲存的話，請按右上角 ✓。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('繼續編輯'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('不儲存，離開'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('聚會設定'),
          actions: [
            IconButton(
              tooltip: '儲存',
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '每週固定的聚會。改完按右上角 ✓ 儲存，所有人的 App 下次打開就會換成新的設定。\n'
                '・改星期：已經排好的日期不會搬動，從下一個還沒排的那週開始用新的星期。\n'
                '・停用：不再出現在服事表分頁，也不再產生新的日期；舊資料都會保留，之後可以再開啟。\n'
                '・按住右邊的把手可以調整順序（服事表分頁的順序）。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _services.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    _services.insert(newIndex, _services.removeAt(oldIndex));
                  });
                },
                itemBuilder: (context, index) {
                  final service = _services[index];
                  return ListTile(
                    key: ValueKey(service.id),
                    title: Text('${service.label}｜${service.name}'),
                    subtitle: Text(
                      service.enabled
                          ? '每週${weekdayLabel(service.weekday)}'
                          : '已停用（原本每週${weekdayLabel(service.weekday)}）',
                    ),
                    onTap: () => _edit(index: index),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: service.enabled,
                          onChanged: (value) => setState(
                            () => _services[index] = service.copyWith(
                              enabled: value,
                            ),
                          ),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
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
                title: const Text('新增聚會'),
                enabled: _services.length < 20,
                subtitle: _services.length < 20
                    ? null
                    : const Text('最多 20 種聚會'),
                onTap: () => _edit(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceDialog extends StatefulWidget {
  const _ServiceDialog({
    required this.initial,
    required this.otherLabels,
    required this.newId,
  });

  final ServiceDefinition? initial;
  final Set<String> otherLabels;
  final String Function() newId;

  @override
  State<_ServiceDialog> createState() => _ServiceDialogState();
}

class _ServiceDialogState extends State<_ServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _label = TextEditingController(text: widget.initial?.label ?? '');
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late int _weekday = widget.initial?.weekday ?? 7;

  @override
  void dispose() {
    _label.dispose();
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final label = _label.text.trim();
    final name = _name.text.trim();
    final initial = widget.initial;
    Navigator.of(context).pop(
      initial == null
          ? ServiceDefinition(
              id: widget.newId(),
              label: label,
              name: name,
              weekday: _weekday,
              enabled: true,
            )
          : initial.copyWith(label: label, name: name, weekday: _weekday),
    );
  }

  String? _text(String? value, {required int max, bool unique = false}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '請填寫';
    if (text.length > max) return '最多 $max 個字';
    if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) return '不能有特殊字元';
    if (unique && widget.otherLabels.contains(text)) return '已經有同樣簡稱的聚會';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '新增聚會' : '修改聚會'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _label,
              autofocus: widget.initial == null,
              decoration: const InputDecoration(
                labelText: '簡稱',
                helperText: '顯示在服事表分頁上，例如「主日」「禱告會」',
              ),
              validator: (value) => _text(value, max: 20, unique: true),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '完整名稱',
                helperText: '例如「主日崇拜」「週三禱告會」',
              ),
              validator: (value) => _text(value, max: 80),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _weekday,
              decoration: const InputDecoration(labelText: '每週'),
              items: [
                for (var day = 1; day <= 7; day++)
                  DropdownMenuItem(value: day, child: Text(weekdayLabel(day))),
              ],
              onChanged: (value) =>
                  setState(() => _weekday = value ?? _weekday),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('確定')),
      ],
    );
  }
}
