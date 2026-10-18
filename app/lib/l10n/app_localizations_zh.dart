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
  String get comingSoon => '還在做';

  @override
  String get signInWithGoogle => '使用 Google 登入';

  @override
  String get signInWithApple => '透過 Apple 登入';

  @override
  String get signInWithEmail => '用 email 登入';

  @override
  String inAppBrowserNote(String app) {
    return '在 $app 裡不能用 Google 登入。請用 Safari 或 Chrome 打開這個網頁，或用 email 登入。';
  }

  @override
  String get copyPageUrl => '複製連結';

  @override
  String get pageUrlCopied => '已複製連結，貼到 Safari 或 Chrome 打開';

  @override
  String get loginTagline => '馬大！馬大！你為許多的事思慮煩擾，\n但是不可少的只有一件；\n馬利亞已經選擇那上好的福分，\n是不能奪去的。';

  @override
  String get loginTaglineSource => '路加福音 10:41–42（和合本）';

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
  String get errInvalidCredential => 'email 或密碼不對';

  @override
  String get errEmailInUse => '這個 email 註冊過了，請直接登入或用 Google 登入';

  @override
  String get errWeakPassword => '密碼至少要 6 個字';

  @override
  String get errInvalidEmail => 'email 格式不對';

  @override
  String get errNeedsLink => '這個 email 已經有帳號。請用原本的方式登入，登入後會自動連在一起。';

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
  String get errDuplicateName => '已經有教會叫這個名字。如果是別人搶先註冊的，請回報問題。';

  @override
  String get contactUs => '回報問題';

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
  String alreadyMember(String church) {
    return '你已經是〈$church〉的同工';
  }

  @override
  String get errInviteInvalid => '找不到這個邀請，請確認邀請碼，或向管理員要新的邀請';

  @override
  String get errInviteExpired => '這個邀請過期了，請向管理員要新的邀請';

  @override
  String get errChurchClosed => '這間教會已停用';

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
  String get churchDeletedExpired => '已經超過 30 天，不能再還原了';

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
  String get noUpcomingServices => '接下來沒有你的服事，排到你時會出現在這裡';

  @override
  String get viewRosters => '看服事表';

  @override
  String get gettingStarted => '開始使用';

  @override
  String get inviteMembers => '邀請同工';

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
  String get setUpServices => '設定聚會';

  @override
  String get noRostersAhead => '接下來沒有聚會';

  @override
  String get rostersNobodyArranged => '還沒有安排任何人';

  @override
  String get rostersStartArranging => '開始安排';

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
    return '也讓「$name」負責$duty？';
  }

  @override
  String pickerAddDutyBody(String duty) {
    return '之後安排$duty時，會列在上面';
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
    return '已交換「$a」和「$b」';
  }

  @override
  String moved(String name, String day) {
    return '已把「$name」移到 $day';
  }

  @override
  String get emptySlot => '待定';

  @override
  String removeFromDuty(String duty) {
    return '從$duty移除';
  }

  @override
  String get events => '特別活動';

  @override
  String get eventsUpdated => '已更新特別活動';

  @override
  String get customEvent => '自訂特別活動';

  @override
  String get addEvent => '新增特別活動';

  @override
  String get eventName => '特別活動名稱';

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
    return '已移除「$name」';
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
  String get churchInfo => '教會資訊';

  @override
  String get manageChurch => '管理教會';

  @override
  String get lineCommunity => 'LINE 社群';

  @override
  String get lineCommunityNote => '問問題、回報問題、和其他教會交流';

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
  String get privacyPolicy => '隱私權政策';

  @override
  String get termsOfService => '服務條款';

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
  String get leave => '退出教會';

  @override
  String leftChurch(String church) {
    return '已退出〈$church〉';
  }

  @override
  String get adminCannotLeave => '管理員不能直接退出。要退出，先把另一位同工設成管理員，再請對方取消你的管理員。';

  @override
  String get churchLogo => '教會 logo';

  @override
  String get uploadLogo => '上傳 logo';

  @override
  String get changeLogo => '更換 logo';

  @override
  String get logoUploaded => '已更新 logo';

  @override
  String get logoTooLarge => '圖片太大了，請選 1 MB 以下的圖片';

  @override
  String get logoNotImage => '請選一張圖片';

  @override
  String memberCount(int count) {
    return '$count 位同工';
  }

  @override
  String get membersOnlyYou => '還沒有其他同工';

  @override
  String get deleteChurch => '刪除教會';

  @override
  String deleteChurchTitle(String church) {
    return '刪除〈$church〉？';
  }

  @override
  String get deleteChurchBody => '所有同工都看不到這間教會。30 天內可以還原，之後資料會永久刪除。';

  @override
  String get roleAdmin => '管理員';

  @override
  String get roleLeader => '小組長';

  @override
  String get roleStaff => '一般同工';

  @override
  String get roleMember => '組員';

  @override
  String get role => '身分';

  @override
  String get roleAdminCan => '所有設定、邀請和移除同工';

  @override
  String get groups => '權限群組';

  @override
  String get groupRosterEditors => '安排服事表';

  @override
  String get groupCalendarEditors => '編輯行事曆';

  @override
  String get zones => '牧區與服事';

  @override
  String get zonesFooter => '能安排服事表的人，只能排自己牧區的聚會';

  @override
  String get removeMember => '移除同工';

  @override
  String memberRemoved(String name) {
    return '已移除「$name」';
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
  String get copyByHand => '沒辦法自動複製，請選取下面的文字自己複製';

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
  String get serviceEnabled => '啟用';

  @override
  String get serviceDisabledFooter => '停用的聚會不會再出現新的服事表，舊的保留';

  @override
  String get templateDuties => '服事項目';

  @override
  String get templateFooter => '新的服事表會帶入這些項目。已經安排的服事表不受影響。';

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
  String get deleteAccountBody => '你會退出所有教會，帳號與個人資料會刪除且無法復原。服事表上的名字會保留。';

  @override
  String deleteAccountLastAdmin(String churches) {
    return '你是〈$churches〉唯一的管理員，請先把管理員交給別的同工';
  }

  @override
  String get goToMembers => '前往同工';

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
  String get adminChurches => '教會';

  @override
  String get adminRename => '改名';

  @override
  String get adminMakeAdmin => '設為管理員';

  @override
  String adminMadeAdmin(String name) {
    return '已把「$name」設為管理員';
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
  String get notifReminderWeeklySub => '每週一晚上，列出這週的服事';

  @override
  String get notifReminderDayBeforeSub => '服事前一天晚上提醒你';

  @override
  String get notifReminderBothSub => '每週一晚上，和服事前一天晚上';

  @override
  String get notifReminderTime => '服事提醒時間';

  @override
  String get notifReminderWeekly => '每週一晚上';

  @override
  String get notifReminderDayBefore => '前一天晚上';

  @override
  String get notifReminderBoth => '兩個都要';

  @override
  String get notifReminderTimeFooter => '都在晚上 7 點';

  @override
  String get notifRosterChange => '服事表異動';

  @override
  String get notifRosterChangeSub => '你被排進或移出服事時。晚上 10 點後的異動，早上 7 點才通知';

  @override
  String get notifMemberLeft => '同工退出';

  @override
  String get notifMemberLeftSub => '有人退出教會時（只通知管理員）';

  @override
  String get notifThisChurch => '這間教會的通知';

  @override
  String get notifPermissionOff => '通知被關掉了，請到系統設定打開';

  @override
  String get notifEnable => '開啟通知';

  @override
  String get notifAskTitle => '被排到服事時通知你';

  @override
  String get notifAskBody => '排進服事、服事表有變動時通知你，每週一晚上也會提醒這週的服事';

  @override
  String get notifAskLater => '稍後再說';

  @override
  String get notifCardHide => '不再顯示';

  @override
  String get notifOpenSettings => '到設定開啟通知';

  @override
  String get notifNotAllowed => '通知還沒開。跳出詢問時，請點「允許」。';

  @override
  String get notifRegisterFailed => '通知還沒設定好，下次打開 App 會再試';

  @override
  String get pushView => '查看';

  @override
  String get zoneSwitch => '屬於這個牧區';

  @override
  String zoneLeft(String service) {
    return '不再屬於$service牧區';
  }

  @override
  String get eventRosterGone => '找不到這個活動的服事表';

  @override
  String get eventRoster => '服事表';

  @override
  String eventRosterPeople(int count) {
    return '$count 人';
  }

  @override
  String get arrangeEventRoster => '安排服事';

  @override
  String get eventRosterEmpty => '還沒有服事項目';

  @override
  String get copyDuties => '沿用其他活動';

  @override
  String get copyDutiesHeader => '沿用哪一場的服事項目';

  @override
  String get copyDutiesNone => '還沒有其他活動的服事表';

  @override
  String dutiesCopied(int count) {
    return '已加入 $count 個服事項目';
  }

  @override
  String get noZoneYet => '你還沒有屬於任何牧區，請找管理員設定';

  @override
  String get waitsForZone => '還沒設定牧區';

  @override
  String waitingForZone(int count) {
    return '$count 位同工還沒設定牧區';
  }

  @override
  String get inviteZones => '加入後屬於';

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
    return '這個月的 $limit 張用完了，下個月 1 日恢復。這段時間可以直接安排服事表。';
  }

  @override
  String get photoPlatformOff => '照片辨識這個月暫停（全站的辨識額度用完了），下個月恢復。這段時間可以直接安排服事表。';

  @override
  String get photoTooLarge => '照片太大，請裁到只剩表格再試';

  @override
  String get photoFailed => '辨識失敗，請換一張清楚一點的照片再試';

  @override
  String get photoUnavailable => '照片辨識暫時無法使用，請稍後再試，或直接安排服事表';

  @override
  String get importPreview => '預覽';

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
  String get calUnverifiedNote => '接下來 Google 會顯示「這個應用程式未經驗證」，點「進階」→「前往」繼續。只會讀寫你選的那個日曆。';

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
  String get calStart => '開始';

  @override
  String get calEnd => '結束';

  @override
  String get calOtherTime => '其他時間…';

  @override
  String calLengthMinutes(int minutes) {
    return '$minutes 分鐘';
  }

  @override
  String calLengthHours(int hours) {
    return '$hours 小時';
  }

  @override
  String calLengthHoursMinutes(int hours, int minutes) {
    return '$hours 小時 $minutes 分鐘';
  }

  @override
  String get calDelete => '刪除活動';

  @override
  String calDeleted(String title) {
    return '已刪除「$title」';
  }

  @override
  String get calSaved => '已儲存活動';

  @override
  String get calPrevMonth => '上個月';

  @override
  String get calNextMonth => '下個月';

  @override
  String get calShowMonth => '顯示月曆';

  @override
  String get calHideMonth => '只看列表';

  @override
  String get calendarSetting => '行事曆';

  @override
  String get support => '支持馬大別忙';

  @override
  String get supportVerse => '乃要均平，就是要你們的富餘，現在可以補他們的不足，使他們的富餘，將來也可以補你們的不足，這就均平了。如經上所記：多收的也沒有餘；少收的也沒有缺。';

  @override
  String get supportVerseSource => '哥林多後書 8:14–15（和合本）';

  @override
  String get supportBody => '支持完全自願，只用來分擔雲端費用，不是給教會的奉獻；每間教會能用的功能都一樣';

  @override
  String get supportTips => '一次性支持';

  @override
  String get supportMonthly => '每月支持';

  @override
  String get supportRestore => '恢復購買';

  @override
  String supportMonthlyTerms(String store) {
    return '每月自動續訂，可以隨時到 $store 的訂閱設定取消';
  }

  @override
  String get manageSubscription => '管理訂閱';

  @override
  String get supportThanks => '謝謝你的支持';

  @override
  String get supportPending => '付款處理中';

  @override
  String get supportFailed => '沒有完成付款，沒有扣款';

  @override
  String get supportUnavailable => '現在無法連上商店，請稍後再試';

  @override
  String get supportComingSoon => 'App 內支持即將開放';

  @override
  String get supporterBadge => '支持者';

  @override
  String get appIcon => 'App 圖示';

  @override
  String get appIconSupporterOnly => '每月支持者可以換 App 圖示';

  @override
  String get appIconDefault => '預設';

  @override
  String get appIconGreen => '綠';

  @override
  String get appIconPurple => '紫';

  @override
  String get appIconNight => '夜';

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
  String get addToHomeIosNote => 'iPhone 上已經加入的圖示不會跟著更新。換了名稱或 logo 之後，請刪掉圖示再加入一次。';

  @override
  String get addToHomeLater => '稍後再說';

  @override
  String addToHomeDone(String name) {
    return '已加入，之後點手機上的「$name」圖示打開';
  }

  @override
  String get addToHomeIntro => '下次點主畫面的圖示，就能打開服事表';

  @override
  String addToHomeBrowserGuide(String device, String browser) {
    return '$device · $browser 教學';
  }

  @override
  String get addToHomeChooseBrowser => '畫面不一樣？';

  @override
  String get addToHomeChooseGuide => '選擇要看的教學';

  @override
  String get addToHomeChooseGuideNote => '只切換教學，不會替你開啟另一個瀏覽器';

  @override
  String get addToHomeSafariLayoutTitle => 'Safari 畫面';

  @override
  String get addToHomeSafariLayoutHint => '請依工具列上的按鈕選擇，不需要更改 Safari 設定';

  @override
  String get addToHomeSafariMoreChoice => '我看到「⋯」';

  @override
  String get addToHomeSafariShareChoice => '我看到分享圖示';

  @override
  String get addToHomeSafariMoreShare => '點「⋯」，再選「分享」';

  @override
  String get addToHomeSafariDirectShareHint => '網址列在上或下都可以，請找「方框向上箭頭」';

  @override
  String get addToHomeInApp => 'App 內建瀏覽器';

  @override
  String get addToHomeOtherBrowser => '其他瀏覽器';

  @override
  String get addToHomeScreenshotNote => '請點瀏覽器上圈出的按鈕';

  @override
  String get addToHomeSafariScreenshot => 'Safari · iOS 26.5 · 繁中模擬器畫面';

  @override
  String get addToHomeChromeAndroidScreenshot => 'Chrome 113 · Android 14 · 繁中模擬器畫面（舊版選單）';

  @override
  String get addToHomeChromeIosScreenshot => 'Chrome 155 · iOS 27.2 · iPhone 13 真機畫面';

  @override
  String get addToHomeAddressBar => '網址列';

  @override
  String get addToHomeChromeShare => '點網址列旁的分享圖示';

  @override
  String get addToHomeChromeShareHint => '不是「⋯」選單，也不是「分享 Chrome」';

  @override
  String get addToHomeChromeScroll => '看不到時，先把分享面板展開，再往下滑';

  @override
  String get addToHomeSafariShare => '點 Safari 的分享圖示';

  @override
  String get addToHomeFirefoxShare => '點網址列的分享圖示';

  @override
  String get addToHomeIpadMore => 'iPad 沒看到這個選項時，先點分享面板中的「更多」';

  @override
  String get addToHomeSelectAdd => '點「加入主畫面」';

  @override
  String get addToHomeShareMore => '只看到一排圖示時，先點「檢視較多」；舊版要往下滑';

  @override
  String get addToHomeIosConfirm => '有網頁 App 開關時保持開啟，最後點右上角的「加入」或「新增」';

  @override
  String get addToHomeOpenTitle => '回主畫面，點新圖示開啟';

  @override
  String addToHomeMenu(String browser) {
    return '點 $browser 的選單';
  }

  @override
  String get addToHomeChromeInstall => '加到主畫面 → 安裝';

  @override
  String get addToHomeChromeInstallHint => '舊版可能叫「安裝應用程式」。請選「安裝」，不是「建立捷徑」。';

  @override
  String get addToHomeFirefoxInstallHint => '再照手機的提示新增；只有「新增至主畫面」時，可能只會建立瀏覽器捷徑';

  @override
  String get addToHomeTrouble => '找不到「加入主畫面」？';

  @override
  String get addToHomeSafariTrouble => '先把分享面板往上拉，查看下方的動作；仍找不到時，點最下方「編輯動作」查看';

  @override
  String addToHomeExternalTitle(String browser) {
    return '先用 $browser 開啟';
  }

  @override
  String addToHomeExternalHint(String browser) {
    return '複製教會網址，再貼到 $browser 的網址列，開啟後繼續教學';
  }

  @override
  String get addToHomeEmbeddedHint => '你正在 App 裡看網頁，請先換到手機的瀏覽器';

  @override
  String get addToHomeUnknownHint => '這個瀏覽器的選單可能不同，改用下方方式繼續';

  @override
  String addToHomeCopiedForBrowser(String browser) {
    return '已複製，請開啟 $browser，貼到網址列';
  }

  @override
  String get addToHomePhoneOnly => '請用手機開啟教會網址，再加入主畫面';

  @override
  String get addToHomeNotificationsAfter => '從主畫面打開後，在「我的」開啟通知，就收得到服事通知';

  @override
  String get addToHomeIosShare => '分享';

  @override
  String get addToHomeIosAdd => '加入';

  @override
  String addToHomeIosOpen(String name) {
    return '點手機上的「$name」圖示打開，再登入一次';
  }

  @override
  String get addToHomeAndroidAdd => '加到主畫面';

  @override
  String get addToHomeAndroidInstall => '安裝';

  @override
  String addToHomeAndroidOpen(String name) {
    return '點手機上的「$name」圖示打開';
  }

  @override
  String get addToHomeCardBody => '一點就打開，也收得到服事通知';

  @override
  String get addToHomeCardHide => '不再顯示';

  @override
  String get notifNeedsHomeScreen => '先加入主畫面，才收得到通知';

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
  String get churchLinkFooter => '顯示在每位同工首頁的最上方，點了用瀏覽器打開';

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
  String get linkSourceFooter => '每天這個時間抓一次。JSON 要有 date（教會的今天）、title、body、link（https）。';

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
  String get linkErrTooLarge => '內容超過 64 KB';

  @override
  String get linkErrBadFormat => '內容不是完整的 date、title、body、link JSON';

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
  String get webhookSecretTooShort => '密鑰至少要 16 個字';

  @override
  String get webhookCalendar => '行事曆異動';

  @override
  String get webhookCalendarHint => '新增、修改、刪除活動';

  @override
  String get webhookRoster => '服事表異動';

  @override
  String get webhookRosterHint => '幾分鐘內的異動合併成一則';

  @override
  String get webhookFooter => '行事曆或服事表有異動時，送通知到這個網址，例如交給 n8n 轉發到 LINE 群組。通知都用密鑰簽章。';

  @override
  String get webhookTest => '傳送測試';

  @override
  String webhookLast(String time, String result) {
    return '上次送出：$time · $result';
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
  String get webhookRotateMessage => '舊的密鑰會立刻失效，接收端要改用新的';

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
  String get webhookOffMessage => '網址和密鑰都會刪掉，之後要重新設定';

  @override
  String get webhookOffAction => '關閉';

  @override
  String get exportData => '匯出資料';

  @override
  String get exportFooter => '匯出教會的全部資料：一份 JSON，加上一份可以用 Excel 打開的服事表';

  @override
  String get exported => '已匯出';

  @override
  String get exportCsvFile => '服事表.csv';

  @override
  String get exportCsvDate => '日期';

  @override
  String get exportCsvService => '聚會／活動';

  @override
  String get exportCsvRole => '服事項目';

  @override
  String get exportCsvPeople => '同工';

  @override
  String get errMoveInvalid => '這不是搬家檔，請確認選對了檔案';

  @override
  String get errMoveTooLarge => '同工超過 2,000 位或服事表超過 20,000 天，沒辦法自動搬。請到 GitHub 的 church-staff-pwa 開 issue。';

  @override
  String get moveFromSelfHost => '從舊版搬過來';

  @override
  String get moveIntro => '在舊版（church-staff-pwa）的 Cloud Shell 執行搬家指令，把得到的搬家檔上傳。確認預覽後才會建立教會。';

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
  String get moveServices => '聚會';

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
    return '〈$church〉的同工資料\n已經搬過來了，要加入嗎？';
  }

  @override
  String get claimJoin => '加入';

  @override
  String get claimDecline => '不加入';

  @override
  String get movedPasswordNote => '從舊版搬過來的同工：舊的密碼不能用，\n請用同一個 email 註冊新帳號，或用 Google 登入';

  @override
  String get pendingDelete => '刪除這筆資料';

  @override
  String pendingDeleteTitle(String name) {
    return '刪除「$name」的資料？';
  }

  @override
  String get pendingDeleteBody => '對方就不能用 email 認領了。服事表上的名字會保留。';

  @override
  String get pendingDeleted => '已刪除';

  @override
  String get mergePending => '合併還沒登入的資料';

  @override
  String get mergePendingFooter => '同工換了 email 加入時，合併舊名單上那筆資料，服事表、牧區和權限群組都會接上';

  @override
  String get mergePendingPick => '選一筆還沒登入的資料';

  @override
  String mergePendingTitle(String pending, String member) {
    return '把「$pending」合併到「$member」？';
  }

  @override
  String mergePendingBody(String pending) {
    return '服事表上的「$pending」會改成這位同工，牧區和權限群組也會加上去';
  }

  @override
  String get mergePendingAction => '合併';

  @override
  String get merged => '已合併';

  @override
  String get fundingTitle => '這個月的雲端費用';

  @override
  String fundingProgress(String available, String target) {
    return '$available / $target';
  }

  @override
  String get fundingEnough => '這個月已經足夠';

  @override
  String fundingMonthsLeft(int months) {
    return '這個月已經足夠，多的還能再維持 $months 個月';
  }

  @override
  String fundingCarried(String amount) {
    return '含前幾個月留下的 $amount';
  }

  @override
  String get fundingCosts => '雲端費用';

  @override
  String fundingTarget(String amount) {
    return '每月目標 $amount';
  }

  @override
  String get fundingTargetUpdating => '每月目標更新中…';

  @override
  String get fundingCostsHeader => '費用';

  @override
  String get fundingCostsFooter => '價格變了再改。每年的項目平均分到每個月。名稱和每月金額會公開在支持頁。';

  @override
  String get fundingMonthsHeader => '最近幾個月';

  @override
  String fundingMonthValue(String received, String target) {
    return '$received / $target';
  }

  @override
  String get costAdd => '新增項目';

  @override
  String get costEdit => '費用項目';

  @override
  String get costName => '名稱';

  @override
  String get costAmount => '金額';

  @override
  String get costPerMonth => '每月';

  @override
  String get costPerYear => '每年';

  @override
  String costValueMonth(String amount) {
    return '$amount · 每月';
  }

  @override
  String costValueYear(String amount) {
    return '$amount · 每年';
  }

  @override
  String moneyTwd(String amount) {
    return 'NT\$$amount';
  }

  @override
  String moneyUsd(String amount) {
    return 'US\$$amount';
  }

  @override
  String get currencyTwd => 'NT\$';

  @override
  String get currencyUsd => 'US\$';

  @override
  String get fundingWhereItGoes => '每個月用在哪裡';

  @override
  String get fundingYearlySplit => '每年付一次的費用平均分到每個月';

  @override
  String get fundingRatesBy => '匯率：Exchange Rate API';

  @override
  String get importAdvanced => '進階';

  @override
  String get importCopyPrompt => '複製 AI 指令';

  @override
  String get importPromptCopied => '已複製，連同照片傳給 AI，再把它回的 JSON 貼上來';

  @override
  String get importFormatHelp => 'date：YYYY-MM-DD；沒有人時 people 填 []。\nevents 可省略；特別活動的 color 填色號 0–5。';

  @override
  String get importPhotoFormatError => '辨識結果的格式不對，請重新辨識或用進階 JSON';

  @override
  String get importJsonSyntaxError => 'JSON 格式不對，請用下方範例的陣列格式';

  @override
  String get importJsonEdit => '編輯 JSON';

  @override
  String get importJsonArrayRequired => '請填 JSON 陣列';

  @override
  String importConfirmName(String name) {
    return '確認「$name」';
  }

  @override
  String get importSameNameScope => '這次匯入的同名人名都用這個對應';

  @override
  String importGuestChoice(String name) {
    return '保留「$name」為外請';
  }

  @override
  String get importEditDate => '編輯日期';

  @override
  String get importDateFormatLabel => '日期（YYYY-MM-DD）';

  @override
  String get importValidDate => '請填有效的 YYYY-MM-DD 日期';

  @override
  String get importEditDuty => '編輯服事項目';

  @override
  String get importDutyLabel => '服事項目';

  @override
  String get importPeopleLines => '名字（每行一人）';

  @override
  String get importAddEventAction => '新增特別活動';

  @override
  String get importEditEvent => '編輯特別活動';

  @override
  String get importConflict => '服事表已變更，請重新檢查差異後再套用';

  @override
  String get importScopeChanged => '教會或帳號已切換，請重新匯入';

  @override
  String importRow(int number) {
    return '第 $number 列';
  }

  @override
  String get importDateLabel => '日期';

  @override
  String get importDateMissing => '請填日期';

  @override
  String get importFixDuty => '修正服事項目';

  @override
  String get importPeopleArrayHint => 'people 請填人名陣列';

  @override
  String get importFixEvent => '修正特別活動';

  @override
  String importRemoveDuty(String role, String names) {
    return '移除$role：$names';
  }

  @override
  String importAddDuty(String role, String names) {
    return '新增$role：$names';
  }

  @override
  String importChangeDuty(String role, String before, String after) {
    return '$role：$before → $after';
  }

  @override
  String importMemberIdentity(String name) {
    return '$name（同工）';
  }

  @override
  String importGuestIdentity(String name) {
    return '$name（外請）';
  }

  @override
  String importRemoveEvent(String name) {
    return '移除特別活動：$name';
  }

  @override
  String importAddEvent(String name) {
    return '新增特別活動：$name';
  }

  @override
  String importChangeEvent(String name) {
    return '特別活動：$name';
  }

  @override
  String importChangedColor(String before, String after) {
    return '$before → $after';
  }

  @override
  String get importNoChange => '安排沒有變更';

  @override
  String get importNoCandidate => '請保留為外請或修正人名';

  @override
  String importCandidates(String names) {
    return '候選：$names';
  }

  @override
  String get importGuestUnlinked => '外請（沒有連到帳號）';

  @override
  String get importNameNeedsConfirm => '請確認人名';

  @override
  String importLinkedMember(String name) {
    return '同工：$name';
  }

  @override
  String get importMode => '匯入方式';

  @override
  String get importMerge => '合併（保留未提到的安排）';

  @override
  String get importReplace => '取代當天全部安排';

  @override
  String get importReplaceHelp => '移除沒提到的服事項目與特別活動；不影響其他日期';

  @override
  String get importFixData => '請修正資料後再匯入';

  @override
  String get importFixRow => '請修正這一列資料';

  @override
  String get importNameLinks => '人名對應';

  @override
  String get importNamesNeedConfirm => '確認人名後才能匯入';

  @override
  String get importRepairSettings => '修正教會設定（選填）';

  @override
  String get importNoSettingsChange => '這次安排不會變更同工或教會設定';

  @override
  String importAddConfiguredDuty(String role) {
    return '加入服事設定：$role';
  }

  @override
  String importUnconfiguredDuty(String role) {
    return '未設定的服事項目：$role';
  }

  @override
  String importGrantQualification(String name, String role) {
    return '讓$name負責$role';
  }

  @override
  String importMissingQualification(String name, String role) {
    return '$name還沒設定$role';
  }

  @override
  String importAddCommonEvent(String name) {
    return '加入常用特別活動：$name';
  }

  @override
  String importNotCommonEvent(String name) {
    return '未設為常用特別活動：$name';
  }

  @override
  String importDiff(String date) {
    return '套用後差異 · $date';
  }

  @override
  String importRequiredField(String field) {
    return '請填$field';
  }

  @override
  String get importColor => '顏色';

  @override
  String get importIssueRowObject => '請填包含 date、duties 的物件';

  @override
  String get importIssueRowFields => '只支援 date、duties、events 欄位';

  @override
  String get importIssueDate => 'date 請填有效的 YYYY-MM-DD 日期';

  @override
  String get importIssueDuplicateDate => '日期重複，請合併成同一列';

  @override
  String get importIssueDutiesArray => 'duties 請填陣列';

  @override
  String importIssueDutyFields(int index) {
    return '第 $index 個服事項目只支援 role、people';
  }

  @override
  String importIssueRole(int index) {
    return '第 $index 個 role 請填不重複的服事項目名稱';
  }

  @override
  String importIssuePeopleArray(int index) {
    return '第 $index 個 people 請填非空白人名的字串陣列；無人時填 []';
  }

  @override
  String importIssueDuplicatePeople(int index) {
    return '第 $index 個 people 不可有重複人名';
  }

  @override
  String get importIssueEventsArray => 'events 請填陣列';

  @override
  String importIssueEventObject(int index, String example) {
    return '第 $index 個特別活動請填 $example';
  }

  @override
  String importIssueEventName(int index) {
    return '第 $index 個特別活動的 name 請填不重複的名稱';
  }

  @override
  String importIssueEventColor(int index) {
    return '第 $index 個特別活動的 color 請填 0 到 5 的整數';
  }

  @override
  String importIssueResolvedDuplicatePeople(String role) {
    return '$role：確認後人名重複，請移除重複的人名';
  }

  @override
  String get appRunningVersion => '目前版本';

  @override
  String appVersionWithFix(String version, int patch) {
    return '$version · 修正 $patch';
  }

  @override
  String get appVersionDevelopment => '開發版本（還沒有發布版本）';

  @override
  String get updateRequiredTitle => '請更新馬大別忙';

  @override
  String get updateRequiredBody => '這個版本太舊了，更新後才能繼續使用';

  @override
  String updateRequiredOpen(String store) {
    return '到 $store 更新';
  }

  @override
  String get appUpdateCheck => '檢查更新';

  @override
  String get appUpdateChecking => '檢查中…';

  @override
  String get appUpdateApply => '更新並重新開啟';

  @override
  String get appUpdateApplying => '更新中…';

  @override
  String get saving => '儲存中…';

  @override
  String get appUpdateCurrent => '已是最新版本';

  @override
  String get appUpdateReady => '有新版本';

  @override
  String get appUpdateFinishEditing => '還有沒儲存的內容，儲存後再更新';

  @override
  String get appUpdateFinishEditingNote => '先儲存正在編輯的內容';

  @override
  String get appUpdateFailed => '沒有更新成功，請檢查網路後再試一次';

  @override
  String get appUpdateScopeChanged => '帳號或教會換了，請重新檢查更新';

  @override
  String get appUpdateBackToMe => '請再點一次「更新並重新開啟」';

  @override
  String get appUpdateCheckFirst => '請先檢查更新';

  @override
  String get servicesAdminOnly => '只有管理員能改服事設定';

  @override
  String get importExampleRole => '司琴';

  @override
  String get importExamplePerson => '李美玉';

  @override
  String get importExampleEvent => '聖餐';

  @override
  String get rosterShowMore => '顯示更多';

  @override
  String get pickerGuestNames => '外請名字';

  @override
  String get serviceSettingsSaved => '服事設定已儲存';

  @override
  String get serviceSyncOriginalEvent => '原本的特別活動';

  @override
  String get serviceSyncOriginalDuty => '原本的服事項目';

  @override
  String serviceFutureSyncTitle(String from, String to) {
    return '同步「$from」為「$to」';
  }

  @override
  String serviceFutureSyncSaved(int count) {
    return '已同步 $count 份未來服事表';
  }

  @override
  String serviceEventColorTitle(String name) {
    return '$name · 顏色';
  }

  @override
  String get serviceEventColor => '顏色';

  @override
  String get serviceSyncFutureRosters => '同步未來服事表';

  @override
  String get rosterFutureChangesNone => '沒有需要變更的未來服事表';

  @override
  String get rosterFutureChangesFooter => '只變更明天起已儲存的服事表';

  @override
  String get rosterFutureChangesConflict => '已有同名項目，請先調整';

  @override
  String get rosterApplyFutureChanges => '套用變更';

  @override
  String get rosterRemoveFutureGuest => '移除未來的外請安排';

  @override
  String rosterRemoveFutureGuestTitle(String name) {
    return '移除「$name」的未來安排';
  }

  @override
  String rosterFutureGuestRemoved(int count) {
    return '已移除 $count 份未來安排';
  }

  @override
  String rosterFutureDutyChange(String role, String before, String after) {
    return '$role：$before → $after';
  }

  @override
  String rosterFutureEventChange(String before, String after) {
    return '$before → $after';
  }

  @override
  String get errConflict => '其他同工剛改過，重新整理後再改一次';

  @override
  String get errOfflineReadOnly => '離線中，連線後才能儲存';

  @override
  String get errTooManyChanges => '一次最多改 500 份服事表，請分成幾次改';

  @override
  String get undoDone => '已復原';

  @override
  String get undoFailed => '復原失敗，請再試一次';

  @override
  String get offlineReadOnlyBanner => '離線中，顯示上次的資料，連線後才能儲存';

  @override
  String get calendarCached => '顯示上次的資料';

  @override
  String calendarReadAt(String time) {
    return '$time 更新';
  }

  @override
  String get calDescription => '活動說明';

  @override
  String get calDuplicate => '複製活動';

  @override
  String get homeUpcomingEvents => '近期活動';

  @override
  String get memberSmallGroups => '小組';

  @override
  String get memberSmallGroupsHint => '每行一個小組';

  @override
  String get linkErrNotToday => '來源還沒有今天的內容';

  @override
  String linkSourceToday(String reason) {
    return '今天的內容沒有更新：$reason';
  }

  @override
  String get linkSourceRetry => '重新抓取';

  @override
  String get listSeparator => '、';

  @override
  String labelValue(String label, String value) {
    return '$label：$value';
  }

  @override
  String nameIsYou(String name) {
    return '$name（你）';
  }

  @override
  String get churchListSeparator => '〉〈';

  @override
  String dayWithEvents(String day, String events) {
    return '$day，$events';
  }

  @override
  String get dotSeparator => ' · ';

  @override
  String get churchStatus => '狀態';

  @override
  String get timeZone => '時區';

  @override
  String timeZoneWithOffset(String city, String offset) {
    return '$city（$offset）';
  }

  @override
  String get timeZoneFooter => '今天的日期、服事提醒和行事曆的時間都照教會的時區';

  @override
  String timeZoneChangeTitle(String city) {
    return '改成$city時間？';
  }

  @override
  String get timeZoneChangeBody => '活動時間會照新時區顯示，服事表的日期不變';

  @override
  String timeZoneChange(String city) {
    return '改成$city時間';
  }

  @override
  String churchLocalTime(String city) {
    return '教會當地時間（$city）';
  }

  @override
  String calendarTimeZoneDiffers(String zone, String city) {
    return '這本日曆的時區是$zone，跟教會的時區（$city）不同。行事曆的時間照教會的時區顯示。';
  }

  @override
  String get cityAuckland => '奧克蘭';

  @override
  String get citySydney => '雪梨';

  @override
  String get cityMelbourne => '墨爾本';

  @override
  String get cityTokyo => '東京';

  @override
  String get citySeoul => '首爾';

  @override
  String get cityTaipei => '台北';

  @override
  String get cityHongKong => '香港';

  @override
  String get citySingapore => '新加坡';

  @override
  String get cityKualaLumpur => '吉隆坡';

  @override
  String get cityLondon => '倫敦';

  @override
  String get cityToronto => '多倫多';

  @override
  String get cityNewYork => '紐約';

  @override
  String get cityChicago => '芝加哥';

  @override
  String get cityDenver => '丹佛';

  @override
  String get cityVancouver => '溫哥華';

  @override
  String get cityLosAngeles => '洛杉磯';

  @override
  String get signInMethods => '登入方式';

  @override
  String get signInMethodPassword => 'Email 與密碼';

  @override
  String get signInMethodsFooter => '用哪一種方式登入都是同一個帳號，教會、服事表和權限都一樣';

  @override
  String get linkGoogle => '連結 Google 帳號';

  @override
  String get linkGoogleFooter => 'Google 帳號的 email 可以和這個帳號不同';

  @override
  String get linkedGoogle => '已連結 Google 帳號';

  @override
  String get unlink => '解除連結';

  @override
  String unlinkTitle(String method) {
    return '解除連結 $method？';
  }

  @override
  String unlinkBody(String email) {
    return '之後就不能用 $email 登入這個帳號';
  }

  @override
  String get errCredentialInUse => '你選的帳號已經是另一個馬大別忙帳號，不能連結。要連結的話，請先用它登入並刪除那個帳號，再回來連結。';

  @override
  String get onlineRefundHeader => '線上支持退款';

  @override
  String get onlineRefundFooter => '在綠界後台退款後，填這筆的特店訂單編號，就會從雲端費用進度扣回。';

  @override
  String get onlineRefundAdd => '扣回一筆退款';

  @override
  String get onlineRefundOrderNo => '特店訂單編號';

  @override
  String get onlineRefundApply => '從進度扣回';

  @override
  String onlineRefunded(String month, String amount) {
    return '已從 $month 扣回 $amount';
  }

  @override
  String get onlineRefundNotFound => '找不到這筆線上支持，請確認特店訂單編號';
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class L10nZhHans extends L10nZh {
  L10nZhHans() : super('zh_Hans');

  @override
  String get appName => '马大别忙';

  @override
  String get tabHome => '首页';

  @override
  String get tabRosters => '事奉表';

  @override
  String get tabCalendar => '行事历';

  @override
  String get tabMe => '我的';

  @override
  String get undo => '撤销';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get done => '完成';

  @override
  String get retry => '重试';

  @override
  String get search => '搜索';

  @override
  String get clear => '清除';

  @override
  String get selected => '已选择';

  @override
  String get close => '关闭';

  @override
  String get add => '添加';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';

  @override
  String get deleted => '已删除';

  @override
  String get loadFailed => '加载失败，请检查网络后再试一次';

  @override
  String get saveFailed => '没有保存成功，请检查网络后再试一次';

  @override
  String get noPermission => '你没有权限做这件事';

  @override
  String get comingSoon => '还在开发中';

  @override
  String get signInWithGoogle => '使用 Google 登录';

  @override
  String get signInWithApple => '通过 Apple 登录';

  @override
  String get signInWithEmail => '用邮箱登录';

  @override
  String inAppBrowserNote(String app) {
    return '在 $app 里不能用 Google 登录。请用 Safari 或 Chrome 打开这个网页，或用邮箱登录。';
  }

  @override
  String get copyPageUrl => '复制链接';

  @override
  String get pageUrlCopied => '已复制链接，粘贴到 Safari 或 Chrome 打开';

  @override
  String get loginTagline => '马大！马大！你为许多的事思虑烦扰，\n但是不可少的只有一件；\n马利亚已经选择那上好的福分，\n是不能夺去的。';

  @override
  String get loginTaglineSource => '路加福音 10:41–42（和合本）';

  @override
  String loginInvitedTo(String church) {
    return '受邀加入“$church”';
  }

  @override
  String get email => '邮箱';

  @override
  String get password => '密码';

  @override
  String get yourName => '你的名字';

  @override
  String get signIn => '登录';

  @override
  String get register => '注册';

  @override
  String get createAccount => '注册新账号';

  @override
  String get haveAccount => '已经有账号？登录';

  @override
  String get forgotPassword => '忘记密码';

  @override
  String resetSent(String email) {
    return '重设密码的邮件已发送到 $email';
  }

  @override
  String get errInvalidCredential => '邮箱或密码不对';

  @override
  String get errEmailInUse => '这个邮箱已经注册过了，请直接登录或用 Google 登录';

  @override
  String get errWeakPassword => '密码至少要 6 个字符';

  @override
  String get errInvalidEmail => '邮箱格式不对';

  @override
  String get errNeedsLink => '这个邮箱已经有账号。请用原本的方式登录，登录后会自动关联在一起。';

  @override
  String get errTooMany => '尝试太多次，请稍后再试';

  @override
  String get errNetwork => '连不上网络，请检查后再试一次';

  @override
  String get errUnknown => '没有成功，请再试一次';

  @override
  String get nameRequired => '请输入名字';

  @override
  String get emailRequired => '请输入邮箱';

  @override
  String get verifyEmailTitle => '验证你的邮箱';

  @override
  String verifyEmailBody(String email) {
    return '验证邮件已发送到 $email，点击邮件里的链接后回到这里';
  }

  @override
  String get verifyResend => '重新发送验证邮件';

  @override
  String get verifyResent => '已重新发送';

  @override
  String get verifyDone => '我已经验证';

  @override
  String get verifyStill => '还没验证成功，请点击邮件里的链接';

  @override
  String get welcomeTitle => '加入你的教会';

  @override
  String get welcomeBody => '请向教会的管理员要邀请链接';

  @override
  String get enterInviteCode => '输入邀请码';

  @override
  String get createChurch => '创建新教会';

  @override
  String get signOut => '退出登录';

  @override
  String get inviteCode => '邀请码';

  @override
  String get next => '下一步';

  @override
  String get churchName => '教会名称';

  @override
  String get createChurchVerifyFirst => '验证邮箱后才能创建教会';

  @override
  String get create => '创建';

  @override
  String get errDuplicateName => '已经有教会叫这个名字。如果是别人抢先注册的，请反馈问题。';

  @override
  String get contactUs => '反馈问题';

  @override
  String joinTitle(String church) {
    return '加入“$church”';
  }

  @override
  String get join => '加入';

  @override
  String joined(String church) {
    return '已加入“$church”';
  }

  @override
  String alreadyMember(String church) {
    return '你已经是“$church”的同工';
  }

  @override
  String get errInviteInvalid => '找不到这个邀请，请确认邀请码，或向管理员要新的邀请';

  @override
  String get errInviteExpired => '这个邀请已过期，请向管理员要新的邀请';

  @override
  String get errChurchClosed => '这间教会已停用';

  @override
  String churchSuspendedTitle(String church) {
    return '“$church”已停用';
  }

  @override
  String get churchSuspendedBody => '有问题请联系教会的管理员';

  @override
  String churchDeletedTitle(String church) {
    return '“$church”已删除';
  }

  @override
  String churchDeletedBody(String date) {
    return '管理员可以在 $date 前恢复';
  }

  @override
  String get churchDeletedExpired => '已经超过 30 天，不能再恢复了';

  @override
  String get churchUnavailable => '无法打开这间教会';

  @override
  String get restoreChurch => '恢复教会';

  @override
  String get churchRestored => '教会已恢复';

  @override
  String get switchChurch => '切换教会';

  @override
  String get myServicesTitle => '我接下来的事奉';

  @override
  String get noUpcomingServices => '接下来没有你的事奉，排到你时会出现在这里';

  @override
  String get viewRosters => '看事奉表';

  @override
  String get gettingStarted => '开始使用';

  @override
  String get inviteMembers => '邀请同工';

  @override
  String get gettingStartedInviteBody => '创建邀请链接，发给同工';

  @override
  String get gettingStartedServices => '事奉设置';

  @override
  String get gettingStartedServicesBody => '星期几、要安排哪些事奉';

  @override
  String get nobodyYet => '待定';

  @override
  String get noServicesConfigured => '还没有设置聚会';

  @override
  String get setUpServices => '设置聚会';

  @override
  String get noRostersAhead => '接下来没有聚会';

  @override
  String get rostersNobodyArranged => '还没有安排任何人';

  @override
  String get rostersStartArranging => '开始安排';

  @override
  String get today => '今天';

  @override
  String get tomorrow => '明天';

  @override
  String get offlineShowingCached => '离线中，显示上次的数据';

  @override
  String dutyCount(int count) {
    return '$count 项事奉';
  }

  @override
  String get addDuty => '添加事奉项目';

  @override
  String get dutyName => '事奉项目名称';

  @override
  String get removeDuty => '移除这项';

  @override
  String dutyRemoved(String duty) {
    return '已移除$duty';
  }

  @override
  String dutyUpdated(String duty) {
    return '已更新$duty';
  }

  @override
  String get pickerServes => '有这项事奉';

  @override
  String get pickerOthers => '其他同工';

  @override
  String pickerUseName(String name) {
    return '用“$name”';
  }

  @override
  String pickerNoOneServes(String duty) {
    return '还没有人负责$duty';
  }

  @override
  String pickerNoResults(String query) {
    return '找不到“$query”';
  }

  @override
  String get pickerSearchHint => '搜索同工';

  @override
  String pickerAddDutyTitle(String name, String duty) {
    return '也让“$name”负责$duty？';
  }

  @override
  String pickerAddDutyBody(String duty) {
    return '之后安排$duty时，会列在上面';
  }

  @override
  String get pickerAddDutyYes => '加上';

  @override
  String get pickerAddDutyNo => '只排这次';

  @override
  String get reorder => '调整顺序';

  @override
  String get reorderHint => '拖动调整先后，每一周都按这个顺序';

  @override
  String get orderSaved => '已更新顺序';

  @override
  String get swap => '交换';

  @override
  String swapWith(String duty) {
    return '和谁交换$duty？';
  }

  @override
  String get swapNone => '其他日期没有可以交换的人';

  @override
  String swapped(String a, String b) {
    return '已交换“$a”和“$b”';
  }

  @override
  String moved(String name, String day) {
    return '已把“$name”移到 $day';
  }

  @override
  String get emptySlot => '待定';

  @override
  String removeFromDuty(String duty) {
    return '从$duty移除';
  }

  @override
  String get events => '特别活动';

  @override
  String get eventsUpdated => '已更新特别活动';

  @override
  String get customEvent => '自定义特别活动';

  @override
  String get addEvent => '添加特别活动';

  @override
  String get eventName => '特别活动名称';

  @override
  String get addToCommon => '加入常用选项';

  @override
  String get eventColor => '颜色';

  @override
  String get colorName0 => '红';

  @override
  String get colorName1 => '橙';

  @override
  String get colorName2 => '黄';

  @override
  String get colorName3 => '绿';

  @override
  String get colorName4 => '蓝';

  @override
  String get colorName5 => '紫';

  @override
  String removed(String name) {
    return '已移除“$name”';
  }

  @override
  String get profile => '个人资料';

  @override
  String get name => '名字';

  @override
  String get nameSaved => '已更新名字';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get churchInfo => '教会信息';

  @override
  String get manageChurch => '管理教会';

  @override
  String get lineCommunity => 'LINE 社群';

  @override
  String get lineCommunityNote => '提问、反馈问题、和其他教会交流';

  @override
  String get members => '同工';

  @override
  String get serviceSettings => '事奉设置';

  @override
  String get invites => '邀请';

  @override
  String get notifications => '通知';

  @override
  String get account => '账号';

  @override
  String get deleteAccount => '删除账号';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get termsOfService => '服务条款';

  @override
  String get developer => '开发';

  @override
  String get components => '组件';

  @override
  String get testCrash => '测试崩溃';

  @override
  String get operatorConsole => '平台后台';

  @override
  String get leaveChurch => '退出教会';

  @override
  String leaveChurchTitle(String church) {
    return '退出“$church”？';
  }

  @override
  String get leaveChurchBody => '需要重新邀请才能回来';

  @override
  String get leave => '退出教会';

  @override
  String leftChurch(String church) {
    return '已退出“$church”';
  }

  @override
  String get adminCannotLeave => '管理员不能直接退出。要退出，先把另一位同工设为管理员，再请对方取消你的管理员。';

  @override
  String get churchLogo => '教会 logo';

  @override
  String get uploadLogo => '上传 logo';

  @override
  String get changeLogo => '更换 logo';

  @override
  String get logoUploaded => '已更新 logo';

  @override
  String get logoTooLarge => '图片太大了，请选 1 MB 以下的图片';

  @override
  String get logoNotImage => '请选一张图片';

  @override
  String memberCount(int count) {
    return '$count 位同工';
  }

  @override
  String get membersOnlyYou => '还没有其他同工';

  @override
  String get deleteChurch => '删除教会';

  @override
  String deleteChurchTitle(String church) {
    return '删除“$church”？';
  }

  @override
  String get deleteChurchBody => '所有同工都看不到这间教会。30 天内可以恢复，之后数据会永久删除。';

  @override
  String get roleAdmin => '管理员';

  @override
  String get roleLeader => '小组长';

  @override
  String get roleStaff => '一般同工';

  @override
  String get roleMember => '组员';

  @override
  String get role => '身份';

  @override
  String get roleAdminCan => '所有设置、邀请和移除同工';

  @override
  String get groups => '权限组';

  @override
  String get groupRosterEditors => '安排事奉表';

  @override
  String get groupCalendarEditors => '编辑行事历';

  @override
  String get zones => '所属聚会与事奉';

  @override
  String get zonesFooter => '能安排事奉表的同工，只能安排自己所属的聚会';

  @override
  String get removeMember => '移除同工';

  @override
  String memberRemoved(String name) {
    return '已移除“$name”';
  }

  @override
  String get memberSaved => '已保存';

  @override
  String get searchMembers => '搜索同工';

  @override
  String get noMembersFound => '找不到这位同工';

  @override
  String get you => '你';

  @override
  String get inviteCreate => '创建邀请链接';

  @override
  String get inviteValidFor => '有效期限';

  @override
  String inviteDays(int days) {
    return '$days 天内有效';
  }

  @override
  String get inviteCopy => '复制链接';

  @override
  String get inviteCopied => '已复制邀请链接';

  @override
  String get copyByHand => '无法自动复制，请选择下面的文字自己复制';

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
  String get inviteNone => '还没有邀请链接';

  @override
  String inviteMessage(String church, String link) {
    return '邀请你加入“$church”的事奉表：$link';
  }

  @override
  String get servicesTitle => '聚会';

  @override
  String get serviceAdd => '添加聚会';

  @override
  String get serviceName => '聚会名称';

  @override
  String get weekday => '星期';

  @override
  String get serviceEnabled => '启用';

  @override
  String get serviceDisabledFooter => '停用的聚会不会再出现新的事奉表，旧的保留';

  @override
  String get templateDuties => '事奉项目';

  @override
  String get templateFooter => '新的事奉表会带入这些项目。已经安排的事奉表不受影响。';

  @override
  String get commonEvents => '常用特别活动';

  @override
  String get rename => '改名';

  @override
  String get remove => '移除';

  @override
  String get moveUp => '上移';

  @override
  String get moveDown => '下移';

  @override
  String get saved => '已保存';

  @override
  String get weekday1 => '周一';

  @override
  String get weekday2 => '周二';

  @override
  String get weekday3 => '周三';

  @override
  String get weekday4 => '周四';

  @override
  String get weekday5 => '周五';

  @override
  String get weekday6 => '周六';

  @override
  String get weekday7 => '周日';

  @override
  String get deleteAccountTitle => '删除你的账号？';

  @override
  String get deleteAccountBody => '你会退出所有教会，账号与个人资料会被删除且无法恢复。事奉表上的名字会保留。';

  @override
  String deleteAccountLastAdmin(String churches) {
    return '你是“$churches”唯一的管理员，请先把管理员交给别的同工';
  }

  @override
  String get goToMembers => '前往同工';

  @override
  String get accountDeleted => '账号已删除';

  @override
  String get serviceDisabled => '停用';

  @override
  String get adminSearchHint => '教会名称或 ID';

  @override
  String get adminNoChurches => '找不到教会';

  @override
  String get adminStats => '统计';

  @override
  String get adminChurches => '教会';

  @override
  String get adminRename => '改名';

  @override
  String get adminMakeAdmin => '设为管理员';

  @override
  String adminMadeAdmin(String name) {
    return '已把“$name”设为管理员';
  }

  @override
  String get adminSuspend => '停用教会';

  @override
  String get adminReopen => '重新启用教会';

  @override
  String adminSuspendTitle(String church) {
    return '停用“$church”？';
  }

  @override
  String get adminSuspendBody => '所有同工会立刻看到停用画面';

  @override
  String get statusActive => '使用中';

  @override
  String get statusSuspended => '已停用';

  @override
  String get statusDeleted => '已删除';

  @override
  String get statsUsers => '用户';

  @override
  String get statsChurches => '教会';

  @override
  String get statsMembers => '成员';

  @override
  String get statsRosters => '事奉表';

  @override
  String get statsReads => 'Firestore 读取';

  @override
  String get statsWrites => 'Firestore 写入';

  @override
  String get statsCost => '估计费用（USD）';

  @override
  String get statsNone => '还没有统计数据';

  @override
  String get statsMoreInConsole => '使用行为与错误详情在 Firebase console';

  @override
  String get notifReminder => '事奉提醒';

  @override
  String get notifReminderWeeklySub => '每周一晚上，列出这周的事奉';

  @override
  String get notifReminderDayBeforeSub => '事奉前一天晚上提醒你';

  @override
  String get notifReminderBothSub => '每周一晚上，和事奉前一天晚上';

  @override
  String get notifReminderTime => '事奉提醒时间';

  @override
  String get notifReminderWeekly => '每周一晚上';

  @override
  String get notifReminderDayBefore => '前一天晚上';

  @override
  String get notifReminderBoth => '两个都要';

  @override
  String get notifReminderTimeFooter => '都在晚上 7 点';

  @override
  String get notifRosterChange => '事奉表变动';

  @override
  String get notifRosterChangeSub => '你被排入或移出事奉时。晚上 10 点后的变动，早上 7 点才通知';

  @override
  String get notifMemberLeft => '同工退出';

  @override
  String get notifMemberLeftSub => '有人退出教会时（只通知管理员）';

  @override
  String get notifThisChurch => '这间教会的通知';

  @override
  String get notifPermissionOff => '通知已关闭，请到系统设置开启';

  @override
  String get notifEnable => '开启通知';

  @override
  String get notifAskTitle => '被排到事奉时通知你';

  @override
  String get notifAskBody => '排入事奉、事奉表有变动时通知你，每周一晚上也会提醒这周的事奉';

  @override
  String get notifAskLater => '稍后再说';

  @override
  String get notifCardHide => '不再显示';

  @override
  String get notifOpenSettings => '到设置开启通知';

  @override
  String get notifNotAllowed => '通知还没开启。弹出询问时，请点“允许”。';

  @override
  String get notifRegisterFailed => '通知还没设置好，下次打开 App 时会再试';

  @override
  String get pushView => '查看';

  @override
  String get zoneSwitch => '属于这个聚会';

  @override
  String zoneLeft(String service) {
    return '不再属于$service';
  }

  @override
  String get eventRosterGone => '找不到这个活动的事奉表';

  @override
  String get eventRoster => '事奉表';

  @override
  String eventRosterPeople(int count) {
    return '$count 人';
  }

  @override
  String get arrangeEventRoster => '安排事奉';

  @override
  String get eventRosterEmpty => '还没有事奉项目';

  @override
  String get copyDuties => '沿用其他活动';

  @override
  String get copyDutiesHeader => '沿用哪一场的事奉项目';

  @override
  String get copyDutiesNone => '还没有其他活动的事奉表';

  @override
  String dutiesCopied(int count) {
    return '已加入 $count 个事奉项目';
  }

  @override
  String get noZoneYet => '你还没有所属聚会，请找管理员设置';

  @override
  String get waitsForZone => '还没设置所属聚会';

  @override
  String waitingForZone(int count) {
    return '$count 位同工还没设置所属聚会';
  }

  @override
  String get inviteZones => '加入后所属聚会';

  @override
  String get photoImport => '照片导入';

  @override
  String photoRemaining(int count) {
    return '这个月还可以识别 $count 张';
  }

  @override
  String get photoTake => '拍照';

  @override
  String get photoPick => '选择照片';

  @override
  String get photoPasteJson => '粘贴 JSON';

  @override
  String get photoRecognizing => '识别中，大约需要一分钟';

  @override
  String photoChurchLimit(int limit) {
    return '这个月的 $limit 张已经用完，下个月 1 日恢复。这段时间可以直接安排事奉表。';
  }

  @override
  String get photoPlatformOff => '照片识别这个月暂停（全站的识别额度用完了），下个月恢复。这段时间可以直接安排事奉表。';

  @override
  String get photoTooLarge => '照片太大，请裁剪到只剩表格再试';

  @override
  String get photoFailed => '识别失败，请换一张清楚一点的照片再试';

  @override
  String get photoUnavailable => '照片识别暂时无法使用，请稍后再试，或直接安排事奉表';

  @override
  String get importPreview => '预览';

  @override
  String get importApply => '应用到事奉表';

  @override
  String importApplied(int count) {
    return '已导入 $count 天';
  }

  @override
  String get importNothing => '照片里没有读到之后的日期';

  @override
  String get importNotInList => '名单里没有这些人（按原文写入，没有关联账号）';

  @override
  String importNear(String names) {
    return '名单里有很像的：$names';
  }

  @override
  String get importAmbiguous => '不确定是哪一位（没有关联账号）';

  @override
  String get importUnknownDuties => '这个聚会没有这些事奉项目';

  @override
  String get importPastDays => '已经过去的日期，没有导入';

  @override
  String get importBadRows => '读不懂的数据';

  @override
  String get jsonHint => '粘贴识别结果的 JSON';

  @override
  String get next2 => '预览';

  @override
  String get calNotConnected => '教会还没有连接行事历';

  @override
  String get calConnect => '连接 Google 日历';

  @override
  String get calReconnect => '重新连接';

  @override
  String get calNeedsReconnect => '行事历的授权已失效';

  @override
  String get calNeedsReconnectStaff => '行事历暂时读取不到，请管理员重新连接';

  @override
  String get calPickCalendar => '选择要用的日历';

  @override
  String get calNoCalendarYet => '还没选择日历';

  @override
  String get calDisconnect => '断开连接';

  @override
  String get calDisconnectTitle => '断开行事历连接？';

  @override
  String get calDisconnectBody => '同工会看不到行事历，Google 日历本身不受影响';

  @override
  String get calUnverifiedNote => '接下来 Google 会显示“Google 尚未验证此应用”，点“高级”→“转至…”继续。只会读写你选的那个日历。';

  @override
  String get calConnectedOk => '已连接 Google 日历';

  @override
  String get calConnectFailed => '没有连接成功，请再试一次';

  @override
  String get calNoEvents => '这个月没有活动';

  @override
  String get calAllDay => '全天';

  @override
  String get calNewEvent => '添加活动';

  @override
  String get calEditEvent => '编辑活动';

  @override
  String get calTitle => '活动名称';

  @override
  String get calLocation => '地点';

  @override
  String get calStart => '开始';

  @override
  String get calEnd => '结束';

  @override
  String get calOtherTime => '其他时间…';

  @override
  String calLengthMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String calLengthHours(int hours) {
    return '$hours 小时';
  }

  @override
  String calLengthHoursMinutes(int hours, int minutes) {
    return '$hours 小时 $minutes 分钟';
  }

  @override
  String get calDelete => '删除活动';

  @override
  String calDeleted(String title) {
    return '已删除“$title”';
  }

  @override
  String get calSaved => '已保存活动';

  @override
  String get calPrevMonth => '上个月';

  @override
  String get calNextMonth => '下个月';

  @override
  String get calShowMonth => '显示月历';

  @override
  String get calHideMonth => '只看列表';

  @override
  String get calendarSetting => '行事历';

  @override
  String get support => '支持马大别忙';

  @override
  String get supportVerse => '乃要均平，就是要你们的富余，现在可以补他们的不足，使他们的富余，将来也可以补你们的不足，这就均平了。如经上所记：多收的也没有余；少收的也没有缺。';

  @override
  String get supportVerseSource => '哥林多后书 8:14–15（和合本）';

  @override
  String get supportBody => '支持完全自愿，只用来分担云端费用，不是给教会的奉献；每间教会能用的功能都一样';

  @override
  String get supportTips => '一次性支持';

  @override
  String get supportMonthly => '每月支持';

  @override
  String get supportRestore => '恢复购买';

  @override
  String supportMonthlyTerms(String store) {
    return '每月自动续订，可以随时在 $store 的订阅设置中取消';
  }

  @override
  String get manageSubscription => '管理订阅';

  @override
  String get supportThanks => '谢谢你的支持';

  @override
  String get supportPending => '付款处理中';

  @override
  String get supportFailed => '没有完成付款，没有扣款';

  @override
  String get supportUnavailable => '现在无法连接商店，请稍后再试';

  @override
  String get supportComingSoon => 'App 内支持即将开放';

  @override
  String get supporterBadge => '支持者';

  @override
  String get appIcon => 'App 图标';

  @override
  String get appIconSupporterOnly => '每月支持者可以更换 App 图标';

  @override
  String get appIconDefault => '默认';

  @override
  String get appIconGreen => '绿';

  @override
  String get appIconPurple => '紫';

  @override
  String get appIconNight => '夜';

  @override
  String get goHome => '回首页';

  @override
  String get churchNotFound => '找不到这间教会';

  @override
  String get churchEntryNotMember => '你还不是这间教会的同工。请向管理员要邀请链接来加入。';

  @override
  String get churchUrl => '教会网址';

  @override
  String get churchUrlCopied => '已复制教会网址';

  @override
  String get churchUrlCopy => '复制教会网址';

  @override
  String get churchUrlShare => '分享教会网址';

  @override
  String get homeName => '主屏幕名称';

  @override
  String get homeNameUnset => '同教会名称';

  @override
  String get homeNameMayBeCut => '部分手机会被截断';

  @override
  String get homeNameFooter => '添加到主屏幕时，图标下方显示的名字。留空就用教会名称。';

  @override
  String get addToHome => '添加到主屏幕';

  @override
  String get addToHomeIosNote => 'iPhone 上已经添加的图标不会跟着更新。更换名称或 logo 之后，请删除图标再添加一次。';

  @override
  String get addToHomeLater => '稍后再说';

  @override
  String addToHomeDone(String name) {
    return '已添加，之后点手机上的“$name”图标打开';
  }

  @override
  String get addToHomeIntro => '下次点主屏幕的图标，就能打开事奉表';

  @override
  String addToHomeBrowserGuide(String device, String browser) {
    return '$device · $browser 教程';
  }

  @override
  String get addToHomeChooseBrowser => '画面不一样？';

  @override
  String get addToHomeChooseGuide => '选择要看的教程';

  @override
  String get addToHomeChooseGuideNote => '只切换教程，不会替你打开另一个浏览器';

  @override
  String get addToHomeSafariLayoutTitle => 'Safari 画面';

  @override
  String get addToHomeSafariLayoutHint => '请按工具栏上的按钮选择，不需要更改 Safari 设置';

  @override
  String get addToHomeSafariMoreChoice => '我看到“⋯”';

  @override
  String get addToHomeSafariShareChoice => '我看到共享图标';

  @override
  String get addToHomeSafariMoreShare => '点“⋯”，再选“共享”';

  @override
  String get addToHomeSafariDirectShareHint => '地址栏在上方或下方都可以，请找“方框向上箭头”';

  @override
  String get addToHomeInApp => 'App 内置浏览器';

  @override
  String get addToHomeOtherBrowser => '其他浏览器';

  @override
  String get addToHomeScreenshotNote => '请点浏览器上圈出的按钮';

  @override
  String get addToHomeSafariScreenshot => 'Safari · iOS 26.5 · 繁体中文模拟器画面';

  @override
  String get addToHomeChromeAndroidScreenshot => 'Chrome 113 · Android 14 · 繁体中文模拟器画面（旧版菜单）';

  @override
  String get addToHomeChromeIosScreenshot => 'Chrome 155 · iOS 27.2 · iPhone 13 真机画面';

  @override
  String get addToHomeAddressBar => '地址栏';

  @override
  String get addToHomeChromeShare => '点地址栏旁的分享图标';

  @override
  String get addToHomeChromeShareHint => '不是“⋯”菜单，也不是“分享 Chrome”';

  @override
  String get addToHomeChromeScroll => '看不到时，先把分享面板展开，再往下滑';

  @override
  String get addToHomeSafariShare => '点 Safari 的共享图标';

  @override
  String get addToHomeFirefoxShare => '点地址栏的分享图标';

  @override
  String get addToHomeIpadMore => 'iPad 如果没看到这个选项，先点共享面板中的“更多”';

  @override
  String get addToHomeSelectAdd => '点“添加到主屏幕”';

  @override
  String get addToHomeShareMore => '如果只看到一排图标，先点“查看更多”；旧版可以往下滑';

  @override
  String get addToHomeIosConfirm => '如果有“作为网页 App 打开”开关，请保持开启；最后点右上角的“添加”';

  @override
  String get addToHomeOpenTitle => '回到主屏幕，点新图标打开';

  @override
  String addToHomeMenu(String browser) {
    return '点 $browser 的菜单';
  }

  @override
  String get addToHomeChromeInstall => '添加到主屏幕 → 安装';

  @override
  String get addToHomeChromeInstallHint => '旧版可能叫“安装应用”。请选“安装”，不是“创建快捷方式”。';

  @override
  String get addToHomeFirefoxInstallHint => '再按手机提示添加；如果只有“添加到主屏幕”，可能只会创建浏览器快捷方式';

  @override
  String get addToHomeTrouble => '找不到“添加到主屏幕”？';

  @override
  String get addToHomeSafariTrouble => '先把共享面板往上拉，查看下方的操作；还是找不到时，点最下方的“编辑操作”查看';

  @override
  String addToHomeExternalTitle(String browser) {
    return '先用 $browser 打开';
  }

  @override
  String addToHomeExternalHint(String browser) {
    return '复制教会网址，再粘贴到 $browser 的地址栏，打开后继续教程';
  }

  @override
  String get addToHomeEmbeddedHint => '你正在 App 里看网页，请先换到手机的浏览器';

  @override
  String get addToHomeUnknownHint => '这个浏览器的菜单可能不同，改用下面的方式继续';

  @override
  String addToHomeCopiedForBrowser(String browser) {
    return '已复制，请打开 $browser，粘贴到地址栏';
  }

  @override
  String get addToHomePhoneOnly => '请用手机打开教会网址，再添加到主屏幕';

  @override
  String get addToHomeNotificationsAfter => '从主屏幕打开后，在“我的”开启通知，就能收到事奉通知';

  @override
  String get addToHomeIosShare => '共享';

  @override
  String get addToHomeIosAdd => '添加';

  @override
  String addToHomeIosOpen(String name) {
    return '点手机上的“$name”图标打开，再登录一次';
  }

  @override
  String get addToHomeAndroidAdd => '添加到主屏幕';

  @override
  String get addToHomeAndroidInstall => '安装';

  @override
  String addToHomeAndroidOpen(String name) {
    return '点手机上的“$name”图标打开';
  }

  @override
  String get addToHomeCardBody => '一点就打开，也收得到事奉通知';

  @override
  String get addToHomeCardHide => '不再显示';

  @override
  String get notifNeedsHomeScreen => '先添加到主屏幕，才收得到通知';

  @override
  String get churchLink => '教会链接';

  @override
  String get churchLinkNone => '未设置';

  @override
  String get churchLinkTitle => '标题';

  @override
  String get churchLinkBody => '描述（选填）';

  @override
  String get churchLinkUrl => '链接';

  @override
  String get churchLinkNeedsTitle => '请输入标题';

  @override
  String get churchLinkNeedsHttps => '请输入 https:// 开头的链接';

  @override
  String get churchLinkFooter => '显示在每位同工首页的最上方，点击后用浏览器打开';

  @override
  String get churchLinkRemove => '移除教会链接';

  @override
  String get churchLinkRemoved => '已移除教会链接';

  @override
  String get churchLinkOpens => '用浏览器打开';

  @override
  String get linkSource => '每日内容来源（选填）';

  @override
  String get linkSourceUrl => 'JSON 网址';

  @override
  String get linkFetchTime => '每天更新时间';

  @override
  String get linkSourceFooter => '每天这个时间获取一次。JSON 要有 date（教会的今天）、title、body、link（https）。';

  @override
  String linkSourceUpdated(String time) {
    return '上次更新：$time';
  }

  @override
  String linkSourceFailed(String reason) {
    return '上次没有获取到：$reason';
  }

  @override
  String linkSourceFetched(String title) {
    return '已保存，获取到“$title”';
  }

  @override
  String get linkErrTimeout => '对方网站 5 秒内没有响应';

  @override
  String get linkErrTooLarge => '内容超过 64 KB';

  @override
  String get linkErrBadFormat => '内容不是完整的 date、title、body、link JSON';

  @override
  String get linkErrNotHttps => '网址或重定向不是 https';

  @override
  String linkErrHttp(String status) {
    return '对方网站响应错误（$status）';
  }

  @override
  String get linkErrNetwork => '连不上对方网站';

  @override
  String get linkErrUnknown => '原因不明，请再试一次';

  @override
  String get webhook => '外部通知';

  @override
  String get webhookUrl => '接收网址';

  @override
  String get webhookNeedsHttps => '请输入 https:// 开头的网址';

  @override
  String get webhookSecretOptional => '密钥（选填，留空会自动生成）';

  @override
  String get webhookSecretTooShort => '密钥至少要 16 个字符';

  @override
  String get webhookCalendar => '行事历变动';

  @override
  String get webhookCalendarHint => '添加、修改、删除活动';

  @override
  String get webhookRoster => '事奉表变动';

  @override
  String get webhookRosterHint => '几分钟内的变动合并成一条';

  @override
  String get webhookFooter => '行事历或事奉表有变动时，发送通知到这个网址，例如交给 n8n 转发到 LINE 群组。通知都用密钥签名。';

  @override
  String get webhookTest => '发送测试';

  @override
  String webhookLast(String time, String result) {
    return '上次发送：$time · $result';
  }

  @override
  String get webhookOk => '成功';

  @override
  String webhookHttp(String status) {
    return '对方响应 $status';
  }

  @override
  String get webhookTimeout => '超时';

  @override
  String get webhookNetwork => '连不上';

  @override
  String get webhookRotate => '更换新的密钥';

  @override
  String get webhookRotateMessage => '旧的密钥会立刻失效，接收端要改用新的';

  @override
  String get webhookGenerate => '自动生成';

  @override
  String get webhookTypeOwn => '自己输入';

  @override
  String get webhookSecretTitle => '密钥';

  @override
  String get webhookSecretOnce => '只会显示这一次。请粘贴到接收端，用来验证通知是马大别忙发送的。';

  @override
  String get webhookCopySecret => '复制密钥';

  @override
  String get webhookSecretCopied => '已复制密钥';

  @override
  String get webhookSecretChanged => '已更换为新的密钥';

  @override
  String get webhookOff => '关闭外部通知';

  @override
  String get webhookOffTitle => '关闭外部通知？';

  @override
  String get webhookOffMessage => '网址和密钥都会删除，之后要重新设置';

  @override
  String get webhookOffAction => '关闭';

  @override
  String get exportData => '导出数据';

  @override
  String get exportFooter => '导出教会的全部数据：一个 JSON 文件，加上一个可以用 Excel 打开的事奉表';

  @override
  String get exported => '已导出';

  @override
  String get exportCsvFile => '事奉表.csv';

  @override
  String get exportCsvDate => '日期';

  @override
  String get exportCsvService => '聚会/活动';

  @override
  String get exportCsvRole => '事奉项目';

  @override
  String get exportCsvPeople => '同工';

  @override
  String get errMoveInvalid => '这不是迁移文件，请确认选对了文件';

  @override
  String get errMoveTooLarge => '同工超过 2,000 位或事奉表超过 20,000 天，无法自动迁移。请到 GitHub 的 church-staff-pwa 提交 issue。';

  @override
  String get moveFromSelfHost => '从旧版迁移过来';

  @override
  String get moveIntro => '在旧版（church-staff-pwa）的 Cloud Shell 执行迁移指令，把得到的迁移文件上传。确认预览后才会创建教会。';

  @override
  String get movePickFile => '选择迁移文件';

  @override
  String get moveReading => '读取迁移文件…';

  @override
  String get moveContents => '迁移文件内容';

  @override
  String get moveMembers => '同工';

  @override
  String moveMembersCount(int count) {
    return '$count 位';
  }

  @override
  String get moveRosters => '事奉表';

  @override
  String moveRostersCount(int count) {
    return '$count 天';
  }

  @override
  String get moveServices => '聚会';

  @override
  String get moveWhoAmI => '这位是我（选填）';

  @override
  String get moveWhoAmIFooter => '选了就接手那位的事奉表、所属聚会和权限。其他同工用同一个邮箱登录马大别忙时，会被询问要不要加入。';

  @override
  String get moveCreate => '创建教会并迁移过来';

  @override
  String moveDone(String church) {
    return '已创建“$church”';
  }

  @override
  String get notSignedInYet => '还没登录';

  @override
  String pendingCount(int count) {
    return '$count 位还没登录';
  }

  @override
  String claimPrompt(String church) {
    return '“$church”的同工信息\n已经迁移过来了，要加入吗？';
  }

  @override
  String get claimJoin => '加入';

  @override
  String get claimDecline => '不加入';

  @override
  String get movedPasswordNote => '从旧版迁移过来的同工：旧的密码不能用，\n请用同一个邮箱注册新账号，或用 Google 登录';

  @override
  String get pendingDelete => '删除这条记录';

  @override
  String pendingDeleteTitle(String name) {
    return '删除“$name”的记录？';
  }

  @override
  String get pendingDeleteBody => '对方就不能用邮箱认领了。事奉表上的名字会保留。';

  @override
  String get pendingDeleted => '已删除';

  @override
  String get mergePending => '合并未登录的记录';

  @override
  String get mergePendingFooter => '同工换了邮箱加入时，合并旧名单上的那条记录，事奉表、所属聚会和权限组都会接上';

  @override
  String get mergePendingPick => '选一条未登录的记录';

  @override
  String mergePendingTitle(String pending, String member) {
    return '把“$pending”合并到“$member”？';
  }

  @override
  String mergePendingBody(String pending) {
    return '事奉表上的“$pending”会改成这位同工，所属聚会和权限组也会加上去';
  }

  @override
  String get mergePendingAction => '合并';

  @override
  String get merged => '已合并';

  @override
  String get fundingTitle => '这个月的云端费用';

  @override
  String fundingProgress(String available, String target) {
    return '$available / $target';
  }

  @override
  String get fundingEnough => '这个月已经足够';

  @override
  String fundingMonthsLeft(int months) {
    return '这个月已经足够，多的还能再维持 $months 个月';
  }

  @override
  String fundingCarried(String amount) {
    return '含前几个月留下的 $amount';
  }

  @override
  String get fundingCosts => '云端费用';

  @override
  String fundingTarget(String amount) {
    return '每月目标 $amount';
  }

  @override
  String get fundingTargetUpdating => '每月目标更新中…';

  @override
  String get fundingCostsHeader => '费用';

  @override
  String get fundingCostsFooter => '价格变了再改。每年的项目平均分到每个月。名称和每月金额会公开在支持页。';

  @override
  String get fundingMonthsHeader => '最近几个月';

  @override
  String fundingMonthValue(String received, String target) {
    return '$received / $target';
  }

  @override
  String get costAdd => '添加项目';

  @override
  String get costEdit => '费用项目';

  @override
  String get costName => '名称';

  @override
  String get costAmount => '金额';

  @override
  String get costPerMonth => '每月';

  @override
  String get costPerYear => '每年';

  @override
  String costValueMonth(String amount) {
    return '$amount · 每月';
  }

  @override
  String costValueYear(String amount) {
    return '$amount · 每年';
  }

  @override
  String moneyTwd(String amount) {
    return 'NT\$$amount';
  }

  @override
  String moneyUsd(String amount) {
    return 'US\$$amount';
  }

  @override
  String get currencyTwd => 'NT\$';

  @override
  String get currencyUsd => 'US\$';

  @override
  String get fundingWhereItGoes => '每个月用在哪里';

  @override
  String get fundingYearlySplit => '每年付一次的费用平均分到每个月';

  @override
  String get fundingRatesBy => '汇率：Exchange Rate API';

  @override
  String get importAdvanced => '高级';

  @override
  String get importCopyPrompt => '复制 AI 指令';

  @override
  String get importPromptCopied => '已复制，连同照片发给 AI，再把它回复的 JSON 粘贴进来';

  @override
  String get importFormatHelp => 'date：YYYY-MM-DD；没有人时 people 填 []。\nevents 可省略；特别活动的 color 填色号 0–5。';

  @override
  String get importPhotoFormatError => '识别结果的格式不对，请重新识别或用高级 JSON';

  @override
  String get importJsonSyntaxError => 'JSON 格式不对，请用下方示例的数组格式';

  @override
  String get importJsonEdit => '编辑 JSON';

  @override
  String get importJsonArrayRequired => '请填 JSON 数组';

  @override
  String importConfirmName(String name) {
    return '确认“$name”';
  }

  @override
  String get importSameNameScope => '这次导入的同名人名都用这个对应';

  @override
  String importGuestChoice(String name) {
    return '保留“$name”为外来人员';
  }

  @override
  String get importEditDate => '编辑日期';

  @override
  String get importDateFormatLabel => '日期（YYYY-MM-DD）';

  @override
  String get importValidDate => '请填有效的 YYYY-MM-DD 日期';

  @override
  String get importEditDuty => '编辑事奉项目';

  @override
  String get importDutyLabel => '事奉项目';

  @override
  String get importPeopleLines => '名字（每行一人）';

  @override
  String get importAddEventAction => '添加特别活动';

  @override
  String get importEditEvent => '编辑特别活动';

  @override
  String get importConflict => '事奉表已更改，请重新检查差异后再应用';

  @override
  String get importScopeChanged => '教会或账号已切换，请重新导入';

  @override
  String importRow(int number) {
    return '第 $number 行';
  }

  @override
  String get importDateLabel => '日期';

  @override
  String get importDateMissing => '请填日期';

  @override
  String get importFixDuty => '修正事奉项目';

  @override
  String get importPeopleArrayHint => 'people 请填人名数组';

  @override
  String get importFixEvent => '修正特别活动';

  @override
  String importRemoveDuty(String role, String names) {
    return '移除$role：$names';
  }

  @override
  String importAddDuty(String role, String names) {
    return '添加$role：$names';
  }

  @override
  String importChangeDuty(String role, String before, String after) {
    return '$role：$before → $after';
  }

  @override
  String importMemberIdentity(String name) {
    return '$name（同工）';
  }

  @override
  String importGuestIdentity(String name) {
    return '$name（外来人员）';
  }

  @override
  String importRemoveEvent(String name) {
    return '移除特别活动：$name';
  }

  @override
  String importAddEvent(String name) {
    return '添加特别活动：$name';
  }

  @override
  String importChangeEvent(String name) {
    return '特别活动：$name';
  }

  @override
  String importChangedColor(String before, String after) {
    return '$before → $after';
  }

  @override
  String get importNoChange => '安排没有更改';

  @override
  String get importNoCandidate => '请保留为外来人员或修正人名';

  @override
  String importCandidates(String names) {
    return '候选：$names';
  }

  @override
  String get importGuestUnlinked => '外来人员（没有关联账号）';

  @override
  String get importNameNeedsConfirm => '请确认人名';

  @override
  String importLinkedMember(String name) {
    return '同工：$name';
  }

  @override
  String get importMode => '导入方式';

  @override
  String get importMerge => '合并（保留没有提到的安排）';

  @override
  String get importReplace => '取代当天全部安排';

  @override
  String get importReplaceHelp => '移除没有提到的事奉项目与特别活动；不影响其他日期';

  @override
  String get importFixData => '请修正数据后再导入';

  @override
  String get importFixRow => '请修正这一行数据';

  @override
  String get importNameLinks => '人名对应';

  @override
  String get importNamesNeedConfirm => '确认人名后才能导入';

  @override
  String get importRepairSettings => '修正教会设置（选填）';

  @override
  String get importNoSettingsChange => '这次安排不会更改同工或教会设置';

  @override
  String importAddConfiguredDuty(String role) {
    return '加入事奉设置：$role';
  }

  @override
  String importUnconfiguredDuty(String role) {
    return '未设置的事奉项目：$role';
  }

  @override
  String importGrantQualification(String name, String role) {
    return '让$name负责$role';
  }

  @override
  String importMissingQualification(String name, String role) {
    return '$name还没设置$role';
  }

  @override
  String importAddCommonEvent(String name) {
    return '加入常用特别活动：$name';
  }

  @override
  String importNotCommonEvent(String name) {
    return '未设为常用特别活动：$name';
  }

  @override
  String importDiff(String date) {
    return '应用后差异 · $date';
  }

  @override
  String importRequiredField(String field) {
    return '请填$field';
  }

  @override
  String get importColor => '颜色';

  @override
  String get importIssueRowObject => '请填包含 date、duties 的对象';

  @override
  String get importIssueRowFields => '只支持 date、duties、events 字段';

  @override
  String get importIssueDate => 'date 请填有效的 YYYY-MM-DD 日期';

  @override
  String get importIssueDuplicateDate => '日期重复，请合并成同一行';

  @override
  String get importIssueDutiesArray => 'duties 请填数组';

  @override
  String importIssueDutyFields(int index) {
    return '第 $index 个事奉项目只支持 role、people';
  }

  @override
  String importIssueRole(int index) {
    return '第 $index 个 role 请填不重复的事奉项目名称';
  }

  @override
  String importIssuePeopleArray(int index) {
    return '第 $index 个 people 请填非空白人名的字符串数组；没有人时填 []';
  }

  @override
  String importIssueDuplicatePeople(int index) {
    return '第 $index 个 people 不可有重复人名';
  }

  @override
  String get importIssueEventsArray => 'events 请填数组';

  @override
  String importIssueEventObject(int index, String example) {
    return '第 $index 个特别活动请填 $example';
  }

  @override
  String importIssueEventName(int index) {
    return '第 $index 个特别活动的 name 请填不重复的名称';
  }

  @override
  String importIssueEventColor(int index) {
    return '第 $index 个特别活动的 color 请填 0 到 5 的整数';
  }

  @override
  String importIssueResolvedDuplicatePeople(String role) {
    return '$role：确认后人名重复，请移除重复的人名';
  }

  @override
  String get appRunningVersion => '当前版本';

  @override
  String appVersionWithFix(String version, int patch) {
    return '$version · 修正 $patch';
  }

  @override
  String get appVersionDevelopment => '开发版本（还没有发布版本）';

  @override
  String get updateRequiredTitle => '请更新马大别忙';

  @override
  String get updateRequiredBody => '这个版本太旧了，更新后才能继续使用';

  @override
  String updateRequiredOpen(String store) {
    return '到 $store 更新';
  }

  @override
  String get appUpdateCheck => '检查更新';

  @override
  String get appUpdateChecking => '检查中…';

  @override
  String get appUpdateApply => '更新并重新打开';

  @override
  String get appUpdateApplying => '更新中…';

  @override
  String get saving => '保存中…';

  @override
  String get appUpdateCurrent => '已是最新版本';

  @override
  String get appUpdateReady => '有新版本';

  @override
  String get appUpdateFinishEditing => '还有没保存的内容，保存后再更新';

  @override
  String get appUpdateFinishEditingNote => '先保存正在编辑的内容';

  @override
  String get appUpdateFailed => '没有更新成功，请检查网络后再试一次';

  @override
  String get appUpdateScopeChanged => '账号或教会换了，请重新检查更新';

  @override
  String get appUpdateBackToMe => '请再点一次“更新并重新打开”';

  @override
  String get appUpdateCheckFirst => '请先检查更新';

  @override
  String get servicesAdminOnly => '只有管理员能改事奉设置';

  @override
  String get importExampleRole => '司琴';

  @override
  String get importExamplePerson => '李美玉';

  @override
  String get importExampleEvent => '圣餐';

  @override
  String get rosterShowMore => '显示更多';

  @override
  String get pickerGuestNames => '外来人员名字';

  @override
  String get serviceSettingsSaved => '事奉设置已保存';

  @override
  String get serviceSyncOriginalEvent => '原本的特别活动';

  @override
  String get serviceSyncOriginalDuty => '原本的事奉项目';

  @override
  String serviceFutureSyncTitle(String from, String to) {
    return '同步“$from”为“$to”';
  }

  @override
  String serviceFutureSyncSaved(int count) {
    return '已同步 $count 份未来事奉表';
  }

  @override
  String serviceEventColorTitle(String name) {
    return '$name · 颜色';
  }

  @override
  String get serviceEventColor => '颜色';

  @override
  String get serviceSyncFutureRosters => '同步未来事奉表';

  @override
  String get rosterFutureChangesNone => '没有需要更改的未来事奉表';

  @override
  String get rosterFutureChangesFooter => '只更改明天起已保存的事奉表';

  @override
  String get rosterFutureChangesConflict => '已有同名项目，请先调整';

  @override
  String get rosterApplyFutureChanges => '应用更改';

  @override
  String get rosterRemoveFutureGuest => '移除未来的外来人员安排';

  @override
  String rosterRemoveFutureGuestTitle(String name) {
    return '移除“$name”的未来安排';
  }

  @override
  String rosterFutureGuestRemoved(int count) {
    return '已移除 $count 份未来安排';
  }

  @override
  String rosterFutureDutyChange(String role, String before, String after) {
    return '$role：$before → $after';
  }

  @override
  String rosterFutureEventChange(String before, String after) {
    return '$before → $after';
  }

  @override
  String get errConflict => '其他同工刚改过，刷新后再改一次';

  @override
  String get errOfflineReadOnly => '离线中，联网后才能保存';

  @override
  String get errTooManyChanges => '一次最多改 500 份事奉表，请分几次改';

  @override
  String get undoDone => '已撤销';

  @override
  String get undoFailed => '撤销失败，请再试一次';

  @override
  String get offlineReadOnlyBanner => '离线中，显示上次的数据，联网后才能保存';

  @override
  String get calendarCached => '显示上次的数据';

  @override
  String calendarReadAt(String time) {
    return '$time 更新';
  }

  @override
  String get calDescription => '活动说明';

  @override
  String get calDuplicate => '复制活动';

  @override
  String get homeUpcomingEvents => '近期活动';

  @override
  String get memberSmallGroups => '小组';

  @override
  String get memberSmallGroupsHint => '每行一个小组';

  @override
  String get linkErrNotToday => '来源还没有提供今天的内容';

  @override
  String linkSourceToday(String reason) {
    return '今天的内容没有更新：$reason';
  }

  @override
  String get linkSourceRetry => '重新获取';

  @override
  String get listSeparator => '、';

  @override
  String labelValue(String label, String value) {
    return '$label：$value';
  }

  @override
  String nameIsYou(String name) {
    return '$name（你）';
  }

  @override
  String get churchListSeparator => '”、“';

  @override
  String dayWithEvents(String day, String events) {
    return '$day，$events';
  }

  @override
  String get dotSeparator => ' · ';

  @override
  String get churchStatus => '状态';

  @override
  String get timeZone => '时区';

  @override
  String timeZoneWithOffset(String city, String offset) {
    return '$city（$offset）';
  }

  @override
  String get timeZoneFooter => '今天的日期、事奉提醒和行事历的时间都按教会的时区';

  @override
  String timeZoneChangeTitle(String city) {
    return '改成$city时间？';
  }

  @override
  String get timeZoneChangeBody => '活动时间会按新时区显示，事奉表的日期不变';

  @override
  String timeZoneChange(String city) {
    return '改成$city时间';
  }

  @override
  String churchLocalTime(String city) {
    return '教会当地时间（$city）';
  }

  @override
  String calendarTimeZoneDiffers(String zone, String city) {
    return '这个日历的时区是$zone，跟教会的时区（$city）不同。行事历的时间按教会的时区显示。';
  }

  @override
  String get cityAuckland => '奥克兰';

  @override
  String get citySydney => '悉尼';

  @override
  String get cityMelbourne => '墨尔本';

  @override
  String get cityTokyo => '东京';

  @override
  String get citySeoul => '首尔';

  @override
  String get cityTaipei => '台北';

  @override
  String get cityHongKong => '香港';

  @override
  String get citySingapore => '新加坡';

  @override
  String get cityKualaLumpur => '吉隆坡';

  @override
  String get cityLondon => '伦敦';

  @override
  String get cityToronto => '多伦多';

  @override
  String get cityNewYork => '纽约';

  @override
  String get cityChicago => '芝加哥';

  @override
  String get cityDenver => '丹佛';

  @override
  String get cityVancouver => '温哥华';

  @override
  String get cityLosAngeles => '洛杉矶';

  @override
  String get signInMethods => '登录方式';

  @override
  String get signInMethodPassword => '邮箱与密码';

  @override
  String get signInMethodsFooter => '用哪一种方式登录都是同一个账号，教会、事奉表和权限都一样';

  @override
  String get linkGoogle => '关联 Google 账号';

  @override
  String get linkGoogleFooter => 'Google 账号的邮箱可以和这个账号不同';

  @override
  String get linkedGoogle => '已关联 Google 账号';

  @override
  String get unlink => '解除关联';

  @override
  String unlinkTitle(String method) {
    return '解除关联 $method？';
  }

  @override
  String unlinkBody(String email) {
    return '之后就不能用 $email 登录这个账号';
  }

  @override
  String get errCredentialInUse => '你选的账号已经是另一个马大别忙账号，不能关联。要关联的话，请先用它登录并删除那个账号，再回来关联。';

  @override
  String get onlineRefundHeader => '在线支持退款';

  @override
  String get onlineRefundFooter => '在绿界后台退款后，填这笔的特店订单编号，就会从云端费用进度扣回。';

  @override
  String get onlineRefundAdd => '扣回一笔退款';

  @override
  String get onlineRefundOrderNo => '特店订单编号';

  @override
  String get onlineRefundApply => '从进度扣回';

  @override
  String onlineRefunded(String month, String amount) {
    return '已从 $month 扣回 $amount';
  }

  @override
  String get onlineRefundNotFound => '找不到这笔在线支持，请确认特店订单编号';
}
