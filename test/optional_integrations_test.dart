import 'dart:convert';

import 'package:church_staff_pwa/core/config/church_config.dart';
import 'package:church_staff_pwa/core/config/google_calendar_config.dart';
import 'package:church_staff_pwa/core/services/app_version_service.dart';
import 'package:church_staff_pwa/core/services/push_notification_service.dart';
import 'package:church_staff_pwa/core/time/church_time.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/session_provider.dart';
import 'package:church_staff_pwa/features/auth/presentation/screens/login_screen.dart';
import 'package:church_staff_pwa/features/auth/presentation/screens/profile_screen.dart';
import 'package:church_staff_pwa/features/calendar/data/calendar_write_service.dart';
import 'package:church_staff_pwa/features/calendar/data/google_calendar_month_reader.dart';
import 'package:church_staff_pwa/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:church_staff_pwa/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:church_staff_pwa/features/roster/data/roster_import_service.dart';
import 'package:church_staff_pwa/features/roster/data/roster_photo.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';
import 'package:church_staff_pwa/features/roster/presentation/screens/roster_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/church_test_config.dart';
import 'support/in_memory_roster_repository.dart';
import 'support/signed_in_auth_repository.dart';

class _NoVersionService extends AppVersionService {
  const _NoVersionService();

  @override
  Future<AppVersionInfo?> fetchVersionInfo() async => null;
}

Future<void> _pumpSignedIn(WidgetTester tester, Widget screen) async {
  final session = SessionProvider(
    SignedInAuthRepository(
      User(
        id: 'test-admin',
        name: '測試同工',
        username: 'tester',
        email: 'tester@example.org',
        role: UserRole.admin,
      ),
    ),
  );
  final rosters = RosterProvider(InMemoryRosterRepository())..toggleEditMode();
  addTearDown(session.dispose);
  addTearDown(rosters.dispose);
  // Restore the session before RosterEditScreen's permission callback runs.
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionProvider>.value(value: session),
        ChangeNotifierProvider<RosterProvider>.value(value: rosters),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async => initializeDateFormatting('zh_TW'));
  setUp(() {
    setTestChurchConfig();
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'disabled Calendar reads and writes never request a token or HTTP',
    () async {
      final client = MockClient((_) async => fail('HTTP must not be called'));
      final reader = GoogleCalendarMonthReader(
        client: client,
        apiKey: 'dummy-key',
        calendarId: 'dummy-calendar',
      );
      expect(await reader.fetchMonth(DateTime.utc(2026, 3)), isEmpty);
      final writer = CalendarWriteService(
        client: client,
        idToken: () async => fail('token must not be requested'),
      );
      await expectLater(
        writer.delete('event'),
        throwsA(isA<CalendarWriteException>()),
      );
    },
  );

  test('Calendar requires both public settings even when enabled', () async {
    ChurchConfig.current = testChurchConfig(calendar: true);
    final client = MockClient((_) async => fail('HTTP must not be called'));
    for (final credentials in [('', 'calendar'), ('key', ''), ('', '')]) {
      GoogleCalendarConfig.configureForTesting(
        apiKey: credentials.$1,
        calendarId: credentials.$2,
      );
      expect(GoogleCalendarConfig.isEnabled, isFalse);
      final reader = GoogleCalendarMonthReader(client: client);
      expect(await reader.fetchMonth(DateTime.utc(2026, 3)), isEmpty);
    }
  });

  test('disabled photo import is blocked before requesting a token', () async {
    final service = RosterImportService(
      client: MockClient((_) async => fail('HTTP must not be called')),
      idToken: () async => fail('token must not be requested'),
    );
    await expectLater(
      service.convert(
        type: ServiceType.sundayService,
        photos: const [RosterPhoto(mimeType: 'image/jpeg', data: 'AAAA')],
      ),
      throwsA(isA<RosterImportException>()),
    );
  });

  test(
    'disabled push never initializes Firebase or requests permission/token',
    () async {
      // No Firebase app exists in this test: even accessing a singleton fails.
      final service = PushNotificationService();
      await service.initialize();
      await service.syncTokenForUser('test-user');
      expect(await service.isNotificationEnabledForUser('test-user'), isFalse);
      final result = await service.setNotificationEnabled(
        userId: 'test-user',
        enabled: true,
      );
      expect(result.enabled, isFalse);
      expect(result.failureReason, PushToggleFailureReason.disabled);
      await service.dispose();
    },
  );

  testWidgets('login uses the configured app name', (tester) async {
    ChurchConfig.current = testChurchConfig(appName: '範例聚會');
    await _pumpSignedIn(tester, const LoginScreen());
    expect(find.text('範例聚會'), findsOneWidget);
  });

  testWidgets('disabled cards make no requests and leave the roster visible', (
    tester,
  ) async {
    await _pumpSignedIn(
      tester,
      DashboardScreen(
        httpClient: MockClient((_) async => fail('HTTP must not be called')),
      ),
    );
    expect(find.text('每日靈糧'), findsNothing);
    expect(find.text('行事曆'), findsNothing);
    expect(find.text('本季服事'), findsOneWidget);
  });

  testWidgets('enabled Calendar with missing keys has no dashboard entry', (
    tester,
  ) async {
    ChurchConfig.current = testChurchConfig(calendar: true);
    await _pumpSignedIn(
      tester,
      DashboardScreen(
        httpClient: MockClient((_) async => fail('HTTP must not be called')),
      ),
    );
    expect(find.text('行事曆'), findsNothing);
  });

  testWidgets('direct navigation to disabled Calendar cannot read or edit', (
    tester,
  ) async {
    await _pumpSignedIn(
      tester,
      CalendarScreen(fetchMonth: (_) async => fail('must not fetch')),
    );
    expect(find.byTooltip('新增活動'), findsNothing);
    expect(find.text('行事曆未啟用或設定不完整'), findsOneWidget);
  });

  testWidgets('disabled push hides its settings without a push provider', (
    tester,
  ) async {
    await _pumpSignedIn(
      tester,
      const ProfileScreen(versionService: _NoVersionService()),
    );
    expect(find.text('服事提醒'), findsNothing);
    expect(find.text('登出'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'profile opens the built-in license page with configured branding',
    (tester) async {
      await _pumpSignedIn(
        tester,
        const ProfileScreen(versionService: _NoVersionService()),
      );
      await tester.ensureVisible(find.text('開源授權'));
      await tester.tap(find.text('開源授權'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      expect(
        tester.widget<LicensePage>(find.byType(LicensePage)).applicationName,
        ChurchConfig.current.appName,
      );
    },
  );

  testWidgets('disabled photo import preserves the manual JSON input', (
    tester,
  ) async {
    await _pumpSignedIn(
      tester,
      DefaultTabController(
        length: 1,
        child: RosterEditScreen(
          onExit: () {},
          tabController: null,
          allowedTypes: [ServiceType.sundayService],
        ),
      ),
    );
    await tester.tap(find.text('匯入服事表'));
    await tester.pumpAndSettle();
    expect(find.text('從照片辨識'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('匯入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'many configured service tabs scroll without changing the layout',
    (tester) async {
      ChurchConfig.current = testChurchConfig(
        services: [
          for (var i = 0; i < 6; i++)
            {
              'id': 'service$i',
              'label': '聚會$i',
              'name': '聚會$i',
              'weekday': 7,
              'enabled': true,
            },
        ],
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pumpSignedIn(
        tester,
        DefaultTabController(
          length: ServiceType.values.length,
          child: RosterEditScreen(
            onExit: () {},
            tabController: null,
            allowedTypes: ServiceType.values,
          ),
        ),
      );
      expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('devotional uses its configured source URL and name', (
    tester,
  ) async {
    ChurchConfig.current = testChurchConfig(
      devotional: {
        'enabled': true,
        'dataUrl': 'https://example.org/devotional.json?edition=study',
        'linkUrl': 'https://example.org/devotional',
        'sourceName': '每日讀經',
      },
    );
    final requests = <Uri>[];
    await _pumpSignedIn(
      tester,
      DashboardScreen(
        httpClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'date': ChurchTime.dateKey(ChurchTime.today()),
              'rawRange': '約翰福音三:16-18',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    expect(requests, hasLength(1));
    expect(requests.single.host, 'example.org');
    expect(requests.single.path, '/devotional.json');
    expect(requests.single.queryParameters['edition'], 'study');
    expect(
      requests.single.queryParameters['d'],
      ChurchTime.dateKey(ChurchTime.today()),
    );
    expect(find.text('每日讀經'), findsOneWidget);
    expect(find.text('約翰福音3:16-18'), findsOneWidget);
  });
}
