import 'dart:convert';

import 'package:church_staff_pwa/core/config/church_config.dart';
import 'package:church_staff_pwa/core/config/default_church_config.dart';
import 'package:church_staff_pwa/core/config/google_calendar_config.dart';
import 'package:flutter_test/flutter_test.dart';

ChurchConfig testChurchConfig({
  String appName = '測試教會',
  String timeZone = 'Asia/Taipei',
  bool calendar = false,
  bool photoImport = false,
  bool pushNotifications = false,
  Map<String, dynamic>? devotional,
  List<Map<String, dynamic>>? services,
}) => ChurchConfig.fromJson({
  ...jsonDecode(defaultChurchConfigJson) as Map<String, dynamic>,
  'appName': appName,
  'timeZone': timeZone,
  'features': {
    'calendar': calendar,
    'photoImport': photoImport,
    'pushNotifications': pushNotifications,
    'lineNotifications': false,
  },
  'devotional': ?devotional,
  'services': ?services,
});

/// Fake public Calendar settings only; the test must still inject its transport.
void setTestChurchConfig({
  String timeZone = 'Asia/Taipei',
  bool calendar = false,
  bool photoImport = false,
}) {
  final previous = ChurchConfig.current;
  ChurchConfig.current = testChurchConfig(
    timeZone: timeZone,
    calendar: calendar,
    photoImport: photoImport,
  );
  GoogleCalendarConfig.configureForTesting(
    apiKey: calendar ? 'test-api-key' : '',
    calendarId: calendar ? 'test-calendar' : '',
  );
  addTearDown(() {
    ChurchConfig.current = previous;
    GoogleCalendarConfig.resetForTesting();
  });
}
