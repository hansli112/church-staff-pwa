import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 把清單將來會顯示的字串，提前在畫面外排版一次。
///
/// 為什麼是「字串」而不是「字元」：Flutter Web 的文字排版有兩層成本，而且
/// 兩層都以字串為單位快取。
///
///   1. 字型 —— CanvasKit 內建字型沒有中文。排版遇到缺字會去 gstatic 抓
///      Noto subset，抓回來之後再通知框架重排一次。
///   2. 斷行與字元邊界分析 —— 引擎的 segmentation cache 是以整個字串當 key
///      的（見 text_fragmenter.dart：短字串 10 萬筆、中等字串 1 萬筆），
///      同一個字串排版過第二次就便宜得多。
///
/// 只預熱字元只解決第 1 層。實測（?bench=1）：同一批中文字串第一次捲是紅
/// 的，換到另一個變體重捲同樣的字串就變綠 —— 貴的是「第一次排版這個字串」，
/// 跟 widget 用 ListTile 還是手寫 Row 幾乎無關。
///
/// 分批進行：一次把幾百個字串塞進同一幀會換來一次明顯的頓挫，所以每幀只處
/// 理 [_chunkSize] 個，攤平在載入階段。全部做完就把自己從樹上移除 —— 常駐
/// 只會讓每一幀白白多背這些 paragraph。
///
/// 必須放在 [Stack] 裡：內容被放到可視範圍外，而 Stack 預設會裁切，所以不
/// 會有實際的繪製成本，但 layout 一定會發生，這正是我們要的。
class TextWarmup extends StatefulWidget {
  const TextWarmup({super.key, required this.strings});

  /// 要預熱的字串（會自行去重）。
  final List<String> strings;

  /// 每一幀處理幾個字串。
  static const int _chunkSize = 24;

  /// 全部排版完之後，再等這麼久才移除 —— 字型是非同步抓回來的，太早撤掉會
  /// 來不及觸發字型變更後的重排。
  static const Duration _settleDuration = Duration(seconds: 4);

  /// 從任意來源取出不重複、非空白的字串。
  static List<String> uniqueStringsOf(Iterable<String> sources) {
    final seen = <String>{};
    final result = <String>[];
    for (final source in sources) {
      final trimmed = source.trim();
      if (trimmed.isEmpty) continue;
      if (seen.add(trimmed)) result.add(trimmed);
    }
    return result;
  }

  @override
  State<TextWarmup> createState() => _TextWarmupState();
}

class _TextWarmupState extends State<TextWarmup> {
  int _warmed = 0;
  bool _settled = false;
  bool _scheduled = false;
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    _scheduleNextChunk();
  }

  @override
  void didUpdateWidget(TextWarmup oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 資料換了（切換帳號、名單重抓）就重來一次。
    if (!identical(oldWidget.strings, widget.strings)) {
      _settleTimer?.cancel();
      _warmed = 0;
      _settled = false;
      _scheduleNextChunk();
    }
  }

  void _scheduleNextChunk() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;

      if (_warmed >= widget.strings.length) {
        // 全部排版完，等字型下載與重排落地之後把自己撤掉。
        _settleTimer?.cancel();
        _settleTimer = Timer(TextWarmup._settleDuration, () {
          if (mounted) setState(() => _settled = true);
        });
        return;
      }

      setState(() {
        _warmed = (_warmed + TextWarmup._chunkSize).clamp(
          0,
          widget.strings.length,
        );
      });
      _scheduleNextChunk();
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_settled || widget.strings.isEmpty) return const SizedBox.shrink();

    // 只放「這一批」：已經排版過的字串留在樹上沒有意義，那些成本已經付過了。
    final start = (_warmed - TextWarmup._chunkSize).clamp(
      0,
      widget.strings.length,
    );
    final chunk = widget.strings.sublist(start, _warmed);
    if (chunk.isEmpty) return const SizedBox.shrink();

    return Positioned(
      // 放在畫面外。Stack 預設 Clip.hardEdge，所以不會真的被畫出來。
      left: -100000,
      top: 0,
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final text in chunk)
              Text(
                text,
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.clip,
                // segmentation cache 以字串為 key，跟字級無關，所以用小字級。
                style: const TextStyle(fontSize: 8),
              ),
          ],
        ),
      ),
    );
  }
}
