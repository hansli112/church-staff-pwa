import 'package:flutter_test/flutter_test.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/domain/staff_order.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';

import 'support/in_memory_roster_repository.dart';

void main() {
  group('RosterProvider rename sync', () {
    late InMemoryRosterRepository repository;
    late RosterProvider provider;

    setUp(() async {
      repository = InMemoryRosterRepository(
        rosters: [
          ServiceRoster(
            id: 'sun-1',
            date: DateTime(2026, 2, 1),
            type: ServiceType.sundayService,
            serviceName: '主日崇拜',
            duties: [
              RosterEntry(role: '領會', people: const ['A']),
              RosterEntry(role: '講員', people: const ['B']),
            ],
            specialEvents: const ['聖餐主日'],
          ),
          ServiceRoster(
            id: 'youth-1',
            date: DateTime(2026, 2, 7),
            type: ServiceType.youth,
            serviceName: '青年崇拜',
            duties: [
              RosterEntry(role: '領會', people: const ['Y']),
            ],
            specialEvents: const ['聖餐主日'],
          ),
        ],
        templates: {
          ServiceType.sundayService: ['領會', '講員'],
          ServiceType.youth: ['領會'],
          ServiceType.children: const [],
        },
        eventOptions: {
          ServiceType.sundayService: const [
            EventOption(name: '聖餐主日', color: 0xFFF39C12),
          ],
          ServiceType.youth: const [
            EventOption(name: '聖餐主日', color: 0xFFF39C12),
          ],
          ServiceType.children: const [],
        },
      );
      provider = RosterProvider(repository);
      await provider.fetchInitialData();
    });

    test(
      'renaming template role updates existing rosters of same type',
      () async {
        await provider.updateTemplates(
          {
            ServiceType.sundayService: ['敬拜主領', '講員'],
            ServiceType.youth: ['領會'],
            ServiceType.children: const [],
          },
          renamedRolesByType: {
            ServiceType.sundayService: {'領會': '敬拜主領'},
          },
        );

        final sunday = provider
            .getRostersByType(ServiceType.sundayService)
            .first;
        final youth = provider.getRostersByType(ServiceType.youth).first;

        expect(sunday.duties.map((d) => d.role), ['敬拜主領', '講員']);
        expect(youth.duties.map((d) => d.role), ['領會']);
      },
    );

    test('renaming event updates existing rosters of same type', () async {
      await provider.updateEventOptions(
        {
          ServiceType.sundayService: const [
            EventOption(name: '聖餐', color: 0xFFF39C12),
          ],
          ServiceType.youth: const [
            EventOption(name: '聖餐主日', color: 0xFFF39C12),
          ],
          ServiceType.children: const [],
        },
        renamedEventsByType: {
          ServiceType.sundayService: {'聖餐主日': '聖餐'},
        },
      );

      final sunday = provider.getRostersByType(ServiceType.sundayService).first;
      final youth = provider.getRostersByType(ServiceType.youth).first;

      expect(sunday.specialEvents, ['聖餐']);
      expect(youth.specialEvents, ['聖餐主日']);
    });
  });

  group('RosterProvider 刪除服事項目', () {
    ServiceRoster youth(String id, DateTime date) => ServiceRoster(
      id: id,
      date: date,
      type: ServiceType.youth,
      serviceName: '青年崇拜',
      duties: [
        RosterEntry(role: '領會', people: const ['Y']),
        RosterEntry(role: '報告', people: const ['R']),
      ],
    );

    late InMemoryRosterRepository repository;
    late RosterProvider provider;

    setUp(() async {
      repository = InMemoryRosterRepository(
        rosters: [
          youth('last-week', DateTime(2026, 9, 19)),
          youth('today', DateTime(2026, 9, 26)),
          youth('next-week', DateTime(2026, 10, 3)),
          ServiceRoster(
            id: 'sunday',
            date: DateTime(2026, 9, 27),
            type: ServiceType.sundayService,
            serviceName: '主日崇拜',
            duties: [
              RosterEntry(role: '報告', people: const ['S']),
            ],
          ),
        ],
        templates: {
          ServiceType.sundayService: ['報告'],
          ServiceType.youth: ['領會', '報告'],
          ServiceType.children: const [],
        },
        staffOrders: {
          ServiceType.youth: StaffOrder({
            '領會': ['Y', 'Z'],
            '報告': ['R', 'Q'],
          }),
        },
      );
      provider = RosterProvider(
        repository,
        now: () => DateTime(2026, 9, 26, 10),
      );
      await provider.fetchInitialData();
    });

    List<String> rolesOf(String id) => [
      for (final d in repository.rosters.firstWhere((r) => r.id == id).duties)
        d.role,
    ];

    Future<void> dropYouthReport() => provider.updateTemplates({
      ServiceType.sundayService: ['報告'],
      ServiceType.youth: ['領會'],
      ServiceType.children: const [],
    });

    test('今天以後的服事表拿掉那一項，過去的不動', () async {
      await dropYouthReport();

      expect(rolesOf('last-week'), ['領會', '報告']);
      expect(rolesOf('today'), ['領會']);
      expect(rolesOf('next-week'), ['領會']);
    });

    test('只刪那個崇拜的：別的崇拜同名的項目還在', () async {
      await dropYouthReport();

      expect(rolesOf('sunday'), ['報告']);
    });

    test('存著的排序也刪掉那一項', () async {
      await dropYouthReport();

      final order = repository.staffOrders[ServiceType.youth]!;
      expect(order.rankingOf('報告'), isEmpty);
      expect(order.rankingOf('領會'), ['Y', 'Z']);
    });

    test('改名不算刪除：服事表上的人跟著新名字走', () async {
      await provider.updateTemplates(
        {
          ServiceType.sundayService: ['報告'],
          ServiceType.youth: ['領會', '宣布'],
          ServiceType.children: const [],
        },
        renamedRolesByType: {
          ServiceType.youth: {'報告': '宣布'},
        },
      );

      expect(rolesOf('next-week'), ['領會', '宣布']);
      expect(rolesOf('last-week'), ['領會', '宣布']);
    });
  });

  // 寫入失敗一律往上丟，不進 error：編輯頁一看到 error 就把整頁換成錯誤畫面。
  group('RosterProvider 寫入失敗', () {
    late InMemoryRosterRepository repository;
    late RosterProvider provider;

    ServiceRoster roster(String id, ServiceType type) => ServiceRoster(
      id: id,
      date: DateTime(2026, 2, 1),
      type: type,
      serviceName: '崇拜',
      duties: [
        RosterEntry(role: '領會', people: const ['A']),
      ],
      specialEvents: const ['聖餐主日'],
    );

    setUp(() async {
      repository = InMemoryRosterRepository(
        rosters: [
          roster('sun-1', ServiceType.sundayService),
          roster('youth-1', ServiceType.youth),
        ],
        templates: {
          ServiceType.sundayService: ['領會'],
          ServiceType.youth: ['領會'],
        },
      );
      provider = RosterProvider(repository);
      await provider.fetchInitialData();
    });

    test('updateRoster 失敗時丟出來，本地不動，error 仍是 null', () async {
      repository.failRosterIds = {'sun-1'};
      final before = provider.getRostersByType(ServiceType.sundayService).first;

      await expectLater(
        provider.updateRoster(before.copyWith(specialEvents: const [])),
        throwsException,
      );

      expect(provider.error, isNull);
      expect(
        provider
            .getRostersByType(ServiceType.sundayService)
            .first
            .specialEvents,
        ['聖餐主日'],
      );
    });

    test('樣板寫入失敗時丟出來，樣板不變', () async {
      repository.failTemplateWrite = StateError('permission-denied');

      await expectLater(
        provider.updateTemplates({
          ServiceType.sundayService: ['敬拜主領'],
        }),
        throwsStateError,
      );

      expect(provider.error, isNull);
      expect(provider.templates[ServiceType.sundayService], ['領會']);
    });

    test('改名同步部分失敗：成功的那幾天照改，丟 PartialUpdateException', () async {
      repository.failRosterIds = {'youth-1'};

      await expectLater(
        provider.updateEventOptions(
          {
            ServiceType.sundayService: const [
              EventOption(name: '聖餐', color: 0xFFF39C12),
            ],
            ServiceType.youth: const [
              EventOption(name: '聖餐', color: 0xFFF39C12),
            ],
          },
          renamedEventsByType: {
            ServiceType.sundayService: {'聖餐主日': '聖餐'},
            ServiceType.youth: {'聖餐主日': '聖餐'},
          },
        ),
        throwsA(
          isA<PartialUpdateException>()
              .having((e) => e.failureCount, 'failureCount', 1)
              .having((e) => e.successCount, 'successCount', 1),
        ),
      );

      expect(provider.error, isNull);
      expect(repository.eventOptionWrites, 1, reason: '活動清單本身已寫入');
      expect(
        provider
            .getRostersByType(ServiceType.sundayService)
            .first
            .specialEvents,
        ['聖餐'],
      );
      expect(provider.getRostersByType(ServiceType.youth).first.specialEvents, [
        '聖餐主日',
      ]);
    });
  });

  group('RosterProvider.addEventOption（匯入結果的「加入活動清單」）', () {
    late InMemoryRosterRepository repository;
    late RosterProvider provider;

    setUp(() async {
      repository = InMemoryRosterRepository(
        rosters: const [],
        templates: const {},
        eventOptions: {
          ServiceType.sundayService: [
            EventOption(name: '聖餐', color: eventColorPalette[0]),
          ],
          ServiceType.youth: [
            EventOption(name: '聖餐', color: eventColorPalette[0]),
          ],
        },
      );
      provider = RosterProvider(repository);
      await provider.fetchInitialData();
    });

    test('加在那個崇拜的清單最後，顏色挑還沒用過的', () async {
      final added = await provider.addEventOption(
        ServiceType.sundayService,
        '孩童奉獻禮',
      );

      expect(added.color, eventColorPalette[1]);
      final saved = (await repository
          .getEventOptions())[ServiceType.sundayService]!;
      expect(saved.map((o) => o.name), ['聖餐', '孩童奉獻禮']);
    });

    test('加完馬上查得到顏色，已經匯入的那幾天不必重匯', () async {
      await provider.addEventOption(ServiceType.sundayService, '孩童奉獻禮');
      expect(
        provider.eventColorFor(ServiceType.sundayService, '孩童奉獻禮'),
        eventColorPalette[1],
      );
    });

    test('別的崇拜的清單不受影響', () async {
      await provider.addEventOption(ServiceType.sundayService, '孩童奉獻禮');
      final youth = (await repository.getEventOptions())[ServiceType.youth]!;
      expect(youth.map((o) => o.name), ['聖餐']);
    });

    test('已經有同名的就不再寫，重按不會多一筆', () async {
      await provider.addEventOption(ServiceType.sundayService, '孩童奉獻禮');
      await provider.addEventOption(ServiceType.sundayService, '孩童奉獻禮');
      expect(repository.eventOptionWrites, 1);
    });

    test('別台裝置在這段期間加的活動不會被蓋掉', () async {
      // 這台的快取還停在載入時；另一台裝置已經在青崇加了一個活動。
      await repository.updateEventOptions({
        ...await repository.getEventOptions(),
        ServiceType.youth: [
          EventOption(name: '聖餐', color: eventColorPalette[0]),
          EventOption(name: '迎新', color: eventColorPalette[1]),
        ],
      });

      await provider.addEventOption(ServiceType.sundayService, '孩童奉獻禮');

      final youth = (await repository.getEventOptions())[ServiceType.youth]!;
      expect(youth.map((o) => o.name), ['聖餐', '迎新']);
    });

    test('別台裝置已經加過同名的，就不再寫，但這台也看得到顏色', () async {
      await repository.updateEventOptions({
        ...await repository.getEventOptions(),
        ServiceType.sundayService: [
          EventOption(name: '聖餐', color: eventColorPalette[0]),
          EventOption(name: '孩童奉獻禮', color: eventColorPalette[4]),
        ],
      });
      final writes = repository.eventOptionWrites;

      final result = await provider.addEventOption(
        ServiceType.sundayService,
        '孩童奉獻禮',
      );

      expect(result.color, eventColorPalette[4]);
      expect(repository.eventOptionWrites, writes);
      expect(
        provider.eventColorFor(ServiceType.sundayService, '孩童奉獻禮'),
        eventColorPalette[4],
      );
    });

    test('寫入失敗時丟例外，而且清單維持原樣', () async {
      repository.failEventOptionWrite = StateError('permission-denied');
      await expectLater(
        provider.addEventOption(ServiceType.sundayService, '孩童奉獻禮'),
        throwsStateError,
      );
      expect(
        provider.eventOptionsFor(ServiceType.sundayService).map((o) => o.name),
        ['聖餐'],
      );
    });
  });
}
