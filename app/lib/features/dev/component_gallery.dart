import 'package:flutter/material.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';

/// Every component in one page, for review in light and dark. Only in
/// development builds; the strings here are not user-facing and so are
/// not in the ARB file.
class ComponentGallery extends StatefulWidget {
  const ComponentGallery({super.key});

  @override
  State<ComponentGallery> createState() => _ComponentGalleryState();
}

class _ComponentGalleryState extends State<ComponentGallery> {
  bool _switch = true;
  bool _busy = false;
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('元件')),
      body: ListView(
        children: [
          const SectionHeader('按鈕'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: Column(
              children: [
                PrimaryButton(
                  label: '儲存',
                  busy: _busy,
                  onPressed: () async {
                    setState(() => _busy = true);
                    await Future<void>.delayed(const Duration(seconds: 1));
                    if (mounted) setState(() => _busy = false);
                  },
                ),
                const SizedBox(height: Space.s),
                SecondaryButton(label: '次要動作', expand: true, onPressed: () {}),
                SecondaryButton(
                  label: '退出教會',
                  expand: true,
                  destructive: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
          ListSection(
            header: '清單',
            footer: '說明文字只在必要時出現。',
            children: [
              ListRow(title: '有箭頭的列', onTap: () {}),
              ListRow(title: '有副標', subtitle: '副標一行', value: '值', onTap: () {}),
              ListRow(
                title: '有圖示',
                leading: const Icon(Icons.person_add_alt),
                onTap: () {},
              ),
              SwitchRow(
                title: '開關',
                value: _switch,
                onChanged: (v) => setState(() => _switch = v),
              ),
              ListRow(title: '刪除', destructive: true, onTap: () {}),
            ],
          ),
          ListSection(
            header: '單選',
            children: [
              for (final (i, label) in ['每週', '每月', '不重複'].indexed)
                ListRow(
                  title: label,
                  selected: _selected == i,
                  onTap: () => setState(() => _selected = i),
                ),
            ],
          ),
          const SectionHeader('標籤'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (var i = 0; i < EventColors.count; i++)
                  Tag.event(
                    context,
                    ['聖餐', '特會', '浸禮', '感恩', '青年', '宣教'][i],
                    i,
                  ),
                Tag(label: '我', background: c.accentSoft, foreground: c.accent),
              ],
            ),
          ),
          const SectionHeader('搜尋'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: SearchField(onChanged: (_) {}),
          ),
          ListSection(
            header: '回饋',
            children: [
              ListRow(
                title: '「已刪除・復原」提示',
                onTap: () => showToast(
                  context,
                  '已刪除',
                  onUndo: () => showToast(context, '已復原'),
                ),
              ),
              ListRow(
                title: '底部面板',
                onTap: () => showAppSheet<void>(
                  context,
                  builder: (context) => const SizedBox(
                    height: 240,
                    child: EmptyState(message: '下滑可以關閉'),
                  ),
                ),
              ),
              ListRow(
                title: '確認視窗',
                onTap: () => confirmDestructive(
                  context,
                  title: '退出〈恩典堂〉？',
                  message: '需要重新邀請才能回來',
                  action: '退出',
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 240,
            child: EmptyState(message: '還沒有人負責司琴', actionLabel: '新增同工'),
          ),
        ],
      ),
    );
  }
}
