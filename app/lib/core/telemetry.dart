import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../data/backend.dart';

/// Crash and error reporting plus product analytics.
///
/// Native apps: Crashlytics and GA4. Web: GA4, and errors go to the
/// logClientError function (Crashlytics has no web SDK). Only uid, church
/// ID and the error are reported, never names, emails or roster content
/// (docs/design.md, 數據與監控).
abstract interface class Telemetry {
  void recordError(Object error, StackTrace stack, {bool fatal = false});

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

class NoTelemetry implements Telemetry {
  const NoTelemetry();

  @override
  void recordError(Object error, StackTrace stack, {bool fatal = false}) {}

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

  final _webErrors = WebErrorFilter();

  @override
  void recordError(Object error, StackTrace stack, {bool fatal = false}) {
    if (kIsWeb) {
      final message = _webErrors.admit(error);
      if (message == null) return;
      _cloud.logError(
        message: message.length > 1000 ? message.substring(0, 1000) : message,
        stack: _trim(stack.toString(), 8000),
        churchId: _churchId,
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
    _analytics?.logScreenView(screenName: name, screenClass: name);
  }

  @override
  void testCrash() {
    if (!kIsWeb) FirebaseCrashlytics.instance.crash();
  }
}
