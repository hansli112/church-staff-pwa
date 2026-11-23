import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';

CalendarEvent event({String? colorId}) =>
    CalendarEvent(title: '同工會', start: DateTime(2026, 10, 9, 19), end: DateTime(2026, 10, 9, 21), colorId: colorId);

void main() {
  test("Google's eleven event colors show as the nearest of the six, 石墨灰 and unknown ones grey", () {
    const shown = {
      '1': 5, '2': 3, '3': 5, '4': 0, '5': 2, '6': 1, //
      '7': 4, '8': null, '9': 4, '10': 3, '11': 0, '24': null,
    };
    for (final MapEntry(:key, :value) in shown.entries) {
      expect(event(colorId: key).color, value, reason: key);
    }
    expect(event().color, isNull);
  });

  test("each of the six picked is one of Google's, shown as that one again", () {
    for (var c = 0; c < 6; c++) {
      expect(event().withColor(c).color, c);
    }
    expect(event().withColor(3).colorId, '10', reason: '羅勒綠');
  });

  test("picking the color it shows in already keeps Google's shade; grey takes it off", () {
    expect(event(colorId: '2').withColor(3).colorId, '2');
    expect(event(colorId: '2').withColor(null).colorId, isNull);
    expect(event(colorId: '8').withColor(null).colorId, '8', reason: '石墨灰 already shows grey');
  });
}
