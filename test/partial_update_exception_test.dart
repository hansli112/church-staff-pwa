import 'package:flutter_test/flutter_test.dart';

import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';

void main() {
  group('PartialUpdateException', () {
    final roster1 = ServiceRoster(
      id: 'r1',
      date: DateTime(2026, 3, 1),
      type: ServiceType.sundayService,
      serviceName: '主日崇拜',
      duties: [RosterEntry(role: '領會', people: const ['A'])],
    );
    final roster2 = ServiceRoster(
      id: 'r2',
      date: DateTime(2026, 3, 8),
      type: ServiceType.youth,
      serviceName: '青年崇拜',
      duties: [RosterEntry(role: '領會', people: const ['B'])],
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
}
