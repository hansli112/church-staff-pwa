import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../deep_link.dart' show appLocation, churchUrlId, inviteChurchId;

/// The app's strings, shipped as an asset so their characters are known
/// before any page is drawn.
const uiStringsAsset = 'lib/l10n/app_zh.arb';

/// How long the page's loading screen waits for fonts at most, once the
/// app is ready to show a page.
const fontsWaitLimit = Duration(seconds: 3);

/// Two characters from each of the files Google Fonts splits Noto Sans TC's
/// most used characters into: the last 20 of its about 100 files hold some
/// 4,300 characters, nearly every name and word a church types. Laying these
/// out fetches all 20 (about 740 KB, 15 of them needed for the app's own
/// text anyway), so names show at once too, not only the app's text. Only
/// for browsers in Traditional Chinese (zh-TW): elsewhere the engine picks
/// other fonts for the same characters.
/// Picked from fonts.googleapis.com/css2?family=Noto+Sans+TC, whose files
/// go from the least used characters to the most; the engine's copy of the
/// list numbers these 20 files 100 to 119. Check them again on a Flutter
/// upgrade: a new copy may split them differently.
const commonCharacters = '玖誦砌蠶渦蔻瀚舜濤蔚滷蒜瑩菸毅芒槽芽疊蘿淚蒂洞舖棄苗武耳減聖泰詳瀏該比著服聯心正';

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
  'gettingStartedInvite',
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

/// Every string of an .arb file, run together, without its notes (`@`
/// keys).
String arbText(String json) => _text(json);

String _text(String json, {Set<String>? keys}) => [
  for (final MapEntry(:key, :value) in (jsonDecode(json) as Map<String, dynamic>).entries)
    if (!key.startsWith('@') && value is String && (keys == null || keys.contains(key))) value,
].join();

/// On the web the engine fetches Chinese fonts when text first needs them,
/// so the first page can show boxes until they arrive. This starts those
/// downloads before the page is drawn. [initialLocation] selects login/home,
/// roster or church-info text, following this app's `from`/`to` links. Other
/// destinations keep the full warmup. Without a location, [startupOnly]
/// retains the login/home selection; the default uses all strings.
///
/// Completes on the next font change after laying out the initial text, or
/// at once if the strings cannot be used. The loading screen owns its wait
/// limit. When supplied, [afterFirstFrame] also releases an unfinished wait
/// after that screen has timed out, and ignores a late asset read.
///
/// The most used characters ([commonCharacters]) warm up only after both
/// readiness and [afterFirstFrame], so they cannot compete with the first
/// usable frame. Without that signal they follow readiness, as before.
/// [layOut] asks the engine for fonts; [systemFonts] reports font changes.
Future<void> warmUpFonts({
  required AssetBundle bundle,
  required Listenable systemFonts,
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
        layOut(commonCharacters);
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
      final json = await bundle.loadString(uiStringsAsset);
      if (done.isCompleted) return;
      final keys = initialLocation != null ? _initialKeys(initialLocation) : (startupOnly ? _startupKeys : null);
      final text = _text(json, keys: keys);
      reading = false;
      if (text.trim().isEmpty) {
        finish();
      } else {
        layOut(text);
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
