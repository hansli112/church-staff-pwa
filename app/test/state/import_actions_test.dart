import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/providers.dart';
import 'package:martha/state/roster_actions.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<RosterActions> editing(MemoryBackend backend) async {
  final container = ProviderContainer(overrides: await testOverrides(backend));
  addTearDown(container.dispose);
  container.listen(appStageProvider, (_, _) {});
  container.listen(rosterEditingProvider('sunday'), (_, _) {});
  await pumpEventQueue();
  return container.read(rosterActionsProvider);
}

void main() {
  test('未確認的縮寫不能繞過預覽直接寫入服事表', () async {
    final backend = seededChurch();
    final actions = await editing(backend);
    final before = savedDay(backend, 11);
    final rows = [
      {
        'date': '2026-10-11',
        'duties': [
          {
            'role': '司琴',
            'people': ['美玉'],
          },
        ],
      },
    ];
    expect(actions.previewImport('sunday', rows).canApply, isFalse);
    await expectLater(
      Future<void>.sync(() => actions.applyImport('sunday', rows).done),
      throwsA(isA<CloudException>()),
    );
    expect(savedDay(backend, 11), before);
  });

  test('匯入復原不覆蓋另一位同工稍後修改的活動', () async {
    final backend = seededChurch();
    final actions = await editing(backend);
    final rows = [
      {
        'date': '2026-10-11',
        'duties': [
          {
            'role': '司琴',
            'people': ['王牧師'],
          },
        ],
      },
    ];
    final write = actions.applyImport('sunday', rows);
    await write.done;
    await pumpEventQueue();
    final newer = savedDay(backend, 11).copyWith(events: const [EventTag(name: '另一位同工新增', color: 3)]);
    await backend.church('grace').saveRoster(newer);
    await pumpEventQueue();
    await expectLater(
      write.undo(),
      throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.conflict)),
    );
    expect(savedDay(backend, 11), newer);
  });

  test('套用前資料改變必須重新預覽，不偷偷接受新的基線', () async {
    final backend = seededChurch();
    final actions = await editing(backend);
    final rows = [
      {
        'date': '2026-10-11',
        'duties': [
          {
            'role': '司琴',
            'people': ['王牧師'],
          },
        ],
      },
    ];
    final preview = actions.previewImport('sunday', rows);
    final newer = savedDay(backend, 11).copyWith(events: const [EventTag(name: '預覽後新增', color: 2)]);
    await backend.church('grace').saveRoster(newer);
    await pumpEventQueue();
    await expectLater(
      Future<void>.sync(() => actions.applyImport('sunday', rows, preview: preview).done),
      throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.conflict)),
    );
    expect(savedDay(backend, 11), newer);
  });
}
