import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/church_writes.dart';
import 'package:martha/state/providers.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Matcher conflict() => throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.conflict));

Future<ProviderContainer> signedIn(MemoryBackend b) async {
  final container = ProviderContainer(overrides: await testOverrides(b));
  addTearDown(container.dispose);
  container.listen(appStageProvider, (_, _) {});
  container.listen(membersProvider, (_, _) {});
  container.listen(servicesProvider, (_, _) {});
  await pumpEventQueue();
  return container;
}

void main() {
  test('editing a member another admin changed meanwhile is refused, keeping their change', () async {
    final b = seededChurch();
    final container = await signedIn(b);
    final shown = b.members['grace']!['mei']!;
    final theirs = shown.copyWith(groups: {Group.rosterEditors});
    b.members['grace']!['mei'] = theirs;
    b.notify();

    final write = container.read(churchWritesProvider).member(shown, shown.copyWith(role: Role.admin));
    await expectLater(write.done, conflict());
    expect(b.members['grace']!['mei']!.groups, theirs.groups);
    expect(b.members['grace']!['mei']!.role, Role.staff);
  });

  test('undoing a member edit is refused once someone changed the member, never overwriting them', () async {
    final b = seededChurch();
    final container = await signedIn(b);
    final before = b.members['grace']!['mei']!;
    final write = container.read(churchWritesProvider).member(before, before.copyWith(zones: const []));
    await write.done;
    final theirs = b.members['grace']!['mei']!.copyWith(groups: {Group.rosterEditors});
    b.members['grace']!['mei'] = theirs;
    b.notify();

    await expectLater(write.undo(), conflict());
    expect(b.members['grace']!['mei']!.groups, {Group.rosterEditors});
    expect(b.members['grace']!['mei']!.zones, isEmpty);
  });

  test('undoing a member edit nobody touched puts the member back', () async {
    final b = seededChurch();
    final container = await signedIn(b);
    final before = b.members['grace']!['mei']!;
    final write = container.read(churchWritesProvider).member(before, before.copyWith(zones: const []));
    await write.done;
    await write.undo();
    expect(b.members['grace']!['mei']!.zones, before.zones);
  });

  test("a member's own notification settings do not make an admin's edit stale", () async {
    final b = seededChurch();
    final container = await signedIn(b);
    final shown = b.members['grace']!['mei']!;
    b.members['grace']!['mei'] = shown.copyWith(mutedNotifications: {NotificationKind.reminder});
    b.notify();

    await container.read(churchWritesProvider).member(shown, shown.copyWith(role: Role.leader)).done;
    final now = b.members['grace']!['mei']!;
    expect(now.role, Role.leader);
    expect(now.mutedNotifications, {NotificationKind.reminder});
  });

  test('reordering services another admin changed meanwhile is refused', () async {
    final b = seededChurch();
    final container = await signedIn(b);
    final shown = b.services['grace']!.services;
    b.setServices('grace', [shown.first.copyWith(name: '別人改的'), ...shown.skip(1)]);

    final write = container.read(churchWritesProvider).serviceList(shown, shown.reversed.toList());
    await expectLater(write.done, conflict());
    expect(b.services['grace']!.services.first.name, '別人改的');
  });

  test('an undo after switching account is refused', () async {
    final b = seededChurch();
    final container = await signedIn(b);
    final before = b.members['grace']!['mei']!;
    final write = container.read(churchWritesProvider).member(before, before.copyWith(zones: const []));
    await write.done;
    b.auth.signInAs('mei@example.com', uid: 'mei', name: '李美玉');
    await pumpEventQueue();
    await expectLater(
      write.undo(),
      throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.permissionDenied)),
    );
  });
}
