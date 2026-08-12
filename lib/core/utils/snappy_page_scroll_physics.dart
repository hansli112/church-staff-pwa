import 'package:flutter/widgets.dart';

/// 讓分頁切換的收尾動畫更快停下來的 [ScrollPhysics]。
///
/// 解決的問題：在服事表左右滑換分頁之後，如果馬上想往下滑，手勢常常沒有反應。
///
/// 成因是 Flutter 的既定行為，不是 bug：分頁還在滑行時把手指放上去，父層的
/// [Scrollable] 會「接住」那個動畫（讓你能中途抓住一頁），於是指標被父層拿走，
/// 底下清單的垂直手勢就收不到了。實測（widget test，在畫面中央模擬手指往下
/// 拖）：動畫途中兩頁的捲動位置都是 0 → 0，完全靜止之後同樣的手勢移動 270。
///
/// 這個接住的行為沒有辦法關掉，能做的是**縮短窗口**。收尾動畫的時間由 spring
/// 決定，換一組更硬、臨界阻尼（ratio > 1，不回彈）的 spring 之後，實測從
/// 甩動到完全靜止由 11 幀（約 176ms）降到 6 幀（約 96ms）。
///
/// 用法是把它當成 `TabBarView.physics` 傳進去。TabBarView 會用自己的分頁
/// physics 去 `applyTo` 我們這一份，把我們變成 parent；而分頁 physics 產生
/// 收尾動畫時取的 `spring` 會沿著 parent 鏈找上來，所以吸附感保留，只有速度
/// 變了。
class SnappyPageScrollPhysics extends ScrollPhysics {
  const SnappyPageScrollPhysics({super.parent});

  @override
  SnappyPageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      SnappyPageScrollPhysics(parent: buildParent(ancestor));

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
    mass: 0.4,
    stiffness: 400,
    // 略大於 1：臨界阻尼再多一點，收得乾脆且不會過衝。
    ratio: 1.1,
  );
}
