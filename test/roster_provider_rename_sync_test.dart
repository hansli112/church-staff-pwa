import 'package:flutter_test/flutter_test.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/domain/repositories/roster_repository.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';

class _FakeRosterRepository implements RosterRepository {
  _FakeRosterRepository({
    required List<ServiceRoster> rosters,
    required Map<ServiceType, List<String>> templates,
    required Map<ServiceType, List<EventOption>> eventOptions,
  }) : _rosters = List<ServiceRoster>.from(rosters),
       _templates = Map<ServiceType, List<String>>.from(templates),
       _eventOptions = Map<ServiceType, List<EventOption>>.from(eventOptions);

  final List<ServiceRoster> _rosters;
  Map<ServiceType, List<String>> _templates;
  Map<ServiceType, List<EventOption>> _eventOptions;

  @override
  Future<List<ServiceRoster>> getUpcomingRosters() async =>
      List<ServiceRoster>.from(_rosters);

  @override
  Future<void> updateRoster(ServiceRoster roster) async {
    final index = _rosters.indexWhere((r) => r.id == roster.id);
    if (index == -1) {
      _rosters.add(roster);
      return;
    }
    _rosters[index] = roster;
  }

  @override
  Future<Map<ServiceType, List<String>>> getServiceTemplates() async =>
      Map<ServiceType, List<String>>.from(_templates);

  @override
  Future<void> updateServiceTemplates(
    Map<ServiceType, List<String>> templates,
  ) async {
    _templates = Map<ServiceType, List<String>>.from(templates);
  }

  @override
  Future<Map<ServiceType, List<EventOption>>> getEventOptions() async =>
      Map<ServiceType, List<EventOption>>.from(_eventOptions);

  @override
  Future<void> updateEventOptions(
    Map<ServiceType, List<EventOption>> options,
  ) async {
    _eventOptions = Map<ServiceType, List<EventOption>>.from(options);
  }
}

void main() {
  group('RosterProvider rename sync', () {
    late _FakeRosterRepository repository;
    late RosterProvider provider;

    setUp(() async {
      repository = _FakeRosterRepository(
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
}
