import 'package:flutter/material.dart';

import '../../domain/entities/event_option.dart';

/// 活動標籤的選色：[eventColorPalette] 排成每排 [columns] 個的格子。
///
/// 用固定的格子而不是 Wrap：Wrap 一排放幾個看螢幕寬度，十個顏色會排成
/// 7+3 或 8+2，一邊長一邊短。色盤照「上排亮色、下排同色系深色」排好了，
/// 格子才對得上。活動設定頁與單次活動的視窗共用這一個，兩邊才長得一樣。
class EventColorPicker extends StatelessWidget {
  const EventColorPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  static const int columns = 5;

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var start = 0; start < eventColorPalette.length; start += columns)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final color in eventColorPalette.skip(start).take(columns))
                _Swatch(
                  color: color,
                  isSelected: color == selected,
                  onTap: () => onSelected(color),
                ),
            ],
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final int color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.all(11),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color(color),
            border: Border.all(
              color: isSelected ? Colors.black54 : Colors.white,
              width: isSelected ? 2 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
