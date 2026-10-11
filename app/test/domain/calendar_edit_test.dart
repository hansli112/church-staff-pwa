import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';

void main() {
  test('copyWith changes or clears description while unrelated edits retain it', () {
    final event = CalendarEvent(
      id: 'meeting',
      title: '同工會',
      start: DateTime(2026, 10, 10, 19),
      end: DateTime(2026, 10, 10, 21),
      description: '帶服事表',
    );
    expect(event.copyWith(title: '禱告會').description, '帶服事表');
    expect(event.copyWith(description: '帶聖經').description, '帶聖經');
    expect(event.copyWith(description: '').description, '');
  });
}
