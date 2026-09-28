import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/roster_import_service.dart';

/// 照片辨識進行中，按鈕底下那一行「現在在幹嘛」。
///
/// 辨識是一個請求送出去、一分鐘後才回來，中間 app 什麼都不知道 —— worker 在
/// 重試也不會告訴我們。所以這裡說的只有兩件確定的事：已經等了多久，以及照
/// 過去的量測，這個時間算不算正常。只有一顆轉圈的話，等到第 90 秒的人分不出
/// 是卡住了還是快好了，就會關掉重來，把當天的免費額度又燒掉一次。
///
/// 計時自己管：出現在畫面上就開始，拿掉就停。呼叫端只要決定畫不畫它。
class PhotoImportProgress extends StatefulWidget {
  const PhotoImportProgress({super.key});

  @override
  State<PhotoImportProgress> createState() => _PhotoImportProgressState();
}

class _PhotoImportProgressState extends State<PhotoImportProgress> {
  final Stopwatch _stopwatch = Stopwatch()..start();
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      photoImportProgressText(_stopwatch.elapsed),
      key: const ValueKey('photo-import-progress'),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 抽出來是為了測：文字只跟經過的時間有關。
String photoImportProgressText(Duration elapsed) {
  final seconds = elapsed.inSeconds;
  if (elapsed < RosterImportService.usualDuration) {
    return '正在讀照片，已經 $seconds 秒\n'
        '通常要一分鐘左右；服務忙碌時伺服器會自動重試';
  }
  final remaining = (RosterImportService.timeout - elapsed).inSeconds;
  if (remaining <= 0) return '快要逾時了，已經 $seconds 秒';
  return '比平常久，仍在等待辨識結果\n'
      '已經 $seconds 秒，最多再等 $remaining 秒';
}
