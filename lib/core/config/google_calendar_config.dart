import 'package:flutter/foundation.dart';

import 'church_config.dart';

class GoogleCalendarConfig {
  static const _apiKey = String.fromEnvironment('GOOGLE_CALENDAR_API_KEY');
  static const _calendarId = String.fromEnvironment('GOOGLE_CALENDAR_ID');
  static String? _testApiKey;
  static String? _testCalendarId;

  static String get apiKey => _testApiKey ?? _apiKey;
  static String get calendarId => _testCalendarId ?? _calendarId;
  static String get timeZone => ChurchConfig.current.timeZone;

  static bool get isEnabled =>
      ChurchConfig.current.features.calendar &&
      apiKey.trim().isNotEmpty &&
      calendarId.trim().isNotEmpty;

  @visibleForTesting
  static void configureForTesting({
    required String apiKey,
    required String calendarId,
  }) {
    _testApiKey = apiKey;
    _testCalendarId = calendarId;
  }

  @visibleForTesting
  static void resetForTesting() {
    _testApiKey = null;
    _testCalendarId = null;
  }
}
