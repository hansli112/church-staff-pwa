import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'roster_photo.dart';

const bool canPickRosterPhotos = true;

/// 開一個檔案選擇器拿服事表照片。
///
/// 沒有用 image_picker 之類的套件：這是 PWA，`<input type="file">` 在手機上
/// 本來就會跳出「相機／相簿」，多一個相依只是多一層。
Future<List<RosterPhoto>> pickRosterPhotos() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    // accept 用 image/* 而不是列副檔名：手機相機拍出來的可能是 HEIC，
    // 列舉一定會漏。真正的把關在 worker 那邊。
    ..accept = 'image/*'
    ..multiple = true;

  final completer = Completer<List<RosterPhoto>>();

  input.onchange = (web.Event _) {
    if (completer.isCompleted) return;
    completer.complete(_readAll(input.files));
  }.toJS;

  // 使用者按取消時瀏覽器只會發 cancel，不會發 change。沒有接這個事件的話
  // 那個 future 永遠不會完成，而畫面上的轉圈也就永遠停不下來。
  input.addEventListener(
    'cancel',
    (web.Event _) {
      if (!completer.isCompleted) completer.complete(const []);
    }.toJS,
  );

  input.click();
  return completer.future;
}

Future<List<RosterPhoto>> _readAll(web.FileList? files) async {
  final length = files?.length ?? 0;
  if (files == null || length == 0) return const [];
  if (length > maxRosterPhotos) {
    throw RosterPhotoException('一次最多 $maxRosterPhotos 張照片');
  }

  final photos = <RosterPhoto>[];
  for (var i = 0; i < length; i++) {
    final file = files.item(i);
    if (file == null) continue;
    photos.add(await _read(file));
  }
  return photos;
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
