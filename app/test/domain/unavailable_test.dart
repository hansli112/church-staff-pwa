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

  test("the days of a service's one cannot serve on, each with its reason; a day with no meeting left out", () {
    final mei = const UnavailableDays().add(_nov(20), _nov(25), note: '出國').add(_nov(8), _nov(8));
    final days = [
      for (final d in [1, 8, 15, 22, 29]) Roster(type: 'sunday', day: _nov(d), noService: d == 15),
    ];
    expect(unavailableAmong(mei, days), [(day: _nov(8), note: ''), (day: _nov(22), note: '出國')]);
    expect(unavailableAmong(const UnavailableDays().add(_nov(15), _nov(15)), days), isEmpty, reason: '沒有聚會');
    expect(unavailableAmong(const UnavailableDays(), days), isEmpty);
  });

  test('an answer since the ask: sent, or the days changed, whichever is later', () {
    final at = DateTime.utc(2026, 11, 20, 9);
    expect(answeredAt(null, null), isNull);
    expect(answeredAt(at, null), at);
    expect(answeredAt(null, at), at);
    expect(answeredAt(at, at.add(const Duration(hours: 1))), at.add(const Duration(hours: 1)));
    expect(answeredAt(at.add(const Duration(hours: 1)), at), at.add(const Duration(hours: 1)));
  });

  test('asked of me: sent only from the moment asked on; waiting until the last month asked is over', () {
    final at = DateTime.utc(2026, 11, 20, 9);
    final asked = UnavailableAsked(at: at, from: Day(2026, 12, 1), to: Day(2027, 1, 1));
    expect(asked.waitingOn(_nov(23)), isTrue);
    expect(UnavailableAsked(at: at, from: asked.from, to: asked.to, sentAt: at).sent, isTrue);
    final before = UnavailableAsked(
      at: at,
      from: asked.from,
      to: asked.to,
      sentAt: at.subtract(const Duration(seconds: 1)),
    );
    expect(before.sent, isFalse, reason: 'sent for an earlier ask');
    expect(asked.waitingOn(Day(2027, 1, 31)), isTrue);
    expect(asked.waitingOn(Day(2027, 2, 1)), isFalse);
  });

  test('a round waits on whom it told and has not sent, in the order told', () {
    final round = UnavailableRound(
      at: DateTime.utc(2026, 11, 20),
      from: Day(2026, 12, 1),
      to: Day(2026, 12, 1),
      told: const ['mei', 'hao', 'yu'],
      sent: const {'hao'},
    );
    expect(round.waiting, ['mei', 'yu']);
    expect(round.currentOn(Day(2026, 12, 31)), isTrue);
    expect(round.currentOn(Day(2027, 1, 1)), isFalse);
  });

  test("the weekdays dimmed: those none of one's services meet on; none for one in no service", () {
    const services = [
      Service(id: 'sunday', name: '主日崇拜', weekdays: [7]),
      Service(id: 'dawn', name: '晨更', weekdays: [1, 2, 3, 4, 5]),
      Service(id: 'prayer', name: '禱告會', weekdays: [3]),
    ];
    const mei = Member(
      uid: 'mei',
      name: '李美玉',
      zones: [
        Zone(serviceType: 'sunday'),
        Zone(serviceType: 'prayer'),
      ],
    );
    expect(dimmedWeekdays(mei, services), {1, 2, 4, 5, 6});
    expect(dimmedWeekdays(const Member(uid: 'hao', name: '陳志豪'), services), isEmpty);
  });
}
