import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

void main() {
  test('offline ensure only retains an existing own profile and never creates an unknown one', () async {
    final backend = MemoryBackend();
    final user = backend.auth.signInAs('admin@example.com');
    final original = UserProfile(uid: user.uid, name: '原名字');
    await backend.profiles.ensure(original);
    backend.setOnline(false);
    await backend.profiles.ensure(UserProfile(uid: user.uid, name: '不同名字'));
    expect((await backend.profiles.watch(user.uid).first)!.name, '原名字');
    await expectLater(
      backend.profiles.ensure(const UserProfile(uid: 'unknown', name: '新名字')),
      throwsA(isA<CloudException>()),
    );
    expect(await backend.profiles.watch('unknown').first, isNull);
  });

  test('offline writes are refused and never appear after reconnecting', () async {
    final backend = MemoryBackend();
    final me = backend.auth.signInAs('admin@example.com');
    final cid = backend.addChurch('恩典堂');
    backend.addMember(cid, Member(uid: me.uid, name: '管理員', role: Role.admin));
    backend.setServices(cid, const [
      Service(id: 'sunday', name: '主日', weekday: 7, duties: ['司琴']),
    ]);
    final church = backend.church(cid);
    final roster = Roster(
      type: 'sunday',
      day: Day(2026, 10, 18),
      duties: const [
        Duty(role: '司琴', people: ['同工']),
      ],
    );

    backend.setOnline(false);
    await expectLater(
      church.saveRoster(roster),
      throwsA(isA<CloudException>().having((e) => e.reason, 'reason', CloudReason.offlineReadOnly)),
    );
    expect(await church.allRosters(), isEmpty);
    backend.setOnline(true);
    await Future<void>.delayed(Duration.zero);
    expect(await church.allRosters(), isEmpty);
    await church.saveRoster(roster);
    expect(await church.allRosters(), [roster]);
  });
}
