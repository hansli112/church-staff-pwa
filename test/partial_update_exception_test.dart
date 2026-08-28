import 'package:flutter_test/flutter_test.dart';

import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/domain/repositories/roster_repository.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';

// ── Fake repository：可指定哪些 roster id 的 updateRoster 應該失敗 ──────────────

class _PartialFailRosterRepository implements RosterRepository {
  /// 若 roster.id 在此 set 中，updateRoster 拋出例外。
  final Set<String> failureRosterIds;

  _PartialFailRosterRepository({required this.failureRosterIds});

  @override
  Future<List<ServiceRoster>> getUpcomingRosters() async => [];

  @override
  Future<List<ServiceRoster>> getUpcomingRostersFromCache() async => const []; // stub：no-op

  @override
  Future<void> ensureQuarterRosters(List<ServiceType> allowedTypes) async {} // stub：no-op

  @override
  Future<void> updateRoster(ServiceRoster roster) async {
    if (failureRosterIds.contains(roster.id)) {
      throw Exception('Firestore write failed for ${roster.id}');
    }
  }

  @override
  Future<void> updateRostersAtomically(List<ServiceRoster> rosters) async {
    for (final roster in rosters) {
      await updateRoster(roster);
    }
  }

  @override
  Future<Map<ServiceType, List<String>>> getServiceTemplates() async => {};

  @override
  Future<void> updateServiceTemplates(
    Map<ServiceType, List<String>> templates,
  ) async {}

  @override
  Future<Map<ServiceType, List<EventOption>>> getEventOptions() async => {};

  @override
  Future<void> updateEventOptions(
    Map<ServiceType, List<EventOption>> options,
  ) async {}
}

void main() {
  group('PartialUpdateException', () {
    final roster1 = ServiceRoster(
      id: 'r1',
      date: DateTime(2026, 3, 1),
      type: ServiceType.sundayService,
      serviceName: '主日崇拜',
      duties: [
        RosterEntry(role: '領會', people: const ['A']),
      ],
    );
    final roster2 = ServiceRoster(
      id: 'r2',
      date: DateTime(2026, 3, 8),
      type: ServiceType.youth,
      serviceName: '青年崇拜',
      duties: [
        RosterEntry(role: '領會', people: const ['B']),
      ],
    );
    final cause = Exception('Firestore write failed');
    final stackTrace = StackTrace.current;

    late PartialUpdateException exception;

    setUp(() {
      exception = PartialUpdateException(
        successCount: 3,
        failureCount: 2,
        failedRosters: [roster1, roster2],
        cause: cause,
        causeStackTrace: stackTrace,
      );
    });

    test('successCount getter 回傳正確值', () {
      expect(exception.successCount, 3);
    });

    test('failureCount getter 回傳正確值', () {
      expect(exception.failureCount, 2);
    });

    test('failedRosters getter 回傳正確列表', () {
      expect(exception.failedRosters, [roster1, roster2]);
      expect(exception.failedRosters.length, 2);
    });

    test('cause getter 回傳傳入的原始例外', () {
      expect(exception.cause, same(cause));
    });

    test('causeStackTrace getter 回傳傳入的 StackTrace', () {
      expect(exception.causeStackTrace, same(stackTrace));
    });

    test('causeStackTrace 未傳時為 null', () {
      final e = PartialUpdateException(
        successCount: 1,
        failureCount: 1,
        failedRosters: [roster1],
        cause: cause,
      );
      expect(e.causeStackTrace, isNull);
    });

    test('toString 包含 successCount、failureCount 與 cause 資訊', () {
      final str = exception.toString();
      expect(str, contains('3'));
      expect(str, contains('2'));
      expect(str, contains('筆'));
    });

    test('toString 符合「N 筆寫入成功，M 筆失敗（首個錯誤：...）」格式', () {
      final causeMsg = Exception('Firestore write failed');
      final e = PartialUpdateException(
        successCount: 5,
        failureCount: 1,
        failedRosters: [roster1],
        cause: causeMsg,
      );
      expect(e.toString(), '5 筆寫入成功，1 筆失敗（首個錯誤：$causeMsg）');
    });

    test('failedRosters 為空列表時不拋例外', () {
      final e = PartialUpdateException(
        successCount: 5,
        failureCount: 0,
        failedRosters: const [],
        cause: cause,
      );
      expect(e.failedRosters, isEmpty);
      expect(e.toString(), isNotEmpty);
    });
  });

  // ── Integration test：RosterProvider.updateRosters 部分失敗 ──────────────────

  group('RosterProvider.updateRosters partial failure integration', () {
    final rosterA = ServiceRoster(
      id: 'a1',
      date: DateTime(2026, 4, 1),
      type: ServiceType.sundayService,
      serviceName: '主日崇拜',
      duties: [
        RosterEntry(role: '領會', people: const ['Alice']),
      ],
    );
    final rosterB = ServiceRoster(
      id: 'b1',
      date: DateTime(2026, 4, 8),
      type: ServiceType.sundayService,
      serviceName: '主日崇拜',
      duties: [
        RosterEntry(role: '講員', people: const ['Bob']),
      ],
    );
    final rosterC = ServiceRoster(
      id: 'c1',
      date: DateTime(2026, 4, 15),
      type: ServiceType.youth,
      serviceName: '青年崇拜',
      duties: [
        RosterEntry(role: '領會', people: const ['Carol']),
      ],
    );

    test(
      'updateRosters 部分失敗時拋出 PartialUpdateException，successCount/failureCount/failedRosters 正確',
      () async {
        // b1 和 c1 會失敗，a1 成功 → successCount=1, failureCount=2
        final repo = _PartialFailRosterRepository(
          failureRosterIds: {'b1', 'c1'},
        );
        final provider = RosterProvider(repo);

        late Object caughtError;
        try {
          await provider.updateRosters([rosterA, rosterB, rosterC]);
          fail('應拋出 PartialUpdateException');
        } catch (e) {
          caughtError = e;
        }

        expect(caughtError, isA<PartialUpdateException>());
        final ex = caughtError as PartialUpdateException;
        expect(ex.successCount, 1);
        expect(ex.failureCount, 2);
        expect(ex.failedRosters.map((r) => r.id).toSet(), {'b1', 'c1'});
        expect(ex.cause, isA<Exception>());
      },
    );

    test('updateRosters 全部失敗時 successCount=0、failureCount=3', () async {
      final repo = _PartialFailRosterRepository(
        failureRosterIds: {'a1', 'b1', 'c1'},
      );
      final provider = RosterProvider(repo);

      late Object caughtError;
      try {
        await provider.updateRosters([rosterA, rosterB, rosterC]);
        fail('應拋出 PartialUpdateException');
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isA<PartialUpdateException>());
      final ex = caughtError as PartialUpdateException;
      expect(ex.successCount, 0);
      expect(ex.failureCount, 3);
      expect(ex.failedRosters.length, 3);
    });

    test('updateRosters 全部成功時不拋例外', () async {
      final repo = _PartialFailRosterRepository(failureRosterIds: {});
      final provider = RosterProvider(repo);

      await expectLater(
        provider.updateRosters([rosterA, rosterB, rosterC]),
        completes,
      );
    });
  });
}
