import 'package:flutter/material.dart';

import '../../domain/entities/recent_activity.dart';

/// 首頁「近期活動」的一列：左邊日期、右邊標題。
///
/// 抽成獨立 widget 是為了讓版面能被測試盯住。日期欄是
/// `Expanded(flex: 2)` + 單行 + ellipsis —— 字串太長不會報錯，只會被默默
/// 截掉，肉眼在開發機上又不見得看得出來。recent_activity_row_test.dart 會
/// 用 TextPainter 量實際字寬並跟欄寬比對，超出就讓測試紅。
class RecentActivityRow extends StatelessWidget {
  const RecentActivityRow({super.key, required this.activity});

  final RecentActivity activity;

  /// 日期欄與標題欄的寬度比。固定比例（而不是讓日期照自然寬度）是為了讓
  /// 每一列的標題都從同一個 x 起始 —— 「全日」與「有時間」兩種格式的自然
  /// 寬度不同，不固定就會參差不齊。
  static const int dateFlex = 2;
  static const int titleFlex = 3;
  static const double columnGap = 8;

  static const TextStyle dateStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle titleStyle = TextStyle(fontSize: 13);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: dateFlex,
            child: Text(
              formatRecentActivityDate(activity),
              key: const ValueKey('recent-activity-date'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dateStyle,
            ),
          ),
          const SizedBox(width: columnGap),
          Expanded(
            flex: titleFlex,
            child: Text(
              activity.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle,
            ),
          ),
        ],
      ),
    );
  }
}
