import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/auth/domain/repositories/auth_repository.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/session_provider.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/user_admin_provider.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/domain/repositories/roster_repository.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';
import 'package:church_staff_pwa/features/roster/presentation/screens/roster_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

/// 切換檢視／編輯模式時，畫面要停在同一天。
///
/// 兩份清單的高度本來就不一樣（編輯模式多一張匯入卡、每列多兩顆 48px 的按鈕，
/// 展開的卡片因此高出一截），所以只保留 `position.pixels` 一定會對到別天 ——
/// 這組測試釘的就是「錨在日期上，不是錨在 pixel 上」。

const _kEditorUser = User(
  id: 'u1',
  name: '編輯者',
  email: 'a@b.c',
  username: 'editor',
  role: UserRole.admin,
  groups: {},
  zones: [],
);

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<User?> getCachedUser() async => _kEditorUser;
  @override
  Future<User?> getCurrentUser() async => _kEditorUser;
  @override
  Future<void> writeCachedUser(User user) async {}
  @override
  Future<User?> login(String username, String password) async => _kEditorUser;
  @override
  Future<void> logout() async {}
  @override
  Future<List<User>> getUsers() async => const [_kEditorUser];
  @override
  Future<void> addUser(User user, String password) async {}
  @override
  Future<void> updateUser(User user, {String? password}) async {}
  @override
  Future<void> deleteUser(String id) async {}
}

class _FakeRosterRepository implements RosterRepository {
  _FakeRosterRepository(this.rosters);

  final List<ServiceRoster> rosters;

  @override
  Future<List<ServiceRoster>> getUpcomingRostersFromCache() async => rosters;
  @override
  Future<List<ServiceRoster>> getUpcomingRosters() async => rosters;
  @override
  Future<void> ensureQuarterRosters(List<ServiceType> allowedTypes) async {}
  @override
  Future<void> updateRoster(ServiceRoster roster) async {}
  @override
  Future<void> updateRostersAtomically(List<ServiceRoster> rosters) async {}
  @override
  Future<Map<ServiceType, List<String>>> getServiceTemplates() async =>
      const {ServiceType.sundayService: ['敬拜主領', '司琴', '招待']};
  @override
  Future<void> updateServiceTemplates(
    Map<ServiceType, List<String>> templates,
  ) async {}
  @override
  Future<Map<ServiceType, List<EventOption>>> getEventOptions() async =>
      const {};
  @override
  Future<void> updateEventOptions(
    Map<ServiceType, List<EventOption>> options,
  ) async {}
}

List<ServiceRoster> _buildRosters(int count) => List.generate(
  count,
  (i) => ServiceRoster(
    id: 'r$i',
    date: DateTime(2026, 1, 4).add(Duration(days: 7 * i)),
    type: ServiceType.sundayService,
    serviceName: '主日崇拜',
    duties: [
      RosterEntry(role: '敬拜主領', people: const ['芳伶']),
      RosterEntry(role: '司琴', people: const ['王小明', '李大華']),
      RosterEntry(role: '招待', people: const ['陳美麗']),
    ],
  ),
);

/// 掛好畫面並等 session 還原完（理由同 permission_ui_test）。
Future<RosterProvider> _pumpRosterScreen(WidgetTester tester) async {
  final session = SessionProvider(_FakeAuthRepository());
  final rosters = RosterProvider(_FakeRosterRepository(_buildRosters(24)));
  final users = UserAdminProvider(_FakeAuthRepository(), session);

  await tester.pumpWidget(
    ChangeNotifierProvider<SessionProvider>.value(
      value: session,
      child: const MaterialApp(home: SizedBox.shrink()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionProvider>.value(value: session),
        ChangeNotifierProvider<RosterProvider>.value(value: rosters),
        ChangeNotifierProvider<UserAdminProvider>.value(value: users),
      ],
      child: const MaterialApp(home: RosterScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return rosters;
}

/// 目前畫面上，指定卡片的上緣落在哪裡（螢幕座標）。找不到代表它根本沒被
/// build 出來 —— 那本身就是「位置跑掉了」。
double _topOf(WidgetTester tester, String rosterId) {
  final finder = find.byKey(ValueKey(rosterId));
  expect(finder, findsOneWidget, reason: '$rosterId 不在畫面上');
  return tester.getTopLeft(finder).dy;
}

/// 目前停在頂端的是哪一張卡片。
String _topmostId(WidgetTester tester, int count) {
  var bestId = '';
  var bestDy = double.negativeInfinity;
  for (var i = 0; i < count; i++) {
    final finder = find.byKey(ValueKey('r$i'));
    if (finder.evaluate().isEmpty) continue;
    final box = tester.getRect(finder);
    if (box.bottom <= 0) continue;
    if (bestDy == double.negativeInfinity || box.top < bestDy) {
      bestDy = box.top;
      bestId = 'r$i';
    }
  }
  return bestId;
}

void main() {
  setUpAll(() async => initializeDateFormatting('zh_TW'));

  testWidgets('切到編輯模式後，原本停在頂端的那一天還在同一個位置', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpRosterScreen(tester);

    // 捲到中段，讓「頂端那張」不是第一張。
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();

    final anchorId = _topmostId(tester, 24);
    expect(anchorId, isNot(''), reason: '捲完之後畫面上應該還有卡片');
    final before = _topOf(tester, anchorId);

    await tester.tap(find.byTooltip('切換至編輯模式'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('切換至檢視模式'), findsOneWidget, reason: '應該已經在編輯模式');
    expect(
      _topOf(tester, anchorId),
      closeTo(before, 1.0),
      reason: '切進編輯模式後，同一天應該停在同一個位置',
    );
  });

  testWidgets('切回檢視模式後也回到同一天', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpRosterScreen(tester);

    await tester.tap(find.byTooltip('切換至編輯模式'));
    await tester.pumpAndSettle();

    // 在編輯模式裡捲動，再切回檢視。
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();

    final anchorId = _topmostId(tester, 24);
    final before = _topOf(tester, anchorId);

    await tester.tap(find.byTooltip('切換至檢視模式'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('切換至編輯模式'), findsOneWidget, reason: '應該已經回到檢視模式');
    expect(
      _topOf(tester, anchorId),
      closeTo(before, 1.0),
      reason: '切回檢視模式後，同一天應該停在同一個位置',
    );
  });

  // 停在最上面時刻意不錨定：把第一張卡片拉回同一個 y，等於把編輯模式頂端的
  // 匯入卡推到畫面外，那顆功能就沒人找得到了。
  testWidgets('本來就在最上面時，切過去仍停在清單頂端', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpRosterScreen(tester);

    await tester.tap(find.byTooltip('切換至編輯模式'));
    await tester.pumpAndSettle();

    expect(find.text('JSON 匯入'), findsOneWidget, reason: '匯入卡應該看得到');
    final listOffset = tester
        .widget<ListView>(find.byType(ListView))
        .controller!
        .position
        .pixels;
    expect(listOffset, closeTo(0, 0.5), reason: '應該仍停在清單頂端');
  });
}
