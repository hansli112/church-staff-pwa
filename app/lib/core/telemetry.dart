import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../data/backend.dart';
import 'web_page.dart';

/// Crash and error reporting plus product analytics.
///
/// Native apps: Crashlytics and GA4. Web: GA4, and errors go to the
/// logClientError function (Crashlytics has no web SDK). Only uid, church
/// ID and the error are reported, never names, emails or roster content
/// (docs/design.md, 數據與監控).
abstract interface class Telemetry {
  /// [fatal]: uncaught (PlatformDispatcher.onError), not reported by the
  /// framework. [during] and [library]: where the framework caught it
  /// ([errorPhase], [FlutterErrorDetails.library]).
  void recordError(Object error, StackTrace stack, {bool fatal = false, String? during, String? library});

  /// Sets the GA4 user property `church_id` and the Crashlytics key.
  void setChurch(String? churchId);
  void setUser(String? uid);

  /// Sets the GA4 user property `role`: mine in the church open now.
  void setRole(String? role);

  /// Tags native crash reports with the Shorebird patch running (0: none),
  /// which the build number Crashlytics records does not show.
  void setPatch(int? patch);
  void logEvent(String name, [Map<String, Object>? parameters]);

  /// A page coming up, by its route's pattern.
  void logScreen(String name);

  /// Crashes the native app, to check that Crashlytics receives crashes.
  /// Development builds only.
  void testCrash();
}

/// Which web errors are reported: at most 20 per page load, and each kind
/// once, so a render loop cannot flood the log or the inbox.
///
/// Errors that name a render object differ only in its name and hash
/// (`RenderBox was not laid out: minified:Class746#20b19`); one failed
/// layout leaves a dozen of them, so they count as one kind.
class WebErrorFilter {
  static const _cap = 20;
  static final _renderObject = RegExp(r'(minified:Class\d+|\b\w+)#[0-9a-f]{5}\b');
  final _sent = <String>{};

  /// The message to report for [error], or null when it is not reported.
  String? admit(Object error) {
    final message = error.toString().replaceAll(_renderObject, 'a render object');
    if (_sent.length >= _cap || !_sent.add(message)) return null;
    return message;
  }
}

/// What the framework was doing when it caught [details]' error, in a few
/// words: 「while dispatching a pointer event」, 「during performLayout()」,
/// 「building Text」. Cut before the first `(` (but an empty `()`), `[`, `#`,
/// `:`, `"`, `'` or line break, where a widget or render object would go on
/// with its arguments, keys and state, which can be names or roster text.
String? errorPhase(FlutterErrorDetails details) {
  final context = details.context?.toDescription();
  if (context == null) return null;
  final cut = context.indexOf(_phaseEnd);
  final phase = (cut < 0 ? context : context.substring(0, cut)).trim();
  if (phase.isEmpty) return null;
  return phase.length > 100 ? phase.substring(0, 100) : phase;
}

final _phaseEnd = RegExp('\\((?!\\))|[\\[#:"\'\\n]');

/// [stack] as text; empty when it cannot be read, as a browser error whose
/// JavaScript stack is gone throws when printed.
String stackText(StackTrace stack) {
  try {
    return stack.toString();
  } catch (_) {
    return '';
  }
}

/// FlutterError.onError: reports the error to [telemetry] first, then
/// prints it ([present], FlutterError.presentError). Printing can throw
/// (a JavaScript stack that is gone), and the error it was about would
/// then never be reported: on the web only what it broke afterwards was.
FlutterExceptionHandler flutterErrorReporter(
  Telemetry telemetry, {
  void Function(FlutterErrorDetails)? present,
}) => (details) {
  telemetry.recordError(
    details.exception,
    details.stack ?? StackTrace.empty,
    during: errorPhase(details),
    library: details.library,
  );
  try {
    (present ?? FlutterError.presentError)(details);
  } catch (_) {
    // Reported above; the console only misses it.
  }
};

class NoTelemetry implements Telemetry {
  const NoTelemetry();

  @override
  void recordError(Object error, StackTrace stack, {bool fatal = false, String? during, String? library}) {}

  @override
  void setChurch(String? churchId) {}

  @override
  void setUser(String? uid) {}

  @override
  void setRole(String? role) {}

  @override
  void setPatch(int? patch) {}

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {}

  @override
  void logScreen(String name) {}

  @override
  void testCrash() {}
}

class FirebaseTelemetry implements Telemetry {
  FirebaseTelemetry({required CloudApi cloud, bool analytics = true})
    : _cloud = cloud,
      _analytics = analytics ? FirebaseAnalytics.instance : null;

  final CloudApi _cloud;
  final FirebaseAnalytics? _analytics;
  String? _churchId;

  /// The page up now, by its route's pattern ([logScreen]).
  String? _screen;

  final _webErrors = WebErrorFilter();

  @override
  void recordError(Object error, StackTrace stack, {bool fatal = false, String? during, String? library}) {
    if (kIsWeb) {
      final message = _webErrors.admit(error);
      if (message == null) return;
      _cloud.logError(
        message: message.length > 1000 ? message.substring(0, 1000) : message,
        stack: _trim(stackText(stack), 8000),
        agent: _trim(userAgent(), 300),
        churchId: _churchId,
        screen: _screen,
        during: during,
        library: library,
        fatal: fatal,
      );
      return;
    }
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal);
  }

  static String _trim(String s, int max) => s.length > max ? s.substring(0, max) : s;

  @override
  void setChurch(String? churchId) {
    _churchId = churchId;
    _analytics?.setUserProperty(name: 'church_id', value: churchId);
    if (!kIsWeb) FirebaseCrashlytics.instance.setCustomKey('church_id', churchId ?? '');
  }

  @override
  void setUser(String? uid) {
    _analytics?.setUserId(id: uid);
    if (!kIsWeb) FirebaseCrashlytics.instance.setUserIdentifier(uid ?? '');
  }

  @override
  void setRole(String? role) {
    _analytics?.setUserProperty(name: 'role', value: role);
  }

  @override
  void setPatch(int? patch) {
    if (!kIsWeb) FirebaseCrashlytics.instance.setCustomKey('shorebird_patch_number', patch ?? 0);
  }

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) {
    _analytics?.logEvent(name: name, parameters: parameters);
  }

  @override
  void logScreen(String name) {
    _screen = name;
    _analytics?.logScreenView(screenName: name, screenClass: name);
  }

  @override
  void testCrash() {
    if (!kIsWeb) FirebaseCrashlytics.instance.crash();
  }
}
