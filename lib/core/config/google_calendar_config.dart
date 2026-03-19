class GoogleCalendarConfig {
  static const String apiKey =
      String.fromEnvironment('GOOGLE_CALENDAR_API_KEY');
  static const String calendarId =
      String.fromEnvironment('GOOGLE_CALENDAR_ID');
  static const String timeZone = 'Asia/Taipei';
}
