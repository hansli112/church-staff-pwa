import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/service_changes.dart';

const _sunday = Service(
  id: 'sunday',
  name: '主日崇拜',
  weekdays: [DateTime.sunday],
  duties: ['司會', '司琴', '招待'],
  events: [
    EventTag(name: '聖餐', color: 0),
    EventTag(name: '浸禮', color: 4),
  ],
  manyDuties: ['招待'],
);

void main() {
  group('duties', () {
    test('one added goes last; one it has already leaves it as it is', () {
      expect(_sunday.withDuty('音控').duties, ['司會', '司琴', '招待', '音控']);
      expect(_sunday.withDuty('司琴'), _sunday);
    });

    test('one taken off goes from 多人服事 too', () {
      final next = _sunday.withoutDuty('招待');
      expect(next.duties, ['司會', '司琴']);
      expect(next.manyDuties, isEmpty);
      expect(validServiceShape(next), isTrue);
    });

    test('one renamed keeps its place and its 多人服事', () {
      final next = _sunday.withDutyRenamed('招待', '接待');
      expect(next.duties, ['司會', '司琴', '接待']);
      expect(next.manyDuties, ['接待']);
      expect(validDutyRename(before: _sunday.duties, after: next.duties, from: '招待', to: '接待'), isTrue);
    });

    test('多人服事 set for one duty, the others as they stood, in the duties\' order', () {
      expect(_sunday.withMany('司會', true, now: const ['招待']).manyDuties, ['司會', '招待']);
      expect(_sunday.withMany('招待', false, now: const ['招待']).manyDuties, isEmpty);
    });
  });

  group('特別活動', () {
    test('one added goes last in the next color; one so named already leaves it', () {
      expect(_sunday.withEvent('愛宴').events.last, const EventTag(name: '愛宴', color: 2));
      expect(_sunday.withEvent('聖餐'), _sunday);
    });

    test('the colors go round after the sixth', () {
      var s = _sunday.copyWith(events: const []);
      for (final name in ['一', '二', '三', '四', '五', '六', '七']) {
        s = s.withEvent(name);
      }
      expect(s.events.last.color, 0);
      expect(validServiceShape(s), isTrue);
    });

    test('one renamed keeps its color and place; one recolored keeps its name', () {
      expect(_sunday.withEventRenamed('聖餐', '主餐').events.first, const EventTag(name: '主餐', color: 0));
      expect(_sunday.withEventColor('浸禮', 1).events.last, const EventTag(name: '浸禮', color: 1));
    });

    test('one taken off', () {
      expect(_sunday.withoutEvent('聖餐').events, const [EventTag(name: '浸禮', color: 4)]);
    });
  });
}
