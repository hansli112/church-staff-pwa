import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

Day _nov(int d) => Day(2026, 11, d);

void main() {
  test('a day, or a stretch either way round, covers its days', () {
    final days = const UnavailableDays().add(_nov(16), _nov(16)).add(_nov(25), _nov(20), note: '出國');
    expect(days.spans, [UnavailableSpan(_nov(16), _nov(16)), UnavailableSpan(_nov(20), _nov(25), note: '出國')]);
    expect(days.on(_nov(22))?.note, '出國');
    expect(days.on(_nov(17)), isNull);
  });

  test('days next to or over a stretch join it, keeping what it says', () {
    final days = const UnavailableDays()
        .add(_nov(20), _nov(25), note: '出國')
        .add(_nov(26), _nov(26))
        .add(_nov(18), _nov(19))
        .add(_nov(10), _nov(10));
    expect(days.spans, [UnavailableSpan(_nov(10), _nov(10)), UnavailableSpan(_nov(18), _nov(26), note: '出國')]);
    expect(days.add(_nov(11), _nov(17)).spans, [UnavailableSpan(_nov(10), _nov(26), note: '出國')]);
    expect(days.add(_nov(24), _nov(27), note: '探親').spans.last, UnavailableSpan(_nov(18), _nov(27), note: '探親'));
  });

  test('taking a day out of a stretch splits it', () {
    final days = const UnavailableDays().add(_nov(20), _nov(25), note: '出國');
    expect(days.without(_nov(22)).spans, [
      UnavailableSpan(_nov(20), _nov(21), note: '出國'),
      UnavailableSpan(_nov(23), _nov(25), note: '出國'),
    ]);
    expect(days.without(_nov(20)).spans, [UnavailableSpan(_nov(21), _nov(25), note: '出國')]);
    expect(days.without(_nov(26)), days);
    expect(const UnavailableDays().add(_nov(3), _nov(3)).without(_nov(3)).isEmpty, isTrue);
  });

  test('taking days out, either way round, splits or drops each stretch they cross', () {
    final days = const UnavailableDays().add(_nov(3), _nov(5)).add(_nov(10), _nov(20), note: '出國');
    expect(days.without(_nov(15), _nov(4)).spans, [
      UnavailableSpan(_nov(3), _nov(3)),
      UnavailableSpan(_nov(16), _nov(20), note: '出國'),
    ]);
    expect(days.without(_nov(12), _nov(13)).spans, [
      UnavailableSpan(_nov(3), _nov(5)),
      UnavailableSpan(_nov(10), _nov(11), note: '出國'),
      UnavailableSpan(_nov(14), _nov(20), note: '出國'),
    ]);
    expect(days.without(_nov(1), _nov(30)).isEmpty, isTrue);
  });

  test('a stretch is noted or taken out whole', () {
    final days = const UnavailableDays().add(_nov(20), _nov(25)).add(_nov(3), _nov(3));
    final trip = days.spans.last;
    expect(days.noted(trip, ' 出國 ').on(_nov(21))?.note, '出國');
    expect(days.remove(trip).spans, [UnavailableSpan(_nov(3), _nov(3))]);
  });

  test('from today on, stretches already over are gone; one under way stays', () {
    final days = const UnavailableDays().add(_nov(3), _nov(5)).add(_nov(9), _nov(12)).add(_nov(20), _nov(20));
    expect(days.since(_nov(10)).spans, [UnavailableSpan(_nov(9), _nov(12)), UnavailableSpan(_nov(20), _nov(20))]);
  });

  test("who cannot serve on a roster's days, an event's over several", () {
    final everyone = {
      'mei': const UnavailableDays().add(_nov(20), _nov(25), note: '出國'),
      'hao': const UnavailableDays().add(_nov(15), _nov(15)),
    };
    expect(unavailableOn(Roster(type: 'sunday', day: _nov(22)), everyone), {
      'mei': UnavailableSpan(_nov(20), _nov(25), note: '出國'),
    });
    expect(unavailableOn(Roster(type: 'sunday', day: _nov(29)), everyone), isEmpty);
    final retreat = Roster(
      type: '',
      day: _nov(14),
      forEvent: RosterEvent(eventId: 'e1', title: '退修會', lastDay: _nov(16)),
    );
    expect(unavailableOn(retreat, everyone).keys, ['hao']);
  });
}
