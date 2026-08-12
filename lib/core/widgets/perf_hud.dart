import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 疊在畫面最上層的即時效能數字，用 `?perf=1` 開啟。
///
/// 為什麼要自己做：Flutter 內建的 `showPerformanceOverlay` 在 Web 上是
/// 沒有實作的 no-op（引擎只會印一行警告）。但 Web 引擎確實有回報
/// [FrameTiming]，裡面 build 與 raster 的時間都是真的，所以直接訂閱
/// `SchedulerBinding.addTimingsCallback` 自己算。
///
/// 這是為了回答一個問題：手機上的卡頓到底卡在哪條 thread。
///   - UI 高    → build / layout 太重，是程式碼的問題，可以繼續優化
///   - RASTER 高 → 畫素真的畫不出來，多半是引擎與裝置的天花板
/// iOS 上沒有 Mac 就看不到 Safari 的 timeline，所以把數字畫在畫面上。
class PerfHud extends StatefulWidget {
  const PerfHud({super.key, required this.child});

  final Widget child;

  @override
  State<PerfHud> createState() => _PerfHudState();
}

class _PerfHudState extends State<PerfHud> {
  /// 約 3 秒的滑動視窗（60fps）。
  static const int _windowSize = 180;
  static const double _budgetMs = 16.0;

  final List<FrameTiming> _frames = <FrameTiming>[];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // 不在 callback 裡直接 setState：那會在每一幀結束時再排一幀，數字本身
    // 就會污染量測。改成固定間隔刷新。
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    _frames.addAll(timings);
    if (_frames.length > _windowSize) {
      _frames.removeRange(0, _frames.length - _windowSize);
    }
  }

  double _ms(Duration d) => d.inMicroseconds / 1000.0;

  ({double avg, double p90, double max}) _stats(
    double Function(FrameTiming) pick,
  ) {
    if (_frames.isEmpty) return (avg: 0, p90: 0, max: 0);
    final values = _frames.map(pick).toList()..sort();
    final total = values.fold<double>(0, (sum, v) => sum + v);
    return (
      avg: total / values.length,
      p90: values[(values.length * 0.9).floor().clamp(0, values.length - 1)],
      max: values.last,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ui = _stats((f) => _ms(f.buildDuration));
    final raster = _stats((f) => _ms(f.rasterDuration));
    final overBudget = _frames
        .where(
          (f) =>
              _ms(f.buildDuration) > _budgetMs ||
              _ms(f.rasterDuration) > _budgetMs,
        )
        .length;

    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          // 不能擋到操作，不然就沒辦法一邊捲一邊看。
          child: IgnorePointer(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SafeArea(
                bottom: false,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.72),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row('UI', ui),
                      _row('RASTER', raster),
                      Text(
                        '>16ms $overBudget/${_frames.length} frames',
                        style: _textStyle(
                          overBudget > 0
                              ? Colors.orangeAccent
                              : Colors.greenAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(String label, ({double avg, double p90, double max}) s) {
    final color = s.p90 > _budgetMs
        ? Colors.redAccent
        : (s.avg > _budgetMs / 2 ? Colors.orangeAccent : Colors.greenAccent);
    String fmt(double v) => v.toStringAsFixed(1).padLeft(5);
    return Text(
      '${label.padRight(6)} avg${fmt(s.avg)} p90${fmt(s.p90)} max${fmt(s.max)}',
      style: _textStyle(color),
    );
  }

  /// 這個 HUD 掛在 MaterialApp.builder，上面沒有 DefaultTextStyle 祖先，
  /// 所以 Flutter 會套用除錯用的黃色雙底線樣式。要自己關掉。
  static TextStyle _textStyle(Color color) => TextStyle(
    color: color,
    fontSize: 12,
    fontFamily: 'monospace',
    decoration: TextDecoration.none,
    fontWeight: FontWeight.normal,
  );
}
