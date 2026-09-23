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

/// 縮小、轉成 JPEG 之後的單張上限，跟 worker 的 MAX_IMAGE_BYTES 一致。
///
/// 會這麼小是因為 Cloudflare 免費方案每個請求只有 10ms CPU，照片越大 worker
/// 解析越久，超過就被 Cloudflare 砍掉（詳見 import-image.js）。長邊 2400px
/// 的 JPEG 一般不到 1MB，碰到這條線的只會是細節多到異常的照片。
const int maxRosterPhotoBytes = 2 * 1024 * 1024;
