import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/firebase/codec.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';

void main() {
  test('claiming pending membership preserves its decoded notification opt-out and small groups', () async {
    final b = MemoryBackend(clock: () => DateTime.utc(2026, 10, 1));
    b.addChurch('恩典堂', id: 'grace');
    b.auth.signInAs('mei@example.com', uid: 'mei');
    b.pendingMembers['grace'] = {
      'old-mei': pendingMemberFromJson('old-mei', {
        'name': '李美玉',
        'email': 'mei@example.com',
        'notificationPrefs': {
          'muted': ['reminder', 'rosterChange'],
        },
        'zones': [
          {
            'serviceType': 'sunday',
            'duties': ['司琴'],
            'smallGroups': ['喜樂小組'],
          },
        ],
      }),
    };
    await b.cloud.claimPending('grace', 'old-mei');
    final member = await b.church('grace').member('mei').first;
    expect(member!.mutedNotifications, {NotificationKind.reminder, NotificationKind.rosterChange});
    expect(member.zones.single.smallGroups, ['喜樂小組']);
    expect(member.serves('sunday', '司琴'), isTrue);
  });

  test('claim and admin merge union pending opt-outs with current preferences and small groups', () async {
    final b = MemoryBackend(clock: () => DateTime.utc(2026, 10, 1));
    b.addChurch('恩典堂', id: 'grace');
    b.auth.signInAs('mei@example.com', uid: 'mei');
    b.addMember(
      'grace',
      const Member(
        uid: 'mei',
        name: '李美玉',
        mutedNotifications: {NotificationKind.memberLeft},
        zones: [
          Zone(serviceType: 'sunday', duties: ['司琴'], smallGroups: ['喜樂小組']),
        ],
      ),
    );
    b.pendingMembers['grace'] = {
      'old-mei': const PendingMember(
        id: 'old-mei',
        name: '李美玉',
        email: 'mei@example.com',
        mutedNotifications: {NotificationKind.reminder},
        zones: [
          Zone(serviceType: 'sunday', duties: ['招待'], smallGroups: ['恩典小組']),
        ],
      ),
      'another-mei': const PendingMember(
        id: 'another-mei',
        name: '李美玉',
        mutedNotifications: {NotificationKind.rosterChange},
        zones: [
          Zone(serviceType: 'youth', smallGroups: ['青年小組']),
        ],
      ),
    };
    await b.cloud.claimPending('grace', 'old-mei');
    final claimed = await b.church('grace').member('mei').first;
    expect(claimed!.mutedNotifications, {NotificationKind.memberLeft, NotificationKind.reminder});
    expect(claimed.zones.single.smallGroups, ['喜樂小組', '恩典小組']);
    expect(claimed.zones.single.duties, ['司琴', '招待']);

    b.auth.signInAs('admin@example.com', uid: 'admin');
    b.addMember('grace', const Member(uid: 'admin', name: '王牧師', role: Role.admin));
    await b.church('grace').mergePending('another-mei', 'mei');
    final merged = (await b.church('grace').allMembers()).singleWhere((m) => m.uid == 'mei');
    expect(merged.mutedNotifications, {
      NotificationKind.memberLeft,
      NotificationKind.reminder,
      NotificationKind.rosterChange,
    });
    expect(merged.zones.singleWhere((z) => z.serviceType == 'sunday').smallGroups, ['喜樂小組', '恩典小組']);
    expect(merged.zones.singleWhere((z) => z.serviceType == 'youth').smallGroups, ['青年小組']);
  });

  test('moving maps legacy reminder opt-out once for the chosen identity and pending members', () async {
    final b = MemoryBackend(clock: () => DateTime.utc(2026, 10, 1));
    b.auth.signInAs('pastor@example.com', uid: 'new-pastor');
    b.moveAnswer = const MovePreview(
      members: 3,
      rosters: 0,
      people: [
        MovePerson(id: 'old-pastor', name: '王牧師', email: 'pastor@example.com'),
        MovePerson(id: 'old-mei', name: '李美玉', email: 'mei@example.com'),
        MovePerson(id: 'old-hao', name: '陳志豪'),
      ],
    );
    final path = await b.cloud.uploadMoveFile(
      utf8.encode(
        jsonEncode({
          'format': 'church-staff-pwa-move',
          'version': 1,
          'users': [
            {
              'id': 'old-pastor',
              'data': {
                'role': 'leader',
                'zones': [
                  {
                    'serviceType': 'sunday',
                    'ministries': ['司會'],
                    'smallGroups': ['恩典小組'],
                  },
                ],
                'notificationPrefs': {
                  'weeklyRosterReminder': false,
                  'muted': ['memberLeft'],
                },
                'fcmTokens': ['legacy-pastor-token'],
              },
            },
            {
              'id': 'old-mei',
              'data': {
                'groups': ['roster-editors'],
                'zones': [
                  {
                    'serviceType': 'sunday',
                    'ministries': ['司琴'],
                    'smallGroups': ['喜樂小組'],
                  },
                ],
                'notificationPrefs': {
                  'weeklyRosterReminder': false,
                  'muted': ['rosterChange'],
                },
                'fcmTokens': ['legacy-mei-token'],
              },
            },
            {
              'id': 'old-hao',
              'data': {
                'notificationPrefs': {'weeklyRosterReminder': true},
              },
            },
          ],
        }),
      ),
    );
    expect((await b.cloud.movePreview(path)).members, 3);
    final cid = await b.cloud.moveCommit(path, churchName: '恩典堂', me: 'old-pastor');
    final data = b.church(cid);
    final admin = await data.member('new-pastor').first;
    expect(admin!.mutedNotifications, {NotificationKind.reminder, NotificationKind.memberLeft});
    expect(admin.role, Role.admin, reason: 'the chosen identity keeps the uploader’s admin access');
    expect(admin.zones.single.smallGroups, ['恩典小組']);
    final pending = await data.allPendingMembers();
    final mei = pending.singleWhere((p) => p.id == 'old-mei');
    expect(mei.mutedNotifications, {NotificationKind.reminder, NotificationKind.rosterChange});
    expect(mei.zones.single, const Zone(serviceType: 'sunday', duties: ['司琴'], smallGroups: ['喜樂小組']));
    expect(mei.groups, {Group.rosterEditors});
    expect(pending.singleWhere((p) => p.id == 'old-hao').mutedNotifications, isEmpty);

    b.auth.signInAs('mei@example.com', uid: 'new-mei');
    await b.cloud.claimPending(cid, 'old-mei');
    final claimed = await data.member('new-mei').first;
    expect(claimed!.mutedNotifications, {NotificationKind.reminder, NotificationKind.rosterChange});
    expect(claimed.zones.single.smallGroups, ['喜樂小組']);
    expect(notificationPrefsToJson(claimed.mutedNotifications), {
      'muted': ['reminder', 'rosterChange'],
    });
  });

  test('pending notification preferences have set equality and an empty default', () {
    const first = PendingMember(
      id: 'old-mei',
      name: '李美玉',
      mutedNotifications: {NotificationKind.reminder, NotificationKind.memberLeft},
    );
    const reordered = PendingMember(
      id: 'old-mei',
      name: '李美玉',
      mutedNotifications: {NotificationKind.memberLeft, NotificationKind.reminder},
    );
    const defaults = PendingMember(id: 'old-mei', name: '李美玉');
    expect(first, reordered);
    expect(first.hashCode, reordered.hashCode);
    expect(first, isNot(defaults));
    expect(defaults.mutedNotifications, isEmpty);
  });

  test('runtime pending member decoding accepts only canonical muted preferences, not legacy weekly mode', () {
    final member = pendingMemberFromJson('old-mei', {
      'name': '李美玉',
      'notificationPrefs': {
        'weeklyRosterReminder': false,
        'muted': ['memberLeft'],
      },
    });
    expect(member.mutedNotifications, {
      NotificationKind.memberLeft,
    }, reason: 'legacy opt-out is mapped only at migration');
  });
}
