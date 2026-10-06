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
  void logEvent(String name, [Map<String, Object>? parameters]);

  /// Crashes the native app, to check that Crashlytics receives crashes.
  /// Development builds only.
  void testCrash();
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
  void logEvent(String name, [Map<String, Object>? parameters]) {}

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

  /// Web: at most this many reports per page load, and each distinct
  /// message once, so a render loop cannot flood the log.
  static const _webCap = 20;
  final _sent = <String>{};

  @override
  void recordError(Object error, StackTrace stack, {bool fatal = false}) {
    if (kIsWeb) {
      final message = error.toString();
      if (_sent.length >= _webCap || !_sent.add(message)) return;
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
  void logEvent(String name, [Map<String, Object>? parameters]) {
    _analytics?.logEvent(name: name, parameters: parameters);
  }

  @override
  void testCrash() {
    if (!kIsWeb) FirebaseCrashlytics.instance.crash();
  }
}
