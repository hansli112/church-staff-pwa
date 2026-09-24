import 'dart:convert';

import 'package:church_staff_pwa/core/config/church_config.dart';
import 'package:church_staff_pwa/core/config/default_church_config.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/auth/domain/repositories/group_settings_repository.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/group_settings_provider.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/user_admin_provider.dart';
import 'package:church_staff_pwa/features/auth/presentation/screens/group_settings_screen.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';
import 'package:church_staff_pwa/features/roster/presentation/screens/role_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/in_memory_roster_repository.dart';

const _midweek = ServiceType('midweek');
const _archived = ServiceType('archived');

Map<ServiceType, List<String>> _oldTemplates() => {
  ServiceType.sundayService: ['原有主日項目'],
  ServiceType.youth: ['原有青年項目'],
  ServiceType.children: ['原有兒童項目'],
  _archived: ['歷史項目'],
};

class _GroupRepository implements GroupSettingsRepository {
  Map<ServiceType, List<String>> templates = _oldTemplates();

  @override
  Future<Map<ServiceType, List<String>>> getSmallGroupTemplates() async =>
      Map.of(templates);

  @override
  Future<void> updateSmallGroupTemplates(
    Map<ServiceType, List<String>> templates,
  ) async {
    this.templates = Map.of(templates);
  }
}

class _RecordingUserAdmin extends ChangeNotifier implements UserAdminProvider {
  Map<ServiceType, List<String>>? ministryCleanup;
  Map<ServiceType, List<String>>? groupCleanup;

  @override
  Future<void> cleanupUserMinistries(
    Map<ServiceType, List<String>> templates,
  ) async {
    ministryCleanup = Map.of(templates);
  }

  @override
  Future<void> cleanupUserSmallGroups(
    Map<ServiceType, List<String>> templates,
  ) async {
    groupCleanup = Map.of(templates);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _openSettings(
  WidgetTester tester, {
  required Widget screen,
  required UserAdminProvider userAdmin,
  RosterProvider? rosters,
  GroupSettingsProvider? groups,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserAdminProvider>.value(value: userAdmin),
        if (rosters != null)
          ChangeNotifierProvider<RosterProvider>.value(value: rosters),
        if (groups != null)
          ChangeNotifierProvider<GroupSettingsProvider>.value(value: groups),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute<void>(builder: (_) => screen)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('週間'));
  await tester.pumpAndSettle();
}

Future<void> _addAndSave(
  WidgetTester tester, {
  required String action,
  required String name,
}) async {
  await tester.tap(find.text(action).last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), name);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
  expect(find.text(name), findsOneWidget);
  await tester.tap(find.byIcon(Icons.check));
  await tester.pumpAndSettle();
  expect(find.text('open'), findsOneWidget);
}

void main() {
  late ChurchConfig previous;
  setUp(() {
    previous = ChurchConfig.current;
    final config = jsonDecode(defaultChurchConfigJson) as Map<String, dynamic>;
    (config['services'] as List).add({
      'id': _midweek.name,
      'label': '週間',
      'name': '週間聚會',
      'weekday': 3,
      'enabled': true,
    });
    ChurchConfig.current = ChurchConfig.fromJson(config);
  });
  tearDown(() => ChurchConfig.current = previous);

  testWidgets(
    'new gathering can add and save a ministry without losing old IDs',
    (tester) async {
      final repository = InMemoryRosterRepository(templates: _oldTemplates());
      final rosters = RosterProvider(repository);
      final userAdmin = _RecordingUserAdmin();
      addTearDown(rosters.dispose);
      addTearDown(userAdmin.dispose);
      await rosters.fetchInitialData();
      expect(rosters.templates.containsKey(_midweek), isFalse);

      await _openSettings(
        tester,
        screen: const RoleSettingsScreen(),
        rosters: rosters,
        userAdmin: userAdmin,
      );
      await _addAndSave(tester, action: '新增項目', name: '新聚會招待');

      final expected = {
        ..._oldTemplates(),
        _midweek: ['新聚會招待'],
      };
      expect(repository.templates, expected);
      expect(rosters.templates, expected);
      expect(userAdmin.ministryCleanup, expected);
      expect(find.byType(RoleSettingsScreen), findsNothing);
    },
  );

  testWidgets('new gathering can add and save a group without losing old IDs', (
    tester,
  ) async {
    final repository = _GroupRepository();
    final groups = GroupSettingsProvider(repository);
    final userAdmin = _RecordingUserAdmin();
    addTearDown(groups.dispose);
    addTearDown(userAdmin.dispose);
    await groups.fetchTemplates();
    expect(groups.templates.containsKey(_midweek), isFalse);

    await _openSettings(
      tester,
      screen: const GroupSettingsScreen(),
      groups: groups,
      userAdmin: userAdmin,
    );
    await _addAndSave(tester, action: '新增小組', name: '新聚會小組');

    final expected = {
      ..._oldTemplates(),
      _midweek: ['新聚會小組'],
    };
    expect(repository.templates, expected);
    expect(groups.templates, expected);
    expect(userAdmin.groupCleanup, expected);
    expect(find.byType(GroupSettingsScreen), findsNothing);
  });
}
