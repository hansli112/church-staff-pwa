import 'day.dart';

/// A church's time zone (#73). Today, the calendar's times and every time
/// shown go by the church's clock, wherever the phone is.
///
/// The same list as CHURCH_TIME_ZONES in functions/src/timeZones.ts, east
/// to west. Cities whose clocks always agree, like New York and Toronto,
/// list the US one first, so a phone in a zone not on the list but on the
/// same clock gets the US city ([forDevice]).
/// The app has no time zone database: each zone's clock changes are
/// written out here, and app/test/domain/church_time_test.dart holds them
/// to testdata/time_zones.json, which Node's database writes.
enum ChurchTimeZone {
  auckland('Pacific/Auckland', 12 * 60, _newZealand),
  sydney('Australia/Sydney', 10 * 60, _australia),
  melbourne('Australia/Melbourne', 10 * 60, _australia),
  tokyo('Asia/Tokyo', 9 * 60),
  seoul('Asia/Seoul', 9 * 60),
  taipei('Asia/Taipei', 8 * 60),
  hongKong('Asia/Hong_Kong', 8 * 60),
  singapore('Asia/Singapore', 8 * 60),
  kualaLumpur('Asia/Kuala_Lumpur', 8 * 60),
  london('Europe/London', 0, _europe),
  newYork('America/New_York', -5 * 60, _northAmerica),
  toronto('America/Toronto', -5 * 60, _northAmerica),
  chicago('America/Chicago', -6 * 60, _northAmerica),
  denver('America/Denver', -7 * 60, _northAmerica),
  losAngeles('America/Los_Angeles', -8 * 60, _northAmerica),
  vancouver('America/Vancouver', -8 * 60, _britishColumbia)
  ;

  const ChurchTimeZone(this.id, this._standard, [this._summer]);

  /// The IANA id the backend stores.
  final String id;

  /// Minutes ahead of UTC outside summer time.
  final int _standard;
  final _SummerTime? _summer;

  /// Where a church made before #73 is: they were all in UTC+8.
  static const fallback = taipei;

  /// The zone stored as [id]; a church without a known one is in [fallback].
  static ChurchTimeZone of(String? id) => byId(id) ?? fallback;

  /// The zone that is IANA zone [id], if it is one of these.
  static ChurchTimeZone? byId(String? id) => values.where((z) => z.id == id).firstOrNull;

  /// The zone for a phone in IANA zone [deviceId] whose clock is [offset]
  /// ahead of UTC at [now]: that zone if it is one of these; else the first
  /// on the same clock now, one in the same part of the world (`America/`,
  /// `Asia/`…) first, as the list is ordered (Shanghai gets Taipei); else
  /// the first whose standard time it is (Brisbane gets Sydney in summer);
  /// else [fallback]. A wrong one the church's admin changes.
  static ChurchTimeZone forDevice(String? deviceId, Duration offset, DateTime now) {
    final exact = byId(deviceId);
    if (exact != null) return exact;
    final area = deviceId?.split('/').first;
    ChurchTimeZone? pick(bool Function(ChurchTimeZone) fits) =>
        values.where((z) => fits(z) && z.id.split('/').first == area).firstOrNull ?? values.where(fits).firstOrNull;
    return pick((z) => z.offsetAt(now) == offset) ?? pick((z) => z._standard == offset.inMinutes) ?? fallback;
  }

  /// How far the church's clock is ahead of UTC at [instant].
  Duration offsetAt(DateTime instant) {
    final summer = _summer;
    if (summer == null) return Duration(minutes: _standard);
    // The changes are given in standard time, so compare in it.
    final standard = instant.toUtc().add(Duration(minutes: _standard));
    final stays = summer.stays;
    if (stays != null && !standard.isBefore(summer.start.on(stays))) return Duration(minutes: _standard + 60);
    final start = summer.start.on(standard.year);
    final end = summer.end.on(standard.year);
    final inSummer = start.isBefore(end)
        ? !standard.isBefore(start) && standard.isBefore(end)
        : !standard.isBefore(start) || standard.isBefore(end);
    return Duration(minutes: _standard + (inSummer ? 60 : 0));
  }

  /// [instant] as the church's clock reads it, in a UTC [DateTime].
  DateTime clock(DateTime instant) => instant.toUtc().add(offsetAt(instant));

  /// The instant the church's clock reads [wall] (its fields, in UTC). A
  /// time read twice as the clocks go back is the first; one skipped going
  /// forward lands as much later (functions/src/zones.ts `instantOf`).
  DateTime instantOf(DateTime wall) {
    final asUtc = churchCivilTime(wall);
    final before = offsetAt(asUtc.subtract(const Duration(days: 1)));
    final after = offsetAt(asUtc.add(const Duration(days: 1)));
    final fits = [
      for (final o in [before, after])
        if (offsetAt(asUtc.subtract(o)) == o) asUtc.subtract(o),
    ]..sort();
    return fits.firstOrNull ?? asUtc.subtract(before);
  }

  /// The church's day at [instant].
  Day today(DateTime instant) {
    final c = clock(instant);
    return Day(c.year, c.month, c.day);
  }
}

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

/// When summer time starts and ends, in standard time.
class _SummerTime {
  const _SummerTime(this.start, this.end, {this.stays});

  final _Change start;
  final _Change end;

  /// The year summer time starts and never ends.
  final int? stays;
}

/// A clock change: the [nth] Sunday of [month] (-1 the last), at [minute]
/// past midnight, standard time.
class _Change {
  const _Change(this.month, this.nth, this.minute);

  final int month;
  final int nth;
  final int minute;

  DateTime on(int year) {
    final DateTime day;
    if (nth > 0) {
      final first = DateTime.utc(year, month);
      day = first.add(Duration(days: (DateTime.sunday - first.weekday) % 7 + 7 * (nth - 1)));
    } else {
      final last = DateTime.utc(year, month + 1, 0);
      day = last.subtract(Duration(days: last.weekday % 7));
    }
    return day.add(Duration(minutes: minute));
  }
}

// From the second Sunday of March at 2:00 to the first of November at 2:00
// summer time (1:00 standard): the US and Canada.
const _northAmerica = _SummerTime(_Change(3, 2, 120), _Change(11, 1, 60));

// The same until British Columbia kept summer time all year from March 2026.
const _britishColumbia = _SummerTime(_Change(3, 2, 120), _Change(11, 1, 60), stays: 2026);

// From the last Sunday of March to the last of October, at 1:00 UTC.
const _europe = _SummerTime(_Change(3, -1, 60), _Change(10, -1, 60));

// From the first Sunday of October at 2:00 to the first of April at 3:00
// summer time (2:00 standard): New South Wales and Victoria.
const _australia = _SummerTime(_Change(10, 1, 120), _Change(4, 1, 120));

// From the last Sunday of September at 2:00 to the first of April at 3:00
// summer time.
const _newZealand = _SummerTime(_Change(9, -1, 120), _Change(4, 1, 120));
