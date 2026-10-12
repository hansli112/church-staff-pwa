@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/church_time.dart';
import 'package:martha/domain/day.dart';

// The app's own clock rules against Node's time zone database
// (testdata/time_zones.json, written by functions/test/zones.test.ts).

void main() {
  final data = jsonDecode(File('../testdata/time_zones.json').readAsStringSync()) as Map<String, dynamic>;
  final zones = (data['zones'] as List).cast<Map<String, dynamic>>();

  test('the same zones as the backend, in the same order', () {
    expect([for (final z in ChurchTimeZone.values) z.id], [for (final z in zones) z['id']]);
  });

  for (final z in zones) {
    test("${z['id']} changes its clock when the database does, and only then", () {
      final timeZone = ChurchTimeZone.of(z['id'] as String);
      var offset = z['offset'] as int;
      var from = DateTime.utc(2020);
      void steady(DateTime until) {
        // A change in between would show at one of these.
        for (var t = from; t.isBefore(until); t = t.add(const Duration(hours: 6))) {
          expect(timeZone.offsetAt(t).inMinutes, offset, reason: '$t');
        }
        expect(timeZone.offsetAt(until.subtract(const Duration(minutes: 1))).inMinutes, offset, reason: '$until');
      }

      for (final change in (z['changes'] as List).cast<List<dynamic>>()) {
        final at = DateTime.parse(change[0] as String);
        steady(at);
        offset = change[1] as int;
        from = at;
      }
      steady(DateTime.utc(2041));
    });
  }

  test('an unknown or missing zone is Taipei, as every church was', () {
    expect(ChurchTimeZone.of(null), ChurchTimeZone.taipei);
    expect(ChurchTimeZone.of('Mars/Olympus_Mons'), ChurchTimeZone.taipei);
    expect(ChurchTimeZone.of('America/Chicago'), ChurchTimeZone.chicago);
  });

  group("a new church's zone, from its maker's phone", () {
    final summer = DateTime.utc(2026, 7, 1);
    final winter = DateTime.utc(2026, 1, 15);
    const h = Duration(hours: 1);
    test('one of the list is itself', () {
      expect(ChurchTimeZone.forDevice('America/Denver', -h * 6, summer), ChurchTimeZone.denver);
      expect(ChurchTimeZone.forDevice('Asia/Kuala_Lumpur', h * 8, summer), ChurchTimeZone.kualaLumpur);
    });
    test('another is the first on the same clock, in its part of the world first', () {
      expect(ChurchTimeZone.forDevice('Asia/Shanghai', h * 8, summer), ChurchTimeZone.taipei);
      expect(ChurchTimeZone.forDevice('Australia/Perth', h * 8, summer), ChurchTimeZone.taipei);
      expect(ChurchTimeZone.forDevice('America/Phoenix', -h * 7, summer), ChurchTimeZone.losAngeles);
      expect(ChurchTimeZone.forDevice('America/Phoenix', -h * 7, winter), ChurchTimeZone.denver);
      expect(ChurchTimeZone.forDevice('Europe/Dublin', Duration.zero, winter), ChurchTimeZone.london);
    });
    test('else the first it is standard time for; else Taipei', () {
      // Brisbane keeps +10 while Sydney is on summer time.
      expect(ChurchTimeZone.forDevice('Australia/Brisbane', h * 10, winter), ChurchTimeZone.sydney);
      expect(ChurchTimeZone.forDevice('Asia/Kolkata', h * 5.5, summer), ChurchTimeZone.taipei);
      expect(ChurchTimeZone.forDevice(null, h * 8, summer), ChurchTimeZone.taipei);
      expect(ChurchTimeZone.forDevice(null, -h * 5, winter), ChurchTimeZone.newYork);
    });
  });

  test("the church's clock and day", () {
    final at = DateTime.utc(2026, 10, 19, 3, 59);
    expect(ChurchTimeZone.newYork.clock(at), DateTime.utc(2026, 10, 18, 23, 59));
    expect(ChurchTimeZone.newYork.today(at), Day(2026, 10, 18));
    expect(ChurchTimeZone.taipei.today(at), Day(2026, 10, 19));
  });

  test('a time on the clock, as the backend reads it', () {
    const la = ChurchTimeZone.losAngeles;
    expect(la.instantOf(DateTime.utc(2026, 10, 18, 10)), DateTime.utc(2026, 10, 18, 17));
    expect(ChurchTimeZone.taipei.instantOf(DateTime.utc(2026, 10, 19)), DateTime.utc(2026, 10, 18, 16));
    // Skipped going forward: an hour later. Read twice going back: the first.
    expect(la.clock(la.instantOf(DateTime.utc(2026, 3, 8, 2, 30))), DateTime.utc(2026, 3, 8, 3, 30));
    expect(la.instantOf(DateTime.utc(2026, 11, 1, 1, 30)), DateTime.utc(2026, 11, 1, 8, 30));
  });
}
