// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class L10nZh extends L10n {
  L10nZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => '馬大別忙';

  @override
  String get tabHome => '首頁';

  @override
  String get tabRosters => '服事表';

  @override
  String get tabCalendar => '行事曆';

  @override
  String get tabMe => '我的';

  @override
  String get undo => '復原';

  @override
  String get cancel => '取消';

  @override
  String get save => '儲存';

  @override
  String get done => '完成';

  @override
  String get retry => '重試';

  @override
  String get search => '搜尋';

  @override
  String get clear => '清除';

  @override
  String get selected => '已選取';

  @override
  String get close => '關閉';

  @override
  String get add => '新增';

  @override
  String get delete => '刪除';

  @override
  String get edit => '編輯';

  @override
  String get deleted => '已刪除';

  @override
  String get loadFailed => '載入失敗，請檢查網路後再試一次';

  @override
  String get saveFailed => '沒有儲存成功，請檢查網路後再試一次';

  @override
  String get noPermission => '你沒有權限做這件事';

  @override
  String get comingSoon => '還在做，很快就好';
}
