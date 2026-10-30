import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';

void main() {
  test('merging a pending member preserves and unions per-zone small groups without changing permissions', () async {
    final b = MemoryBackend(clock: () => DateTime.utc(2026, 10, 1));
    b.addChurch('恩典堂', id: 'grace');
    b.auth.signInAs('admin@example.com', uid: 'admin');
    b.addMember('grace', const Member(uid: 'admin', name: '王牧師', role: Role.admin));
    b.addMember(
      'grace',
      const Member(
        uid: 'mei',
        name: '李美玉',
        zones: [
          Zone(serviceType: 'sunday', duties: ['司琴'], smallGroups: ['喜樂小組']),
        ],
      ),
    );
    b.pendingMembers['grace'] = {
      'old-mei': const PendingMember(
        id: 'old-mei',
        name: '李美玉',
        zones: [
          Zone(serviceType: 'sunday', duties: ['招待'], smallGroups: ['喜樂小組', '恩典小組']),
          Zone(serviceType: 'youth', smallGroups: ['青年小組']),
        ],
      ),
    };
    final data = b.church('grace');
    await data.mergePending('old-mei', 'mei');
    final member = (await data.export.members()).singleWhere((m) => m.uid == 'mei');
    expect(member.zones, const [
      Zone(serviceType: 'sunday', duties: ['司琴', '招待'], smallGroups: ['喜樂小組', '恩典小組']),
      Zone(serviceType: 'youth', smallGroups: ['青年小組']),
    ]);
    expect(member.groups, isEmpty);
    expect(await data.export.pendingMembers(), isEmpty);
  });

  test('claiming pending member data preserves small groups for new and existing membership', () async {
    final b = MemoryBackend(clock: () => DateTime.utc(2026, 10, 1));
    b.addChurch('恩典堂', id: 'grace');
    b.addChurch('青年堂', id: 'youth');
    b.auth.signInAs('mei@example.com', uid: 'mei');
    b.addMember(
      'grace',
      const Member(
        uid: 'mei',
        name: '李美玉',
        zones: [
          Zone(serviceType: 'sunday', smallGroups: ['喜樂小組']),
        ],
      ),
    );
    const pending = PendingMember(
      id: 'old-mei',
      name: '李美玉',
      email: 'mei@example.com',
      zones: [
        Zone(serviceType: 'sunday', smallGroups: ['恩典小組']),
      ],
    );
    b.pendingMembers['grace'] = {'old-mei': pending};
    b.pendingMembers['youth'] = {'old-mei': pending};
    await b.cloud.claimPending('grace', 'old-mei');
    await b.cloud.claimPending('youth', 'old-mei');
    final existing = await b.church('grace').member('mei').first;
    final created = await b.church('youth').member('mei').first;
    expect(existing!.zones.single.smallGroups, ['喜樂小組', '恩典小組']);
    expect(created!.zones.single.smallGroups, ['恩典小組']);
    expect(existing.groups, isEmpty);
    expect(created.groups, isEmpty);
  });
}
