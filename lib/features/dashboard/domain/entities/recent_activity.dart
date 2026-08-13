import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 首頁「近期活動」列出的一筆行事曆活動。
///
/// 這裡刻意帶著結束時間。先前的版本只存開始時間，於是跨日活動整個壞掉：
/// 篩選條件是「開始時間還沒過」，所以 8/12–8/14 的特會在 8/13 當天會從首頁
/// 消失 —— 明明正在進行中。Google Calendar 的 `timeMin` 是用活動的**結束**
/// 時間過濾的，那筆資料本來就有回傳，是前端自己丟掉的。
@immutable
class RecentActivity {
  const RecentActivity({
    required this.startTime,
    required this.endTime,
    required this.isAllDay,
    required this.title,
  });

  final DateTime startTime;

  /// 活動結束時間，採 Google Calendar 的慣例：**不含**這個瞬間。
  /// 全日活動的 `end.date` 是隔天，一日活動的 end 是次日零點。
  final DateTime endTime;

  final bool isAllDay;
  final String title;

  DateTime get startDay => DateUtils.dateOnly(startTime);

  /// 活動實際涵蓋的最後一天。
  ///
  /// 因為 [endTime] 是排他的，直接 dateOnly 會多算一天：8/12–8/14 的全日
  /// 活動，Google 給的 end.date 是 8/15。減一微秒再取日期才會落在 8/14。
  /// 行事曆畫面的 CalendarEvent.endDay 用的是同一套算法，兩邊要一致，
  /// 否則同一筆活動在兩個畫面上的天數會對不起來。
  DateTime get endDay {
    final normalizedEnd = endTime.isBefore(startTime) ? startTime : endTime;
    final adjusted = normalizedEnd.subtract(const Duration(microseconds: 1));
    final endDayOnly = DateUtils.dateOnly(adjusted);
    return endDayOnly.isBefore(startDay) ? startDay : endDayOnly;
  }

  bool get spansMultipleDays => endDay.isAfter(startDay);

  /// [now] 當下這筆活動是否仍未結束（包含正在進行中）。
  ///
  /// 全日活動以「天」為單位判斷：只要今天還沒超過最後一天就算數，不會因為
  /// 現在是下午三點就把今天的全日活動視為過去式。
  bool isCurrentOrUpcoming(DateTime now) {
    if (isAllDay) return !endDay.isBefore(DateUtils.dateOnly(now));
    return endTime.isAfter(now);
  }

  bool isOngoing(DateTime now) {
    if (isAllDay) {
      final today = DateUtils.dateOnly(now);
      return !today.isBefore(startDay) && !today.isAfter(endDay);
    }
    return !startTime.isAfter(now) && endTime.isAfter(now);
  }

  Map<String, dynamic> toJson() => {
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'isAllDay': isAllDay,
    'title': title,
  };

  /// 舊版快取沒有 endTime。真的讀到舊資料時退化成「當天結束」，寧可少顯示
  /// 一天也不要憑空生出一個不存在的區間；快取 key 已經升版，正常情況下走
  /// 不到這條路。
  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    final start = DateTime.parse(json['startTime'] as String).toLocal();
    final endRaw = json['endTime'];
    return RecentActivity(
      startTime: start,
      endTime: endRaw is String
          ? DateTime.parse(endRaw).toLocal()
          : start.add(const Duration(minutes: 1)),
      isAllDay: json['isAllDay'] as bool? ?? false,
      title: json['title'] as String,
    );
  }
}

/// 篩掉已結束的活動、依開始時間排序，取前 [limit] 筆。
///
/// 進行中的活動會排在最前面（它的開始時間最早），這是刻意的：正在辦的活動
/// 比還沒到的更該被看見。
List<RecentActivity> selectRecentActivities(
  List<RecentActivity> activities, {
  required DateTime now,
  required int limit,
}) {
  final upcoming =
      activities.where((activity) => activity.isCurrentOrUpcoming(now)).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
  if (upcoming.length <= limit) return upcoming;
  return upcoming.take(limit).toList();
}

final _monthDay = DateFormat('MM/dd', 'zh_TW');
final _monthDayWeekday = DateFormat('MM/dd (EEEEE)', 'zh_TW');
final _monthDayWeekdayTime = DateFormat('MM/dd (EEEEE) HH:mm', 'zh_TW');

/// 首頁那一欄要顯示的日期文字。
///
/// 版面限制：這串字擠在 `Expanded(flex: 2)` 裡、單行、超出就 ellipsis ——
/// 也就是說太長不會報錯，只會被默默截掉。所以跨日的格式刻意不帶星期，
/// 「08/12–08/14」比原本最長的「08/12 (三) 15:30」還短，欄寬不會被撐爆。
/// recent_activity_test.dart 有一條測試專門盯住這個寬度上限。
String formatRecentActivityDate(RecentActivity activity) {
  if (activity.spansMultipleDays) {
    return '${_monthDay.format(activity.startDay)}'
        '–${_monthDay.format(activity.endDay)}';
  }
  return activity.isAllDay
      ? _monthDayWeekday.format(activity.startTime)
      : _monthDayWeekdayTime.format(activity.startTime);
}
