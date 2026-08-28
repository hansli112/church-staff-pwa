import 'package:flutter/material.dart';

/// 服事項目一列的最小高度。
///
/// 48 是編輯模式那兩顆 IconButton 的觸控目標高度（給長輩按的，不能再縮），
/// 檢視模式沒有按鈕但跟著用同一個值 —— 兩邊列高只要差一點，切換模式時整張
/// 卡片的長度就不一樣，畫面會整段位移。
const double kDutyRowMinHeight = 48.0;

/// 服事項目的一列：左邊項目名稱、中間人名、右邊（編輯模式才有的）操作按鈕。
///
/// 檢視卡片與編輯卡片共用這一份配置，不是為了少寫幾行，是為了「兩邊逐列對得
/// 齊」這件事只有一個地方能改壞。
class DutyRow extends StatelessWidget {
  const DutyRow({
    super.key,
    required this.role,
    required this.people,
    this.roleColor,
    this.trailing = const [],
  });

  final String role;

  /// 這一項的人。刻意收一份清單而不是排好的字串 —— 中文預設每個字都可以斷
  /// 行，接成一串丟給 Text 的話，欄寬不夠時會從名字中間切開（「陳美／麗」）。
  final List<String> people;

  final Color? roleColor;

  /// 放在最右邊的操作按鈕。檢視模式留空。
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kDutyRowMinHeight),
      child: Row(
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
      ),
    );
  }
}
