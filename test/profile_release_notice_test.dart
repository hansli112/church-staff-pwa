import 'package:church_staff_pwa/core/services/app_version_service.dart';
import 'package:church_staff_pwa/core/services/release_check_service.dart';
import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/session_provider.dart';
import 'package:church_staff_pwa/features/auth/presentation/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/church_test_config.dart';
import 'support/signed_in_auth_repository.dart';

class _Version extends AppVersionService {
  const _Version({this.release, this.channel});
  final String? release;
  final String? channel;

  @override
  Future<AppVersionInfo?> fetchVersionInfo() async => AppVersionInfo(
    generatedAt: DateTime(2026, 9, 28),
    release: release,
    channel: channel,
  );
}

class _Latest extends ReleaseCheckService {
  _Latest(this.version);
  final String version;
  int fetches = 0;

  @override
  Future<ReleaseInfo?> fetchLatest() async {
    fetches += 1;
    return ReleaseInfo(
      version: version,
      notes: const ['可以上傳教會 Logo'],
      guideUrl: 'https://example.org/update',
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required UserRole role,
  required AppVersionService version,
  required ReleaseCheckService latest,
}) async {
  final session = SessionProvider(
    SignedInAuthRepository(
      User(
        id: 'u1',
        name: '測試同工',
        username: 'tester',
        email: 'tester@example.org',
        role: role,
      ),
    ),
  );
  addTearDown(session.dispose);
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pumpWidget(
    ChangeNotifierProvider<SessionProvider>.value(
      value: session,
      child: MaterialApp(
        home: ProfileScreen(versionService: version, releaseService: latest),
      ),
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

  testWidgets('精靈裝的網站、GitHub 有新版：管理員看到提醒和更新說明', (tester) async {
    await _pump(
      tester,
      role: UserRole.admin,
      version: const _Version(release: '2026.9.1', channel: 'installer'),
      latest: _Latest('2026.10.1'),
    );
    expect(find.text('有新版本可以更新'), findsOneWidget);
    expect(find.textContaining('目前 2026.9.1，最新 2026.10.1'), findsOneWidget);
    expect(find.text('・可以上傳教會 Logo'), findsOneWidget);
    expect(find.text('怎麼更新'), findsOneWidget);
  });

  testWidgets('已經是最新版：不提醒', (tester) async {
    await _pump(
      tester,
      role: UserRole.admin,
      version: const _Version(release: '2026.10.1', channel: 'installer'),
      latest: _Latest('2026.10.1'),
    );
    expect(find.text('有新版本可以更新'), findsNothing);
  });

  testWidgets('不是精靈裝的（跟著 Git 自動部署）：不提醒，也不去問 GitHub', (tester) async {
    final latest = _Latest('2027.1.1');
    await _pump(
      tester,
      role: UserRole.admin,
      version: const _Version(),
      latest: latest,
    );
    expect(find.text('有新版本可以更新'), findsNothing);
    expect(latest.fetches, 0);
  });

  testWidgets('一般同工：不提醒', (tester) async {
    await _pump(
      tester,
      role: UserRole.member,
      version: const _Version(release: '2026.9.1', channel: 'installer'),
      latest: _Latest('2026.10.1'),
    );
    expect(find.text('有新版本可以更新'), findsNothing);
  });
}
