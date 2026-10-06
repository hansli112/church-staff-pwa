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
  String get loginTagline => '馬大！馬大！你為許多的事思慮煩擾，\n但是不可少的只有一件；\n馬利亞已經選擇那上好的福分，\n是不能奪去的。';

  @override
  String get loginTaglineSource => '路加福音 10:41–42';

  @override
  String loginInvitedTo(String church) {
    return '受邀加入〈$church〉';
  }

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
  String get gettingStarted => '開始使用';

  @override
  String get gettingStartedInvite => '邀請同工';

  @override
  String get gettingStartedInviteBody => '建立邀請連結，傳給同工';

  @override
  String get gettingStartedServices => '服事設定';

  @override
  String get gettingStartedServicesBody => '星期幾、要安排哪些服事';

  @override
  String get nobodyYet => '待定';

  @override
  String get noServicesConfigured => '還沒有設定聚會';

  @override
  String get setUpServices => '服事設定';

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
  String get testCrash => '測試當機';

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
  String get adminCannotLeave => '管理員不能直接退出。要退出，先把另一位同工設成管理員，再請對方取消你的管理員';

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
  String get roleAdminCan => '所有設定、邀請和移除同工';

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
    return '$days 天內有效';
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
  String get remove => '移除';

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
  String get notifNotAllowed => '通知還沒開。瀏覽器問要不要允許時，請按「允許」';

  @override
  String get pushView => '查看';

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
  String get photoUnavailable => '照片辨識暫時無法使用，請稍後再試，或先貼上 JSON';

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

  @override
  String get support => '支持馬大別忙';

  @override
  String get supportBody => '馬大別忙免費給每間教會使用。支持是自願的，不會多出任何功能';

  @override
  String get supportTips => '一次性支持';

  @override
  String get supportMonthly => '每月支持';

  @override
  String get supportRestore => '恢復購買';

  @override
  String get supportThanks => '謝謝你的支持';

  @override
  String get supportPending => '付款處理中';

  @override
  String get supportFailed => '沒有完成付款，沒有扣款';

  @override
  String get supportUnavailable => '現在無法連上商店';

  @override
  String get supporterBadge => '支持者';

  @override
  String get appIcon => 'App 圖示';

  @override
  String get appIconSupporterOnly => '每月支持者可以換 App 圖示';

  @override
  String get appIconDefault => '藍';

  @override
  String get appIconGreen => '綠';

  @override
  String get appIconPurple => '紫';

  @override
  String get appIconNight => '夜';

  @override
  String get savedOffline => '已存在這台裝置，連上網路後會自動同步';

  @override
  String get goHome => '回首頁';

  @override
  String get churchNotFound => '找不到這間教會';

  @override
  String get churchEntryNotMember => '你還不是這間教會的同工。請向管理員要邀請連結來加入。';

  @override
  String get churchUrl => '教會網址';

  @override
  String get churchUrlCopied => '已複製教會網址';

  @override
  String get churchUrlCopy => '複製教會網址';

  @override
  String get churchUrlShare => '分享教會網址';

  @override
  String get homeName => '主畫面名稱';

  @override
  String get homeNameUnset => '同教會名稱';

  @override
  String get homeNameMayBeCut => '部分手機會被截斷';

  @override
  String get homeNameFooter => '加入主畫面時，圖示下方顯示的名字。留空就用教會名稱。';

  @override
  String get addToHome => '加入主畫面';

  @override
  String get addToHomeIphone => '用 Safari 打開教會網址，點「分享」，再點「加入主畫面」';

  @override
  String get addToHomeAndroid => '用 Chrome 打開教會網址，點右上角的選單，再點「加到主畫面」';

  @override
  String get addToHomeIosNote => 'iPhone 上已經加入的圖示不會跟著更新。換了名稱或 logo 之後，請刪掉圖示再加入一次。';

  @override
  String get churchLink => '教會連結';

  @override
  String get churchLinkNone => '未設定';

  @override
  String get churchLinkTitle => '標題';

  @override
  String get churchLinkBody => '敘述（選填）';

  @override
  String get churchLinkUrl => '連結';

  @override
  String get churchLinkNeedsTitle => '請輸入標題';

  @override
  String get churchLinkNeedsHttps => '請輸入 https:// 開頭的連結';

  @override
  String get churchLinkFooter => '顯示在每位同工首頁的最上方，點了用瀏覽器打開。';

  @override
  String get churchLinkRemove => '移除教會連結';

  @override
  String get churchLinkRemoved => '已移除教會連結';

  @override
  String get churchLinkOpens => '用瀏覽器打開';

  @override
  String get linkSource => '每日內容來源（選填）';

  @override
  String get linkSourceUrl => 'JSON 網址';

  @override
  String get linkFetchTime => '每天更新時間';

  @override
  String get linkSourceFooter => '每天在這個時間抓一次，格式是有 title、body、link 的 JSON。抓到後 48 小時內，首頁顯示抓到的內容；抓不到就顯示上面的固定內容。';

  @override
  String linkSourceUpdated(String time) {
    return '上次更新：$time';
  }

  @override
  String linkSourceFailed(String reason) {
    return '上次沒有抓到：$reason';
  }

  @override
  String linkSourceFetched(String title) {
    return '已儲存，抓到「$title」';
  }

  @override
  String get linkErrTimeout => '對方網站 5 秒內沒有回應';

  @override
  String get linkErrTooLarge => '內容超過 64KB';

  @override
  String get linkErrBadFormat => '內容不是有 title 的 JSON';

  @override
  String get linkErrNotHttps => '網址或轉址不是 https';

  @override
  String linkErrHttp(String status) {
    return '對方網站回應錯誤（$status）';
  }

  @override
  String get linkErrNetwork => '連不上對方網站';

  @override
  String get linkErrUnknown => '原因不明，請再試一次';

  @override
  String get webhook => '外部通知';

  @override
  String get webhookUrl => '接收網址';

  @override
  String get webhookNeedsHttps => '請輸入 https:// 開頭的網址';

  @override
  String get webhookSecretOptional => '密鑰（選填，留空會自動產生）';

  @override
  String get webhookSecretTooShort => '密鑰至少要 16 個字元';

  @override
  String get webhookCalendar => '行事曆異動';

  @override
  String get webhookCalendarHint => '新增、修改、刪除活動';

  @override
  String get webhookRoster => '服事表異動';

  @override
  String get webhookRosterHint => '幾分鐘內的異動合併成一則';

  @override
  String get webhookFooter => '行事曆或服事表有異動時，把通知送到這個網址，例如交給 n8n 轉發到 LINE 群組。每則通知都用密鑰簽章。';

  @override
  String get webhookTest => '傳送測試';

  @override
  String webhookLast(String time, String result) {
    return '上次送出：$time・$result';
  }

  @override
  String get webhookOk => '成功';

  @override
  String webhookHttp(String status) {
    return '對方回應 $status';
  }

  @override
  String get webhookTimeout => '逾時';

  @override
  String get webhookNetwork => '連不上';

  @override
  String get webhookRotate => '換新的密鑰';

  @override
  String get webhookRotateMessage => '舊的密鑰會立刻失效，接收端要改用新的。';

  @override
  String get webhookGenerate => '自動產生';

  @override
  String get webhookTypeOwn => '自己輸入';

  @override
  String get webhookSecretTitle => '密鑰';

  @override
  String get webhookSecretOnce => '只會顯示這一次。請貼到接收端，用來驗證通知是馬大別忙送的。';

  @override
  String get webhookCopySecret => '複製密鑰';

  @override
  String get webhookSecretCopied => '已複製密鑰';

  @override
  String get webhookSecretChanged => '已換成新的密鑰';

  @override
  String get webhookOff => '關閉外部通知';

  @override
  String get webhookOffTitle => '關閉外部通知？';

  @override
  String get webhookOffMessage => '網址和密鑰都會刪掉，之後要重新設定。';

  @override
  String get webhookOffAction => '關閉';

  @override
  String get exportData => '匯出資料';

  @override
  String get exportFooter => '下載教會的全部資料：一份 JSON，加上一份可以用 Excel 打開的服事表。';

  @override
  String get exported => '已匯出';

  @override
  String get errMoveInvalid => '這不是搬家檔，請確認選對了檔案';

  @override
  String get errMoveTooLarge => '同工超過 2,000 位或服事表超過 20,000 天，沒辦法自動搬，請聯絡我們';

  @override
  String get moveFromSelfHost => '從舊版搬過來';

  @override
  String get moveIntro => '在舊版（church-staff-pwa）的 Cloud Shell 執行搬家指令，會得到一個搬家檔。上傳後先看預覽，確認了才會建立教會。';

  @override
  String get movePickFile => '選擇搬家檔';

  @override
  String get moveReading => '讀取搬家檔…';

  @override
  String get moveContents => '搬家檔內容';

  @override
  String get moveMembers => '同工';

  @override
  String moveMembersCount(int count) {
    return '$count 位';
  }

  @override
  String get moveRosters => '服事表';

  @override
  String moveRostersCount(int count) {
    return '$count 天';
  }

  @override
  String get moveServices => '服事';

  @override
  String get moveWhoAmI => '這位是我（選填）';

  @override
  String get moveWhoAmIFooter => '選了就接手那位的服事表、牧區和權限。其他同工用同一個 email 登入馬大別忙時，會被問要不要加入。';

  @override
  String get moveCreate => '建立教會並搬過來';

  @override
  String moveDone(String church) {
    return '已建立〈$church〉';
  }

  @override
  String get notSignedInYet => '還沒登入';

  @override
  String pendingCount(int count) {
    return '$count 位還沒登入';
  }

  @override
  String claimPrompt(String church) {
    return '〈$church〉的同工資料已經搬過來了，要加入嗎？';
  }

  @override
  String get claimJoin => '加入';

  @override
  String get claimDecline => '不要';

  @override
  String get movedPasswordNote => '從舊版搬過來的同工：舊的密碼不能用，請用同一個 email 註冊新帳號，或用 Google 登入。';

  @override
  String get pendingDelete => '刪除這筆資料';

  @override
  String pendingDeleteTitle(String name) {
    return '刪除〈$name〉的資料？';
  }

  @override
  String get pendingDeleteBody => '他就不能用 email 認領了。服事表上的名字會保留。';

  @override
  String get pendingDeleted => '已刪除';

  @override
  String get mergePending => '合併還沒登入的資料';

  @override
  String get mergePendingFooter => '同工換了 email 加入時，把舊名單上他的那筆資料合併過來，服事表、牧區、權限都會接上。';

  @override
  String get mergePendingPick => '選一筆還沒登入的資料';

  @override
  String mergePendingTitle(String pending, String member) {
    return '把〈$pending〉合併到〈$member〉？';
  }

  @override
  String mergePendingBody(String pending) {
    return '服事表上的〈$pending〉會改成這位同工，牧區和權限群組也會加上去。';
  }

  @override
  String get mergePendingAction => '合併';

  @override
  String get merged => '已合併';
}
