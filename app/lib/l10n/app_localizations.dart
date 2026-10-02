import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

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
  static const List<Locale> supportedLocales = <Locale>[Locale('zh')];

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

  /// No description provided for @loginTagline.
  ///
  /// In zh, this message translates to:
  /// **'同工服事表，大家一起看'**
  String get loginTagline;

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
  /// **'Email 或密碼不對'**
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
  /// **'Email 格式不對'**
  String get errInvalidEmail;

  /// No description provided for @errNeedsLink.
  ///
  /// In zh, this message translates to:
  /// **'這個 email 已經有帳號。請用原本的方式登入，登入後會自動連在一起'**
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
  /// **'已經有教會叫這個名字。如果是被別人搶先註冊，請聯絡我們'**
  String get errDuplicateName;

  /// No description provided for @contactUs.
  ///
  /// In zh, this message translates to:
  /// **'聯絡我們'**
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

  /// No description provided for @errInviteInvalid.
  ///
  /// In zh, this message translates to:
  /// **'這個邀請已失效，請向管理員要新的邀請'**
  String get errInviteInvalid;

  /// No description provided for @errInviteExpired.
  ///
  /// In zh, this message translates to:
  /// **'這個邀請過期了，請向管理員要新的邀請'**
  String get errInviteExpired;

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
  /// **'接下來沒有你的服事'**
  String get noUpcomingServices;

  /// No description provided for @viewRosters.
  ///
  /// In zh, this message translates to:
  /// **'看服事表'**
  String get viewRosters;

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
  /// **'也讓{name}負責{duty}？'**
  String pickerAddDutyTitle(String name, String duty);

  /// No description provided for @pickerAddDutyBody.
  ///
  /// In zh, this message translates to:
  /// **'之後安排{duty}時，他會出現在上面'**
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
  /// **'已交換 {a} 和 {b}'**
  String swapped(String a, String b);

  /// No description provided for @moved.
  ///
  /// In zh, this message translates to:
  /// **'已把 {name} 移到 {day}'**
  String moved(String name, String day);

  /// No description provided for @emptySlot.
  ///
  /// In zh, this message translates to:
  /// **'空著'**
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

  /// No description provided for @customEvent.
  ///
  /// In zh, this message translates to:
  /// **'自訂活動'**
  String get customEvent;

  /// No description provided for @eventName.
  ///
  /// In zh, this message translates to:
  /// **'活動名稱'**
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
  /// **'已移除{name}'**
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

  /// No description provided for @languageZhHant.
  ///
  /// In zh, this message translates to:
  /// **'繁體中文'**
  String get languageZhHant;

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
  /// **'退出'**
  String get leave;

  /// No description provided for @leftChurch.
  ///
  /// In zh, this message translates to:
  /// **'已退出〈{church}〉'**
  String leftChurch(String church);

  /// No description provided for @adminCannotLeave.
  ///
  /// In zh, this message translates to:
  /// **'管理員要先把管理員交給別人，才能退出'**
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
  /// **'圖片太大了，請選 1MB 以下的圖片'**
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
  /// **'所有同工都看不到這間教會。30 天內可以還原，之後資料會永久刪除'**
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
  /// **'同工'**
  String get roleStaff;

  /// No description provided for @roleMember.
  ///
  /// In zh, this message translates to:
  /// **'組員'**
  String get roleMember;

  /// No description provided for @role.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get role;

  /// No description provided for @groups.
  ///
  /// In zh, this message translates to:
  /// **'權限'**
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
  /// **'勾選他在各聚會負責的服事。有「安排服事表」權限的人，只能安排自己牧區的服事表'**
  String get zonesFooter;

  /// No description provided for @removeMember.
  ///
  /// In zh, this message translates to:
  /// **'移除同工'**
  String get removeMember;

  /// No description provided for @memberRemoved.
  ///
  /// In zh, this message translates to:
  /// **'已移除{name}'**
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
  /// **'{days} 天'**
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
  /// **'舉行中'**
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
  /// **'新的服事表會帶入這些項目。已經安排的服事表不受影響'**
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
  /// **'你會退出所有教會，帳號與個人資料會刪除且無法復原。服事表上的名字會保留'**
  String get deleteAccountBody;

  /// No description provided for @deleteAccountLastAdmin.
  ///
  /// In zh, this message translates to:
  /// **'你是〈{churches}〉唯一的管理員。請先到「同工」把管理員交給別人'**
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
  /// **'已設 {name} 為管理員'**
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

  /// No description provided for @notifReminderSub.
  ///
  /// In zh, this message translates to:
  /// **'服事前一天晚上提醒你'**
  String get notifReminderSub;

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
  /// **'有人退出教會時（管理員）'**
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
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
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
