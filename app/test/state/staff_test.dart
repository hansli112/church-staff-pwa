import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/state/providers.dart';
import 'package:martha/state/staff_actions.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<ProviderContainer> opened(MemoryBackend b) async {
  final container = ProviderContainer(overrides: await testOverrides(b));
  addTearDown(container.dispose);
  container.listen(appStageProvider, (_, _) {});
  container.listen(staffProvider, (_, _) {});
  await pumpEventQueue();
  return container;
}

void main() {
  test('a 同工 added by name is on the list the moment adding is done, in the service, on the duty', () async {
    final c = await opened(seededChurch());
    final id = await c.read(staffActionsProvider).add('王小明', 'sunday', duty: '司琴');
    final staff = c.read(staffProvider).requireValue;
    final added = staff.all.singleWhere((m) => m.uid == id);
    expect(added.name, '王小明');
    expect(added.serves('sunday', '司琴'), isTrue);
    expect(staff.noAccount, contains(id));
  });

  test('a name already one of the 同工, however written, is refused and nobody is added', () async {
    final c = await opened(seededChurch());
    await expectLater(
      c.read(staffActionsProvider).add(' 李美玉', 'sunday'),
      throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.duplicateName)),
    );
    await pumpEventQueue();
    expect(c.read(staffProvider).requireValue.all.where((m) => m.name.trim() == '李美玉'), hasLength(1));
  });

  test('the backend copy takes over from what was shown', () async {
    final b = seededChurch();
    final c = await opened(b);
    final id = await c.read(staffActionsProvider).add('王小明', 'sunday');
    await pumpEventQueue();
    expect(c.read(staffProvider).requireValue.all.where((m) => m.uid == id), hasLength(1));
  });
}
