import 'dart:async';

import 'package:flutter/material.dart';

/// 把資料裡會用到的字先在畫面外排版一次，逼引擎提前把需要的字型抓下來。
///
/// 為什麼需要這個：CanvasKit 內建的字型沒有中文字。排版遇到缺字時，引擎會
/// 去 fonts.gstatic.com 抓對應的 Noto subset，**抓回來之後再通知框架重新
/// 排版**。這一整串都發生在 UI thread —— 表現出來就是「捲到沒看過的名字
/// 就掉幀，同一批名字捲第二遍就順了」。
///
/// 把這些字提前排版過，字型就會在使用者開始捲之前載入完成，捲動時只剩單純
/// 的 paragraph layout，不會再有字型變更引發的全域重排。
///
/// 內容被塞在 [Stack] 的可視範圍外，而 Stack 預設會裁切，所以不會有實際的
/// 繪製成本；但 layout 一定會發生，這正是我們要的。
///
/// 用完就撤：字型下載是排版當下觸發的，之後這個 widget 留在樹上只會讓每一
/// 幀多背一個幾百字的 paragraph，沒有任何好處。[_settleDuration] 給的是
/// 「排版 → 下載 → 字型變更重排」跑完的餘裕。
class GlyphWarmup extends StatefulWidget {
  const GlyphWarmup({super.key, required this.characters});

  /// 要預熱的字元（去重後的集合，順序無所謂）。
  final String characters;

  /// 撤掉之前要等多久 —— 字型是非同步抓回來的，太早移除會來不及觸發重排。
  static const Duration _settleDuration = Duration(seconds: 5);

  @override
  State<GlyphWarmup> createState() => _GlyphWarmupState();

  /// 從任意字串集合取出不重複的字元。
  ///
  /// 回傳的字串通常只有幾百個字（教會名冊的用字範圍很窄），排版一次的成本
  /// 遠小於捲動途中被字型下載打斷。
  static String uniqueCharactersOf(Iterable<String> sources) {
    final seen = <int>{};
    final buffer = StringBuffer();
    for (final source in sources) {
      for (final rune in source.runes) {
        // 空白與控制字元不會觸發字型 fallback，跳過。
        if (rune <= 0x20) continue;
        if (seen.add(rune)) buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }
}

class _GlyphWarmupState extends State<GlyphWarmup> {
  bool _settled = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleRemoval();
  }

  @override
  void didUpdateWidget(GlyphWarmup oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 資料換了（例如切換帳號、名單重抓）就要再預熱一次。
    if (oldWidget.characters != widget.characters) {
      _settled = false;
      _scheduleRemoval();
    }
  }

  void _scheduleRemoval() {
    _timer?.cancel();
    _timer = Timer(GlyphWarmup._settleDuration, () {
      if (mounted) setState(() => _settled = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final characters = widget.characters;
    if (_settled || characters.isEmpty) return const SizedBox.shrink();

    return Positioned(
      // 放在畫面外。Stack 預設 Clip.hardEdge，所以不會真的被畫出來。
      left: -100000,
      top: 0,
      child: IgnorePointer(
        child: Text(
          characters,
          // 單行不換行：排版一列就夠了，不需要為了預熱做多行斷行計算。
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.clip,
          // 字型 fallback 是以 (字元, 字型family) 決定的，字級不影響要抓哪些
          // subset，所以用小字級降低成本。
          style: const TextStyle(fontSize: 8),
        ),
      ),
    );
  }
}
