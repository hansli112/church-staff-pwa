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

  @override
  String get signInWithGoogle => '使用 Google 登入';

  @override
  String get signInWithEmail => '用 email 登入';

  @override
  String get loginTagline => '同工服事表，大家一起看';

  @override
  String get email => 'Email';

  @override
  String get password => '密碼';

  @override
  String get yourName => '你的名字';

  @override
  String get signIn => '登入';

  @override
  String get register => '註冊';

  @override
  String get createAccount => '註冊新帳號';

  @override
  String get haveAccount => '已經有帳號？登入';

  @override
  String get forgotPassword => '忘記密碼';

  @override
  String resetSent(String email) {
    return '重設密碼的信已寄到 $email';
  }

  @override
  String get errInvalidCredential => 'Email 或密碼不對';

  @override
  String get errEmailInUse => '這個 email 註冊過了，請直接登入或用 Google 登入';

  @override
  String get errWeakPassword => '密碼至少要 6 個字';

  @override
  String get errInvalidEmail => 'Email 格式不對';

  @override
  String get errNeedsLink => '這個 email 已經有帳號。請用原本的方式登入，登入後會自動連在一起';

  @override
  String get errTooMany => '嘗試太多次，請稍後再試';

  @override
  String get errNetwork => '連不上網路，請檢查後再試一次';

  @override
  String get errUnknown => '沒有成功，請再試一次';

  @override
  String get nameRequired => '請輸入名字';

  @override
  String get emailRequired => '請輸入 email';

  @override
  String get verifyEmailTitle => '驗證你的 email';

  @override
  String verifyEmailBody(String email) {
    return '驗證信已寄到 $email，點信裡的連結後回到這裡';
  }

  @override
  String get verifyResend => '重寄驗證信';

  @override
  String get verifyResent => '已重寄';

  @override
  String get verifyDone => '我已經驗證';

  @override
  String get verifyStill => '還沒驗證成功，請點信裡的連結';

  @override
  String get welcomeTitle => '加入你的教會';

  @override
  String get welcomeBody => '請教會的管理員給你邀請連結';

  @override
  String get enterInviteCode => '輸入邀請碼';

  @override
  String get createChurch => '建立新教會';

  @override
  String get signOut => '登出';

  @override
  String get inviteCode => '邀請碼';

  @override
  String get next => '下一步';

  @override
  String get churchName => '教會名稱';

  @override
  String get createChurchVerifyFirst => '驗證 email 後才能建立教會';

  @override
  String get create => '建立';

  @override
  String get errDuplicateName => '已經有教會叫這個名字。如果是被別人搶先註冊，請聯絡我們';

  @override
  String get contactUs => '聯絡我們';

  @override
  String joinTitle(String church) {
    return '加入〈$church〉';
  }

  @override
  String get join => '加入';

  @override
  String joined(String church) {
    return '已加入〈$church〉';
  }

  @override
  String get errInviteInvalid => '這個邀請已失效，請向管理員要新的邀請';

  @override
  String get errInviteExpired => '這個邀請過期了，請向管理員要新的邀請';

  @override
  String churchSuspendedTitle(String church) {
    return '〈$church〉已停用';
  }

  @override
  String get churchSuspendedBody => '有問題請聯絡教會的管理員';

  @override
  String churchDeletedTitle(String church) {
    return '〈$church〉已刪除';
  }

  @override
  String churchDeletedBody(String date) {
    return '管理員可以在 $date 前還原';
  }

  @override
  String get churchUnavailable => '無法開啟這間教會';

  @override
  String get restoreChurch => '還原教會';

  @override
  String get churchRestored => '教會已還原';

  @override
  String get switchChurch => '切換教會';

  @override
  String get myServicesTitle => '我接下來的服事';

  @override
  String get noUpcomingServices => '接下來沒有你的服事';

  @override
  String get viewRosters => '看服事表';

  @override
  String get nobodyYet => '待定';

  @override
  String get noServicesConfigured => '還沒有設定聚會';

  @override
  String get setUpServices => '設定聚會';

  @override
  String get noRostersAhead => '接下來沒有聚會';

  @override
  String get today => '今天';

  @override
  String get tomorrow => '明天';

  @override
  String get offlineShowingCached => '離線中，顯示上次的資料';

  @override
  String dutyCount(int count) {
    return '$count 項服事';
  }

  @override
  String get addDuty => '新增服事項目';

  @override
  String get dutyName => '服事項目名稱';

  @override
  String get removeDuty => '移除這項';

  @override
  String dutyRemoved(String duty) {
    return '已移除$duty';
  }

  @override
  String dutyUpdated(String duty) {
    return '已更新$duty';
  }

  @override
  String get pickerServes => '有這項服事';

  @override
  String get pickerOthers => '其他同工';

  @override
  String pickerUseName(String name) {
    return '用「$name」';
  }

  @override
  String pickerNoOneServes(String duty) {
    return '還沒有人負責$duty';
  }

  @override
  String pickerNoResults(String query) {
    return '找不到「$query」';
  }

  @override
  String get pickerSearchHint => '搜尋同工';

  @override
  String pickerAddDutyTitle(String name, String duty) {
    return '也讓$name負責$duty？';
  }

  @override
  String pickerAddDutyBody(String duty) {
    return '之後安排$duty時，他會出現在上面';
  }

  @override
  String get pickerAddDutyYes => '加上';

  @override
  String get pickerAddDutyNo => '只排這次';

  @override
  String get reorder => '調整順序';

  @override
  String get reorderHint => '拖曳調整先後，每一週都照這個順序';

  @override
  String get orderSaved => '已更新順序';

  @override
  String get swap => '交換';

  @override
  String swapWith(String duty) {
    return '和誰交換$duty？';
  }

  @override
  String get swapNone => '其他日期沒有可以交換的人';

  @override
  String swapped(String a, String b) {
    return '已交換 $a 和 $b';
  }

  @override
  String moved(String name, String day) {
    return '已把 $name 移到 $day';
  }

  @override
  String get emptySlot => '空著';

  @override
  String removeFromDuty(String duty) {
    return '從$duty移除';
  }

  @override
  String get events => '特別活動';

  @override
  String get customEvent => '自訂活動';

  @override
  String get eventName => '活動名稱';

  @override
  String get addToCommon => '加入常用選項';

  @override
  String get eventColor => '顏色';

  @override
  String get colorName0 => '紅';

  @override
  String get colorName1 => '橘';

  @override
  String get colorName2 => '黃';

  @override
  String get colorName3 => '綠';

  @override
  String get colorName4 => '藍';

  @override
  String get colorName5 => '紫';

  @override
  String removed(String name) {
    return '已移除$name';
  }

  @override
  String get profile => '個人資料';

  @override
  String get name => '名字';

  @override
  String get nameSaved => '已更新名字';

  @override
  String get language => '語言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get languageZhHant => '繁體中文';

  @override
  String get churchInfo => '教會資訊';

  @override
  String get members => '同工';

  @override
  String get serviceSettings => '服事設定';

  @override
  String get invites => '邀請';

  @override
  String get notifications => '通知';

  @override
  String get account => '帳號';

  @override
  String get deleteAccount => '刪除帳號';

  @override
  String get developer => '開發';

  @override
  String get components => '元件';

  @override
  String get operatorConsole => '平台後台';

  @override
  String get leaveChurch => '退出教會';

  @override
  String leaveChurchTitle(String church) {
    return '退出〈$church〉？';
  }

  @override
  String get leaveChurchBody => '需要重新邀請才能回來';

  @override
  String get leave => '退出';

  @override
  String leftChurch(String church) {
    return '已退出〈$church〉';
  }

  @override
  String get adminCannotLeave => '管理員要先把管理員交給別人，才能退出';

  @override
  String get churchLogo => '教會 logo';

  @override
  String get uploadLogo => '上傳 logo';

  @override
  String get changeLogo => '更換 logo';

  @override
  String get logoUploaded => '已更新 logo';

  @override
  String get logoTooLarge => '圖片太大了，請選 1MB 以下的圖片';

  @override
  String get logoNotImage => '請選一張圖片';

  @override
  String memberCount(int count) {
    return '$count 位同工';
  }

  @override
  String get deleteChurch => '刪除教會';

  @override
  String deleteChurchTitle(String church) {
    return '刪除〈$church〉？';
  }

  @override
  String get deleteChurchBody => '所有同工都看不到這間教會。30 天內可以還原，之後資料會永久刪除';

  @override
  String get roleAdmin => '管理員';

  @override
  String get roleLeader => '小組長';

  @override
  String get roleStaff => '同工';

  @override
  String get roleMember => '組員';

  @override
  String get role => '角色';

  @override
  String get groups => '權限';

  @override
  String get groupRosterEditors => '安排服事表';

  @override
  String get groupCalendarEditors => '編輯行事曆';

  @override
  String get zones => '牧區與服事';

  @override
  String get zonesFooter => '勾選他在各聚會負責的服事。有「安排服事表」權限的人，只能安排自己牧區的服事表';

  @override
  String get removeMember => '移除同工';

  @override
  String memberRemoved(String name) {
    return '已移除$name';
  }

  @override
  String get memberSaved => '已儲存';

  @override
  String get searchMembers => '搜尋同工';

  @override
  String get noMembersFound => '找不到這位同工';

  @override
  String get you => '你';

  @override
  String get inviteCreate => '建立邀請連結';

  @override
  String get inviteValidFor => '有效期限';

  @override
  String inviteDays(int days) {
    return '$days 天';
  }

  @override
  String get inviteCopy => '複製連結';

  @override
  String get inviteCopied => '已複製邀請連結';

  @override
  String get inviteShare => '分享';

  @override
  String get inviteRevoke => '撤回';

  @override
  String get inviteRevoked => '已撤回';

  @override
  String inviteExpiresOn(String date) {
    return '$date 到期';
  }

  @override
  String get inviteNone => '還沒有邀請連結';

  @override
  String inviteMessage(String church, String link) {
    return '邀請你加入〈$church〉的服事表：$link';
  }

  @override
  String get servicesTitle => '聚會';

  @override
  String get serviceAdd => '新增聚會';

  @override
  String get serviceName => '聚會名稱';

  @override
  String get weekday => '星期';

  @override
  String get serviceEnabled => '舉行中';

  @override
  String get serviceDisabledFooter => '停用的聚會不會再出現新的服事表，舊的保留';

  @override
  String get templateDuties => '服事項目';

  @override
  String get templateFooter => '新的服事表會帶入這些項目。已經安排的服事表不受影響';

  @override
  String get commonEvents => '常用特別活動';

  @override
  String get rename => '改名';

  @override
  String get moveUp => '上移';

  @override
  String get moveDown => '下移';

  @override
  String get saved => '已儲存';

  @override
  String get weekday1 => '週一';

  @override
  String get weekday2 => '週二';

  @override
  String get weekday3 => '週三';

  @override
  String get weekday4 => '週四';

  @override
  String get weekday5 => '週五';

  @override
  String get weekday6 => '週六';

  @override
  String get weekday7 => '週日';

  @override
  String get deleteAccountTitle => '刪除你的帳號？';

  @override
  String get deleteAccountBody => '你會退出所有教會，帳號與個人資料會刪除且無法復原。服事表上的名字會保留';

  @override
  String deleteAccountLastAdmin(String churches) {
    return '你是〈$churches〉唯一的管理員。請先到「同工」把管理員交給別人';
  }

  @override
  String get accountDeleted => '帳號已刪除';

  @override
  String get serviceDisabled => '停用';

  @override
  String get adminSearchHint => '教會名稱或 ID';

  @override
  String get adminNoChurches => '找不到教會';

  @override
  String get adminStats => '統計';

  @override
  String get adminRename => '改名';

  @override
  String get adminMakeAdmin => '設為管理員';

  @override
  String adminMadeAdmin(String name) {
    return '已設 $name 為管理員';
  }

  @override
  String get adminSuspend => '停用教會';

  @override
  String get adminReopen => '恢復教會';

  @override
  String adminSuspendTitle(String church) {
    return '停用〈$church〉？';
  }

  @override
  String get adminSuspendBody => '所有同工會立刻看到停用畫面';

  @override
  String get statusActive => '使用中';

  @override
  String get statusSuspended => '已停用';

  @override
  String get statusDeleted => '已刪除';

  @override
  String get statsUsers => '使用者';

  @override
  String get statsChurches => '教會';

  @override
  String get statsMembers => '成員';

  @override
  String get statsRosters => '服事表';

  @override
  String get statsReads => 'Firestore 讀取';

  @override
  String get statsWrites => 'Firestore 寫入';

  @override
  String get statsCost => '估計費用（USD）';

  @override
  String get statsNone => '還沒有統計資料';

  @override
  String get statsMoreInConsole => '行為與錯誤細節在 Firebase console';

  @override
  String get notifReminder => '服事提醒';

  @override
  String get notifReminderSub => '服事前一天晚上提醒你';

  @override
  String get notifRosterChange => '服事表異動';

  @override
  String get notifRosterChangeSub => '你被排進或移出服事時';

  @override
  String get notifMemberLeft => '同工退出';

  @override
  String get notifMemberLeftSub => '有人退出教會時（管理員）';

  @override
  String get notifThisChurch => '這間教會的通知';

  @override
  String get notifPermissionOff => '通知被關掉了，請到系統設定打開';

  @override
  String get notifEnable => '開啟通知';

  @override
  String get zoneSwitch => '負責這個聚會';

  @override
  String get photoImport => '照片匯入';

  @override
  String photoRemaining(int count) {
    return '這個月還可以辨識 $count 張';
  }

  @override
  String get photoTake => '拍照';

  @override
  String get photoPick => '選照片';

  @override
  String get photoPasteJson => '貼上 JSON';

  @override
  String get photoRecognizing => '辨識中，大約需要一分鐘';

  @override
  String photoChurchLimit(int limit) {
    return '這個月的 $limit 張用完了，下個月 1 日恢復。可以先貼上 JSON';
  }

  @override
  String get photoPlatformOff => '照片辨識這個月暫停（全站的辨識額度用完了），下個月恢復。可以先貼上 JSON';

  @override
  String get photoTooLarge => '照片太大，請裁到只剩表格再試';

  @override
  String get photoFailed => '辨識失敗，請換一張清楚一點的照片再試';

  @override
  String get importPreview => '確認後套用';

  @override
  String get importApply => '套用到服事表';

  @override
  String importApplied(int count) {
    return '已匯入 $count 天';
  }

  @override
  String get importNothing => '照片裡沒有讀到之後的日期';

  @override
  String get importNotInList => '名單裡沒有這些人（照原文寫入，沒有連到帳號）';

  @override
  String importNear(String names) {
    return '名單裡有很像的：$names';
  }

  @override
  String get importAmbiguous => '不確定是哪一位（沒有連到帳號）';

  @override
  String get importUnknownDuties => '這個聚會沒有這些服事項目';

  @override
  String get importPastDays => '已經過去的日期，沒有匯入';

  @override
  String get importBadRows => '讀不懂的資料';

  @override
  String get jsonHint => '貼上辨識結果的 JSON';

  @override
  String get next2 => '預覽';

  @override
  String get calNotConnected => '教會還沒有連接行事曆';

  @override
  String get calConnect => '連接 Google 日曆';

  @override
  String get calReconnect => '重新連接';

  @override
  String get calNeedsReconnect => '行事曆的授權失效了';

  @override
  String get calNeedsReconnectStaff => '行事曆暫時讀不到，請管理員重新連接';

  @override
  String get calPickCalendar => '選擇要用的日曆';

  @override
  String get calNoCalendarYet => '還沒選日曆';

  @override
  String get calDisconnect => '中斷連接';

  @override
  String get calDisconnectTitle => '中斷行事曆連接？';

  @override
  String get calDisconnectBody => '同工會看不到行事曆，Google 日曆本身不受影響';

  @override
  String get calUnverifiedNote => '接下來 Google 會顯示「這個應用程式未經驗證」。這是因為馬大別忙還在審核中，點「進階」→「前往」即可。只會讀寫你選的那個日曆';

  @override
  String get calConnectedOk => '已連接 Google 日曆';

  @override
  String get calConnectFailed => '沒有連接成功，請再試一次';

  @override
  String get calNoEvents => '這個月沒有活動';

  @override
  String get calAllDay => '整天';

  @override
  String get calNewEvent => '新增活動';

  @override
  String get calEditEvent => '編輯活動';

  @override
  String get calTitle => '活動名稱';

  @override
  String get calLocation => '地點';

  @override
  String get calDate => '日期';

  @override
  String get calStart => '開始';

  @override
  String get calEnd => '結束';

  @override
  String get calDelete => '刪除活動';

  @override
  String calDeleted(String title) {
    return '已刪除$title';
  }

  @override
  String get calSaved => '已儲存活動';

  @override
  String get calPrevMonth => '上個月';

  @override
  String get calNextMonth => '下個月';

  @override
  String get calendarSetting => '行事曆';
}
