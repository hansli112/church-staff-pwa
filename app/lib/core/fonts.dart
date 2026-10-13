import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../deep_link.dart' show appLocation, churchUrlId, inviteChurchId;
import 'date_data.dart';
import 'languages.dart';

/// The app's strings in [language], shipped as assets so their characters
/// are known before any page is drawn.
String uiStringsAsset(AppLanguage language) => switch (language) {
  AppLanguage.zhHant => 'lib/l10n/app_zh.arb',
  AppLanguage.zhHans => 'lib/l10n/app_zh_Hans.arb',
  AppLanguage.en => 'lib/l10n/app_en.arb',
  AppLanguage.ja => 'lib/l10n/app_ja.arb',
  AppLanguage.ko => 'lib/l10n/app_ko.arb',
};

/// How long the page's loading screen waits for fonts at most, once the
/// app is ready to show a page.
const fontsWaitLimit = Duration(seconds: 3);

/// Two characters from each of the files Google Fonts splits a Noto Sans
/// font for Chinese, Japanese or Korean into, of its most used characters:
/// in Noto Sans TC the last 20 of its about 100 files hold some 4,300
/// characters, nearly every name and word a church types. Laying these out
/// fetches all 20 (about 740 KB, 15 of them needed for the app's own text
/// anyway), so names show at once too, not only the app's text.
///
/// The font is the one the engine draws these in for a browser whose
/// language is [browserLanguage] (navigator.language), as its font fallback
/// picks (font_fallbacks.dart, `_selectFont`): Traditional Chinese, Hong
/// Kong's, Japanese or Korean for theirs, else Simplified Chinese, which it
/// takes on a tie. The app's language does not change it.
///
/// Picked from the engine's copy of the lists (font_fallback_data.dart),
/// whose files go from the least used characters to the most: two from each
/// of the 20 numbered last (`.100.woff2` to `.119.woff2`). Check them again
/// on a Flutter upgrade: a new copy may split them differently.
String commonCharacters(String browserLanguage) => switch (browserLanguage) {
  'zh-Hant' || 'zh-TW' || 'zh-MO' => '玖誦砌蠶渦蔻瀚舜濤蔚滷蒜瑩菸毅芒槽芽疊蘿淚蒂洞舖棄苗武耳減聖泰詳瀏該比著服聯心正',
  'zh-HK' => '昊糯樟茸拱竄戳綫揉筍户綺昂罷拘盃惱籌斤胃捕纖拆糕幻穩扣禁ェ・怎羅投育康約工相台最',
  'ja' => '息繁幅百導盛復策振群星緒扱級富準座絶役聞想福工組常素天細売次対機後索合株月点べソ',
  'ko' => '智늪市뀜比룽最뺨小랏英쏙꽉얌돕썩뜬앵랬앗뢰옛맘젝뜨읽벨좌몰첨맨잘르외른임미은로시',
  _ => '極舅搓級梧缤暮磷拐绽挪缆扯纲悔筛敦聪撒胞措绑忧珍尊瓣恋稳庆突局秘带签完码外次もデ',
};

/// Text on the first login/home pages and the auth/church-entry states that
/// may appear instead. Other screens ask for their fonts when opened.
const _startupKeys = {
  'appName',
  'tabHome',
  'tabRosters',
  'tabCalendar',
  'tabMe',
  'cancel',
  'done',
  'retry',
  'close',
  'loadFailed',
  'noPermission',
  'signInWithGoogle',
  'signInWithEmail',
  'inAppBrowserNote',
  'copyPageUrl',
  'pageUrlCopied',
  'loginTagline',
  'loginTaglineSource',
  'loginInvitedTo',
  'email',
  'password',
  'yourName',
  'signIn',
  'register',
  'createAccount',
  'haveAccount',
  'forgotPassword',
  'movedPasswordNote',
  'verifyEmailTitle',
  'verifyEmailBody',
  'verifyResend',
  'verifyResent',
  'verifyDone',
  'verifyStill',
  'welcomeTitle',
  'welcomeBody',
  'enterInviteCode',
  'createChurch',
  'signOut',
  'inviteCode',
  'next',
  'churchName',
  'createChurchVerifyFirst',
  'create',
  'contactUs',
  'joinTitle',
  'join',
  'joined',
  'alreadyMember',
  'errInviteInvalid',
  'errInviteExpired',
  'errChurchClosed',
  'churchSuspendedTitle',
  'churchSuspendedBody',
  'churchDeletedTitle',
  'churchDeletedBody',
  'churchDeletedExpired',
  'churchUnavailable',
  'restoreChurch',
  'churchRestored',
  'switchChurch',
  'myServicesTitle',
  'noUpcomingServices',
  'viewRosters',
  'gettingStarted',
  'inviteMembers',
  'gettingStartedInviteBody',
  'gettingStartedServices',
  'gettingStartedServicesBody',
  'nobodyYet',
  'noServicesConfigured',
  'setUpServices',
  'noRostersAhead',
  'today',
  'tomorrow',
  'offlineShowingCached',
  'waitingForZone',
  'claimPrompt',
  'claimJoin',
  'claimDecline',
  'addToHome',
  'addToHomeCardBody',
  'addToHomeCardHide',
  'pushView',
  'goHome',
  'churchNotFound',
  'churchEntryNotMember',
  'weekday1',
  'weekday2',
  'weekday3',
  'weekday4',
  'weekday5',
  'weekday6',
  'weekday7',
};

const _rosterKeys = {
  'eventRosterGone',
  'eventRoster',
  'eventRosterPeople',
  'eventRosterEmpty',
  'dutyCount',
  'edit',
  'addDuty',
  'events',
  'emptySlot',
};

const _churchInfoKeys = {
  'churchInfo',
  'churchLogo',
  'churchUrl',
  'homeName',
  'homeNameUnset',
  'timeZone',
  'timeZoneWithOffset',
  'cityAuckland',
  'citySydney',
  'cityMelbourne',
  'cityTokyo',
  'citySeoul',
  'cityTaipei',
  'cityHongKong',
  'citySingapore',
  'cityKualaLumpur',
  'cityLondon',
  'cityNewYork',
  'cityToronto',
  'cityChicago',
  'cityDenver',
  'cityLosAngeles',
  'cityVancouver',
  'addToHomeIosNote',
  'members',
  'invites',
  'serviceSettings',
  'calendarSetting',
  'churchLink',
  'churchLinkNone',
  'webhook',
  'uploadLogo',
  'changeLogo',
  'exportFooter',
  'exportData',
  'adminCannotLeave',
  'deleteChurch',
  'leaveChurch',
};

Set<String>? _initialKeys(Uri location, [int depth = 0]) {
  if (depth >= 4) return null;
  if (churchUrlId(location) != null || inviteChurchId(location) != null) {
    final to = appLocation(location.queryParameters['to']);
    final destination = to == null ? null : Uri.tryParse(to);
    return destination == null ? _startupKeys : _initialKeys(destination, depth + 1);
  }
  if (const {'/login', '/loading'}.contains(location.path)) {
    final from = appLocation(location.queryParameters['from']);
    final destination = from == null ? null : Uri.tryParse(from);
    return destination == null ? _startupKeys : _initialKeys(destination, depth + 1);
  }
  if (const {'', '/', '/home'}.contains(location.path)) return _startupKeys;
  if (location.path == '/me/church') return {..._startupKeys, ..._churchInfoKeys};
  final parts = location.pathSegments;
  if (parts.length == 3 && parts.first == 'rosters' && parts[1] != 'import') {
    return {..._startupKeys, ..._rosterKeys};
  }
  return null;
}

/// What [language]'s pages show that no .arb string holds: what its dates
/// are written with (10月4日 週日), the patterns of the dates pages show and
/// the weekdays; and every language's name in itself (简体中文), as the
/// language page lists them.
String _textBeyondStrings(AppLanguage language) {
  final (symbols, patterns) = dateData(language);
  return [
    for (final p in const ['MMMd', 'MMMEd', 'yMMMd', 'yMMMEd', 'yMMMM']) patterns[p]!,
    ...symbols.SHORTWEEKDAYS,
    for (final l in AppLanguage.values) l.label,
  ].join();
}

/// Every string of an .arb file, run together, without its notes (`@`
/// keys).
String arbText(String json) => _text(json);

String _text(String json, {Set<String>? keys}) => [
  for (final MapEntry(:key, :value) in (jsonDecode(json) as Map<String, dynamic>).entries)
    if (!key.startsWith('@') && value is String && (keys == null || keys.contains(key))) value,
].join();

/// On the web the engine fetches Chinese fonts when text first needs them,
/// so the first page can show boxes until they arrive. This starts those
/// downloads before the page is drawn, with the text of its dates and the
/// languages' names.
/// [initialLocation] selects login/home, roster or church-info text,
/// following this app's `from`/`to` links. Other destinations keep the full
/// warmup. Without a location, [startupOnly] retains the login/home
/// selection; the default uses all strings. The strings are [languages]',
/// each one's.
///
/// Completes on the next font change after laying out the initial text, or
/// at once if the strings cannot be used. The loading screen owns its wait
/// limit. When supplied, [afterFirstFrame] also releases an unfinished wait
/// after that screen has timed out, and ignores a late asset read.
///
/// The most used characters ([commonCharacters], for [browserLanguage])
/// warm up only after both readiness and [afterFirstFrame], so they cannot
/// compete with the first usable frame. Without that signal they follow
/// readiness, as before. [layOut] asks the engine for fonts; [systemFonts]
/// reports font changes.
Future<void> warmUpFonts({
  required AssetBundle bundle,
  required Listenable systemFonts,
  Iterable<AppLanguage> languages = const [AppLanguage.zhHant],
  String browserLanguage = '',
  bool startupOnly = false,
  Uri? initialLocation,
  Future<void>? afterFirstFrame,
  void Function(String text) layOut = _layOut,
}) {
  final done = Completer<void>();
  var reading = true;
  void finish() {
    if (reading || done.isCompleted) return;
    done.complete();
    // Not while it is calling its listeners: it cannot take that.
    scheduleMicrotask(() {
      systemFonts.removeListener(finish);
      unawaited(() async {
        try {
          await afterFirstFrame;
        } catch (_) {
          return;
        }
        layOut(commonCharacters(browserLanguage));
      }());
    });
  }

  systemFonts.addListener(finish);
  unawaited(
    afterFirstFrame?.then<void>((_) {
      // The page can draw after the caller's font wait has timed out.
      reading = false;
      finish();
    }, onError: (Object _) {}),
  );
  unawaited(() async {
    try {
      final keys = initialLocation != null ? _initialKeys(initialLocation) : (startupOnly ? _startupKeys : null);
      final text = [
        for (final language in languages) _text(await bundle.loadString(uiStringsAsset(language)), keys: keys),
      ].join();
      if (done.isCompleted) return;
      reading = false;
      if (text.trim().isEmpty) {
        finish();
      } else {
        layOut(text + languages.map(_textBeyondStrings).join());
      }
    } catch (_) {
      reading = false;
      // Without them, the first page asks for the fonts it needs.
      finish();
    }
  }());
  return done.future;
}

void _layOut(String text) => (ui.ParagraphBuilder(ui.ParagraphStyle())..addText(text)).build();
