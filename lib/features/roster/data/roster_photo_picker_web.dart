import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'roster_photo.dart';

const bool canPickRosterPhotos = true;

/// 開一個檔案選擇器拿一張服事表照片。
///
/// 沒有用 image_picker 之類的套件：這是 PWA，`<input type="file">` 在手機上
/// 本來就會跳出「相機／相簿」，多一個相依只是多一層。
Future<RosterPhoto?> pickRosterPhoto() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    // accept 用 image/* 而不是列副檔名：手機相機拍出來的可能是 HEIC，
    // 列舉一定會漏。真正的把關在 worker 那邊。
    ..accept = 'image/*';
  // 一定要掛進 DOM。沒掛上去的 input 在手機瀏覽器（iOS Safari、Android 開
  // 相機時）常常不發 change，或在使用者選照片的期間就被回收 —— 症狀是選完
  // 照片什麼都沒發生，沒有錯誤也沒有轉圈。
  input.style
    ..position = 'fixed'
    ..left = '-10000px'
    ..opacity = '0';
  web.document.body?.append(input);

  final completer = Completer<RosterPhoto?>();

  input.onchange = (web.Event _) {
    if (completer.isCompleted) return;
    final file = input.files?.item(0);
    completer.complete(file == null ? null : readRosterPhoto(file));
  }.toJS;

  // 使用者按取消時瀏覽器只會發 cancel，不會發 change。沒有接這個事件的話
  // 那個 future 永遠不會完成，而畫面上的轉圈也就永遠停不下來。
  input.addEventListener(
    'cancel',
    (web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }.toJS,
  );

  input.click();
  try {
    return await completer.future;
  } finally {
    input.remove();
  }
}

/// 照片在手機上先縮成長邊這麼多 px 再送出。
///
/// 不縮的話，一張 iPhone 照片是 3-5MB，base64 之後 worker 光是把請求解析再
/// 組給 Gemini 就要十幾 ms CPU —— 超過 Cloudflare 免費方案每個請求 10ms 的
/// 上限，Cloudflare 直接回 503，畫面上變成「辨識服務忙碌中」，看起來像是
/// Gemini 的問題。實際踩過。
///
/// 2400 是依實測挑的：驗證過的服事表截圖最大 1755px，全部辨識正確，留一點
/// 餘裕給手機拍的斜角與邊框。Gemini 自己也會把圖縮到差不多這個尺度，送更大
/// 只是多花上傳時間。
const int _maxEdge = 2400;

/// JPEG 品質。表格是細字，0.85 以下開始糊。
const double _jpegQuality = 0.85;

/// 原圖大到這樣就不讀了：解碼一張的記憶體是長×寬×4，手機分頁會被系統砍掉。
const int _maxSourceBytes = 40 * 1024 * 1024;

/// 讀一張照片、縮小、轉成 JPEG。
///
/// 公開只是為了 test/roster_photo_picker_web_test.dart —— 這段只有真的瀏覽器
/// 跑得動（canvas、影像解碼），VM 上的測試碰不到。
@visibleForTesting
Future<RosterPhoto> readRosterPhoto(web.File file) async {
  if (file.size > _maxSourceBytes) {
    throw RosterPhotoException('${file.name} 太大了，請換一張照片');
  }

  final url = web.URL.createObjectURL(file);
  try {
    final image = web.HTMLImageElement()..src = url;
    try {
      await image.decode().toDart;
    } catch (_) {
      throw RosterPhotoException('${file.name} 打不開，請換一張照片');
    }

    final width = image.naturalWidth;
    final height = image.naturalHeight;
    final scale = math.min(1.0, _maxEdge / math.max(width, height));
    final canvas = web.HTMLCanvasElement()
      ..width = (width * scale).round()
      ..height = (height * scale).round();
    // 瀏覽器畫進 canvas 時會照 EXIF 轉正，直拍的照片不會躺著送出去。
    (canvas.getContext('2d') as web.CanvasRenderingContext2D).drawImage(
      image,
      0,
      0,
      canvas.width,
      canvas.height,
    );

    // 一律轉成 JPEG：iPhone 的 HEIC 也在這裡變成 worker 與 Gemini 都認得的格式。
    final bytes = await _encodeJpeg(canvas);
    if (bytes.length > maxRosterPhotoBytes) {
      throw RosterPhotoException('${file.name} 縮小後還是太大，請裁掉表格以外的部分');
    }
    return RosterPhoto(mimeType: 'image/jpeg', data: base64Encode(bytes));
  } finally {
    web.URL.revokeObjectURL(url);
  }
}

Future<Uint8List> _encodeJpeg(web.HTMLCanvasElement canvas) async {
  final completer = Completer<web.Blob?>();
  canvas.toBlob(
    (web.Blob? blob) {
      completer.complete(blob);
    }.toJS,
    'image/jpeg',
    _jpegQuality.toJS,
  );
  final blob = await completer.future;
  if (blob == null) {
    // iOS 對 canvas 有像素上限，超過時 toBlob 給 null 而不是丟錯。
    throw const RosterPhotoException('照片轉檔失敗，請換一張照片');
  }
  final buffer = await blob.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}
