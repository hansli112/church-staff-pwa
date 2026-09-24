import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/church_config.dart';
import '../../../core/config/google_calendar_config.dart';
import '../../../core/time/church_time.dart';
import '../domain/entities/calendar_event.dart';
import 'google_calendar_event.dart';

/// Google answered, but not with a listing. The message is already in Chinese
/// and ready for the month header.
class CalendarReadException implements Exception {
  final String message;
  const CalendarReadException(this.message);

  @override
  String toString() => 'CalendarReadException: $message';
}

/// Church midnight on the 1st through church midnight on the next 1st.
/// Construct each boundary separately: across DST a month is not a fixed
/// number of 24-hour days, and the viewer's device zone is irrelevant.
///
/// [timeMax] is exclusive on Google's side (it bounds the event *start*), so
/// the next month's midnight is the right edge as-is.
({DateTime timeMin, DateTime timeMax}) calendarMonthWindow(DateTime month) => (
  timeMin: ChurchTime.atDate(DateTime.utc(month.year, month.month, 1)).toUtc(),
  timeMax: ChurchTime.atDate(
    DateTime.utc(month.year, month.month + 1, 1),
  ).toUtc(),
);

/// Reads one month of the church calendar straight from Google with the public
/// API key. Read-only by design; writes go through [CalendarWriteService].
class GoogleCalendarMonthReader {
  static const Duration _timeout = Duration(seconds: 10);

  final http.Client? _client;
  final String _apiKey;
  final String _calendarId;

  /// [client] is the test seam. Left null in the app, where each request uses
  /// `http.get` exactly as before.
  GoogleCalendarMonthReader({
    http.Client? client,
    String? apiKey,
    String? calendarId,
  }) : _client = client,
       _apiKey = apiKey ?? GoogleCalendarConfig.apiKey,
       _calendarId = calendarId ?? GoogleCalendarConfig.calendarId;

  /// Throws [CalendarReadException] when Google rejects the request; anything
  /// else thrown (timeout, no network) means the listing never arrived.
  Future<List<CalendarEvent>> fetchMonth(DateTime month) async {
    if (!ChurchConfig.current.features.calendar ||
        _apiKey.trim().isEmpty ||
        _calendarId.trim().isEmpty) {
      return const [];
    }
    final window = calendarMonthWindow(month);
    final uri =
        Uri.https('www.googleapis.com', '', {
          'key': _apiKey,
          'singleEvents': 'true',
          'orderBy': 'startTime',
          'maxResults': '250',
          'timeMin': window.timeMin.toIso8601String(),
          'timeMax': window.timeMax.toIso8601String(),
          'timeZone': GoogleCalendarConfig.timeZone,
        }).replace(
          pathSegments: ['calendar', 'v3', 'calendars', _calendarId, 'events'],
        );

    final client = _client;
    final response = await (client == null ? http.get(uri) : client.get(uri))
        .timeout(_timeout);

    if (response.statusCode != 200) {
      String? message;
      try {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
        message =
            (errorBody['error'] as Map<String, dynamic>?)?['message']
                as String?;
      } catch (_) {}
      throw CalendarReadException(
        message == null || message.isEmpty
            ? '載入失敗（${response.statusCode}）'
            : '載入失敗（${response.statusCode}）：$message',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List<dynamic>? ?? [];
    final events = <CalendarEvent>[];

    for (var i = 0; i < items.length; i++) {
      try {
        final event = calendarEventFromGoogleItem(
          items[i] as Map<String, dynamic>,
          fallbackIndex: i,
        );
        if (event != null) events.add(event);
      } catch (e, st) {
        debugPrint('Skipping malformed calendar item #$i: $e');
        debugPrintStack(stackTrace: st);
      }
    }
    return events;
  }
}
