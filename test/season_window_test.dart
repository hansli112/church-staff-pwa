import 'package:church_staff_pwa/features/dashboard/domain/season_window.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('早於季末兩週只看本季', () {
    final window = seasonWindow(DateTime.utc(2026, 9, 16));
    expect(window.start, DateTime.utc(2026, 7, 1));
    expect(window.end, DateTime.utc(2026, 9, 30));
    expect(window.includesNextQuarter, isFalse);
    expect(window.title, '本季服事');
  });

  test('季末最後兩週一併列出下一季', () {
    for (final day in [
      DateTime.utc(2026, 9, 17),
      DateTime.utc(2026, 9, 28),
      DateTime.utc(2026, 9, 30),
    ]) {
      final window = seasonWindow(day);
      expect(window.end, DateTime.utc(2026, 12, 31), reason: '$day');
      expect(window.title, '本季與下季服事');
      expect(window.emptyText, '本季與下季尚無排到服事');
    }
  });

  test('第四季末跨年到明年第一季', () {
    final window = seasonWindow(DateTime.utc(2026, 12, 20));
    expect(window.start, DateTime.utc(2026, 10, 1));
    expect(window.end, DateTime.utc(2027, 3, 31));
  });

  test('新的一季從第一天起只看本季', () {
    final window = seasonWindow(DateTime.utc(2026, 10, 1));
    expect(window.start, DateTime.utc(2026, 10, 1));
    expect(window.end, DateTime.utc(2026, 12, 31));
    expect(window.includesNextQuarter, isFalse);
  });
}
