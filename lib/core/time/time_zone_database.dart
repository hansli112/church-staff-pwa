// 用 latest_all 而不是 latest：latest 少了 tzdata 只留作別名的時區
// （Europe/Amsterdam、Asia/Kuala_Lumpur、Asia/Calcutta…）。安裝精靈用 Node 的
// Intl 檢查時區，這些都會放行；App 不認得的話，網站會一直停在載入中。
import 'package:timezone/data/latest_all.dart' as database;
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
