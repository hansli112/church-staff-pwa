import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// 「畫面頂端是哪一張卡片、離頂端多遠」的一筆紀錄。
///
/// 為什麼不能只記 `position.pixels`：檢視與編輯是兩份高度不同的清單（編輯多了
/// 匯入卡、每列多了兩顆 48px 的按鈕、展開的卡片因此高上一截），同一個 offset
/// 在兩邊指到的是不同的日期。記「哪一天」才換得回原本在看的地方，
/// [pixels] 只當還原時的第一次粗估。
@immutable
class ScrollAnchor {
  const ScrollAnchor({
    required this.itemId,
    required this.dy,
    required this.pixels,
  });

  /// 頂端那張卡片的 id。
  final String itemId;

  /// 該卡片左上角相對清單頂端的位移。卡片被切掉上緣時為負值。
  final double dy;

  /// 當下的捲動位置。還原時先跳到這裡，讓目標卡片被 build 出來。
  final double pixels;
}

/// 掛在清單每個項目上的標記，讓 [ScrollAnchorSupport] 認得出這是哪一張卡片。
@immutable
class ScrollAnchorTag {
  const ScrollAnchorTag(this.id);
  final String id;
}

/// 包住清單項目，替它掛上 [ScrollAnchorTag]。
class ScrollAnchorItem extends StatelessWidget {
  const ScrollAnchorItem({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MetaData(metaData: ScrollAnchorTag(id), child: child);
  }
}

/// 讓一個捲動清單記得住、也還原得回「頂端那張卡片的位置」。
///
/// 用法：把 [anchorListKey] 放到 ListView 上、[anchorController] 當它的
/// controller、每個項目用 [ScrollAnchorItem] 包起來，切換畫面前呼叫
/// [captureScrollAnchor] 存起來，新畫面掛好後呼叫 [restoreScrollAnchor]。
mixin ScrollAnchorSupport<T extends StatefulWidget> on State<T> {
  final GlobalKey anchorListKey = GlobalKey();
  final ScrollController anchorController = ScrollController();

  @override
  void dispose() {
    anchorController.dispose();
    super.dispose();
  }

  /// 記下目前頂端的卡片。清單還沒掛上或看不到任何卡片時回傳 null。
  ScrollAnchor? captureScrollAnchor() {
    if (!anchorController.hasClients) return null;
    final entries = _visibleItems();
    if (entries.isEmpty) return null;
    // 「頂端那張」＝ 還沒被捲出畫面的第一張：下緣仍在 0 以下的都不算。
    _AnchorHit? best;
    for (final entry in entries) {
      if (entry.dy + entry.height <= 0) continue;
      if (best == null || entry.dy < best.dy) best = entry;
    }
    best ??= entries.first;
    return ScrollAnchor(
      itemId: best.id,
      dy: best.dy,
      pixels: anchorController.position.pixels,
    );
  }

  /// 把 [anchor] 那張卡片挪回原本的位置。
  ///
  /// 清單是 lazy build 的，目標卡片一開始可能根本不在樹上，所以先用當初的
  /// pixel 位置粗估一次，等它被 build 出來再依實際位移修正。收合的卡片兩個
  /// 模式一樣高，粗估通常只差一兩張卡片，修正一次就到位。
  Future<void> restoreScrollAnchor(ScrollAnchor anchor) async {
    // 本來就停在最上面的話什麼都不用做 —— 硬把第一張卡片拉回同一個 y，只會
    // 把清單頂端新增的東西（編輯模式的匯入卡）推到看不見的地方。
    if (anchor.pixels <= 0.5) return;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (!mounted) return;
      if (!anchorController.hasClients) {
        // endOfFrame 只在 idle 時自己排一幀，而第一輪是在 post-frame callback
        // 裡跑的 —— 不主動排一幀的話，這個 await 會等到某個無關的重繪才醒，
        // 還原就靜靜地沒發生。
        SchedulerBinding.instance.ensureVisualUpdate();
        await SchedulerBinding.instance.endOfFrame;
        continue;
      }
      final hit = _findItem(anchor.itemId);
      if (hit == null) {
        // 還沒被 build 出來：先跳到當初的位置，下一輪再修正。跳不動（已經在
        // 邊界上）也不能就此收工 —— 卡片可能下一幀才被 build 出來。
        _jumpTo(anchor.pixels);
        SchedulerBinding.instance.ensureVisualUpdate();
      } else {
        final delta = hit.dy - anchor.dy;
        if (delta.abs() < 0.5) return;
        if (!_jumpTo(anchorController.position.pixels + delta)) return;
      }
      await SchedulerBinding.instance.endOfFrame;
    }
  }

  /// 回傳 false 代表已經在邊界上，再跳也不會動 —— 呼叫端就可以收工，
  /// 不必空轉剩下的重試次數。
  bool _jumpTo(double target) {
    final position = anchorController.position;
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clamped - position.pixels).abs() < 0.5) return false;
    anchorController.jumpTo(clamped);
    return true;
  }

  _AnchorHit? _findItem(String id) {
    for (final entry in _visibleItems()) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// 掃出目前這一幀真的存在於樹上的項目。ListView 只 build 看得到的那幾張，
  /// 所以這裡走訪的是十幾個 render object，不是整份服事表。
  List<_AnchorHit> _visibleItems() {
    final listRender = anchorListKey.currentContext?.findRenderObject();
    if (listRender is! RenderBox || !listRender.hasSize) return const [];

    final hits = <_AnchorHit>[];
    void visit(RenderObject node) {
      if (node is RenderMetaData) {
        final tag = node.metaData;
        if (tag is ScrollAnchorTag) {
          if (node.hasSize && node.attached) {
            hits.add(
              _AnchorHit(
                id: tag.id,
                dy: node.localToGlobal(Offset.zero, ancestor: listRender).dy,
                height: node.size.height,
              ),
            );
          }
          // 標記底下不會再有另一張卡片，不必再往下走。
          return;
        }
      }
      node.visitChildren(visit);
    }

    listRender.visitChildren(visit);
    return hits;
  }
}

class _AnchorHit {
  const _AnchorHit({required this.id, required this.dy, required this.height});
  final String id;
  final double dy;
  final double height;
}
