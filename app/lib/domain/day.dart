/// A calendar date with no time or time zone: the day a service happens.
///
/// Stored as `YYYY-MM-DD` (the roster's `dateKey`). Arithmetic runs on UTC
/// dates so adding seven days never lands on a different day because of the
/// device's time zone or daylight saving.
class Day implements Comparable<Day> {
  Day(int year, int month, int day) : _utc = DateTime.utc(year, month, day);

  Day._(this._utc);

  /// Today on this device.
  factory Day.today([DateTime? now]) {
    final n = now ?? DateTime.now();
    return Day(n.year, n.month, n.day);
  }

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
