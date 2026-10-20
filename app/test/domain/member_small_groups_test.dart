import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/firebase/codec.dart';
import 'package:martha/domain/export.dart';
import 'package:martha/domain/models.dart';

void main() {
  test('member small groups stay with their zone when duties are edited', () {
    final member = memberFromJson('mei', {
      'name': '李美玉',
      'groups': ['roster-editors'],
      'zones': [
        {
          'serviceType': 'sunday',
          'duties': ['司琴'],
          'smallGroups': ['喜樂小組', '恩典小組'],
        },
        {'serviceType': 'youth', 'duties': []},
      ],
    });
    final edited = member.withDuty('sunday', '招待');
    expect(memberToJson(edited)['zones'], [
      {
        'serviceType': 'sunday',
        'duties': ['司琴', '招待'],
        'smallGroups': ['喜樂小組', '恩典小組'],
      },
      {'serviceType': 'youth', 'duties': [], 'smallGroups': []},
    ]);
    expect(memberToJson(edited)['groups'], ['roster-editors'], reason: 'small groups are not permission groups');
  });

  test('church export preserves small groups for signed-in and pending members', () {
    const zones = [
      Zone(serviceType: 'sunday', duties: ['招待'], smallGroups: ['喜樂小組']),
    ];
    final json = exportJson(
      const ChurchSnapshot(
        church: Church(id: 'grace', name: '恩典堂'),
        services: ServiceSettings(services: []),
        members: [Member(uid: 'mei', name: '李美玉', zones: zones)],
        pendingMembers: [PendingMember(id: 'old-hao', name: '陳志豪', zones: zones)],
      ),
      DateTime.utc(2026, 10, 1),
    );
    const expected = [
      {
        'serviceType': 'sunday',
        'duties': ['招待'],
        'smallGroups': ['喜樂小組'],
      },
    ];
    expect(((json['members'] as List).single as Map)['zones'], expected);
    expect(((json['pendingMembers'] as List).single as Map)['zones'], expected);
  });

  test('zone small groups participate in equality and can be cleared independently of duties', () {
    const zone = Zone(serviceType: 'sunday', duties: ['司琴'], smallGroups: ['喜樂小組']);
    const same = Zone(serviceType: 'sunday', duties: ['司琴'], smallGroups: ['喜樂小組']);
    expect(zone, same);
    expect(zone.hashCode, same.hashCode);
    final cleared = zone.copyWith(smallGroups: []);
    expect(cleared.smallGroups, isEmpty);
    expect(cleared.duties, ['司琴']);
    expect(cleared, isNot(zone));
    expect(const Zone(serviceType: 'sunday').smallGroups, isEmpty);
  });

  test("a 小組長's 身分 an older app saved without it comes back from leadSmallGroups (#85)", () {
    final lead = memberFromJson('hao', {
      'name': '陳志豪',
      'role': 'staff',
      'identities': [
        {'kind': 'lead', 'service': 'sunday'},
      ],
      'leadSmallGroups': ['joy'],
    });
    expect(lead.identities, const [ServiceLead('sunday'), SmallGroupLead('joy')]);
    expect(memberToJson(lead)['leadSmallGroups'], ['joy'], reason: 'the next save keeps it');
    // An admin with none stored stays one.
    final admin = memberFromJson('pastor', {
      'name': '王牧師',
      'role': 'admin',
      'leadSmallGroups': ['joy'],
    });
    expect(admin.identities, const [AdminIdentity(), SmallGroupLead('joy')]);
    expect(admin.isAdmin, isTrue);
  });
}
