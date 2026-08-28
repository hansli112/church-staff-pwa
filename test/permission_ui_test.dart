import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/auth/domain/repositories/auth_repository.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/session_provider.dart';
import 'package:church_staff_pwa/features/auth/presentation/screens/profile_screen.dart';
import 'package:church_staff_pwa/features/auth/presentation/screens/user_management_screen.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/domain/repositories/roster_repository.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';
import 'package:church_staff_pwa/features/roster/presentation/screens/roster_edit_screen.dart';
import 'package:church_staff_pwa/features/roster/presentation/screens/roster_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 權限的三個強制點裡，UI 只是最外層的一層 —— 真正擋住寫入的是
/// `firestore.rules` 與 `worker/google_calendar.js`。但入口顯不顯示決定使用者
/// 會不會撞到一個按了必定失敗的按鈕，所以這裡把「誰看得到什麼」釘住。

User _user({
  required UserRole role,
  Set<UserGroup> groups = const {},
  List<UserZoneInfo> zones = const [],
}) => User(
  id: 'u1',
  name: '測試者',
  email: 'a@b.c',
  username: 'tester',
  role: role,
  groups: groups,
  zones: zones,
);

class FakeAuthRepository implements AuthRepository {
  final User? user;
  FakeAuthRepository(this.user);

  @override
  Future<User?> getCachedUser() async => user;

  @override
  Future<User?> getCurrentUser() async => user;

  @override
  Future<void> writeCachedUser(User user) async {}

  @override
  Future<User?> login(String username, String password) async => user;

  @override
  Future<void> logout() async {}

  @override
  Future<List<User>> getUsers() async => const [];

  @override
  Future<void> addUser(User user, String password) async {}

  @override
  Future<void> updateUser(User user, {String? password}) async {}

  @override
  Future<void> deleteUser(String id) async {}
}

class _FakeRosterRepository implements RosterRepository {
  int ensureCallCount = 0;

  @override
  Future<List<ServiceRoster>> getUpcomingRostersFromCache() async => const [];

  @override
  Future<List<ServiceRoster>> getUpcomingRosters() async => const [];

  List<ServiceType> ensureTypes = const [];

  @override
  Future<void> ensureQuarterRosters(List<ServiceType> allowedTypes) async {
    ensureCallCount++;
    ensureTypes = allowedTypes;
  }

  @override
  Future<void> updateRoster(ServiceRoster roster) async {}

  @override
  Future<Map<ServiceType, List<String>>> getServiceTemplates() async =>
      const {};

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

/// 進入 RosterEditScreen，回報它有沒有把人踢出去。
///
/// **Session 必須先還原完畢再掛畫面。** SessionProvider 是非同步還原的，而
/// `ChangeNotifierProvider.create` 是 lazy 的 —— 直接在同一棵樹裡 create 的話
/// provider 要到第一次 build 才被建出來，還原的 microtask 來不及在同一幀的
/// post-frame callback 之前跑完，於是 initState 看到的永遠是「沒有權限」，
/// 每個測試都被踢出去一次，權限判斷等於完全沒被測到（把 canEditRoster 改回
/// isAdmin 也不會有任何測試變紅）。所以先把 provider 掛在一棵空樹上 settle
/// 完，再用 `.value` 掛到真正的畫面上。
///
/// 用空的 allowedTypes 進場：畫面走 EmptyState 那條早退路徑，不必準備
/// TabController 與 roster 資料，但 AppBar 的 actions 照樣建出來。
Future<int> _pumpRosterEdit(WidgetTester tester, {required User user}) async {
  final session = SessionProvider(FakeAuthRepository(user));
  final rosters = RosterProvider(_FakeRosterRepository());

  await tester.pumpWidget(
    ChangeNotifierProvider<SessionProvider>.value(
      value: session,
      child: const MaterialApp(home: SizedBox.shrink()),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    session.isRestoring,
    isFalse,
    reason: 'session 沒還原完就掛畫面的話，底下的權限斷言全都測不到東西',
  );

  var exitCalls = 0;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionProvider>.value(value: session),
        ChangeNotifierProvider<RosterProvider>.value(value: rosters),
      ],
      child: MaterialApp(
        home: RosterEditScreen(
          onExit: () => exitCalls++,
          tabController: null,
          allowedTypes: const [],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return exitCalls;
}

/// 掛上唯讀的服事表畫面，回報 TabBar 上出現哪幾個聚會別。
///
/// 會顯示哪些分頁是這支測試的重點：它是「只屬於青崇／兒主的人卻看得到主日」
/// 這個 bug 的迴歸點。session 一樣要先還原完再掛畫面（理由見 [_pumpRosterEdit]）。
Future<List<String>> _pumpRosterTabs(
  WidgetTester tester, {
  required User user,
}) async {
  final session = SessionProvider(FakeAuthRepository(user));
  final rosters = RosterProvider(_FakeRosterRepository());

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
      ],
      child: const MaterialApp(home: RosterScreen()),
    ),
  );
  await tester.pumpAndSettle();

  return tester
      .widgetList<Tab>(find.byType(Tab))
      .map((tab) => (tab.text ?? ''))
      .toList();
}

/// 個人頁不需要 PushNotificationService 才能 build（它只在按鈕的 handler 裡被
/// read），所以這裡只給 SessionProvider。版本資訊那個 FutureBuilder 會因為
/// flutter_test 擋掉對外 HTTP 而失敗，這對這組斷言沒有影響。
Future<void> _pumpProfile(WidgetTester tester, {required User user}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => SessionProvider(FakeAuthRepository(user)),
      child: const MaterialApp(home: ProfileScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Map<String, dynamic> _json(Object? groups) => {
  'id': 'u1',
  'name': '測試者',
  'email': 'a@b.c',
  'username': 'tester',
  'role': 'staff',
  'zones': <dynamic>[],
  // null 代表整個欄位不存在 —— 那是所有既有帳號的形狀。
  'groups': ?groups,
};

void main() {
  // hasValidGroups() 只擋得住經過 App 的寫入。Firebase console 手改、Admin SDK
  // 腳本、遷移程式都繞得過去，而 fromJson 是整份名單共用的解析路徑 —— 這裡拋
  // 例外的話，倒的不是那一個人，是所有人的帳號管理與人員選擇器。
  group('User.fromJson 解析 groups', () {
    test('沒有 groups 欄位（所有既有帳號的形狀）', () {
      expect(User.fromJson(_json(null)).groups, isEmpty);
    });

    test('認得的名稱照順序解析出來', () {
      final user = User.fromJson(_json(['calendar-editors', 'roster-editors']));
      expect(user.groups, {UserGroup.rosterEditors, UserGroup.calendarEditors});
    });

    test('認不得的名稱丟掉，認得的留著', () {
      final user = User.fromJson(_json(['finance-editors', 'roster-editors']));
      expect(user.groups, {UserGroup.rosterEditors});
    });

    test('groups 是字串而不是陣列：當成沒有權限，不拋例外', () {
      expect(User.fromJson(_json('roster-editors')).groups, isEmpty);
    });

    test('groups 是 map：當成沒有權限，不拋例外', () {
      expect(User.fromJson(_json({'roster-editors': true})).groups, isEmpty);
    });

    test('陣列裡混進非字串：丟掉那一個，不影響其他人', () {
      final user = User.fromJson(_json([42, 'roster-editors', null]));
      expect(user.groups, {UserGroup.rosterEditors});
    });

    // 壞掉的權限欄位不該連帶讓這個人的身分也讀不出來。
    test('groups 壞掉時其餘欄位仍然解析得出來', () {
      final user = User.fromJson(_json('壞資料'));
      expect(user.name, '測試者');
      expect(user.role, UserRole.staff);
    });
  });

  group('個人頁的權限標籤', () {
    testWidgets('被授予的 group 顯示成標籤', (tester) async {
      await _pumpProfile(
        tester,
        user: _user(role: UserRole.staff, groups: {UserGroup.calendarEditors}),
      );

      expect(find.text('同工'), findsOneWidget);
      expect(find.text('行事曆編輯'), findsOneWidget);
      expect(find.text('服事表編輯'), findsNothing);
    });

    testWidgets('沒有 group 的人只看到角色標籤', (tester) async {
      await _pumpProfile(tester, user: _user(role: UserRole.leader));

      expect(find.text('小組長'), findsOneWidget);
      expect(find.text('行事曆編輯'), findsNothing);
      expect(find.text('服事表編輯'), findsNothing);
    });

    // 管理員隱含全部，列出來反而像是只被指定了那幾項。
    testWidgets('管理員不列出 group 標籤', (tester) async {
      await _pumpProfile(
        tester,
        user: _user(role: UserRole.admin, groups: {UserGroup.rosterEditors}),
      );

      expect(find.text('管理員'), findsOneWidget);
      expect(find.text('服事表編輯'), findsNothing);
    });
  });

  group('使用者列表副標', () {
    test('沒有任何 group 的人只顯示角色與牧區', () {
      final subtitle = userListSubtitle(_user(role: UserRole.leader), '主日');
      expect(subtitle, '小組長 | 主日');
    });

    // 角色與牧區都是身分，排在一起；編輯權是另一回事，接在最後。
    test('編輯權排在身分（角色＋牧區）後面', () {
      final subtitle = userListSubtitle(
        _user(role: UserRole.staff, groups: {UserGroup.calendarEditors}),
        '主日',
      );
      expect(subtitle, '同工 | 主日 | 可編輯：行事曆');
    });

    // 最長的情況：三個牧區都有。標籤都是兩個字，所以權限還是排得進去。
    test('多個牧區時編輯權仍在最後', () {
      final subtitle = userListSubtitle(
        _user(role: UserRole.staff, groups: {UserGroup.rosterEditors}),
        '主日, 青崇, 兒主',
      );
      expect(subtitle, '同工 | 主日, 青崇, 兒主 | 可編輯：服事表');
    });

    test('兩個 group 依 UserGroup 宣告順序排列', () {
      final subtitle = userListSubtitle(
        _user(
          role: UserRole.staff,
          groups: {UserGroup.calendarEditors, UserGroup.rosterEditors},
        ),
        '',
      );
      expect(subtitle, '同工 | 可編輯：服事表、行事曆');
    });

    // 管理員隱含全部，逐項列出反而像是「只被指定了這幾項」。
    test('管理員不列出 group，即使文件裡有', () {
      final subtitle = userListSubtitle(
        _user(role: UserRole.admin, groups: {UserGroup.rosterEditors}),
        '主日',
      );
      expect(subtitle, '管理員 | 主日');
    });

    test('沒有牧區時不會留下多餘的分隔線', () {
      expect(userListSubtitle(_user(role: UserRole.member), ''), '組員');
    });
  });

  group('服事表編輯模式的設定按鈕', () {
    // settings 的寫入權在 firestore.rules 裡是 admin only，所以非 admin 看到
    // 這兩顆只會按下去然後失敗。
    testWidgets('管理員看得到兩顆設定按鈕', (tester) async {
      final exits = await _pumpRosterEdit(
        tester,
        user: _user(role: UserRole.admin),
      );

      expect(exits, 0);
      expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
      expect(find.byIcon(Icons.list_alt_outlined), findsOneWidget);
    });

    testWidgets('服事表編輯者進得來，但看不到設定按鈕', (tester) async {
      final exits = await _pumpRosterEdit(
        tester,
        user: _user(role: UserRole.staff, groups: {UserGroup.rosterEditors}),
      );

      expect(exits, 0, reason: '有 roster-editors 就不該被擋在編輯模式外');
      expect(find.byIcon(Icons.palette_outlined), findsNothing);
      expect(find.byIcon(Icons.list_alt_outlined), findsNothing);
      expect(find.byIcon(Icons.view_list), findsOneWidget);
    });
  });

  // 編輯權（group）跟牧區（zones）是兩個軸：group 決定「能不能改」，牧區決定
  // 「能改哪一本」。曾經給了 roster-editors 就整組聚會別全開 —— 只屬於青崇／
  // 兒主的人因此看得到主日。
  group('服事表的聚會別範圍', () {
    test('一般人只拿到自己的牧區', () {
      final user = _user(
        role: UserRole.member,
        zones: const [UserZoneInfo(serviceType: ServiceType.youth)],
      );
      expect(user.allowedRosterTypes, [ServiceType.youth]);
    });

    test('服事表編輯者一樣只拿到自己的牧區', () {
      final user = _user(
        role: UserRole.staff,
        groups: {UserGroup.rosterEditors},
        zones: const [
          UserZoneInfo(serviceType: ServiceType.youth),
          UserZoneInfo(serviceType: ServiceType.children),
        ],
      );
      expect(user.allowedRosterTypes, [
        ServiceType.youth,
        ServiceType.children,
      ]);
      expect(
        user.allowedRosterTypes,
        isNot(contains(ServiceType.sundayService)),
      );
    });

    // admin 等同 root：一個牧區都沒有也拿得到全部。
    test('管理員沒有任何牧區也拿得到全部', () {
      expect(
        _user(role: UserRole.admin).allowedRosterTypes,
        ServiceType.values,
      );
    });

    test('沒有牧區的編輯者拿到空的', () {
      final user = _user(
        role: UserRole.staff,
        groups: {UserGroup.rosterEditors},
      );
      expect(user.allowedRosterTypes, isEmpty);
    });

    // zoneTypes 是寫進 Firestore 給 firestore.rules 用的投影。順序跟著
    // ServiceType.values，否則同樣的內容換個順序就是一筆多餘的寫入。
    test('toJson 帶出 zoneTypes，順序固定', () {
      final user = _user(
        role: UserRole.staff,
        zones: const [
          UserZoneInfo(serviceType: ServiceType.children),
          UserZoneInfo(serviceType: ServiceType.sundayService),
        ],
      );
      expect(user.toJson()['zoneTypes'], ['sundayService', 'children']);
    });

    test('沒有牧區時 zoneTypes 是空陣列', () {
      expect(_user(role: UserRole.member).toJson()['zoneTypes'], isEmpty);
    });
  });

  group('服事表分頁只出現自己的牧區', () {
    testWidgets('只屬於青崇與兒主的編輯者看不到主日', (tester) async {
      final tabs = await _pumpRosterTabs(
        tester,
        user: _user(
          role: UserRole.staff,
          groups: {UserGroup.rosterEditors},
          zones: const [
            UserZoneInfo(serviceType: ServiceType.youth),
            UserZoneInfo(serviceType: ServiceType.children),
          ],
        ),
      );

      expect(tabs, ['青崇', '兒主']);
    });

    testWidgets('管理員看得到全部', (tester) async {
      final tabs = await _pumpRosterTabs(
        tester,
        user: _user(role: UserRole.admin),
      );

      expect(tabs, ['主日', '青崇', '兒主']);
    });

    testWidgets('沒有牧區的編輯者看到的是空狀態，不是全部', (tester) async {
      final tabs = await _pumpRosterTabs(
        tester,
        user: _user(role: UserRole.staff, groups: {UserGroup.rosterEditors}),
      );

      expect(tabs, isEmpty);
      expect(find.text('尚未設定可檢視的牧區'), findsOneWidget);
    });
  });

  group('進入編輯模式的權限閘', () {
    // 釘的是 roster_edit_screen initState 的守衛本身。把它改回 isAdmin，
    // 「服事表編輯者進得來」那條會紅。
    testWidgets('只有行事曆 group 的人會被踢出去', (tester) async {
      final exits = await _pumpRosterEdit(
        tester,
        user: _user(role: UserRole.staff, groups: {UserGroup.calendarEditors}),
      );

      expect(exits, 1);
      expect(find.text('沒有權限進入編輯模式'), findsOneWidget);
    });

    testWidgets('沒有任何 group 的小組長會被踢出去', (tester) async {
      final exits = await _pumpRosterEdit(
        tester,
        user: _user(role: UserRole.leader),
      );

      expect(exits, 1);
    });
  });
}
