import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

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
    completer.complete(file == null ? null : _read(file));
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

Future<RosterPhoto> _read(web.File file) async {
  final size = file.size;
  if (size > maxRosterPhotoBytes) {
    final mb = (maxRosterPhotoBytes / 1024 / 1024).round();
    throw RosterPhotoException(
      '${file.name} 有 ${(size / 1024 / 1024).toStringAsFixed(1)}MB，'
      '超過 ${mb}MB。請先縮小再試',
    );
  }

  final reader = web.FileReader();
  final completer = Completer<Uint8List>();
  reader.onload = (web.Event _) {
    if (completer.isCompleted) return;
    final buffer = reader.result as JSArrayBuffer?;
    if (buffer == null) {
      completer.completeError(RosterPhotoException('${file.name} 讀不到內容'));
      return;
    }
    completer.complete(buffer.toDart.asUint8List());
  }.toJS;
  reader.onerror = (web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(RosterPhotoException('${file.name} 讀取失敗'));
    }
  }.toJS;
  reader.readAsArrayBuffer(file);

  final bytes = await completer.future;
  // 有些來源（例如某些相簿）給的 File 沒有 type，那就讓 worker 用副檔名以外的
  // 方式退回去擋。這裡不猜，猜錯只會讓錯誤訊息更難懂。
  final mimeType = file.type.isEmpty ? 'image/jpeg' : file.type;
  return RosterPhoto(mimeType: mimeType, data: base64Encode(bytes));
}
