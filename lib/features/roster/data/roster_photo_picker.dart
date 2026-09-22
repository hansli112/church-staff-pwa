import 'roster_photo.dart';
import 'roster_photo_picker_stub.dart'
    if (dart.library.html) 'roster_photo_picker_web.dart'
    as impl;

/// 這個平台能不能直接選照片。
///
/// 只有網頁版能 —— app 本來就是 PWA，但非 web 的建置照樣要編得過，而給一顆
/// 按下去必定失敗的按鈕比不給還糟。UI 靠這個決定要不要畫那顆按鈕。
bool get canPickRosterPhotos => impl.canPickRosterPhotos;

/// 開啟檔案選擇器。使用者取消就回空清單，不是丟例外 —— 取消不是錯誤。
Future<List<RosterPhoto>> pickRosterPhotos() => impl.pickRosterPhotos();
