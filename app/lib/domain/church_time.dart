import 'day.dart';

/// The church clock used by the backend, independent of the device's zone.
const churchOffset = Duration(hours: 8);

/// Civil church fields, held in a UTC DateTime so DST cannot move them.
DateTime churchCivilTime(DateTime fields) => DateTime.utc(
  fields.year,
  fields.month,
  fields.day,
  fields.hour,
  fields.minute,
  fields.second,
  fields.millisecond,
  fields.microsecond,
);

/// An actual instant as the church's calendar fields.
DateTime churchTime(DateTime instant) => instant.toUtc().add(churchOffset);

/// The actual instant of civil church fields.
DateTime churchInstant(DateTime civil) => churchCivilTime(civil).subtract(churchOffset);

Day churchToday(DateTime instant) {
  final day = churchTime(instant);
  return Day(day.year, day.month, day.day);
}
