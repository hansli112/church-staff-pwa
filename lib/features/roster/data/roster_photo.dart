import 'package:flutter/foundation.dart';

/// 一張要送去辨識的服事表照片。
///
/// [data] 已經是 base64，因為它唯一的去處就是 JSON 請求的 body。存 bytes 再
/// 在送出前轉一次，等於在手機上把同一份資料多留一份在記憶體裡。
@immutable
class RosterPhoto {
  final String mimeType;
  final String data;

  const RosterPhoto({required this.mimeType, required this.data});

  Map<String, dynamic> toJson() => {'mimeType': mimeType, 'data': data};
}

/// 選照片時使用者看得懂、也能處理的失敗。
class RosterPhotoException implements Exception {
  final String message;
  const RosterPhotoException(this.message);

  @override
  String toString() => message;
}

/// 單張上限，跟 worker 的 MAX_IMAGE_BYTES 一致。
///
/// 在這裡先擋是為了讓使用者立刻知道，而不是等整張照片上傳完才收到 413。
const int maxRosterPhotoBytes = 6 * 1024 * 1024;
