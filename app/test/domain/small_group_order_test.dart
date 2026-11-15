import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';

void main() {
  SmallGroupDetails g(String id, String service, {int? order}) =>
      SmallGroupDetails(id: id, name: id, service: service, order: order);

  test("the church's 小組 by service, as its services are listed, then as dragged; never placed last", () {
    final list = [
      g('b1', 'youth', order: 0),
      g('a-new', 'sunday'),
      g('a2', 'sunday', order: 1),
      g('a1', 'sunday', order: 0),
      g('b2', 'youth', order: 1),
      g('gone', 'closed', order: 0),
    ];
    expect(
      [
        for (final x in list.inChurchOrder(['sunday', 'youth'])) x.id,
      ],
      ['a1', 'a2', 'a-new', 'b1', 'b2', 'gone'],
    );
  });

  test('回報人數 lists them by service, then by weekday, Sunday first; no 聚會時間 last; one day as dragged', () {
    SmallGroupDetails on(String id, String service, int? weekday, {int? order}) =>
        SmallGroupDetails(id: id, name: id, service: service, weekday: weekday, order: order);
    final list = [
      on('none', 'sunday', null, order: 0),
      on('fri-b', 'sunday', DateTime.friday, order: 2),
      on('fri-a', 'sunday', DateTime.friday, order: 1),
      on('mon', 'sunday', DateTime.monday, order: 3),
      on('youth-tue', 'youth', DateTime.tuesday),
      on('sun', 'sunday', DateTime.sunday, order: 4),
    ];
    expect(
      [
        for (final x in list.inMeetingOrder(['sunday', 'youth'])) x.id,
      ],
      ['sun', 'mon', 'fri-a', 'fri-b', 'none', 'youth-tue'],
    );
  });
}
