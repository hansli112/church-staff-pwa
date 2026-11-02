import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';

final _groups = ChurchGroups(
  services: const ServiceSettings(
    services: [
      Service(id: 'sunday', name: '主日崇拜', weekday: 7),
      Service(id: 'old', name: '晨禱', weekday: 3, enabled: false),
    ],
  ),
  ministries: const MinistrySettings(
    ministries: [Ministry(id: 'worship', name: '敬拜團')],
  ),
  smallGroups: const [SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday')],
);

void main() {
  test('every group to pick from, with its name: services in use, 事工, 小組', () {
    expect(
      [for (final g in _groups.all) (g.group.key, g.name)],
      [
        ('service:sunday', '主日崇拜'),
        ('ministry:worship', '敬拜團'),
        ('small:joy', '喜樂小組'),
      ],
    );
  });

  test('a key is looked up with its name, a 小組 with the service it is in', () {
    final joy = _groups.byKey('small:joy')!;
    expect(joy.name, '喜樂小組');
    expect((joy.group as SmallGroup).service, 'sunday');
    expect(_groups.byKey('service:old')?.name, '晨禱', reason: 'not in use, still named');
    expect(_groups.byKey('small:gone'), isNull);
    expect(_groups.byKey(''), isNull, reason: "the church's");
  });

  test("a 小組's service's 負責人 manage it once it is resolved", () {
    const lead = Member(uid: 'u', name: 'u', identities: [ServiceLead('sunday')]);
    expect(lead.managesGroup(_groups.byKey('small:joy')!.group), isTrue);
    expect(lead.managesGroup(const SmallGroup('joy')), isFalse, reason: 'its service not known');
  });

  test('what someone leads, services, then 事工, then 小組', () {
    const me = Member(
      uid: 'u',
      name: 'u',
      identities: [SmallGroupLead('joy'), MinistryLead('worship'), ServiceLead('old'), ServiceLead('gone')],
    );
    expect([for (final g in _groups.ledBy(me)) g.name], ['晨禱', '敬拜團', '喜樂小組']);
  });

  test('a 事工 belongs to the one service its duties are in, or it was added on; else to none', () {
    expect(const Ministry(id: 'a', name: 'a', duties: [MinistryDuty('sunday', '司琴')]).service, 'sunday');
    expect(
      const Ministry(id: 'a', name: 'a', addedIn: 'youth').service,
      'youth',
      reason: 'no duties yet',
    );
    expect(
      const Ministry(id: 'a', name: 'a', addedIn: 'youth', duties: [MinistryDuty('sunday', '司琴')]).service,
      'sunday',
      reason: 'its duties say',
    );
    expect(
      const Ministry(id: 'a', name: 'a', duties: [MinistryDuty('sunday', '司琴'), MinistryDuty('youth', '司琴')]).service,
      isNull,
    );
    expect(
      const Ministry(id: 'a', name: 'a').service,
      isNull,
      reason: '多媒體, only for events',
    );
  });

  test("each service's own 敬拜團 is named with its service where they show together", () {
    final groups = ChurchGroups(
      services: const ServiceSettings(
        services: [
          Service(id: 'sunday', name: '主日崇拜', weekday: 7),
          Service(id: 'youth', name: '青年崇拜', weekday: 6),
        ],
      ),
      ministries: const MinistrySettings(
        ministries: [
          Ministry(id: 'a', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]),
          Ministry(id: 'b', name: '敬拜團', addedIn: 'youth'),
          Ministry(id: 'c', name: '音控組', duties: [MinistryDuty('sunday', '音控')]),
        ],
      ),
      smallGroups: const [],
    );
    expect(
      [for (final g in groups.all) g.name],
      ['主日崇拜', '青年崇拜', '主日崇拜 · 敬拜團', '青年崇拜 · 敬拜團', '音控組'],
    );
  });
}
