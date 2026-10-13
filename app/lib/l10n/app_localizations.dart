import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ];

  /// No description provided for @appName.
  ///
  /// In zh, this message translates to:
  /// **'馬大別忙'**
  String get appName;

  /// No description provided for @tabHome.
  ///
  /// In zh, this message translates to:
  /// **'首頁'**
  String get tabHome;

  /// No description provided for @tabRosters.
  ///
  /// In zh, this message translates to:
  /// **'服事表'**
  String get tabRosters;

  /// No description provided for @tabCalendar.
  ///
  /// In zh, this message translates to:
  /// **'行事曆'**
  String get tabCalendar;

  /// No description provided for @tabMe.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get tabMe;

  /// No description provided for @undo.
  ///
  /// In zh, this message translates to:
  /// **'復原'**
  String get undo;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'儲存'**
  String get save;

  /// No description provided for @done.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get done;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重試'**
  String get retry;

  /// No description provided for @search.
  ///
  /// In zh, this message translates to:
  /// **'搜尋'**
  String get search;

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get clear;

  /// No description provided for @selected.
  ///
  /// In zh, this message translates to:
  /// **'已選取'**
  String get selected;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'關閉'**
  String get close;

  /// No description provided for @add.
  ///
  /// In zh, this message translates to:
  /// **'新增'**
  String get add;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'刪除'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'編輯'**
  String get edit;

  /// No description provided for @deleted.
  ///
  /// In zh, this message translates to:
  /// **'已刪除'**
  String get deleted;

  /// No description provided for @loadFailed.
  ///
  /// In zh, this message translates to:
  /// **'載入失敗，請檢查網路後再試一次'**
  String get loadFailed;

  /// No description provided for @saveFailed.
  ///
  /// In zh, this message translates to:
  /// **'沒有儲存成功，請檢查網路後再試一次'**
  String get saveFailed;

  /// No description provided for @noPermission.
  ///
  /// In zh, this message translates to:
  /// **'你沒有權限做這件事'**
  String get noPermission;

  /// Placeholder for a tab that is not built yet
  ///
  /// In zh, this message translates to:
  /// **'還在做，很快就好'**
  String get comingSoon;

  /// No description provided for @signInWithGoogle.
  ///
  /// In zh, this message translates to:
  /// **'使用 Google 登入'**
  String get signInWithGoogle;

  /// No description provided for @signInWithEmail.
  ///
  /// In zh, this message translates to:
  /// **'用 email 登入'**
  String get signInWithEmail;

  /// No description provided for @inAppBrowserNote.
  ///
  /// In zh, this message translates to:
  /// **'在 {app} 裡不能用 Google 登入。請用 Safari 或 Chrome 打開這個網頁，或用 email 登入。'**
  String inAppBrowserNote(String app);

  /// No description provided for @copyPageUrl.
  ///
  /// In zh, this message translates to:
  /// **'複製連結'**
  String get copyPageUrl;

  /// No description provided for @pageUrlCopied.
  ///
  /// In zh, this message translates to:
  /// **'已複製連結，貼到 Safari 或 Chrome 打開'**
  String get pageUrlCopied;

  /// No description provided for @loginTagline.
  ///
  /// In zh, this message translates to:
  /// **'馬大！馬大！你為許多的事思慮煩擾，\n但是不可少的只有一件；\n馬利亞已經選擇那上好的福分，\n是不能奪去的。'**
  String get loginTagline;

  /// No description provided for @loginTaglineSource.
  ///
  /// In zh, this message translates to:
  /// **'路加福音 10:41–42'**
  String get loginTaglineSource;

  /// On the login page when it was opened from an invite link
  ///
  /// In zh, this message translates to:
  /// **'受邀加入〈{church}〉'**
  String loginInvitedTo(String church);

  /// No description provided for @email.
  ///
  /// In zh, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In zh, this message translates to:
  /// **'密碼'**
  String get password;

  /// No description provided for @yourName.
  ///
  /// In zh, this message translates to:
  /// **'你的名字'**
  String get yourName;

  /// No description provided for @signIn.
  ///
  /// In zh, this message translates to:
  /// **'登入'**
  String get signIn;

  /// No description provided for @register.
  ///
  /// In zh, this message translates to:
  /// **'註冊'**
  String get register;

  /// No description provided for @createAccount.
  ///
  /// In zh, this message translates to:
  /// **'註冊新帳號'**
  String get createAccount;

  /// No description provided for @haveAccount.
  ///
  /// In zh, this message translates to:
  /// **'已經有帳號？登入'**
  String get haveAccount;

  /// No description provided for @forgotPassword.
  ///
  /// In zh, this message translates to:
  /// **'忘記密碼'**
  String get forgotPassword;

  /// No description provided for @resetSent.
  ///
  /// In zh, this message translates to:
  /// **'重設密碼的信已寄到 {email}'**
  String resetSent(String email);

  /// No description provided for @errInvalidCredential.
  ///
  /// In zh, this message translates to:
  /// **'email 或密碼不對'**
  String get errInvalidCredential;

  /// No description provided for @errEmailInUse.
  ///
  /// In zh, this message translates to:
  /// **'這個 email 註冊過了，請直接登入或用 Google 登入'**
  String get errEmailInUse;

  /// No description provided for @errWeakPassword.
  ///
  /// In zh, this message translates to:
  /// **'密碼至少要 6 個字'**
  String get errWeakPassword;

  /// No description provided for @errInvalidEmail.
  ///
  /// In zh, this message translates to:
  /// **'email 格式不對'**
  String get errInvalidEmail;

  /// No description provided for @errNeedsLink.
  ///
  /// In zh, this message translates to:
  /// **'這個 email 已經有帳號。請用原本的方式登入，登入後會自動連在一起。'**
  String get errNeedsLink;

  /// No description provided for @errTooMany.
  ///
  /// In zh, this message translates to:
  /// **'嘗試太多次，請稍後再試'**
  String get errTooMany;

  /// No description provided for @errNetwork.
  ///
  /// In zh, this message translates to:
  /// **'連不上網路，請檢查後再試一次'**
  String get errNetwork;

  /// No description provided for @errUnknown.
  ///
  /// In zh, this message translates to:
  /// **'沒有成功，請再試一次'**
  String get errUnknown;

  /// No description provided for @nameRequired.
  ///
  /// In zh, this message translates to:
  /// **'請輸入名字'**
  String get nameRequired;

  /// No description provided for @emailRequired.
  ///
  /// In zh, this message translates to:
  /// **'請輸入 email'**
  String get emailRequired;

  /// No description provided for @verifyEmailTitle.
  ///
  /// In zh, this message translates to:
  /// **'驗證你的 email'**
  String get verifyEmailTitle;

  /// No description provided for @verifyEmailBody.
  ///
  /// In zh, this message translates to:
  /// **'驗證信已寄到 {email}，點信裡的連結後回到這裡'**
  String verifyEmailBody(String email);

  /// No description provided for @verifyResend.
  ///
  /// In zh, this message translates to:
  /// **'重寄驗證信'**
  String get verifyResend;

  /// No description provided for @verifyResent.
  ///
  /// In zh, this message translates to:
  /// **'已重寄'**
  String get verifyResent;

  /// No description provided for @verifyDone.
  ///
  /// In zh, this message translates to:
  /// **'我已經驗證'**
  String get verifyDone;

  /// No description provided for @verifyStill.
  ///
  /// In zh, this message translates to:
  /// **'還沒驗證成功，請點信裡的連結'**
  String get verifyStill;

  /// No description provided for @welcomeTitle.
  ///
  /// In zh, this message translates to:
  /// **'加入你的教會'**
  String get welcomeTitle;

  /// No description provided for @welcomeBody.
  ///
  /// In zh, this message translates to:
  /// **'請教會的管理員給你邀請連結'**
  String get welcomeBody;

  /// No description provided for @enterInviteCode.
  ///
  /// In zh, this message translates to:
  /// **'輸入邀請碼'**
  String get enterInviteCode;

  /// No description provided for @createChurch.
  ///
  /// In zh, this message translates to:
  /// **'建立新教會'**
  String get createChurch;

  /// No description provided for @signOut.
  ///
  /// In zh, this message translates to:
  /// **'登出'**
  String get signOut;

  /// No description provided for @inviteCode.
  ///
  /// In zh, this message translates to:
  /// **'邀請碼'**
  String get inviteCode;

  /// No description provided for @next.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get next;

  /// No description provided for @churchName.
  ///
  /// In zh, this message translates to:
  /// **'教會名稱'**
  String get churchName;

  /// No description provided for @createChurchVerifyFirst.
  ///
  /// In zh, this message translates to:
  /// **'驗證 email 後才能建立教會'**
  String get createChurchVerifyFirst;

  /// No description provided for @create.
  ///
  /// In zh, this message translates to:
  /// **'建立'**
  String get create;

  /// No description provided for @errDuplicateName.
  ///
  /// In zh, this message translates to:
  /// **'已經有教會叫這個名字。如果是別人搶先註冊的，請回報問題。'**
  String get errDuplicateName;

  /// No description provided for @contactUs.
  ///
  /// In zh, this message translates to:
  /// **'回報問題'**
  String get contactUs;

  /// No description provided for @joinTitle.
  ///
  /// In zh, this message translates to:
  /// **'加入〈{church}〉'**
  String joinTitle(String church);

  /// No description provided for @join.
  ///
  /// In zh, this message translates to:
  /// **'加入'**
  String get join;

  /// No description provided for @joined.
  ///
  /// In zh, this message translates to:
  /// **'已加入〈{church}〉'**
  String joined(String church);

  /// An invite link opened by someone already in that church
  ///
  /// In zh, this message translates to:
  /// **'你已經是〈{church}〉的同工'**
  String alreadyMember(String church);

  /// No description provided for @errInviteInvalid.
  ///
  /// In zh, this message translates to:
  /// **'找不到這個邀請，請確認邀請碼，或向管理員要新的邀請'**
  String get errInviteInvalid;

  /// No description provided for @errInviteExpired.
  ///
  /// In zh, this message translates to:
  /// **'這個邀請過期了，請向管理員要新的邀請'**
  String get errInviteExpired;

  /// The church is suspended or deleted (教會停用), so nothing can be done in it
  ///
  /// In zh, this message translates to:
  /// **'這間教會已停用'**
  String get errChurchClosed;

  /// No description provided for @churchSuspendedTitle.
  ///
  /// In zh, this message translates to:
  /// **'〈{church}〉已停用'**
  String churchSuspendedTitle(String church);

  /// No description provided for @churchSuspendedBody.
  ///
  /// In zh, this message translates to:
  /// **'有問題請聯絡教會的管理員'**
  String get churchSuspendedBody;

  /// No description provided for @churchDeletedTitle.
  ///
  /// In zh, this message translates to:
  /// **'〈{church}〉已刪除'**
  String churchDeletedTitle(String church);

  /// No description provided for @churchDeletedBody.
  ///
  /// In zh, this message translates to:
  /// **'管理員可以在 {date} 前還原'**
  String churchDeletedBody(String date);

  /// No description provided for @churchDeletedExpired.
  ///
  /// In zh, this message translates to:
  /// **'已經超過 30 天，不能再還原了'**
  String get churchDeletedExpired;

  /// No description provided for @churchUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'無法開啟這間教會'**
  String get churchUnavailable;

  /// No description provided for @restoreChurch.
  ///
  /// In zh, this message translates to:
  /// **'還原教會'**
  String get restoreChurch;

  /// No description provided for @churchRestored.
  ///
  /// In zh, this message translates to:
  /// **'教會已還原'**
  String get churchRestored;

  /// No description provided for @switchChurch.
  ///
  /// In zh, this message translates to:
  /// **'切換教會'**
  String get switchChurch;

  /// No description provided for @myServicesTitle.
  ///
  /// In zh, this message translates to:
  /// **'我接下來的服事'**
  String get myServicesTitle;

  /// No description provided for @noUpcomingServices.
  ///
  /// In zh, this message translates to:
  /// **'接下來沒有你的服事，排到你時會出現在這裡'**
  String get noUpcomingServices;

  /// No description provided for @viewRosters.
  ///
  /// In zh, this message translates to:
  /// **'看服事表'**
  String get viewRosters;

  /// Home page section for an admin who is still the church's only member
  ///
  /// In zh, this message translates to:
  /// **'開始使用'**
  String get gettingStarted;

  /// No description provided for @gettingStartedInvite.
  ///
  /// In zh, this message translates to:
  /// **'邀請同工'**
  String get gettingStartedInvite;

  /// No description provided for @gettingStartedInviteBody.
  ///
  /// In zh, this message translates to:
  /// **'建立邀請連結，傳給同工'**
  String get gettingStartedInviteBody;

  /// No description provided for @gettingStartedServices.
  ///
  /// In zh, this message translates to:
  /// **'服事設定'**
  String get gettingStartedServices;

  /// No description provided for @gettingStartedServicesBody.
  ///
  /// In zh, this message translates to:
  /// **'星期幾、要安排哪些服事'**
  String get gettingStartedServicesBody;

  /// No description provided for @nobodyYet.
  ///
  /// In zh, this message translates to:
  /// **'待定'**
  String get nobodyYet;

  /// No description provided for @noServicesConfigured.
  ///
  /// In zh, this message translates to:
  /// **'還沒有設定聚會'**
  String get noServicesConfigured;

  /// No description provided for @setUpServices.
  ///
  /// In zh, this message translates to:
  /// **'設定聚會'**
  String get setUpServices;

  /// No description provided for @noRostersAhead.
  ///
  /// In zh, this message translates to:
  /// **'接下來沒有聚會'**
  String get noRostersAhead;

  /// No description provided for @today.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get today;

  /// No description provided for @tomorrow.
  ///
  /// In zh, this message translates to:
  /// **'明天'**
  String get tomorrow;

  /// No description provided for @offlineShowingCached.
  ///
  /// In zh, this message translates to:
  /// **'離線中，顯示上次的資料'**
  String get offlineShowingCached;

  /// No description provided for @dutyCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 項服事'**
  String dutyCount(int count);

  /// No description provided for @addDuty.
  ///
  /// In zh, this message translates to:
  /// **'新增服事項目'**
  String get addDuty;

  /// No description provided for @dutyName.
  ///
  /// In zh, this message translates to:
  /// **'服事項目名稱'**
  String get dutyName;

  /// No description provided for @removeDuty.
  ///
  /// In zh, this message translates to:
  /// **'移除這項'**
  String get removeDuty;

  /// No description provided for @dutyRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移除{duty}'**
  String dutyRemoved(String duty);

  /// No description provided for @dutyUpdated.
  ///
  /// In zh, this message translates to:
  /// **'已更新{duty}'**
  String dutyUpdated(String duty);

  /// No description provided for @pickerServes.
  ///
  /// In zh, this message translates to:
  /// **'有這項服事'**
  String get pickerServes;

  /// No description provided for @pickerOthers.
  ///
  /// In zh, this message translates to:
  /// **'其他同工'**
  String get pickerOthers;

  /// No description provided for @pickerUseName.
  ///
  /// In zh, this message translates to:
  /// **'用「{name}」'**
  String pickerUseName(String name);

  /// No description provided for @pickerNoOneServes.
  ///
  /// In zh, this message translates to:
  /// **'還沒有人負責{duty}'**
  String pickerNoOneServes(String duty);

  /// No description provided for @pickerNoResults.
  ///
  /// In zh, this message translates to:
  /// **'找不到「{query}」'**
  String pickerNoResults(String query);

  /// No description provided for @pickerSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜尋同工'**
  String get pickerSearchHint;

  /// No description provided for @pickerAddDutyTitle.
  ///
  /// In zh, this message translates to:
  /// **'也讓「{name}」負責{duty}？'**
  String pickerAddDutyTitle(String name, String duty);

  /// No description provided for @pickerAddDutyBody.
  ///
  /// In zh, this message translates to:
  /// **'之後安排{duty}時，會列在上面'**
  String pickerAddDutyBody(String duty);

  /// No description provided for @pickerAddDutyYes.
  ///
  /// In zh, this message translates to:
  /// **'加上'**
  String get pickerAddDutyYes;

  /// No description provided for @pickerAddDutyNo.
  ///
  /// In zh, this message translates to:
  /// **'只排這次'**
  String get pickerAddDutyNo;

  /// No description provided for @reorder.
  ///
  /// In zh, this message translates to:
  /// **'調整順序'**
  String get reorder;

  /// No description provided for @reorderHint.
  ///
  /// In zh, this message translates to:
  /// **'拖曳調整先後，每一週都照這個順序'**
  String get reorderHint;

  /// No description provided for @orderSaved.
  ///
  /// In zh, this message translates to:
  /// **'已更新順序'**
  String get orderSaved;

  /// No description provided for @swap.
  ///
  /// In zh, this message translates to:
  /// **'交換'**
  String get swap;

  /// No description provided for @swapWith.
  ///
  /// In zh, this message translates to:
  /// **'和誰交換{duty}？'**
  String swapWith(String duty);

  /// No description provided for @swapNone.
  ///
  /// In zh, this message translates to:
  /// **'其他日期沒有可以交換的人'**
  String get swapNone;

  /// No description provided for @swapped.
  ///
  /// In zh, this message translates to:
  /// **'已交換「{a}」和「{b}」'**
  String swapped(String a, String b);

  /// No description provided for @moved.
  ///
  /// In zh, this message translates to:
  /// **'已把「{name}」移到 {day}'**
  String moved(String name, String day);

  /// No description provided for @emptySlot.
  ///
  /// In zh, this message translates to:
  /// **'待定'**
  String get emptySlot;

  /// No description provided for @removeFromDuty.
  ///
  /// In zh, this message translates to:
  /// **'從{duty}移除'**
  String removeFromDuty(String duty);

  /// No description provided for @events.
  ///
  /// In zh, this message translates to:
  /// **'特別活動'**
  String get events;

  /// No description provided for @eventsUpdated.
  ///
  /// In zh, this message translates to:
  /// **'已更新特別活動'**
  String get eventsUpdated;

  /// No description provided for @customEvent.
  ///
  /// In zh, this message translates to:
  /// **'自訂特別活動'**
  String get customEvent;

  /// No description provided for @eventName.
  ///
  /// In zh, this message translates to:
  /// **'特別活動名稱'**
  String get eventName;

  /// No description provided for @addToCommon.
  ///
  /// In zh, this message translates to:
  /// **'加入常用選項'**
  String get addToCommon;

  /// No description provided for @eventColor.
  ///
  /// In zh, this message translates to:
  /// **'顏色'**
  String get eventColor;

  /// No description provided for @colorName0.
  ///
  /// In zh, this message translates to:
  /// **'紅'**
  String get colorName0;

  /// No description provided for @colorName1.
  ///
  /// In zh, this message translates to:
  /// **'橘'**
  String get colorName1;

  /// No description provided for @colorName2.
  ///
  /// In zh, this message translates to:
  /// **'黃'**
  String get colorName2;

  /// No description provided for @colorName3.
  ///
  /// In zh, this message translates to:
  /// **'綠'**
  String get colorName3;

  /// No description provided for @colorName4.
  ///
  /// In zh, this message translates to:
  /// **'藍'**
  String get colorName4;

  /// No description provided for @colorName5.
  ///
  /// In zh, this message translates to:
  /// **'紫'**
  String get colorName5;

  /// No description provided for @removed.
  ///
  /// In zh, this message translates to:
  /// **'已移除「{name}」'**
  String removed(String name);

  /// No description provided for @profile.
  ///
  /// In zh, this message translates to:
  /// **'個人資料'**
  String get profile;

  /// No description provided for @name.
  ///
  /// In zh, this message translates to:
  /// **'名字'**
  String get name;

  /// No description provided for @nameSaved.
  ///
  /// In zh, this message translates to:
  /// **'已更新名字'**
  String get nameSaved;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'語言'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟隨系統'**
  String get languageSystem;

  /// No description provided for @churchInfo.
  ///
  /// In zh, this message translates to:
  /// **'教會資訊'**
  String get churchInfo;

  /// No description provided for @members.
  ///
  /// In zh, this message translates to:
  /// **'同工'**
  String get members;

  /// No description provided for @serviceSettings.
  ///
  /// In zh, this message translates to:
  /// **'服事設定'**
  String get serviceSettings;

  /// No description provided for @invites.
  ///
  /// In zh, this message translates to:
  /// **'邀請'**
  String get invites;

  /// No description provided for @notifications.
  ///
  /// In zh, this message translates to:
  /// **'通知'**
  String get notifications;

  /// No description provided for @account.
  ///
  /// In zh, this message translates to:
  /// **'帳號'**
  String get account;

  /// No description provided for @deleteAccount.
  ///
  /// In zh, this message translates to:
  /// **'刪除帳號'**
  String get deleteAccount;

  /// No description provided for @privacyPolicy.
  ///
  /// In zh, this message translates to:
  /// **'隱私權政策'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In zh, this message translates to:
  /// **'服務條款'**
  String get termsOfService;

  /// No description provided for @developer.
  ///
  /// In zh, this message translates to:
  /// **'開發'**
  String get developer;

  /// No description provided for @components.
  ///
  /// In zh, this message translates to:
  /// **'元件'**
  String get components;

  /// No description provided for @testCrash.
  ///
  /// In zh, this message translates to:
  /// **'測試當機'**
  String get testCrash;

  /// No description provided for @operatorConsole.
  ///
  /// In zh, this message translates to:
  /// **'平台後台'**
  String get operatorConsole;

  /// No description provided for @leaveChurch.
  ///
  /// In zh, this message translates to:
  /// **'退出教會'**
  String get leaveChurch;

  /// No description provided for @leaveChurchTitle.
  ///
  /// In zh, this message translates to:
  /// **'退出〈{church}〉？'**
  String leaveChurchTitle(String church);

  /// No description provided for @leaveChurchBody.
  ///
  /// In zh, this message translates to:
  /// **'需要重新邀請才能回來'**
  String get leaveChurchBody;

  /// No description provided for @leave.
  ///
  /// In zh, this message translates to:
  /// **'退出教會'**
  String get leave;

  /// No description provided for @leftChurch.
  ///
  /// In zh, this message translates to:
  /// **'已退出〈{church}〉'**
  String leftChurch(String church);

  /// No description provided for @adminCannotLeave.
  ///
  /// In zh, this message translates to:
  /// **'管理員不能直接退出。要退出，先把另一位同工設成管理員，再請對方取消你的管理員。'**
  String get adminCannotLeave;

  /// No description provided for @churchLogo.
  ///
  /// In zh, this message translates to:
  /// **'教會 logo'**
  String get churchLogo;

  /// No description provided for @uploadLogo.
  ///
  /// In zh, this message translates to:
  /// **'上傳 logo'**
  String get uploadLogo;

  /// No description provided for @changeLogo.
  ///
  /// In zh, this message translates to:
  /// **'更換 logo'**
  String get changeLogo;

  /// No description provided for @logoUploaded.
  ///
  /// In zh, this message translates to:
  /// **'已更新 logo'**
  String get logoUploaded;

  /// No description provided for @logoTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'圖片太大了，請選 1 MB 以下的圖片'**
  String get logoTooLarge;

  /// No description provided for @logoNotImage.
  ///
  /// In zh, this message translates to:
  /// **'請選一張圖片'**
  String get logoNotImage;

  /// No description provided for @memberCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 位同工'**
  String memberCount(int count);

  /// No description provided for @deleteChurch.
  ///
  /// In zh, this message translates to:
  /// **'刪除教會'**
  String get deleteChurch;

  /// No description provided for @deleteChurchTitle.
  ///
  /// In zh, this message translates to:
  /// **'刪除〈{church}〉？'**
  String deleteChurchTitle(String church);

  /// No description provided for @deleteChurchBody.
  ///
  /// In zh, this message translates to:
  /// **'所有同工都看不到這間教會。30 天內可以還原，之後資料會永久刪除。'**
  String get deleteChurchBody;

  /// No description provided for @roleAdmin.
  ///
  /// In zh, this message translates to:
  /// **'管理員'**
  String get roleAdmin;

  /// No description provided for @roleLeader.
  ///
  /// In zh, this message translates to:
  /// **'小組長'**
  String get roleLeader;

  /// No description provided for @roleStaff.
  ///
  /// In zh, this message translates to:
  /// **'一般同工'**
  String get roleStaff;

  /// No description provided for @roleMember.
  ///
  /// In zh, this message translates to:
  /// **'組員'**
  String get roleMember;

  /// No description provided for @role.
  ///
  /// In zh, this message translates to:
  /// **'身分'**
  String get role;

  /// No description provided for @roleAdminCan.
  ///
  /// In zh, this message translates to:
  /// **'所有設定、邀請和移除同工'**
  String get roleAdminCan;

  /// No description provided for @groups.
  ///
  /// In zh, this message translates to:
  /// **'權限群組'**
  String get groups;

  /// No description provided for @groupRosterEditors.
  ///
  /// In zh, this message translates to:
  /// **'安排服事表'**
  String get groupRosterEditors;

  /// No description provided for @groupCalendarEditors.
  ///
  /// In zh, this message translates to:
  /// **'編輯行事曆'**
  String get groupCalendarEditors;

  /// No description provided for @zones.
  ///
  /// In zh, this message translates to:
  /// **'牧區與服事'**
  String get zones;

  /// No description provided for @zonesFooter.
  ///
  /// In zh, this message translates to:
  /// **'能安排服事表的人，只能排自己牧區的聚會'**
  String get zonesFooter;

  /// No description provided for @removeMember.
  ///
  /// In zh, this message translates to:
  /// **'移除同工'**
  String get removeMember;

  /// No description provided for @memberRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移除「{name}」'**
  String memberRemoved(String name);

  /// No description provided for @memberSaved.
  ///
  /// In zh, this message translates to:
  /// **'已儲存'**
  String get memberSaved;

  /// No description provided for @searchMembers.
  ///
  /// In zh, this message translates to:
  /// **'搜尋同工'**
  String get searchMembers;

  /// No description provided for @noMembersFound.
  ///
  /// In zh, this message translates to:
  /// **'找不到這位同工'**
  String get noMembersFound;

  /// No description provided for @you.
  ///
  /// In zh, this message translates to:
  /// **'你'**
  String get you;

  /// No description provided for @inviteCreate.
  ///
  /// In zh, this message translates to:
  /// **'建立邀請連結'**
  String get inviteCreate;

  /// No description provided for @inviteValidFor.
  ///
  /// In zh, this message translates to:
  /// **'有效期限'**
  String get inviteValidFor;

  /// No description provided for @inviteDays.
  ///
  /// In zh, this message translates to:
  /// **'{days} 天內有效'**
  String inviteDays(int days);

  /// No description provided for @inviteCopy.
  ///
  /// In zh, this message translates to:
  /// **'複製連結'**
  String get inviteCopy;

  /// No description provided for @inviteCopied.
  ///
  /// In zh, this message translates to:
  /// **'已複製邀請連結'**
  String get inviteCopied;

  /// No description provided for @copyByHand.
  ///
  /// In zh, this message translates to:
  /// **'沒辦法自動複製，請選取下面的文字自己複製'**
  String get copyByHand;

  /// No description provided for @inviteShare.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get inviteShare;

  /// No description provided for @inviteRevoke.
  ///
  /// In zh, this message translates to:
  /// **'撤回'**
  String get inviteRevoke;

  /// No description provided for @inviteRevoked.
  ///
  /// In zh, this message translates to:
  /// **'已撤回'**
  String get inviteRevoked;

  /// No description provided for @inviteExpiresOn.
  ///
  /// In zh, this message translates to:
  /// **'{date} 到期'**
  String inviteExpiresOn(String date);

  /// No description provided for @inviteNone.
  ///
  /// In zh, this message translates to:
  /// **'還沒有邀請連結'**
  String get inviteNone;

  /// No description provided for @inviteMessage.
  ///
  /// In zh, this message translates to:
  /// **'邀請你加入〈{church}〉的服事表：{link}'**
  String inviteMessage(String church, String link);

  /// No description provided for @servicesTitle.
  ///
  /// In zh, this message translates to:
  /// **'聚會'**
  String get servicesTitle;

  /// No description provided for @serviceAdd.
  ///
  /// In zh, this message translates to:
  /// **'新增聚會'**
  String get serviceAdd;

  /// No description provided for @serviceName.
  ///
  /// In zh, this message translates to:
  /// **'聚會名稱'**
  String get serviceName;

  /// No description provided for @weekday.
  ///
  /// In zh, this message translates to:
  /// **'星期'**
  String get weekday;

  /// No description provided for @serviceEnabled.
  ///
  /// In zh, this message translates to:
  /// **'啟用'**
  String get serviceEnabled;

  /// No description provided for @serviceDisabledFooter.
  ///
  /// In zh, this message translates to:
  /// **'停用的聚會不會再出現新的服事表，舊的保留'**
  String get serviceDisabledFooter;

  /// No description provided for @templateDuties.
  ///
  /// In zh, this message translates to:
  /// **'服事項目'**
  String get templateDuties;

  /// No description provided for @templateFooter.
  ///
  /// In zh, this message translates to:
  /// **'新的服事表會帶入這些項目。已經安排的服事表不受影響。'**
  String get templateFooter;

  /// No description provided for @commonEvents.
  ///
  /// In zh, this message translates to:
  /// **'常用特別活動'**
  String get commonEvents;

  /// No description provided for @rename.
  ///
  /// In zh, this message translates to:
  /// **'改名'**
  String get rename;

  /// No description provided for @remove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get remove;

  /// No description provided for @moveUp.
  ///
  /// In zh, this message translates to:
  /// **'上移'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In zh, this message translates to:
  /// **'下移'**
  String get moveDown;

  /// No description provided for @saved.
  ///
  /// In zh, this message translates to:
  /// **'已儲存'**
  String get saved;

  /// No description provided for @weekday1.
  ///
  /// In zh, this message translates to:
  /// **'週一'**
  String get weekday1;

  /// No description provided for @weekday2.
  ///
  /// In zh, this message translates to:
  /// **'週二'**
  String get weekday2;

  /// No description provided for @weekday3.
  ///
  /// In zh, this message translates to:
  /// **'週三'**
  String get weekday3;

  /// No description provided for @weekday4.
  ///
  /// In zh, this message translates to:
  /// **'週四'**
  String get weekday4;

  /// No description provided for @weekday5.
  ///
  /// In zh, this message translates to:
  /// **'週五'**
  String get weekday5;

  /// No description provided for @weekday6.
  ///
  /// In zh, this message translates to:
  /// **'週六'**
  String get weekday6;

  /// No description provided for @weekday7.
  ///
  /// In zh, this message translates to:
  /// **'週日'**
  String get weekday7;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In zh, this message translates to:
  /// **'刪除你的帳號？'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountBody.
  ///
  /// In zh, this message translates to:
  /// **'你會退出所有教會，帳號與個人資料會刪除且無法復原。服事表上的名字會保留。'**
  String get deleteAccountBody;

  /// No description provided for @deleteAccountLastAdmin.
  ///
  /// In zh, this message translates to:
  /// **'你是〈{churches}〉唯一的管理員，請先把管理員交給別的同工'**
  String deleteAccountLastAdmin(String churches);

  /// No description provided for @accountDeleted.
  ///
  /// In zh, this message translates to:
  /// **'帳號已刪除'**
  String get accountDeleted;

  /// No description provided for @serviceDisabled.
  ///
  /// In zh, this message translates to:
  /// **'停用'**
  String get serviceDisabled;

  /// No description provided for @adminSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'教會名稱或 ID'**
  String get adminSearchHint;

  /// No description provided for @adminNoChurches.
  ///
  /// In zh, this message translates to:
  /// **'找不到教會'**
  String get adminNoChurches;

  /// No description provided for @adminStats.
  ///
  /// In zh, this message translates to:
  /// **'統計'**
  String get adminStats;

  /// No description provided for @adminRename.
  ///
  /// In zh, this message translates to:
  /// **'改名'**
  String get adminRename;

  /// No description provided for @adminMakeAdmin.
  ///
  /// In zh, this message translates to:
  /// **'設為管理員'**
  String get adminMakeAdmin;

  /// No description provided for @adminMadeAdmin.
  ///
  /// In zh, this message translates to:
  /// **'已把「{name}」設為管理員'**
  String adminMadeAdmin(String name);

  /// No description provided for @adminSuspend.
  ///
  /// In zh, this message translates to:
  /// **'停用教會'**
  String get adminSuspend;

  /// No description provided for @adminReopen.
  ///
  /// In zh, this message translates to:
  /// **'恢復教會'**
  String get adminReopen;

  /// No description provided for @adminSuspendTitle.
  ///
  /// In zh, this message translates to:
  /// **'停用〈{church}〉？'**
  String adminSuspendTitle(String church);

  /// No description provided for @adminSuspendBody.
  ///
  /// In zh, this message translates to:
  /// **'所有同工會立刻看到停用畫面'**
  String get adminSuspendBody;

  /// No description provided for @statusActive.
  ///
  /// In zh, this message translates to:
  /// **'使用中'**
  String get statusActive;

  /// No description provided for @statusSuspended.
  ///
  /// In zh, this message translates to:
  /// **'已停用'**
  String get statusSuspended;

  /// No description provided for @statusDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已刪除'**
  String get statusDeleted;

  /// No description provided for @statsUsers.
  ///
  /// In zh, this message translates to:
  /// **'使用者'**
  String get statsUsers;

  /// No description provided for @statsChurches.
  ///
  /// In zh, this message translates to:
  /// **'教會'**
  String get statsChurches;

  /// No description provided for @statsMembers.
  ///
  /// In zh, this message translates to:
  /// **'成員'**
  String get statsMembers;

  /// No description provided for @statsRosters.
  ///
  /// In zh, this message translates to:
  /// **'服事表'**
  String get statsRosters;

  /// No description provided for @statsReads.
  ///
  /// In zh, this message translates to:
  /// **'Firestore 讀取'**
  String get statsReads;

  /// No description provided for @statsWrites.
  ///
  /// In zh, this message translates to:
  /// **'Firestore 寫入'**
  String get statsWrites;

  /// No description provided for @statsCost.
  ///
  /// In zh, this message translates to:
  /// **'估計費用（USD）'**
  String get statsCost;

  /// No description provided for @statsNone.
  ///
  /// In zh, this message translates to:
  /// **'還沒有統計資料'**
  String get statsNone;

  /// No description provided for @statsMoreInConsole.
  ///
  /// In zh, this message translates to:
  /// **'行為與錯誤細節在 Firebase console'**
  String get statsMoreInConsole;

  /// No description provided for @notifReminder.
  ///
  /// In zh, this message translates to:
  /// **'服事提醒'**
  String get notifReminder;

  /// No description provided for @notifReminderWeeklySub.
  ///
  /// In zh, this message translates to:
  /// **'每週一晚上，列出這週的服事'**
  String get notifReminderWeeklySub;

  /// No description provided for @notifReminderDayBeforeSub.
  ///
  /// In zh, this message translates to:
  /// **'服事前一天晚上提醒你'**
  String get notifReminderDayBeforeSub;

  /// No description provided for @notifReminderBothSub.
  ///
  /// In zh, this message translates to:
  /// **'每週一晚上，和服事前一天晚上'**
  String get notifReminderBothSub;

  /// No description provided for @notifReminderTime.
  ///
  /// In zh, this message translates to:
  /// **'服事提醒時間'**
  String get notifReminderTime;

  /// No description provided for @notifReminderWeekly.
  ///
  /// In zh, this message translates to:
  /// **'每週一晚上'**
  String get notifReminderWeekly;

  /// No description provided for @notifReminderDayBefore.
  ///
  /// In zh, this message translates to:
  /// **'前一天晚上'**
  String get notifReminderDayBefore;

  /// No description provided for @notifReminderBoth.
  ///
  /// In zh, this message translates to:
  /// **'兩個都要'**
  String get notifReminderBoth;

  /// No description provided for @notifReminderTimeFooter.
  ///
  /// In zh, this message translates to:
  /// **'都在晚上 7 點'**
  String get notifReminderTimeFooter;

  /// No description provided for @notifRosterChange.
  ///
  /// In zh, this message translates to:
  /// **'服事表異動'**
  String get notifRosterChange;

  /// No description provided for @notifRosterChangeSub.
  ///
  /// In zh, this message translates to:
  /// **'你被排進或移出服事時'**
  String get notifRosterChangeSub;

  /// No description provided for @notifMemberLeft.
  ///
  /// In zh, this message translates to:
  /// **'同工退出'**
  String get notifMemberLeft;

  /// No description provided for @notifMemberLeftSub.
  ///
  /// In zh, this message translates to:
  /// **'有人退出教會時（只通知管理員）'**
  String get notifMemberLeftSub;

  /// No description provided for @notifThisChurch.
  ///
  /// In zh, this message translates to:
  /// **'這間教會的通知'**
  String get notifThisChurch;

  /// No description provided for @notifPermissionOff.
  ///
  /// In zh, this message translates to:
  /// **'通知被關掉了，請到系統設定打開'**
  String get notifPermissionOff;

  /// No description provided for @notifEnable.
  ///
  /// In zh, this message translates to:
  /// **'開啟通知'**
  String get notifEnable;

  /// No description provided for @notifNotAllowed.
  ///
  /// In zh, this message translates to:
  /// **'通知還沒開。跳出詢問時，請點「允許」。'**
  String get notifNotAllowed;

  /// No description provided for @notifRegisterFailed.
  ///
  /// In zh, this message translates to:
  /// **'通知還沒設定好，下次打開 App 會再試'**
  String get notifRegisterFailed;

  /// No description provided for @pushView.
  ///
  /// In zh, this message translates to:
  /// **'查看'**
  String get pushView;

  /// No description provided for @zoneSwitch.
  ///
  /// In zh, this message translates to:
  /// **'屬於這個牧區'**
  String get zoneSwitch;

  /// No description provided for @zoneLeft.
  ///
  /// In zh, this message translates to:
  /// **'不再屬於{service}牧區'**
  String zoneLeft(String service);

  /// No description provided for @eventRosterGone.
  ///
  /// In zh, this message translates to:
  /// **'找不到這個活動的服事表'**
  String get eventRosterGone;

  /// No description provided for @eventRoster.
  ///
  /// In zh, this message translates to:
  /// **'服事表'**
  String get eventRoster;

  /// No description provided for @eventRosterPeople.
  ///
  /// In zh, this message translates to:
  /// **'{count} 人'**
  String eventRosterPeople(int count);

  /// No description provided for @arrangeEventRoster.
  ///
  /// In zh, this message translates to:
  /// **'安排服事'**
  String get arrangeEventRoster;

  /// No description provided for @eventRosterEmpty.
  ///
  /// In zh, this message translates to:
  /// **'還沒有服事項目'**
  String get eventRosterEmpty;

  /// No description provided for @copyDuties.
  ///
  /// In zh, this message translates to:
  /// **'沿用其他活動'**
  String get copyDuties;

  /// No description provided for @copyDutiesHeader.
  ///
  /// In zh, this message translates to:
  /// **'沿用哪一場的服事項目'**
  String get copyDutiesHeader;

  /// No description provided for @copyDutiesNone.
  ///
  /// In zh, this message translates to:
  /// **'還沒有其他活動的服事表'**
  String get copyDutiesNone;

  /// No description provided for @dutiesCopied.
  ///
  /// In zh, this message translates to:
  /// **'已加入 {count} 個服事項目'**
  String dutiesCopied(int count);

  /// No description provided for @noZoneYet.
  ///
  /// In zh, this message translates to:
  /// **'你還沒有屬於任何牧區，請找管理員設定'**
  String get noZoneYet;

  /// No description provided for @waitsForZone.
  ///
  /// In zh, this message translates to:
  /// **'還沒設定牧區'**
  String get waitsForZone;

  /// No description provided for @waitingForZone.
  ///
  /// In zh, this message translates to:
  /// **'{count} 位同工還沒設定牧區'**
  String waitingForZone(int count);

  /// No description provided for @inviteZones.
  ///
  /// In zh, this message translates to:
  /// **'加入後屬於'**
  String get inviteZones;

  /// No description provided for @photoImport.
  ///
  /// In zh, this message translates to:
  /// **'照片匯入'**
  String get photoImport;

  /// No description provided for @photoRemaining.
  ///
  /// In zh, this message translates to:
  /// **'這個月還可以辨識 {count} 張'**
  String photoRemaining(int count);

  /// No description provided for @photoTake.
  ///
  /// In zh, this message translates to:
  /// **'拍照'**
  String get photoTake;

  /// No description provided for @photoPick.
  ///
  /// In zh, this message translates to:
  /// **'選照片'**
  String get photoPick;

  /// No description provided for @photoPasteJson.
  ///
  /// In zh, this message translates to:
  /// **'貼上 JSON'**
  String get photoPasteJson;

  /// No description provided for @photoRecognizing.
  ///
  /// In zh, this message translates to:
  /// **'辨識中，大約需要一分鐘'**
  String get photoRecognizing;

  /// No description provided for @photoChurchLimit.
  ///
  /// In zh, this message translates to:
  /// **'這個月的 {limit} 張用完了，下個月 1 日恢復。這段時間可以直接安排服事表。'**
  String photoChurchLimit(int limit);

  /// No description provided for @photoPlatformOff.
  ///
  /// In zh, this message translates to:
  /// **'照片辨識這個月暫停（全站的辨識額度用完了），下個月恢復。這段時間可以直接安排服事表。'**
  String get photoPlatformOff;

  /// No description provided for @photoTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'照片太大，請裁到只剩表格再試'**
  String get photoTooLarge;

  /// No description provided for @photoFailed.
  ///
  /// In zh, this message translates to:
  /// **'辨識失敗，請換一張清楚一點的照片再試'**
  String get photoFailed;

  /// No description provided for @photoUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'照片辨識暫時無法使用，請稍後再試，或直接安排服事表'**
  String get photoUnavailable;

  /// No description provided for @importPreview.
  ///
  /// In zh, this message translates to:
  /// **'預覽'**
  String get importPreview;

  /// No description provided for @importApply.
  ///
  /// In zh, this message translates to:
  /// **'套用到服事表'**
  String get importApply;

  /// No description provided for @importApplied.
  ///
  /// In zh, this message translates to:
  /// **'已匯入 {count} 天'**
  String importApplied(int count);

  /// No description provided for @importNothing.
  ///
  /// In zh, this message translates to:
  /// **'照片裡沒有讀到之後的日期'**
  String get importNothing;

  /// No description provided for @importNotInList.
  ///
  /// In zh, this message translates to:
  /// **'名單裡沒有這些人（照原文寫入，沒有連到帳號）'**
  String get importNotInList;

  /// No description provided for @importNear.
  ///
  /// In zh, this message translates to:
  /// **'名單裡有很像的：{names}'**
  String importNear(String names);

  /// No description provided for @importAmbiguous.
  ///
  /// In zh, this message translates to:
  /// **'不確定是哪一位（沒有連到帳號）'**
  String get importAmbiguous;

  /// No description provided for @importUnknownDuties.
  ///
  /// In zh, this message translates to:
  /// **'這個聚會沒有這些服事項目'**
  String get importUnknownDuties;

  /// No description provided for @importPastDays.
  ///
  /// In zh, this message translates to:
  /// **'已經過去的日期，沒有匯入'**
  String get importPastDays;

  /// No description provided for @importBadRows.
  ///
  /// In zh, this message translates to:
  /// **'讀不懂的資料'**
  String get importBadRows;

  /// No description provided for @jsonHint.
  ///
  /// In zh, this message translates to:
  /// **'貼上辨識結果的 JSON'**
  String get jsonHint;

  /// No description provided for @next2.
  ///
  /// In zh, this message translates to:
  /// **'預覽'**
  String get next2;

  /// No description provided for @calNotConnected.
  ///
  /// In zh, this message translates to:
  /// **'教會還沒有連接行事曆'**
  String get calNotConnected;

  /// No description provided for @calConnect.
  ///
  /// In zh, this message translates to:
  /// **'連接 Google 日曆'**
  String get calConnect;

  /// No description provided for @calReconnect.
  ///
  /// In zh, this message translates to:
  /// **'重新連接'**
  String get calReconnect;

  /// No description provided for @calNeedsReconnect.
  ///
  /// In zh, this message translates to:
  /// **'行事曆的授權失效了'**
  String get calNeedsReconnect;

  /// No description provided for @calNeedsReconnectStaff.
  ///
  /// In zh, this message translates to:
  /// **'行事曆暫時讀不到，請管理員重新連接'**
  String get calNeedsReconnectStaff;

  /// No description provided for @calPickCalendar.
  ///
  /// In zh, this message translates to:
  /// **'選擇要用的日曆'**
  String get calPickCalendar;

  /// No description provided for @calNoCalendarYet.
  ///
  /// In zh, this message translates to:
  /// **'還沒選日曆'**
  String get calNoCalendarYet;

  /// No description provided for @calDisconnect.
  ///
  /// In zh, this message translates to:
  /// **'中斷連接'**
  String get calDisconnect;

  /// No description provided for @calDisconnectTitle.
  ///
  /// In zh, this message translates to:
  /// **'中斷行事曆連接？'**
  String get calDisconnectTitle;

  /// No description provided for @calDisconnectBody.
  ///
  /// In zh, this message translates to:
  /// **'同工會看不到行事曆，Google 日曆本身不受影響'**
  String get calDisconnectBody;

  /// No description provided for @calUnverifiedNote.
  ///
  /// In zh, this message translates to:
  /// **'接下來 Google 會顯示「這個應用程式未經驗證」，點「進階」→「前往」繼續。只會讀寫你選的那個日曆。'**
  String get calUnverifiedNote;

  /// No description provided for @calConnectedOk.
  ///
  /// In zh, this message translates to:
  /// **'已連接 Google 日曆'**
  String get calConnectedOk;

  /// No description provided for @calConnectFailed.
  ///
  /// In zh, this message translates to:
  /// **'沒有連接成功，請再試一次'**
  String get calConnectFailed;

  /// No description provided for @calNoEvents.
  ///
  /// In zh, this message translates to:
  /// **'這個月沒有活動'**
  String get calNoEvents;

  /// No description provided for @calAllDay.
  ///
  /// In zh, this message translates to:
  /// **'整天'**
  String get calAllDay;

  /// No description provided for @calNewEvent.
  ///
  /// In zh, this message translates to:
  /// **'新增活動'**
  String get calNewEvent;

  /// No description provided for @calEditEvent.
  ///
  /// In zh, this message translates to:
  /// **'編輯活動'**
  String get calEditEvent;

  /// No description provided for @calTitle.
  ///
  /// In zh, this message translates to:
  /// **'活動名稱'**
  String get calTitle;

  /// No description provided for @calLocation.
  ///
  /// In zh, this message translates to:
  /// **'地點'**
  String get calLocation;

  /// No description provided for @calStart.
  ///
  /// In zh, this message translates to:
  /// **'開始'**
  String get calStart;

  /// No description provided for @calEnd.
  ///
  /// In zh, this message translates to:
  /// **'結束'**
  String get calEnd;

  /// No description provided for @calOtherTime.
  ///
  /// In zh, this message translates to:
  /// **'其他時間…'**
  String get calOtherTime;

  /// No description provided for @calLengthMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes} 分鐘'**
  String calLengthMinutes(int minutes);

  /// No description provided for @calLengthHours.
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小時'**
  String calLengthHours(int hours);

  /// No description provided for @calLengthHoursMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{hours} 小時 {minutes} 分鐘'**
  String calLengthHoursMinutes(int hours, int minutes);

  /// No description provided for @calDelete.
  ///
  /// In zh, this message translates to:
  /// **'刪除活動'**
  String get calDelete;

  /// No description provided for @calDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已刪除「{title}」'**
  String calDeleted(String title);

  /// No description provided for @calSaved.
  ///
  /// In zh, this message translates to:
  /// **'已儲存活動'**
  String get calSaved;

  /// No description provided for @calPrevMonth.
  ///
  /// In zh, this message translates to:
  /// **'上個月'**
  String get calPrevMonth;

  /// No description provided for @calNextMonth.
  ///
  /// In zh, this message translates to:
  /// **'下個月'**
  String get calNextMonth;

  /// No description provided for @calShowMonth.
  ///
  /// In zh, this message translates to:
  /// **'顯示月曆'**
  String get calShowMonth;

  /// No description provided for @calHideMonth.
  ///
  /// In zh, this message translates to:
  /// **'只看列表'**
  String get calHideMonth;

  /// No description provided for @calendarSetting.
  ///
  /// In zh, this message translates to:
  /// **'行事曆'**
  String get calendarSetting;

  /// No description provided for @support.
  ///
  /// In zh, this message translates to:
  /// **'支持馬大別忙'**
  String get support;

  /// No description provided for @supportVerse.
  ///
  /// In zh, this message translates to:
  /// **'乃要均平，就是要你們的富餘，現在可以補他們的不足，使他們的富餘，將來也可以補你們的不足，這就均平了。'**
  String get supportVerse;

  /// No description provided for @supportVerseSource.
  ///
  /// In zh, this message translates to:
  /// **'哥林多後書 8:14'**
  String get supportVerseSource;

  /// No description provided for @supportBody.
  ///
  /// In zh, this message translates to:
  /// **'馬大別忙免費給每間教會使用，雲端費用由大家一起分擔。支持完全自願，教會能用的功能都一樣。'**
  String get supportBody;

  /// No description provided for @supportTips.
  ///
  /// In zh, this message translates to:
  /// **'一次性支持'**
  String get supportTips;

  /// No description provided for @supportMonthly.
  ///
  /// In zh, this message translates to:
  /// **'每月支持'**
  String get supportMonthly;

  /// No description provided for @supportRestore.
  ///
  /// In zh, this message translates to:
  /// **'恢復購買'**
  String get supportRestore;

  /// No description provided for @supportThanks.
  ///
  /// In zh, this message translates to:
  /// **'謝謝你的支持'**
  String get supportThanks;

  /// No description provided for @supportPending.
  ///
  /// In zh, this message translates to:
  /// **'付款處理中'**
  String get supportPending;

  /// No description provided for @supportFailed.
  ///
  /// In zh, this message translates to:
  /// **'沒有完成付款，沒有扣款'**
  String get supportFailed;

  /// No description provided for @supportUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'現在無法連上商店，請稍後再試'**
  String get supportUnavailable;

  /// No description provided for @supporterBadge.
  ///
  /// In zh, this message translates to:
  /// **'支持者'**
  String get supporterBadge;

  /// No description provided for @appIcon.
  ///
  /// In zh, this message translates to:
  /// **'App 圖示'**
  String get appIcon;

  /// No description provided for @appIconSupporterOnly.
  ///
  /// In zh, this message translates to:
  /// **'每月支持者可以換 App 圖示'**
  String get appIconSupporterOnly;

  /// No description provided for @appIconDefault.
  ///
  /// In zh, this message translates to:
  /// **'藍'**
  String get appIconDefault;

  /// No description provided for @appIconGreen.
  ///
  /// In zh, this message translates to:
  /// **'綠'**
  String get appIconGreen;

  /// No description provided for @appIconPurple.
  ///
  /// In zh, this message translates to:
  /// **'紫'**
  String get appIconPurple;

  /// No description provided for @appIconNight.
  ///
  /// In zh, this message translates to:
  /// **'夜'**
  String get appIconNight;

  /// No description provided for @goHome.
  ///
  /// In zh, this message translates to:
  /// **'回首頁'**
  String get goHome;

  /// No description provided for @churchNotFound.
  ///
  /// In zh, this message translates to:
  /// **'找不到這間教會'**
  String get churchNotFound;

  /// No description provided for @churchEntryNotMember.
  ///
  /// In zh, this message translates to:
  /// **'你還不是這間教會的同工。請向管理員要邀請連結來加入。'**
  String get churchEntryNotMember;

  /// No description provided for @churchUrl.
  ///
  /// In zh, this message translates to:
  /// **'教會網址'**
  String get churchUrl;

  /// No description provided for @churchUrlCopied.
  ///
  /// In zh, this message translates to:
  /// **'已複製教會網址'**
  String get churchUrlCopied;

  /// No description provided for @churchUrlCopy.
  ///
  /// In zh, this message translates to:
  /// **'複製教會網址'**
  String get churchUrlCopy;

  /// No description provided for @churchUrlShare.
  ///
  /// In zh, this message translates to:
  /// **'分享教會網址'**
  String get churchUrlShare;

  /// No description provided for @homeName.
  ///
  /// In zh, this message translates to:
  /// **'主畫面名稱'**
  String get homeName;

  /// No description provided for @homeNameUnset.
  ///
  /// In zh, this message translates to:
  /// **'同教會名稱'**
  String get homeNameUnset;

  /// No description provided for @homeNameMayBeCut.
  ///
  /// In zh, this message translates to:
  /// **'部分手機會被截斷'**
  String get homeNameMayBeCut;

  /// No description provided for @homeNameFooter.
  ///
  /// In zh, this message translates to:
  /// **'加入主畫面時，圖示下方顯示的名字。留空就用教會名稱。'**
  String get homeNameFooter;

  /// No description provided for @addToHome.
  ///
  /// In zh, this message translates to:
  /// **'加入主畫面'**
  String get addToHome;

  /// No description provided for @addToHomeIosNote.
  ///
  /// In zh, this message translates to:
  /// **'iPhone 上已經加入的圖示不會跟著更新。換了名稱或 logo 之後，請刪掉圖示再加入一次。'**
  String get addToHomeIosNote;

  /// No description provided for @addToHomeLater.
  ///
  /// In zh, this message translates to:
  /// **'稍後再說'**
  String get addToHomeLater;

  /// No description provided for @addToHomeDone.
  ///
  /// In zh, this message translates to:
  /// **'已加入，之後點手機上的「{name}」圖示打開'**
  String addToHomeDone(String name);

  /// No description provided for @addToHomeIntro.
  ///
  /// In zh, this message translates to:
  /// **'下次點主畫面的圖示，就能打開服事表'**
  String get addToHomeIntro;

  /// No description provided for @addToHomeBrowserGuide.
  ///
  /// In zh, this message translates to:
  /// **'{device} · {browser} 教學'**
  String addToHomeBrowserGuide(String device, String browser);

  /// No description provided for @addToHomeChooseBrowser.
  ///
  /// In zh, this message translates to:
  /// **'畫面不一樣？'**
  String get addToHomeChooseBrowser;

  /// No description provided for @addToHomeChooseGuide.
  ///
  /// In zh, this message translates to:
  /// **'選擇要看的教學'**
  String get addToHomeChooseGuide;

  /// No description provided for @addToHomeChooseGuideNote.
  ///
  /// In zh, this message translates to:
  /// **'只切換教學，不會替你開啟另一個瀏覽器'**
  String get addToHomeChooseGuideNote;

  /// No description provided for @addToHomeSafariLayoutTitle.
  ///
  /// In zh, this message translates to:
  /// **'Safari 畫面'**
  String get addToHomeSafariLayoutTitle;

  /// No description provided for @addToHomeSafariLayoutHint.
  ///
  /// In zh, this message translates to:
  /// **'請依工具列上的按鈕選擇，不需要更改 Safari 設定'**
  String get addToHomeSafariLayoutHint;

  /// No description provided for @addToHomeSafariMoreChoice.
  ///
  /// In zh, this message translates to:
  /// **'我看到「⋯」'**
  String get addToHomeSafariMoreChoice;

  /// No description provided for @addToHomeSafariShareChoice.
  ///
  /// In zh, this message translates to:
  /// **'我看到分享圖示'**
  String get addToHomeSafariShareChoice;

  /// No description provided for @addToHomeSafariMoreShare.
  ///
  /// In zh, this message translates to:
  /// **'點「⋯」，再選「分享」'**
  String get addToHomeSafariMoreShare;

  /// No description provided for @addToHomeSafariDirectShareHint.
  ///
  /// In zh, this message translates to:
  /// **'網址列在上或下都可以，請找「方框向上箭頭」'**
  String get addToHomeSafariDirectShareHint;

  /// No description provided for @addToHomeInApp.
  ///
  /// In zh, this message translates to:
  /// **'App 內建瀏覽器'**
  String get addToHomeInApp;

  /// No description provided for @addToHomeOtherBrowser.
  ///
  /// In zh, this message translates to:
  /// **'其他瀏覽器'**
  String get addToHomeOtherBrowser;

  /// No description provided for @addToHomeScreenshotNote.
  ///
  /// In zh, this message translates to:
  /// **'請點瀏覽器上圈出的按鈕'**
  String get addToHomeScreenshotNote;

  /// No description provided for @addToHomeSafariScreenshot.
  ///
  /// In zh, this message translates to:
  /// **'Safari · iOS 26.5 · 繁中模擬器畫面'**
  String get addToHomeSafariScreenshot;

  /// No description provided for @addToHomeChromeAndroidScreenshot.
  ///
  /// In zh, this message translates to:
  /// **'Chrome 113 · Android 14 · 繁中模擬器畫面（舊版選單）'**
  String get addToHomeChromeAndroidScreenshot;

  /// No description provided for @addToHomeChromeIosScreenshot.
  ///
  /// In zh, this message translates to:
  /// **'Chrome 155 · iOS 27.2 · iPhone 13 真機畫面'**
  String get addToHomeChromeIosScreenshot;

  /// No description provided for @addToHomeAddressBar.
  ///
  /// In zh, this message translates to:
  /// **'網址列'**
  String get addToHomeAddressBar;

  /// No description provided for @addToHomeChromeShare.
  ///
  /// In zh, this message translates to:
  /// **'點網址列旁的分享圖示'**
  String get addToHomeChromeShare;

  /// No description provided for @addToHomeChromeShareHint.
  ///
  /// In zh, this message translates to:
  /// **'不是「⋯」選單，也不是「分享 Chrome」'**
  String get addToHomeChromeShareHint;

  /// No description provided for @addToHomeChromeScroll.
  ///
  /// In zh, this message translates to:
  /// **'看不到時，先把分享面板展開，再往下滑'**
  String get addToHomeChromeScroll;

  /// No description provided for @addToHomeSafariShare.
  ///
  /// In zh, this message translates to:
  /// **'點 Safari 的分享圖示'**
  String get addToHomeSafariShare;

  /// No description provided for @addToHomeFirefoxShare.
  ///
  /// In zh, this message translates to:
  /// **'點網址列的分享圖示'**
  String get addToHomeFirefoxShare;

  /// No description provided for @addToHomeIpadMore.
  ///
  /// In zh, this message translates to:
  /// **'iPad 沒看到這個選項時，先點分享面板中的「更多」'**
  String get addToHomeIpadMore;

  /// No description provided for @addToHomeSelectAdd.
  ///
  /// In zh, this message translates to:
  /// **'點「加入主畫面」'**
  String get addToHomeSelectAdd;

  /// No description provided for @addToHomeShareMore.
  ///
  /// In zh, this message translates to:
  /// **'只看到一排圖示時，先點「檢視較多」；舊版要往下滑'**
  String get addToHomeShareMore;

  /// No description provided for @addToHomeIosConfirm.
  ///
  /// In zh, this message translates to:
  /// **'有網頁 App 開關時保持開啟，最後點右上角的「加入」或「新增」'**
  String get addToHomeIosConfirm;

  /// No description provided for @addToHomeOpenTitle.
  ///
  /// In zh, this message translates to:
  /// **'回主畫面，點新圖示開啟'**
  String get addToHomeOpenTitle;

  /// No description provided for @addToHomeMenu.
  ///
  /// In zh, this message translates to:
  /// **'點 {browser} 的選單'**
  String addToHomeMenu(String browser);

  /// No description provided for @addToHomeChromeInstall.
  ///
  /// In zh, this message translates to:
  /// **'加到主畫面 → 安裝'**
  String get addToHomeChromeInstall;

  /// No description provided for @addToHomeChromeInstallHint.
  ///
  /// In zh, this message translates to:
  /// **'舊版可能叫「安裝應用程式」。請選「安裝」，不是「建立捷徑」。'**
  String get addToHomeChromeInstallHint;

  /// No description provided for @addToHomeFirefoxInstallHint.
  ///
  /// In zh, this message translates to:
  /// **'再照手機的提示新增；只有「新增至主畫面」時，可能只會建立瀏覽器捷徑'**
  String get addToHomeFirefoxInstallHint;

  /// No description provided for @addToHomeTrouble.
  ///
  /// In zh, this message translates to:
  /// **'找不到「加入主畫面」？'**
  String get addToHomeTrouble;

  /// No description provided for @addToHomeSafariTrouble.
  ///
  /// In zh, this message translates to:
  /// **'先把分享面板往上拉，查看下方的動作；仍找不到時，點最下方「編輯動作」查看'**
  String get addToHomeSafariTrouble;

  /// No description provided for @addToHomeExternalTitle.
  ///
  /// In zh, this message translates to:
  /// **'先用 {browser} 開啟'**
  String addToHomeExternalTitle(String browser);

  /// No description provided for @addToHomeExternalHint.
  ///
  /// In zh, this message translates to:
  /// **'複製教會網址，再貼到 {browser} 的網址列，開啟後繼續教學'**
  String addToHomeExternalHint(String browser);

  /// No description provided for @addToHomeEmbeddedHint.
  ///
  /// In zh, this message translates to:
  /// **'你正在 App 裡看網頁，請先換到手機的瀏覽器'**
  String get addToHomeEmbeddedHint;

  /// No description provided for @addToHomeUnknownHint.
  ///
  /// In zh, this message translates to:
  /// **'這個瀏覽器的選單可能不同，改用下方方式繼續'**
  String get addToHomeUnknownHint;

  /// No description provided for @addToHomeCopiedForBrowser.
  ///
  /// In zh, this message translates to:
  /// **'已複製，請開啟 {browser}，貼到網址列'**
  String addToHomeCopiedForBrowser(String browser);

  /// No description provided for @addToHomePhoneOnly.
  ///
  /// In zh, this message translates to:
  /// **'請用手機開啟教會網址，再加入主畫面'**
  String get addToHomePhoneOnly;

  /// No description provided for @addToHomeNotificationsAfter.
  ///
  /// In zh, this message translates to:
  /// **'從主畫面打開後，在「我的」開啟通知，就收得到服事通知'**
  String get addToHomeNotificationsAfter;

  /// No description provided for @addToHomeIosShare.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get addToHomeIosShare;

  /// No description provided for @addToHomeIosAdd.
  ///
  /// In zh, this message translates to:
  /// **'加入'**
  String get addToHomeIosAdd;

  /// No description provided for @addToHomeIosOpen.
  ///
  /// In zh, this message translates to:
  /// **'點手機上的「{name}」圖示打開，再登入一次'**
  String addToHomeIosOpen(String name);

  /// No description provided for @addToHomeAndroidAdd.
  ///
  /// In zh, this message translates to:
  /// **'加到主畫面'**
  String get addToHomeAndroidAdd;

  /// No description provided for @addToHomeAndroidInstall.
  ///
  /// In zh, this message translates to:
  /// **'安裝'**
  String get addToHomeAndroidInstall;

  /// No description provided for @addToHomeAndroidOpen.
  ///
  /// In zh, this message translates to:
  /// **'點手機上的「{name}」圖示打開'**
  String addToHomeAndroidOpen(String name);

  /// No description provided for @addToHomeCardBody.
  ///
  /// In zh, this message translates to:
  /// **'一點就打開，也收得到服事通知'**
  String get addToHomeCardBody;

  /// No description provided for @addToHomeCardHide.
  ///
  /// In zh, this message translates to:
  /// **'不再顯示'**
  String get addToHomeCardHide;

  /// No description provided for @notifNeedsHomeScreen.
  ///
  /// In zh, this message translates to:
  /// **'先加入主畫面，才收得到通知'**
  String get notifNeedsHomeScreen;

  /// No description provided for @churchLink.
  ///
  /// In zh, this message translates to:
  /// **'教會連結'**
  String get churchLink;

  /// No description provided for @churchLinkNone.
  ///
  /// In zh, this message translates to:
  /// **'未設定'**
  String get churchLinkNone;

  /// No description provided for @churchLinkTitle.
  ///
  /// In zh, this message translates to:
  /// **'標題'**
  String get churchLinkTitle;

  /// No description provided for @churchLinkBody.
  ///
  /// In zh, this message translates to:
  /// **'敘述（選填）'**
  String get churchLinkBody;

  /// No description provided for @churchLinkUrl.
  ///
  /// In zh, this message translates to:
  /// **'連結'**
  String get churchLinkUrl;

  /// No description provided for @churchLinkNeedsTitle.
  ///
  /// In zh, this message translates to:
  /// **'請輸入標題'**
  String get churchLinkNeedsTitle;

  /// No description provided for @churchLinkNeedsHttps.
  ///
  /// In zh, this message translates to:
  /// **'請輸入 https:// 開頭的連結'**
  String get churchLinkNeedsHttps;

  /// No description provided for @churchLinkFooter.
  ///
  /// In zh, this message translates to:
  /// **'顯示在每位同工首頁的最上方，點了用瀏覽器打開'**
  String get churchLinkFooter;

  /// No description provided for @churchLinkRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除教會連結'**
  String get churchLinkRemove;

  /// No description provided for @churchLinkRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移除教會連結'**
  String get churchLinkRemoved;

  /// No description provided for @churchLinkOpens.
  ///
  /// In zh, this message translates to:
  /// **'用瀏覽器打開'**
  String get churchLinkOpens;

  /// No description provided for @linkSource.
  ///
  /// In zh, this message translates to:
  /// **'每日內容來源（選填）'**
  String get linkSource;

  /// No description provided for @linkSourceUrl.
  ///
  /// In zh, this message translates to:
  /// **'JSON 網址'**
  String get linkSourceUrl;

  /// No description provided for @linkFetchTime.
  ///
  /// In zh, this message translates to:
  /// **'每天更新時間'**
  String get linkFetchTime;

  /// No description provided for @linkSourceFooter.
  ///
  /// In zh, this message translates to:
  /// **'每天這個時間抓一次。JSON 要有 date（教會的今天）、title、body、link（https）。'**
  String get linkSourceFooter;

  /// No description provided for @linkSourceUpdated.
  ///
  /// In zh, this message translates to:
  /// **'上次更新：{time}'**
  String linkSourceUpdated(String time);

  /// No description provided for @linkSourceFailed.
  ///
  /// In zh, this message translates to:
  /// **'上次沒有抓到：{reason}'**
  String linkSourceFailed(String reason);

  /// No description provided for @linkSourceFetched.
  ///
  /// In zh, this message translates to:
  /// **'已儲存，抓到「{title}」'**
  String linkSourceFetched(String title);

  /// No description provided for @linkErrTimeout.
  ///
  /// In zh, this message translates to:
  /// **'對方網站 5 秒內沒有回應'**
  String get linkErrTimeout;

  /// No description provided for @linkErrTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'內容超過 64 KB'**
  String get linkErrTooLarge;

  /// No description provided for @linkErrBadFormat.
  ///
  /// In zh, this message translates to:
  /// **'內容不是完整的 date、title、body、link JSON'**
  String get linkErrBadFormat;

  /// No description provided for @linkErrNotHttps.
  ///
  /// In zh, this message translates to:
  /// **'網址或轉址不是 https'**
  String get linkErrNotHttps;

  /// No description provided for @linkErrHttp.
  ///
  /// In zh, this message translates to:
  /// **'對方網站回應錯誤（{status}）'**
  String linkErrHttp(String status);

  /// No description provided for @linkErrNetwork.
  ///
  /// In zh, this message translates to:
  /// **'連不上對方網站'**
  String get linkErrNetwork;

  /// No description provided for @linkErrUnknown.
  ///
  /// In zh, this message translates to:
  /// **'原因不明，請再試一次'**
  String get linkErrUnknown;

  /// No description provided for @webhook.
  ///
  /// In zh, this message translates to:
  /// **'外部通知'**
  String get webhook;

  /// No description provided for @webhookUrl.
  ///
  /// In zh, this message translates to:
  /// **'接收網址'**
  String get webhookUrl;

  /// No description provided for @webhookNeedsHttps.
  ///
  /// In zh, this message translates to:
  /// **'請輸入 https:// 開頭的網址'**
  String get webhookNeedsHttps;

  /// No description provided for @webhookSecretOptional.
  ///
  /// In zh, this message translates to:
  /// **'密鑰（選填，留空會自動產生）'**
  String get webhookSecretOptional;

  /// No description provided for @webhookSecretTooShort.
  ///
  /// In zh, this message translates to:
  /// **'密鑰至少要 16 個字'**
  String get webhookSecretTooShort;

  /// No description provided for @webhookCalendar.
  ///
  /// In zh, this message translates to:
  /// **'行事曆異動'**
  String get webhookCalendar;

  /// No description provided for @webhookCalendarHint.
  ///
  /// In zh, this message translates to:
  /// **'新增、修改、刪除活動'**
  String get webhookCalendarHint;

  /// No description provided for @webhookRoster.
  ///
  /// In zh, this message translates to:
  /// **'服事表異動'**
  String get webhookRoster;

  /// No description provided for @webhookRosterHint.
  ///
  /// In zh, this message translates to:
  /// **'幾分鐘內的異動合併成一則'**
  String get webhookRosterHint;

  /// No description provided for @webhookFooter.
  ///
  /// In zh, this message translates to:
  /// **'行事曆或服事表有異動時，送通知到這個網址，例如交給 n8n 轉發到 LINE 群組。通知都用密鑰簽章。'**
  String get webhookFooter;

  /// No description provided for @webhookTest.
  ///
  /// In zh, this message translates to:
  /// **'傳送測試'**
  String get webhookTest;

  /// No description provided for @webhookLast.
  ///
  /// In zh, this message translates to:
  /// **'上次送出：{time} · {result}'**
  String webhookLast(String time, String result);

  /// No description provided for @webhookOk.
  ///
  /// In zh, this message translates to:
  /// **'成功'**
  String get webhookOk;

  /// No description provided for @webhookHttp.
  ///
  /// In zh, this message translates to:
  /// **'對方回應 {status}'**
  String webhookHttp(String status);

  /// No description provided for @webhookTimeout.
  ///
  /// In zh, this message translates to:
  /// **'逾時'**
  String get webhookTimeout;

  /// No description provided for @webhookNetwork.
  ///
  /// In zh, this message translates to:
  /// **'連不上'**
  String get webhookNetwork;

  /// No description provided for @webhookRotate.
  ///
  /// In zh, this message translates to:
  /// **'換新的密鑰'**
  String get webhookRotate;

  /// No description provided for @webhookRotateMessage.
  ///
  /// In zh, this message translates to:
  /// **'舊的密鑰會立刻失效，接收端要改用新的'**
  String get webhookRotateMessage;

  /// No description provided for @webhookGenerate.
  ///
  /// In zh, this message translates to:
  /// **'自動產生'**
  String get webhookGenerate;

  /// No description provided for @webhookTypeOwn.
  ///
  /// In zh, this message translates to:
  /// **'自己輸入'**
  String get webhookTypeOwn;

  /// No description provided for @webhookSecretTitle.
  ///
  /// In zh, this message translates to:
  /// **'密鑰'**
  String get webhookSecretTitle;

  /// No description provided for @webhookSecretOnce.
  ///
  /// In zh, this message translates to:
  /// **'只會顯示這一次。請貼到接收端，用來驗證通知是馬大別忙送的。'**
  String get webhookSecretOnce;

  /// No description provided for @webhookCopySecret.
  ///
  /// In zh, this message translates to:
  /// **'複製密鑰'**
  String get webhookCopySecret;

  /// No description provided for @webhookSecretCopied.
  ///
  /// In zh, this message translates to:
  /// **'已複製密鑰'**
  String get webhookSecretCopied;

  /// No description provided for @webhookSecretChanged.
  ///
  /// In zh, this message translates to:
  /// **'已換成新的密鑰'**
  String get webhookSecretChanged;

  /// No description provided for @webhookOff.
  ///
  /// In zh, this message translates to:
  /// **'關閉外部通知'**
  String get webhookOff;

  /// No description provided for @webhookOffTitle.
  ///
  /// In zh, this message translates to:
  /// **'關閉外部通知？'**
  String get webhookOffTitle;

  /// No description provided for @webhookOffMessage.
  ///
  /// In zh, this message translates to:
  /// **'網址和密鑰都會刪掉，之後要重新設定'**
  String get webhookOffMessage;

  /// No description provided for @webhookOffAction.
  ///
  /// In zh, this message translates to:
  /// **'關閉'**
  String get webhookOffAction;

  /// No description provided for @exportData.
  ///
  /// In zh, this message translates to:
  /// **'匯出資料'**
  String get exportData;

  /// No description provided for @exportFooter.
  ///
  /// In zh, this message translates to:
  /// **'匯出教會的全部資料：一份 JSON，加上一份可以用 Excel 打開的服事表'**
  String get exportFooter;

  /// No description provided for @exported.
  ///
  /// In zh, this message translates to:
  /// **'已匯出'**
  String get exported;

  /// The exported schedule's file name, in the zip; Excel opens it.
  ///
  /// In zh, this message translates to:
  /// **'服事表.csv'**
  String get exportCsvFile;

  /// Column of the exported schedule: the day.
  ///
  /// In zh, this message translates to:
  /// **'日期'**
  String get exportCsvDate;

  /// Column of the exported schedule: the service's name, or the event's title.
  ///
  /// In zh, this message translates to:
  /// **'聚會／活動'**
  String get exportCsvService;

  /// Column of the exported schedule: the role.
  ///
  /// In zh, this message translates to:
  /// **'服事項目'**
  String get exportCsvRole;

  /// Column of the exported schedule: the people on the role.
  ///
  /// In zh, this message translates to:
  /// **'同工'**
  String get exportCsvPeople;

  /// No description provided for @errMoveInvalid.
  ///
  /// In zh, this message translates to:
  /// **'這不是搬家檔，請確認選對了檔案'**
  String get errMoveInvalid;

  /// No description provided for @errMoveTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'同工超過 2,000 位或服事表超過 20,000 天，沒辦法自動搬。請到 GitHub 的 church-staff-pwa 開 issue。'**
  String get errMoveTooLarge;

  /// No description provided for @moveFromSelfHost.
  ///
  /// In zh, this message translates to:
  /// **'從舊版搬過來'**
  String get moveFromSelfHost;

  /// No description provided for @moveIntro.
  ///
  /// In zh, this message translates to:
  /// **'在舊版（church-staff-pwa）的 Cloud Shell 執行搬家指令，把得到的搬家檔上傳。確認預覽後才會建立教會。'**
  String get moveIntro;

  /// No description provided for @movePickFile.
  ///
  /// In zh, this message translates to:
  /// **'選擇搬家檔'**
  String get movePickFile;

  /// No description provided for @moveReading.
  ///
  /// In zh, this message translates to:
  /// **'讀取搬家檔…'**
  String get moveReading;

  /// No description provided for @moveContents.
  ///
  /// In zh, this message translates to:
  /// **'搬家檔內容'**
  String get moveContents;

  /// No description provided for @moveMembers.
  ///
  /// In zh, this message translates to:
  /// **'同工'**
  String get moveMembers;

  /// No description provided for @moveMembersCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 位'**
  String moveMembersCount(int count);

  /// No description provided for @moveRosters.
  ///
  /// In zh, this message translates to:
  /// **'服事表'**
  String get moveRosters;

  /// No description provided for @moveRostersCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 天'**
  String moveRostersCount(int count);

  /// No description provided for @moveServices.
  ///
  /// In zh, this message translates to:
  /// **'聚會'**
  String get moveServices;

  /// No description provided for @moveWhoAmI.
  ///
  /// In zh, this message translates to:
  /// **'這位是我（選填）'**
  String get moveWhoAmI;

  /// No description provided for @moveWhoAmIFooter.
  ///
  /// In zh, this message translates to:
  /// **'選了就接手那位的服事表、牧區和權限。其他同工用同一個 email 登入馬大別忙時，會被問要不要加入。'**
  String get moveWhoAmIFooter;

  /// No description provided for @moveCreate.
  ///
  /// In zh, this message translates to:
  /// **'建立教會並搬過來'**
  String get moveCreate;

  /// No description provided for @moveDone.
  ///
  /// In zh, this message translates to:
  /// **'已建立〈{church}〉'**
  String moveDone(String church);

  /// No description provided for @notSignedInYet.
  ///
  /// In zh, this message translates to:
  /// **'還沒登入'**
  String get notSignedInYet;

  /// No description provided for @pendingCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 位還沒登入'**
  String pendingCount(int count);

  /// No description provided for @claimPrompt.
  ///
  /// In zh, this message translates to:
  /// **'〈{church}〉的同工資料已經搬過來了，要加入嗎？'**
  String claimPrompt(String church);

  /// No description provided for @claimJoin.
  ///
  /// In zh, this message translates to:
  /// **'加入'**
  String get claimJoin;

  /// No description provided for @claimDecline.
  ///
  /// In zh, this message translates to:
  /// **'不加入'**
  String get claimDecline;

  /// No description provided for @movedPasswordNote.
  ///
  /// In zh, this message translates to:
  /// **'從舊版搬過來的同工：舊的密碼不能用，請用同一個 email 註冊新帳號，或用 Google 登入'**
  String get movedPasswordNote;

  /// No description provided for @pendingDelete.
  ///
  /// In zh, this message translates to:
  /// **'刪除這筆資料'**
  String get pendingDelete;

  /// No description provided for @pendingDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'刪除「{name}」的資料？'**
  String pendingDeleteTitle(String name);

  /// No description provided for @pendingDeleteBody.
  ///
  /// In zh, this message translates to:
  /// **'對方就不能用 email 認領了。服事表上的名字會保留。'**
  String get pendingDeleteBody;

  /// No description provided for @pendingDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已刪除'**
  String get pendingDeleted;

  /// No description provided for @mergePending.
  ///
  /// In zh, this message translates to:
  /// **'合併還沒登入的資料'**
  String get mergePending;

  /// No description provided for @mergePendingFooter.
  ///
  /// In zh, this message translates to:
  /// **'同工換了 email 加入時，合併舊名單上那筆資料，服事表、牧區和權限群組都會接上'**
  String get mergePendingFooter;

  /// No description provided for @mergePendingPick.
  ///
  /// In zh, this message translates to:
  /// **'選一筆還沒登入的資料'**
  String get mergePendingPick;

  /// No description provided for @mergePendingTitle.
  ///
  /// In zh, this message translates to:
  /// **'把「{pending}」合併到「{member}」？'**
  String mergePendingTitle(String pending, String member);

  /// No description provided for @mergePendingBody.
  ///
  /// In zh, this message translates to:
  /// **'服事表上的「{pending}」會改成這位同工，牧區和權限群組也會加上去'**
  String mergePendingBody(String pending);

  /// No description provided for @mergePendingAction.
  ///
  /// In zh, this message translates to:
  /// **'合併'**
  String get mergePendingAction;

  /// No description provided for @merged.
  ///
  /// In zh, this message translates to:
  /// **'已合併'**
  String get merged;

  /// No description provided for @fundingTitle.
  ///
  /// In zh, this message translates to:
  /// **'這個月的雲端費用'**
  String get fundingTitle;

  /// No description provided for @fundingProgress.
  ///
  /// In zh, this message translates to:
  /// **'{available} / {target}'**
  String fundingProgress(String available, String target);

  /// No description provided for @fundingEnough.
  ///
  /// In zh, this message translates to:
  /// **'這個月已經足夠'**
  String get fundingEnough;

  /// No description provided for @fundingMonthsLeft.
  ///
  /// In zh, this message translates to:
  /// **'這個月已經足夠，多的還能再維持 {months} 個月'**
  String fundingMonthsLeft(int months);

  /// No description provided for @fundingCarried.
  ///
  /// In zh, this message translates to:
  /// **'含前幾個月留下的 {amount}'**
  String fundingCarried(String amount);

  /// No description provided for @fundingCosts.
  ///
  /// In zh, this message translates to:
  /// **'雲端費用'**
  String get fundingCosts;

  /// No description provided for @fundingTarget.
  ///
  /// In zh, this message translates to:
  /// **'每月目標 {amount}'**
  String fundingTarget(String amount);

  /// No description provided for @fundingCostsHeader.
  ///
  /// In zh, this message translates to:
  /// **'費用'**
  String get fundingCostsHeader;

  /// No description provided for @fundingCostsFooter.
  ///
  /// In zh, this message translates to:
  /// **'價格變了再改。每年的項目平均分到每個月。'**
  String get fundingCostsFooter;

  /// No description provided for @fundingMonthsHeader.
  ///
  /// In zh, this message translates to:
  /// **'最近幾個月'**
  String get fundingMonthsHeader;

  /// No description provided for @fundingMonthValue.
  ///
  /// In zh, this message translates to:
  /// **'{received} / {target}'**
  String fundingMonthValue(String received, String target);

  /// No description provided for @costAdd.
  ///
  /// In zh, this message translates to:
  /// **'新增項目'**
  String get costAdd;

  /// No description provided for @costEdit.
  ///
  /// In zh, this message translates to:
  /// **'費用項目'**
  String get costEdit;

  /// No description provided for @costName.
  ///
  /// In zh, this message translates to:
  /// **'名稱'**
  String get costName;

  /// No description provided for @costAmount.
  ///
  /// In zh, this message translates to:
  /// **'金額'**
  String get costAmount;

  /// No description provided for @costPerMonth.
  ///
  /// In zh, this message translates to:
  /// **'每月'**
  String get costPerMonth;

  /// No description provided for @costPerYear.
  ///
  /// In zh, this message translates to:
  /// **'每年'**
  String get costPerYear;

  /// No description provided for @costValueMonth.
  ///
  /// In zh, this message translates to:
  /// **'{amount} · 每月'**
  String costValueMonth(String amount);

  /// No description provided for @costValueYear.
  ///
  /// In zh, this message translates to:
  /// **'{amount} · 每年'**
  String costValueYear(String amount);

  /// No description provided for @moneyTwd.
  ///
  /// In zh, this message translates to:
  /// **'NT\${amount}'**
  String moneyTwd(String amount);

  /// No description provided for @moneyUsd.
  ///
  /// In zh, this message translates to:
  /// **'US\${amount}'**
  String moneyUsd(String amount);

  /// No description provided for @currencyTwd.
  ///
  /// In zh, this message translates to:
  /// **'NT\$'**
  String get currencyTwd;

  /// No description provided for @currencyUsd.
  ///
  /// In zh, this message translates to:
  /// **'US\$'**
  String get currencyUsd;

  /// No description provided for @fundingRatesBy.
  ///
  /// In zh, this message translates to:
  /// **'匯率：Exchange Rate API'**
  String get fundingRatesBy;

  /// Import source advanced controls heading
  ///
  /// In zh, this message translates to:
  /// **'進階'**
  String get importAdvanced;

  /// Explanation below the unlocalized canonical JSON protocol example
  ///
  /// In zh, this message translates to:
  /// **'date：YYYY-MM-DD；沒有人時 people 填 []。\nevents 可省略；特別活動的 color 只接受 0–5 的顏色編號。'**
  String get importFormatHelp;

  /// Photo recognizer returned an invalid canonical JSON response
  ///
  /// In zh, this message translates to:
  /// **'辨識結果的格式不對，請重新辨識或用進階 JSON'**
  String get importPhotoFormatError;

  /// Pasted import JSON syntax or root-array error
  ///
  /// In zh, this message translates to:
  /// **'JSON 格式不對，請用下方範例的陣列格式'**
  String get importJsonSyntaxError;

  /// Import preview source JSON edit action and sheet title
  ///
  /// In zh, this message translates to:
  /// **'編輯 JSON'**
  String get importJsonEdit;

  /// Import source JSON editor validation
  ///
  /// In zh, this message translates to:
  /// **'請填 JSON 陣列'**
  String get importJsonArrayRequired;

  /// Import identity confirmation sheet title
  ///
  /// In zh, this message translates to:
  /// **'確認「{name}」'**
  String importConfirmName(String name);

  /// Explains that a confirmed raw-name mapping covers this import only
  ///
  /// In zh, this message translates to:
  /// **'這次匯入的同名人名都用這個對應'**
  String get importSameNameScope;

  /// Explicitly preserve an imported name without linking any member UID
  ///
  /// In zh, this message translates to:
  /// **'保留「{name}」為外請'**
  String importGuestChoice(String name);

  /// Import row date editor sheet title
  ///
  /// In zh, this message translates to:
  /// **'編輯日期'**
  String get importEditDate;

  /// Import date field label; protocol format YYYY-MM-DD stays unchanged
  ///
  /// In zh, this message translates to:
  /// **'日期（YYYY-MM-DD）'**
  String get importDateFormatLabel;

  /// Import date field validation
  ///
  /// In zh, this message translates to:
  /// **'請填有效的 YYYY-MM-DD 日期'**
  String get importValidDate;

  /// Import duty and people editor sheet title
  ///
  /// In zh, this message translates to:
  /// **'編輯服事項目'**
  String get importEditDuty;

  /// Import duty editor role field label
  ///
  /// In zh, this message translates to:
  /// **'服事項目'**
  String get importDutyLabel;

  /// Import people multiline field label
  ///
  /// In zh, this message translates to:
  /// **'名字（每行一人）'**
  String get importPeopleLines;

  /// Add an import event action and editor sheet title
  ///
  /// In zh, this message translates to:
  /// **'新增特別活動'**
  String get importAddEventAction;

  /// Import event name and palette editor sheet title
  ///
  /// In zh, this message translates to:
  /// **'編輯特別活動'**
  String get importEditEvent;

  /// Applying an import rejected a change not included in the displayed preview
  ///
  /// In zh, this message translates to:
  /// **'服事表已變更，請重新檢查差異後再套用'**
  String get importConflict;

  /// Old import input and preview cleared after church or account scope changed
  ///
  /// In zh, this message translates to:
  /// **'教會或帳號已切換，請重新匯入'**
  String get importScopeChanged;

  /// One-based import source row label
  ///
  /// In zh, this message translates to:
  /// **'第 {number} 列'**
  String importRow(int number);

  /// Editable import row date label
  ///
  /// In zh, this message translates to:
  /// **'日期'**
  String get importDateLabel;

  /// Import row has no string date
  ///
  /// In zh, this message translates to:
  /// **'請填日期'**
  String get importDateMissing;

  /// Malformed import duty edit action
  ///
  /// In zh, this message translates to:
  /// **'修正服事項目'**
  String get importFixDuty;

  /// Malformed imported people field hint; people is a protocol field name
  ///
  /// In zh, this message translates to:
  /// **'people 請填人名陣列'**
  String get importPeopleArrayHint;

  /// Malformed import event edit action
  ///
  /// In zh, this message translates to:
  /// **'修正特別活動'**
  String get importFixEvent;

  /// Import diff removes a duty and its current names
  ///
  /// In zh, this message translates to:
  /// **'移除{role}：{names}'**
  String importRemoveDuty(String role, String names);

  /// Import diff adds a duty with arranged names
  ///
  /// In zh, this message translates to:
  /// **'新增{role}：{names}'**
  String importAddDuty(String role, String names);

  /// Import duty diff before and after names
  ///
  /// In zh, this message translates to:
  /// **'{role}：{before} → {after}'**
  String importChangeDuty(String role, String before, String after);

  /// Import diff name is linked to a member UID
  ///
  /// In zh, this message translates to:
  /// **'{name}（同工）'**
  String importMemberIdentity(String name);

  /// Import diff name is explicitly not linked to a member UID
  ///
  /// In zh, this message translates to:
  /// **'{name}（外請）'**
  String importGuestIdentity(String name);

  /// Import diff removes an event
  ///
  /// In zh, this message translates to:
  /// **'移除特別活動：{name}'**
  String importRemoveEvent(String name);

  /// Import diff adds an event
  ///
  /// In zh, this message translates to:
  /// **'新增特別活動：{name}'**
  String importAddEvent(String name);

  /// Import diff changes an existing event color
  ///
  /// In zh, this message translates to:
  /// **'特別活動：{name}'**
  String importChangeEvent(String name);

  /// Localized palette labels before and after import event color change
  ///
  /// In zh, this message translates to:
  /// **'{before} → {after}'**
  String importChangedColor(String before, String after);

  /// Import diff has no arrangement changes
  ///
  /// In zh, this message translates to:
  /// **'安排沒有變更'**
  String get importNoChange;

  /// Imported name has no member candidate and requires an explicit decision
  ///
  /// In zh, this message translates to:
  /// **'請保留為外請或修正人名'**
  String get importNoCandidate;

  /// Unconfirmed import name member candidates
  ///
  /// In zh, this message translates to:
  /// **'候選：{names}'**
  String importCandidates(String names);

  /// Imported name explicitly remains an unlinked guest
  ///
  /// In zh, this message translates to:
  /// **'外請（沒有連到帳號）'**
  String get importGuestUnlinked;

  /// Import name identity still needs confirmation
  ///
  /// In zh, this message translates to:
  /// **'請確認人名'**
  String get importNameNeedsConfirm;

  /// Imported raw name is linked to this member
  ///
  /// In zh, this message translates to:
  /// **'同工：{name}'**
  String importLinkedMember(String name);

  /// Import merge or replacement mode section heading
  ///
  /// In zh, this message translates to:
  /// **'匯入方式'**
  String get importMode;

  /// Default import mode keeps unmentioned arrangements
  ///
  /// In zh, this message translates to:
  /// **'合併（保留未提到的安排）'**
  String get importMerge;

  /// Explicit import replacement mode
  ///
  /// In zh, this message translates to:
  /// **'取代當天全部安排'**
  String get importReplace;

  /// Import replacement affects only the previewed dates
  ///
  /// In zh, this message translates to:
  /// **'移除沒提到的服事項目與特別活動；不影響其他日期'**
  String get importReplaceHelp;

  /// Invalid canonical import data blocks all writes
  ///
  /// In zh, this message translates to:
  /// **'請修正資料後再匯入'**
  String get importFixData;

  /// Import row correction action hint
  ///
  /// In zh, this message translates to:
  /// **'請修正這一列資料'**
  String get importFixRow;

  /// Imported name identity mapping section heading
  ///
  /// In zh, this message translates to:
  /// **'人名對應'**
  String get importNameLinks;

  /// Unconfirmed import names block all writes
  ///
  /// In zh, this message translates to:
  /// **'確認人名後才能匯入'**
  String get importNamesNeedConfirm;

  /// Admin-only optional import repair section heading
  ///
  /// In zh, this message translates to:
  /// **'修正教會設定（選填）'**
  String get importRepairSettings;

  /// Ordinary editor import does not grant qualifications or change settings
  ///
  /// In zh, this message translates to:
  /// **'這次安排不會變更同工或教會設定'**
  String get importNoSettingsChange;

  /// Admin adds an imported duty to the service template
  ///
  /// In zh, this message translates to:
  /// **'加入服事設定：{role}'**
  String importAddConfiguredDuty(String role);

  /// Imported one-day duty is not in the service template
  ///
  /// In zh, this message translates to:
  /// **'未設定的服事項目：{role}'**
  String importUnconfiguredDuty(String role);

  /// Admin grants this imported duty to the matched member
  ///
  /// In zh, this message translates to:
  /// **'讓{name}負責{role}'**
  String importGrantQualification(String name, String role);

  /// Matched member has no configured qualification for this duty
  ///
  /// In zh, this message translates to:
  /// **'{name}還沒設定{role}'**
  String importMissingQualification(String name, String role);

  /// Admin keeps an imported event as a common service option
  ///
  /// In zh, this message translates to:
  /// **'加入常用特別活動：{name}'**
  String importAddCommonEvent(String name);

  /// Imported event remains a one-day event rather than a common option
  ///
  /// In zh, this message translates to:
  /// **'未設為常用特別活動：{name}'**
  String importNotCommonEvent(String name);

  /// Import diff section heading with the existing localized date label
  ///
  /// In zh, this message translates to:
  /// **'套用後差異 · {date}'**
  String importDiff(String date);

  /// Required import editor field validation
  ///
  /// In zh, this message translates to:
  /// **'請填{field}'**
  String importRequiredField(String field);

  /// Import event palette field label
  ///
  /// In zh, this message translates to:
  /// **'顏色'**
  String get importColor;

  /// ImportIssueCode.rowObject
  ///
  /// In zh, this message translates to:
  /// **'請填包含 date、duties 的物件'**
  String get importIssueRowObject;

  /// ImportIssueCode.rowFields
  ///
  /// In zh, this message translates to:
  /// **'只支援 date、duties、events 欄位'**
  String get importIssueRowFields;

  /// ImportIssueCode.date
  ///
  /// In zh, this message translates to:
  /// **'date 請填有效的 YYYY-MM-DD 日期'**
  String get importIssueDate;

  /// ImportIssueCode.duplicateDate
  ///
  /// In zh, this message translates to:
  /// **'日期重複，請合併成同一列'**
  String get importIssueDuplicateDate;

  /// ImportIssueCode.dutiesArray
  ///
  /// In zh, this message translates to:
  /// **'duties 請填陣列'**
  String get importIssueDutiesArray;

  /// ImportIssueCode.dutyFields; source duty item position is one-based
  ///
  /// In zh, this message translates to:
  /// **'第 {index} 個服事項目只支援 role、people'**
  String importIssueDutyFields(int index);

  /// ImportIssueCode.role; source duty item position is one-based
  ///
  /// In zh, this message translates to:
  /// **'第 {index} 個 role 請填不重複的服事項目名稱'**
  String importIssueRole(int index);

  /// ImportIssueCode.peopleArray; source duty item position is one-based
  ///
  /// In zh, this message translates to:
  /// **'第 {index} 個 people 請填非空白人名的字串陣列；無人時填 []'**
  String importIssuePeopleArray(int index);

  /// ImportIssueCode.duplicatePeople; source duty item position is one-based
  ///
  /// In zh, this message translates to:
  /// **'第 {index} 個 people 不可有重複人名'**
  String importIssueDuplicatePeople(int index);

  /// ImportIssueCode.eventsArray
  ///
  /// In zh, this message translates to:
  /// **'events 請填陣列'**
  String get importIssueEventsArray;

  /// ImportIssueCode.eventObject; example is a protocol JSON literal supplied by UI (field names untranslated, the name value is eventName); avoids ICU interpreting JSON braces
  ///
  /// In zh, this message translates to:
  /// **'第 {index} 個特別活動請填 {example}'**
  String importIssueEventObject(int index, String example);

  /// ImportIssueCode.eventName; source event item position is one-based
  ///
  /// In zh, this message translates to:
  /// **'第 {index} 個特別活動的 name 請填不重複的名稱'**
  String importIssueEventName(int index);

  /// ImportIssueCode.eventColor; source event item position is one-based
  ///
  /// In zh, this message translates to:
  /// **'第 {index} 個特別活動的 color 請填 0 到 5 的整數'**
  String importIssueEventColor(int index);

  /// ImportIssueCode.resolvedDuplicatePeople; role is the imported duty label
  ///
  /// In zh, this message translates to:
  /// **'{role}：確認後人名重複，請移除重複的人名'**
  String importIssueResolvedDuplicatePeople(String role);

  /// The release that actually booted the running PWA, never the server-latest release. Its opaque release id is shown as the row subtitle.
  ///
  /// In zh, this message translates to:
  /// **'目前版本'**
  String get appRunningVersion;

  /// Web development build without a generated release manifest; no update or native store claim.
  ///
  /// In zh, this message translates to:
  /// **'開發版本（還沒有發布版本）'**
  String get appVersionDevelopment;

  /// No description provided for @appUpdateNativeTitle.
  ///
  /// In zh, this message translates to:
  /// **'App 更新'**
  String get appUpdateNativeTitle;

  /// No description provided for @appUpdateNativeNote.
  ///
  /// In zh, this message translates to:
  /// **'請到 App Store 或 Google Play 檢查更新'**
  String get appUpdateNativeNote;

  /// No description provided for @appUpdateCheck.
  ///
  /// In zh, this message translates to:
  /// **'檢查更新'**
  String get appUpdateCheck;

  /// No description provided for @appUpdateChecking.
  ///
  /// In zh, this message translates to:
  /// **'檢查中…'**
  String get appUpdateChecking;

  /// No description provided for @appUpdateApply.
  ///
  /// In zh, this message translates to:
  /// **'更新並重新開啟'**
  String get appUpdateApply;

  /// No description provided for @appUpdateApplying.
  ///
  /// In zh, this message translates to:
  /// **'更新中…'**
  String get appUpdateApplying;

  /// Only after an explicit server check confirms the currently running release is latest.
  ///
  /// In zh, this message translates to:
  /// **'已是最新版本'**
  String get appUpdateCurrent;

  /// No description provided for @appUpdateReady.
  ///
  /// In zh, this message translates to:
  /// **'有新版本'**
  String get appUpdateReady;

  /// No description provided for @appUpdateFinishEditing.
  ///
  /// In zh, this message translates to:
  /// **'還有沒儲存的內容，儲存後再更新'**
  String get appUpdateFinishEditing;

  /// No description provided for @appUpdateFinishEditingNote.
  ///
  /// In zh, this message translates to:
  /// **'先儲存正在編輯的內容'**
  String get appUpdateFinishEditingNote;

  /// No description provided for @appUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'沒有更新成功，請檢查網路後再試一次'**
  String get appUpdateFailed;

  /// No description provided for @appUpdateScopeChanged.
  ///
  /// In zh, this message translates to:
  /// **'帳號或教會換了，請重新檢查更新'**
  String get appUpdateScopeChanged;

  /// No description provided for @appUpdateBackToMe.
  ///
  /// In zh, this message translates to:
  /// **'請再點一次「更新並重新開啟」'**
  String get appUpdateBackToMe;

  /// No description provided for @appUpdateCheckFirst.
  ///
  /// In zh, this message translates to:
  /// **'請先檢查更新'**
  String get appUpdateCheckFirst;

  /// Empty state of service settings for someone who is not an admin
  ///
  /// In zh, this message translates to:
  /// **'只有管理員能改服事設定'**
  String get servicesAdminOnly;

  /// Example duty in the import JSON example; only the value is translated
  ///
  /// In zh, this message translates to:
  /// **'司琴'**
  String get importExampleRole;

  /// Example name in the import JSON example
  ///
  /// In zh, this message translates to:
  /// **'李美玉'**
  String get importExamplePerson;

  /// Example occasion (特別活動) in the import JSON example
  ///
  /// In zh, this message translates to:
  /// **'聖餐'**
  String get importExampleEvent;

  /// No description provided for @rosterShowMore.
  ///
  /// In zh, this message translates to:
  /// **'顯示更多'**
  String get rosterShowMore;

  /// No description provided for @pickerGuestNames.
  ///
  /// In zh, this message translates to:
  /// **'外請名字'**
  String get pickerGuestNames;

  /// No description provided for @serviceSettingsSaved.
  ///
  /// In zh, this message translates to:
  /// **'服事設定已儲存'**
  String get serviceSettingsSaved;

  /// No description provided for @serviceSyncOriginalEvent.
  ///
  /// In zh, this message translates to:
  /// **'原本的特別活動'**
  String get serviceSyncOriginalEvent;

  /// No description provided for @serviceSyncOriginalDuty.
  ///
  /// In zh, this message translates to:
  /// **'原本的服事項目'**
  String get serviceSyncOriginalDuty;

  /// No description provided for @serviceFutureSyncTitle.
  ///
  /// In zh, this message translates to:
  /// **'同步「{from}」為「{to}」'**
  String serviceFutureSyncTitle(String from, String to);

  /// No description provided for @serviceFutureSyncSaved.
  ///
  /// In zh, this message translates to:
  /// **'已同步 {count} 份未來服事表'**
  String serviceFutureSyncSaved(int count);

  /// No description provided for @serviceEventColorTitle.
  ///
  /// In zh, this message translates to:
  /// **'{name} · 顏色'**
  String serviceEventColorTitle(String name);

  /// No description provided for @serviceEventColor.
  ///
  /// In zh, this message translates to:
  /// **'顏色'**
  String get serviceEventColor;

  /// No description provided for @serviceSyncFutureRosters.
  ///
  /// In zh, this message translates to:
  /// **'同步未來服事表'**
  String get serviceSyncFutureRosters;

  /// No description provided for @rosterFutureChangesNone.
  ///
  /// In zh, this message translates to:
  /// **'沒有需要變更的未來服事表'**
  String get rosterFutureChangesNone;

  /// No description provided for @rosterFutureChangesFooter.
  ///
  /// In zh, this message translates to:
  /// **'只變更明天起已儲存的服事表'**
  String get rosterFutureChangesFooter;

  /// No description provided for @rosterFutureChangesConflict.
  ///
  /// In zh, this message translates to:
  /// **'已有同名項目，請先調整'**
  String get rosterFutureChangesConflict;

  /// No description provided for @rosterApplyFutureChanges.
  ///
  /// In zh, this message translates to:
  /// **'套用變更'**
  String get rosterApplyFutureChanges;

  /// No description provided for @rosterRemoveFutureGuest.
  ///
  /// In zh, this message translates to:
  /// **'移除未來的外請安排'**
  String get rosterRemoveFutureGuest;

  /// No description provided for @rosterRemoveFutureGuestTitle.
  ///
  /// In zh, this message translates to:
  /// **'移除「{name}」的未來安排'**
  String rosterRemoveFutureGuestTitle(String name);

  /// No description provided for @rosterFutureGuestRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移除 {count} 份未來安排'**
  String rosterFutureGuestRemoved(int count);

  /// No description provided for @rosterFutureDutyChange.
  ///
  /// In zh, this message translates to:
  /// **'{role}：{before} → {after}'**
  String rosterFutureDutyChange(String role, String before, String after);

  /// No description provided for @rosterFutureEventChange.
  ///
  /// In zh, this message translates to:
  /// **'{before} → {after}'**
  String rosterFutureEventChange(String before, String after);

  /// No description provided for @errConflict.
  ///
  /// In zh, this message translates to:
  /// **'其他同工剛改過，重新整理後再改一次'**
  String get errConflict;

  /// No description provided for @errOfflineReadOnly.
  ///
  /// In zh, this message translates to:
  /// **'離線中，連線後才能儲存'**
  String get errOfflineReadOnly;

  /// No description provided for @errTooManyChanges.
  ///
  /// In zh, this message translates to:
  /// **'一次最多改 500 份服事表，請分成幾次改'**
  String get errTooManyChanges;

  /// No description provided for @undoDone.
  ///
  /// In zh, this message translates to:
  /// **'已復原'**
  String get undoDone;

  /// No description provided for @undoFailed.
  ///
  /// In zh, this message translates to:
  /// **'復原失敗，請再試一次'**
  String get undoFailed;

  /// No description provided for @offlineReadOnlyBanner.
  ///
  /// In zh, this message translates to:
  /// **'離線中，顯示上次的資料，連線後才能儲存'**
  String get offlineReadOnlyBanner;

  /// Calendar content shown from a previous read, never presented as fresh
  ///
  /// In zh, this message translates to:
  /// **'顯示上次的資料'**
  String get calendarCached;

  /// Church-time stamp of the last complete read
  ///
  /// In zh, this message translates to:
  /// **'{time} 更新'**
  String calendarReadAt(String time);

  /// No description provided for @calDescription.
  ///
  /// In zh, this message translates to:
  /// **'活動說明'**
  String get calDescription;

  /// No description provided for @calDuplicate.
  ///
  /// In zh, this message translates to:
  /// **'複製活動'**
  String get calDuplicate;

  /// No description provided for @homeUpcomingEvents.
  ///
  /// In zh, this message translates to:
  /// **'近期活動'**
  String get homeUpcomingEvents;

  /// No description provided for @memberSmallGroups.
  ///
  /// In zh, this message translates to:
  /// **'小組'**
  String get memberSmallGroups;

  /// No description provided for @memberSmallGroupsHint.
  ///
  /// In zh, this message translates to:
  /// **'每行一個小組'**
  String get memberSmallGroupsHint;

  /// No description provided for @linkErrNotToday.
  ///
  /// In zh, this message translates to:
  /// **'來源還沒有今天的內容'**
  String get linkErrNotToday;

  /// No description provided for @linkSourceToday.
  ///
  /// In zh, this message translates to:
  /// **'今天的內容沒有更新：{reason}'**
  String linkSourceToday(String reason);

  /// No description provided for @linkSourceRetry.
  ///
  /// In zh, this message translates to:
  /// **'重新抓取'**
  String get linkSourceRetry;

  /// Between items in a list of names or roles.
  ///
  /// In zh, this message translates to:
  /// **'、'**
  String get listSeparator;

  /// A label and what it says, as in a notification shown in the app.
  ///
  /// In zh, this message translates to:
  /// **'{label}：{value}'**
  String labelValue(String label, String value);

  /// The signed-in member in the member list.
  ///
  /// In zh, this message translates to:
  /// **'{name}（你）'**
  String nameIsYou(String name);

  /// Between church names in deleteAccountLastAdmin, inside its quotes.
  ///
  /// In zh, this message translates to:
  /// **'〉〈'**
  String get churchListSeparator;

  /// A calendar day and its events, read by screen readers.
  ///
  /// In zh, this message translates to:
  /// **'{day}，{events}'**
  String dayWithEvents(String day, String events);

  /// Between short facts on one line, such as a status and a count.
  ///
  /// In zh, this message translates to:
  /// **' · '**
  String get dotSeparator;

  /// A church's status (active, suspended, deleted) in the platform console.
  ///
  /// In zh, this message translates to:
  /// **'狀態'**
  String get churchStatus;

  /// The church's time zone, in church settings.
  ///
  /// In zh, this message translates to:
  /// **'時區'**
  String get timeZone;

  /// A time zone by its city, with how far it is from UTC now.
  ///
  /// In zh, this message translates to:
  /// **'{city}（{offset}）'**
  String timeZoneWithOffset(String city, String offset);

  /// No description provided for @timeZoneFooter.
  ///
  /// In zh, this message translates to:
  /// **'今天的日期、服事提醒和行事曆的時間都照教會的時區'**
  String get timeZoneFooter;

  /// No description provided for @timeZoneChangeTitle.
  ///
  /// In zh, this message translates to:
  /// **'改成{city}時間？'**
  String timeZoneChangeTitle(String city);

  /// No description provided for @timeZoneChangeBody.
  ///
  /// In zh, this message translates to:
  /// **'活動時間會照新時區顯示，服事表的日期不變'**
  String get timeZoneChangeBody;

  /// Confirms changing the church's time zone.
  ///
  /// In zh, this message translates to:
  /// **'改成{city}時間'**
  String timeZoneChange(String city);

  /// Under times, when the phone is in another time zone than the church.
  ///
  /// In zh, this message translates to:
  /// **'教會當地時間（{city}）'**
  String churchLocalTime(String city);

  /// Under the calendar list, when the picked Google calendar's time zone is not the church's.
  ///
  /// In zh, this message translates to:
  /// **'這本日曆的時區是{zone}，跟教會的時區（{city}）不同。行事曆的時間照教會的時區顯示。'**
  String calendarTimeZoneDiffers(String zone, String city);

  /// No description provided for @cityAuckland.
  ///
  /// In zh, this message translates to:
  /// **'奧克蘭'**
  String get cityAuckland;

  /// No description provided for @citySydney.
  ///
  /// In zh, this message translates to:
  /// **'雪梨'**
  String get citySydney;

  /// No description provided for @cityMelbourne.
  ///
  /// In zh, this message translates to:
  /// **'墨爾本'**
  String get cityMelbourne;

  /// No description provided for @cityTokyo.
  ///
  /// In zh, this message translates to:
  /// **'東京'**
  String get cityTokyo;

  /// No description provided for @citySeoul.
  ///
  /// In zh, this message translates to:
  /// **'首爾'**
  String get citySeoul;

  /// No description provided for @cityTaipei.
  ///
  /// In zh, this message translates to:
  /// **'台北'**
  String get cityTaipei;

  /// No description provided for @cityHongKong.
  ///
  /// In zh, this message translates to:
  /// **'香港'**
  String get cityHongKong;

  /// No description provided for @citySingapore.
  ///
  /// In zh, this message translates to:
  /// **'新加坡'**
  String get citySingapore;

  /// No description provided for @cityKualaLumpur.
  ///
  /// In zh, this message translates to:
  /// **'吉隆坡'**
  String get cityKualaLumpur;

  /// No description provided for @cityLondon.
  ///
  /// In zh, this message translates to:
  /// **'倫敦'**
  String get cityLondon;

  /// No description provided for @cityToronto.
  ///
  /// In zh, this message translates to:
  /// **'多倫多'**
  String get cityToronto;

  /// No description provided for @cityNewYork.
  ///
  /// In zh, this message translates to:
  /// **'紐約'**
  String get cityNewYork;

  /// No description provided for @cityChicago.
  ///
  /// In zh, this message translates to:
  /// **'芝加哥'**
  String get cityChicago;

  /// No description provided for @cityDenver.
  ///
  /// In zh, this message translates to:
  /// **'丹佛'**
  String get cityDenver;

  /// No description provided for @cityVancouver.
  ///
  /// In zh, this message translates to:
  /// **'溫哥華'**
  String get cityVancouver;

  /// No description provided for @cityLosAngeles.
  ///
  /// In zh, this message translates to:
  /// **'洛杉磯'**
  String get cityLosAngeles;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'ja', 'ko', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return L10nZhHans();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return L10nEn();
    case 'ja':
      return L10nJa();
    case 'ko':
      return L10nKo();
    case 'zh':
      return L10nZh();
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
