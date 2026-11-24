/// A calendar date with no time or time zone: the day a service happens.
///
/// Stored as `YYYY-MM-DD` (the roster's `dateKey`). Arithmetic runs on UTC
/// dates so adding seven days never lands on a different day because of the
/// device's time zone or daylight saving.
class Day implements Comparable<Day> {
  Day(int year, int month, int day) : _utc = DateTime.utc(year, month, day);

  Day._(this._utc);

  /// Parses `YYYY-MM-DD`. Throws [FormatException] on anything else,
  /// including dates that do not exist such as 2026-02-30.
  factory Day.parse(String key) {
    final match = _pattern.firstMatch(key);
    if (match == null) throw FormatException('Not a YYYY-MM-DD date', key);
    final day = Day(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
    if (day.key != key) throw FormatException('No such date', key);
    return day;
  }

  static Day? tryParse(String? key) {
    if (key == null) return null;
    try {
      return Day.parse(key);
    } on FormatException {
      return null;
    }
  }

  static final _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final DateTime _utc;

  /// Its midnight as wall time: the fields in a UTC [DateTime], as
  /// [CalendarEvent.start] holds them, for date formats and pickers.
  DateTime get midnight => _utc;

  int get year => _utc.year;
  int get month => _utc.month;
  int get day => _utc.day;

  /// 1 = Monday … 7 = Sunday, as [DateTime.weekday].
  int get weekday => _utc.weekday;

  String get key =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  Day addDays(int days) => Day._(_utc.add(Duration(days: days)));

  /// The Monday of this day's week.
  Day get weekStart => addDays(-(weekday - DateTime.monday));

  /// The first day of this day's month.
  Day get firstOfMonth => Day(year, month, 1);

  /// The last day of this day's month.
  Day get lastOfMonth => Day(year, month + 1, 1).addDays(-1);

  /// The first day on or after this one that falls on [weekday].
  Day nextOnOrAfter(int weekday) => addDays((weekday - this.weekday + 7) % 7);

  int daysUntil(Day other) => other._utc.difference(_utc).inDays;

  bool isBefore(Day other) => _utc.isBefore(other._utc);
  bool isAfter(Day other) => _utc.isAfter(other._utc);

  @override
  int compareTo(Day other) => _utc.compareTo(other._utc);

  @override
  bool operator ==(Object other) => other is Day && other._utc == _utc;

  @override
  int get hashCode => _utc.hashCode;

  @override
  String toString() => key;
}

/// How many months from [month] (its first day) through December of the
/// year after [today]'s: how far ahead 安排服事, 不能服事的日子 and asking
/// for them go, so that late in the year all of next year is there.
int monthsThroughNextYear(Day month, {required Day today}) => (today.year + 1 - month.year) * 12 + 12 - month.month + 1;

/// Which weekday of its month [day] is: 1 for the first … 5 for a fifth.
int weekOfMonth(Day day) => (day.day - 1) ~/ 7 + 1;

/// Which weeks something meets on its weekday: every one (1), every other
/// (2) from [startsOn], a day it meets; or [monthWeeks] of each month.
typedef MeetingWeeks = ({int every, Day? startsOn, List<int> monthWeeks});

/// Whether [day], on its weekday, is one of [weeks].
bool onMeetingWeeks(MeetingWeeks weeks, Day day) {
  if (weeks.monthWeeks.isNotEmpty) return weeks.monthWeeks.contains(weekOfMonth(day));
  final start = weeks.startsOn;
  if (weeks.every == 2 && start != null) return (start.daysUntil(day) ~/ 7).isEven;
  return true;
}
