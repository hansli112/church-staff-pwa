import 'package:flutter/material.dart';

/// 編輯模式一列服事的最小高度。
///
/// 48 是那顆刪除 IconButton 的觸控目標高度，給長輩按的，不能再縮。檢視模式
/// 沒有按鈕，不吃這個下限（見 [DutyRow.dense]）—— 切換模式時的位移是靠錨定
/// 日期修的（見 `ScrollAnchor`），不是靠兩邊列高一樣。
const double kDutyRowMinHeight = 48.0;

/// 服事項目的一列：左邊項目名稱、中間人名、右邊（編輯模式才有的）操作按鈕。
///
/// 檢視卡片與編輯卡片共用這一份配置，差別只有 [dense]。
class DutyRow extends StatelessWidget {
  const DutyRow({
    super.key,
    required this.role,
    required this.people,
    this.roleColor,
    this.trailing = const [],
    this.dense = false,
  });

  final String role;

  /// 這一項的人。刻意收一份清單而不是排好的字串 —— 中文預設每個字都可以斷
  /// 行，接成一串丟給 Text 的話，欄寬不夠時會從名字中間切開（「陳美／麗」）。
  final List<String> people;

  final Color? roleColor;

  /// 放在最右邊的操作按鈕。檢視模式留空。
  final List<Widget> trailing;

  /// 檢視模式的排法：列高跟著文字走，不撐到 [kDutyRowMinHeight]。這個畫面是
  /// 拿來讀的，一頁看得到幾天比每列多出 25px 的留白重要。文字靠上對齊，名字
  /// 換行時項目名稱才不會跟著往下飄。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: dense
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            role,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: roleColor ?? Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          // 一個名字一段（頓號跟在名字後面），斷行機會就只剩名字之間。
          child: Wrap(
            children: [
              for (var i = 0; i < people.length; i++)
                Text(
                  i == people.length - 1 ? people[i] : '${people[i]}、',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
        ...trailing,
      ],
    );
    if (dense) return row;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kDutyRowMinHeight),
      child: row,
    );
  }
}
