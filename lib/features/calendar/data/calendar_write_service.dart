import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../presentation/widgets/_calendar_models.dart';

/// A failure the user is meant to read. The message is already in Chinese —
/// either straight from the API or mapped from a transport failure — so callers
/// can put it in a SnackBar without further translation.
class CalendarWriteException implements Exception {
  final String message;
  const CalendarWriteException(this.message);

  @override
  String toString() => 'CalendarWriteException: $message';
}

typedef IdTokenProvider = Future<String?> Function();

/// What the form collected, in the terms a person entered it.
///
/// Notably [endDate] is **inclusive** — the day the user picked. Google's
/// exclusive `end.date` is none of the client's business; the server converts.
@immutable
class CalendarEventDraft {
  final String title;
  final bool allDay;
  final DateTime startDate;
  final DateTime endDate;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final String location;
  final String description;

  const CalendarEventDraft({
    required this.title,
    required this.allDay,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    this.location = '',
    this.description = '',
  });

  /// A blank draft for [day], defaulting to a timed evening event: church
  /// events almost always have a start and an end, and an all-day default made
  /// people turn the switch off before they could enter one.
  factory CalendarEventDraft.forDay(DateTime day) {
    final date = DateUtils.dateOnly(day);
    return CalendarEventDraft(
      title: '',
      allDay: false,
      startDate: date,
      endDate: date,
      startTime: const TimeOfDay(hour: 19, minute: 0),
      endTime: const TimeOfDay(hour: 21, minute: 0),
    );
  }

  /// Pre-fills the edit form from an existing event.
  ///
  /// For an all-day event [CalendarEvent.endDay] has already walked back
  /// Google's exclusive end, so the date shown is the one the user picked.
  ///
  /// A timed event must NOT use endDay: that walk-back subtracts a microsecond,
  /// so an event running 22:00 → 00:00 next day comes back as the *start* day
  /// paired with 00:00 — a negative range the form then refuses to save, making
  /// such events uneditable. The end date of a timed event is simply the
  /// calendar day its end instant falls on (clamped to the start day).
  factory CalendarEventDraft.fromEvent(CalendarEvent event) {
    final timedEndDate = DateUtils.dateOnly(event.endTime);
    return CalendarEventDraft(
      title: event.title,
      allDay: event.isAllDay,
      startDate: event.startDay,
      endDate: event.isAllDay
          ? event.endDay
          : (timedEndDate.isBefore(event.startDay)
                ? event.startDay
                : timedEndDate),
      startTime: TimeOfDay.fromDateTime(event.startTime),
      endTime: TimeOfDay.fromDateTime(event.endTime),
      location: event.location ?? '',
      description: event.description ?? '',
    );
  }

  CalendarEventDraft copyWith({
    String? title,
    bool? allDay,
    DateTime? startDate,
    DateTime? endDate,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    String? location,
    String? description,
  }) {
    return CalendarEventDraft(
      title: title ?? this.title,
      allDay: allDay ?? this.allDay,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      description: description ?? this.description,
    );
  }

  static String _pad(int value, [int width = 2]) =>
      value.toString().padLeft(width, '0');

  static String formatDate(DateTime date) =>
      '${_pad(date.year, 4)}-${_pad(date.month)}-${_pad(date.day)}';

  static String _formatDateTime(DateTime date, TimeOfDay time) =>
      '${formatDate(date)}T${_pad(time.hour)}:${_pad(time.minute)}';

  /// The request body. Wall-clock time with no offset on purpose: the server
  /// attaches `timeZone: Asia/Taipei`, so "19:00" means 19:00 in Taipei
  /// regardless of where the admin's device thinks it is.
  Map<String, dynamic> toJson() {
    return {
      'title': title.trim(),
      'allDay': allDay,
      'start': allDay
          ? formatDate(startDate)
          : _formatDateTime(startDate, startTime),
      'end': allDay ? formatDate(endDate) : _formatDateTime(endDate, endTime),
      'location': location.trim(),
      'description': description.trim(),
    };
  }

  /// Client-side validation, so an obvious mistake does not need a round trip.
  /// The server validates independently — this is convenience, not enforcement.
  String? validate() {
    if (title.trim().isEmpty) return '請填寫標題';
    if (allDay) {
      if (endDate.isBefore(startDate)) return '結束日期不能早於開始日期';
      return null;
    }
    final start = _formatDateTime(startDate, startTime);
    final end = _formatDateTime(endDate, endTime);
    if (end.compareTo(start) < 0) return '結束時間不能早於開始時間';
    return null;
  }
}

/// Writes to the church Google Calendar through the app's own /api endpoints.
///
/// The browser cannot write to Google Calendar directly — it reads with a public
/// API key, which is read-only, and putting a writable credential in the client
/// would hand it to every visitor. The endpoints are Cloudflare Pages Functions
/// deployed alongside the app, so they are same-origin: no CORS, no second host.
class CalendarWriteService {
  static const Duration _timeout = Duration(seconds: 20);

  final http.Client _client;
  final IdTokenProvider _idToken;
  final Uri _endpoint;

  CalendarWriteService({
    http.Client? client,
    IdTokenProvider? idToken,
    Uri? endpoint,
  }) : _client = client ?? http.Client(),
       _idToken = idToken ?? _firebaseIdToken,
       _endpoint = endpoint ?? Uri.base.resolve('/api/calendar/events');

  static Future<String?> _firebaseIdToken() =>
      FirebaseAuth.instance.currentUser?.getIdToken() ?? Future.value(null);

  Future<CalendarEvent> create(CalendarEventDraft draft) async {
    final response = await _send('POST', _endpoint, body: draft.toJson());
    return _parseEvent(response);
  }

  Future<CalendarEvent> update(String eventId, CalendarEventDraft draft) async {
    final response = await _send(
      'PATCH',
      _eventUri(eventId),
      body: draft.toJson(),
    );
    return _parseEvent(response);
  }

  Future<void> delete(String eventId) async {
    await _send('DELETE', _eventUri(eventId));
  }

  /// Appends the id as a path *segment* rather than splicing it into the path
  /// string, so an id that needs escaping is encoded exactly once and cannot
  /// smuggle in an extra path separator.
  Uri _eventUri(String eventId) =>
      _endpoint.replace(pathSegments: [..._endpoint.pathSegments, eventId]);

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
  }) async {
    final token = await _idToken();
    if (token == null || token.isEmpty) {
      throw const CalendarWriteException('請先登入');
    }

    final request = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw const CalendarWriteException('操作逾時，請稍後再試');
    } catch (_) {
      // Offline is the common case here, and a write is not something to queue
      // silently — an event that appears an hour later is worse than a refusal.
      throw const CalendarWriteException('連線失敗，請檢查網路後再試一次');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw CalendarWriteException(_errorMessage(response));
  }

  /// Prefers the message the API wrote; falls back only when there is not one,
  /// which is what happens if something in front of the function (Cloudflare,
  /// a stale service worker) answers instead.
  String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final message = decoded['error'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } catch (_) {
      // Fall through to the status-based message.
    }
    return switch (response.statusCode) {
      401 => '請重新登入後再試一次',
      403 => '沒有權限執行此操作',
      404 => '這個活動已經不存在了',
      >= 500 => '伺服器忙碌中，請稍後再試',
      _ => '操作失敗，請稍後再試',
    };
  }

  CalendarEvent _parseEvent(http.Response response) {
    final CalendarEvent? event;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      event = calendarEventFromGoogleItem(decoded as Map<String, dynamic>);
    } catch (_) {
      throw const CalendarWriteException('已送出，但回應看不懂，請重新整理確認');
    }
    if (event == null) {
      throw const CalendarWriteException('已送出，但回應看不懂，請重新整理確認');
    }
    return event;
  }
}
