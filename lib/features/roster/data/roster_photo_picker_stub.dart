import 'roster_photo.dart';

const bool canPickRosterPhotos = false;

Future<List<RosterPhoto>> pickRosterPhotos() async {
  // 走不到這裡 —— canPickRosterPhotos 是 false，UI 不會畫那顆按鈕。
  throw const RosterPhotoException('這個版本不支援直接選照片');
}
