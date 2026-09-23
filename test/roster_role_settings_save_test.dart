import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/user_admin_provider.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';
import 'package:church_staff_pwa/features/roster/presentation/screens/role_settings_screen.dart';

import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/presentation/write_failure.dart';

import 'support/in_memory_roster_repository.dart';

/// 只記錄 cleanupUserMinistries 有沒有被叫到。其餘方法這個畫面用不到。
class _RecordingUserAdmin extends ChangeNotifier implements UserAdminProvider {
  final List<Map<ServiceType, List<String>>> cleanups = [];

  @override
  Future<void> cleanupUserMinistries(
    Map<ServiceType, List<String>> templates,
  ) async {
    cleanups.add(templates);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 樣板寫進去了，但改名同步到服事表時有一天沒寫成功。
class _PartialRenameRosterProvider extends RosterProvider {
  _PartialRenameRosterProvider(super.repository);

  @override
  Future<void> updateTemplates(
    Map<ServiceType, List<String>> newTemplates, {
    Map<ServiceType, Map<String, String>> renamedRolesByType = const {},
  }) async {
    throw PartialUpdateException(
      successCount: 2,
      failureCount: 1,
      failedRosters: const <ServiceRoster>[],
      cause: Exception('write failed'),
    );
  }
}

Future<void> _openRoleSettings(
  WidgetTester tester,
  RosterProvider rosterProvider,
  UserAdminProvider userAdmin,
) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<RosterProvider>.value(value: rosterProvider),
        ChangeNotifierProvider<UserAdminProvider>.value(value: userAdmin),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RoleSettingsScreen(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('writeFailureMessage', () {
    test('一般失敗：動詞＋原因', () {
      expect(writeFailureMessage('更新', Exception('x')), startsWith('更新失敗：'));
    });

    test('部分失敗不說「失敗」，說幾天沒成功、幾天已完成，再接畫面的補充', () {
      final message = writeFailureMessage(
        '儲存',
        PartialUpdateException(
          successCount: 2,
          failureCount: 1,
          failedRosters: const [],
          cause: Exception('x'),
        ),
        partialNote: '設定本身已儲存',
      );
      expect(message, '有 1 天的服事表沒有儲存成功，其餘 2 天已完成。設定本身已儲存');
    });

    test('partialNote 只接在部分失敗後面', () {
      expect(
        writeFailureMessage('儲存', Exception('x'), partialNote: '設定本身已儲存'),
        isNot(contains('設定本身已儲存')),
      );
    });
  });

  testWidgets('樣板寫進去、只有改名同步部分失敗：照樣清同工設定，留在這頁', (tester) async {
    final rosterProvider = _PartialRenameRosterProvider(
      InMemoryRosterRepository(
        templates: {
          for (final type in ServiceType.values) type: ['領會'],
        },
      ),
    );
    await rosterProvider.fetchInitialData();
    final userAdmin = _RecordingUserAdmin();
    await _openRoleSettings(tester, rosterProvider, userAdmin);

    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(userAdmin.cleanups, hasLength(1));
    expect(find.byType(RoleSettingsScreen), findsOneWidget);
    expect(find.textContaining('設定本身已儲存'), findsOneWidget);
  });

  // 清同工設定是依「新樣板」刪掉不在裡面的服事。樣板沒寫進去還照清的話，
  // 同工的服事被刪了，樣板卻還是舊的 —— 以前就是這樣。
  testWidgets('樣板存檔失敗：不清同工設定、留在這頁；再存一次成功才清', (tester) async {
    final repository = InMemoryRosterRepository(
      templates: {
        for (final type in ServiceType.values) type: ['領會'],
      },
    )..failTemplateWrite = StateError('permission-denied');
    final rosterProvider = RosterProvider(repository);
    await rosterProvider.fetchInitialData();
    final userAdmin = _RecordingUserAdmin();

    await _openRoleSettings(tester, rosterProvider, userAdmin);

    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(userAdmin.cleanups, isEmpty);
    expect(find.byType(RoleSettingsScreen), findsOneWidget);
    expect(find.textContaining('儲存失敗'), findsOneWidget);

    repository.failTemplateWrite = null;
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(userAdmin.cleanups, hasLength(1));
    expect(find.byType(RoleSettingsScreen), findsNothing);
  });
}
