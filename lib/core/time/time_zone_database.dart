import 'package:timezone/data/latest.dart' as database;
import 'package:timezone/timezone.dart' as tz;

bool _initialized = false;

tz.Location timeZoneLocation(String name) {
  if (name == 'UTC' || name == 'Etc/UTC') return tz.UTC;
  if (!_initialized) {
    database.initializeTimeZones();
    _initialized = true;
  }
  return tz.getLocation(name);
}
