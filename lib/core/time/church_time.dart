import 'package:timezone/timezone.dart' as tz;

import '../config/church_config.dart';
import 'time_zone_database.dart';

/// 時間點使用教會時區；只有日期的值使用 UTC 年月日，避免裝置時區及 DST
/// 讓加七天變成不同的日子。日期值不是活動開始的 UTC 時間點。
abstract final class ChurchTime {
  static String get timeZone => ChurchConfig.current.timeZone;

  static tz.TZDateTime now() => inZone(DateTime.now());

  static tz.TZDateTime inZone(DateTime instant) =>
      tz.TZDateTime.from(instant, timeZoneLocation(timeZone));

  static DateTime today() => dateOnly(now());

  static DateTime dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  /// 行事曆與首頁共用快取語意：全天存日期，有時間的活動存時間點。
  static DateTime parseEventTime(String value, {required bool isAllDay}) {
    final parsed = DateTime.parse(value);
    return isAllDay ? dateOnly(parsed) : inZone(parsed);
  }

  static DateTime eventInstant(DateTime value, {required bool isAllDay}) =>
      isAllDay ? atDate(value) : value;

  static tz.TZDateTime atDate(DateTime date) => tz.TZDateTime(
    timeZoneLocation(timeZone),
    date.year,
    date.month,
    date.day,
  );

  static tz.TZDateTime atTime(DateTime date, int hour, int minute) {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw const FormatException('無效的時間');
    }
    final result = tz.TZDateTime(
      timeZoneLocation(timeZone),
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    );
    if (result.year != date.year ||
        result.month != date.month ||
        result.day != date.day ||
        result.hour != hour ||
        result.minute != minute) {
      throw const FormatException('這個時間因夏令時間切換而不存在，請選其他時間');
    }
    return result;
  }

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime parseDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('日期必須是 YYYY-MM-DD');
    }
    final parts = value.split('-').map(int.parse).toList();
    final date = DateTime.utc(parts[0], parts[1], parts[2]);
    if (dateKey(date) != value) throw const FormatException('無效的日期');
    return date;
  }
}
