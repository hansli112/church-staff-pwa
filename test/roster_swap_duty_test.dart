import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/auth/domain/repositories/auth_repository.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/session_provider.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/user_admin_provider.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/domain/repositories/roster_repository.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';
import 'package:church_staff_pwa/features/roster/presentation/widgets/roster_card.dart';

/// 交換服事（「1/1 的破冰跟 1/8 換一下」）。
///
/// 這組測試守兩件事：
///   1. 兩筆一定走同一次 atomic 寫入 —— 分兩次寫的話，中間失敗會留下一個人
///      被排兩天、另一個人的那天空著。
///   2. 寫失敗時本地狀態不能先被改掉 —— 否則畫面顯示已交換，Firestore 上卻
///      沒有，而且沒有任何提示。
class _FakeRosterRepository implements RosterRepository {
  _FakeRosterRepository({required List<ServiceRoster> rosters})
    : _rosters = List<ServiceRoster>.from(rosters);

  final List<ServiceRoster> _rosters;

  /// 每次 updateRostersAtomically 收到的批次，用來驗證「兩筆同一批」。
  final List<List<ServiceRoster>> atomicBatches = [];

  /// 個別寫入的次數。交換不該用到這條路。
  int singleWriteCount = 0;

  bool failAtomicWrites = false;

  @override
  Future<List<ServiceRoster>> getUpcomingRosters() async =>
      List<ServiceRoster>.from(_rosters);

  @override
  Future<List<ServiceRoster>> getUpcomingRostersFromCache() async => const [];

  @override
  Future<void> ensureQuarterRosters(List<ServiceType> allowedTypes) async {}

  @override
  Future<void> updateRoster(ServiceRoster roster) async {
    singleWriteCount++;
  }

  @override
  Future<void> updateRostersAtomically(List<ServiceRoster> rosters) async {
    if (failAtomicWrites) {
      throw Exception('batch commit failed');
    }
    atomicBatches.add(List<ServiceRoster>.from(rosters));
    for (final roster in rosters) {
      final index = _rosters.indexWhere((r) => r.id == roster.id);
      if (index == -1) {
        _rosters.add(roster);
      } else {
        _rosters[index] = roster;
      }
    }
  }

  @override
  Future<Map<ServiceType, List<String>>> getServiceTemplates() async => {
    ServiceType.sundayService: const ['破冰'],
  };

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

/// 交換入口現在在「編輯服事項目」的視窗裡，而那個視窗會去 UserAdminProvider
/// 撈同工名單 —— 所以這組 UI 測試得連 session 一起掛上。
const _kEditor = User(
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
  Future<User?> getCachedUser() async => _kEditor;
  @override
  Future<User?> getCurrentUser() async => _kEditor;
  @override
  Future<void> writeCachedUser(User user) async {}
  @override
  Future<User?> login(String username, String password) async => _kEditor;
  @override
  Future<void> logout() async {}
  @override
  Future<List<User>> getUsers() async => const [_kEditor];
  @override
  Future<void> addUser(User user, String password) async {}
  @override
  Future<void> updateUser(User user, {String? password}) async {}
  @override
  Future<void> deleteUser(String id) async {}
}

ServiceRoster _roster({
  required String id,
  required int day,
  required List<RosterEntry> duties,
}) {
  return ServiceRoster(
    id: id,
    date: DateTime(2026, 1, day),
    type: ServiceType.sundayService,
    serviceName: '主日崇拜',
    duties: duties,
  );
}

RosterEntry _duty(
  List<String> people, {
  String role = '破冰',
  Map<String, String> ids = const {},
}) {
  return RosterEntry(
    role: role,
    people: people,
    peopleOrder: people.where((p) => p != '待定').toList(),
    personIdsByName: ids,
  );
}

/// 直接把 provider 的內部狀態填好，不必跑完整的 fetch 流程。
Future<RosterProvider> _providerWith(_FakeRosterRepository repo) async {
  final provider = RosterProvider(repo);
  await provider.fetchRosters();
  return provider;
}

RosterEntry _dutyOf(RosterProvider provider, String rosterId) =>
    provider.rosters.firstWhere((r) => r.id == rosterId).duties.first;

void main() {
  group('replaceDutyPerson', () {
    test('換掉指定的人，其他人與順序不動', () {
      final result = RosterProvider.replaceDutyPerson(
        _duty(['芳伶', '小明'], ids: {'芳伶': 'uid-fang', '小明': 'uid-ming'}),
        '芳伶',
        '志豪',
        toId: 'uid-hao',
      );

      expect(result.people, ['志豪', '小明']);
      expect(result.peopleOrder, ['志豪', '小明']);
      expect(result.personIdsByName, {'志豪': 'uid-hao', '小明': 'uid-ming'});
    });

    test('換成待定：這一天還有別人時不補佔位符', () {
      final result = RosterProvider.replaceDutyPerson(
        _duty(['芳伶', '小明']),
        '芳伶',
        '待定',
      );

      expect(result.people, ['小明']);
      expect(result.peopleOrder, ['小明']);
    });

    test('換成待定：全空了才補回佔位符', () {
      final result = RosterProvider.replaceDutyPerson(
        _duty(['芳伶'], ids: {'芳伶': 'uid-fang'}),
        '芳伶',
        '待定',
      );

      expect(result.people, ['待定']);
      expect(result.peopleOrder, isEmpty);
      // 名字都不在了，uid 不能留著 —— 下次交換會被誤搬。
      expect(result.personIdsByName, isEmpty);
    });

    test('待定被換成真人時，佔位符要消失', () {
      final result = RosterProvider.replaceDutyPerson(
        _duty(['待定']),
        '待定',
        '芳伶',
        toId: 'uid-fang',
      );

      expect(result.people, ['芳伶']);
      expect(result.peopleOrder, ['芳伶']);
      expect(result.personIdsByName, {'芳伶': 'uid-fang'});
    });

    test('換進來的人本來就在這一天：不留下兩個同名', () {
      final result = RosterProvider.replaceDutyPerson(
        _duty(['芳伶', '小明']),
        '芳伶',
        '小明',
      );

      expect(result.people, ['小明']);
    });

    test('people 是空的（UI 顯示成待定）時，換進來的人不能消失', () {
      // 沒有人的 duty 在交換清單上長得跟「待定」一樣，所以 from 會是「待定」。
      // 把空清單原樣跑完的話，替換不到東西，補回一個待定 —— 換過來的人就在
      // 同一個 batch 裡憑空不見，而來源那天已經把他移走了。
      final result = RosterProvider.replaceDutyPerson(
        RosterEntry(role: '破冰', people: const []),
        '待定',
        '芳伶',
        toId: 'uid-fang',
      );

      expect(result.people, ['芳伶']);
      expect(result.peopleOrder, ['芳伶']);
      expect(result.personIdsByName, {'芳伶': 'uid-fang'});
    });

    test('舊資料沒有 peopleOrder 時，照 people 的順序補起來', () {
      final duty = RosterEntry(role: '破冰', people: ['芳伶', '小明']);
      final result = RosterProvider.replaceDutyPerson(duty, '芳伶', '志豪');

      expect(result.people, ['志豪', '小明']);
      expect(result.peopleOrder, ['志豪', '小明']);
    });
  });

  group('swapDutyPeople', () {
    test('兩筆走同一次 atomic 寫入，本地狀態也跟著換', () async {
      final repo = _FakeRosterRepository(
        rosters: [
          _roster(
            id: 'a',
            day: 4,
            duties: [
              _duty(['芳伶'], ids: {'芳伶': 'uid-fang'}),
            ],
          ),
          _roster(
            id: 'b',
            day: 11,
            duties: [
              _duty(['小明'], ids: {'小明': 'uid-ming'}),
            ],
          ),
        ],
      );
      final provider = await _providerWith(repo);

      await provider.swapDutyPeople(
        sourceRosterId: 'a',
        sourceDutyIndex: 0,
        sourcePerson: '芳伶',
        targetRosterId: 'b',
        targetDutyIndex: 0,
        targetPerson: '小明',
      );

      expect(repo.atomicBatches, hasLength(1));
      expect(repo.atomicBatches.single.map((r) => r.id), ['a', 'b']);
      expect(repo.singleWriteCount, 0);

      expect(_dutyOf(provider, 'a').people, ['小明']);
      expect(_dutyOf(provider, 'a').personIdsByName, {'小明': 'uid-ming'});
      expect(_dutyOf(provider, 'b').people, ['芳伶']);
      expect(_dutyOf(provider, 'b').personIdsByName, {'芳伶': 'uid-fang'});
    });

    test('rosters 換成新的 instance，衍生快取才會失效', () async {
      final repo = _FakeRosterRepository(
        rosters: [
          _roster(
            id: 'a',
            day: 4,
            duties: [
              _duty(['芳伶']),
            ],
          ),
          _roster(
            id: 'b',
            day: 11,
            duties: [
              _duty(['小明']),
            ],
          ),
        ],
      );
      final provider = await _providerWith(repo);
      final before = provider.getRostersByType(ServiceType.sundayService);

      await provider.swapDutyPeople(
        sourceRosterId: 'a',
        sourceDutyIndex: 0,
        sourcePerson: '芳伶',
        targetRosterId: 'b',
        targetDutyIndex: 0,
        targetPerson: '小明',
      );

      final after = provider.getRostersByType(ServiceType.sundayService);
      expect(identical(before, after), isFalse);
      expect(after.first.duties.first.people, ['小明']);
    });

    test('寫入失敗時往上丟，且本地狀態不動', () async {
      final repo = _FakeRosterRepository(
        rosters: [
          _roster(
            id: 'a',
            day: 4,
            duties: [
              _duty(['芳伶']),
            ],
          ),
          _roster(
            id: 'b',
            day: 11,
            duties: [
              _duty(['小明']),
            ],
          ),
        ],
      )..failAtomicWrites = true;
      final provider = await _providerWith(repo);

      await expectLater(
        provider.swapDutyPeople(
          sourceRosterId: 'a',
          sourceDutyIndex: 0,
          sourcePerson: '芳伶',
          targetRosterId: 'b',
          targetDutyIndex: 0,
          targetPerson: '小明',
        ),
        throwsA(isA<Exception>()),
      );

      expect(_dutyOf(provider, 'a').people, ['芳伶']);
      expect(_dutyOf(provider, 'b').people, ['小明']);
      // 交換失敗不該把服事表整個標成錯誤 —— 錯誤由 sheet 就地顯示。
      expect(provider.error, isNull);
    });

    test('找不到服事表時丟 StateError，不會靜默無事發生', () async {
      final repo = _FakeRosterRepository(
        rosters: [
          _roster(
            id: 'a',
            day: 4,
            duties: [
              _duty(['芳伶']),
            ],
          ),
        ],
      );
      final provider = await _providerWith(repo);

      await expectLater(
        provider.swapDutyPeople(
          sourceRosterId: 'a',
          sourceDutyIndex: 0,
          sourcePerson: '芳伶',
          targetRosterId: 'missing',
          targetDutyIndex: 0,
          targetPerson: '小明',
        ),
        throwsA(isA<StateError>()),
      );
      expect(repo.atomicBatches, isEmpty);
    });

    test('服事項目索引超出範圍時丟 StateError', () async {
      final repo = _FakeRosterRepository(
        rosters: [
          _roster(
            id: 'a',
            day: 4,
            duties: [
              _duty(['芳伶']),
            ],
          ),
          _roster(
            id: 'b',
            day: 11,
            duties: [
              _duty(['小明']),
            ],
          ),
        ],
      );
      final provider = await _providerWith(repo);

      await expectLater(
        provider.swapDutyPeople(
          sourceRosterId: 'a',
          sourceDutyIndex: 0,
          sourcePerson: '芳伶',
          targetRosterId: 'b',
          targetDutyIndex: 5,
          targetPerson: '小明',
        ),
        throwsA(isA<StateError>()),
      );
      expect(repo.atomicBatches, isEmpty);
    });
  });

  group('交換 sheet', () {
    setUpAll(() async {
      // 卡片標題與候選清單都用 zh_TW 的 DateFormat，沒初始化會直接丟
      // LocaleDataException。
      await initializeDateFormatting('zh_TW');
    });

    /// 掛一張展開的服事表卡片，並且已經在編輯模式 —— 交換入口只在編輯模式出現。
    Future<RosterProvider> pumpCard(
      WidgetTester tester,
      _FakeRosterRepository repo,
    ) async {
      final provider = await _providerWith(repo);
      provider.toggleEditMode();

      // session 要先還原完，UserAdminProvider.getUsers() 才過得了 canEditRoster。
      final session = SessionProvider(_FakeAuthRepository());
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
            ChangeNotifierProvider<RosterProvider>.value(value: provider),
            ChangeNotifierProvider<SessionProvider>.value(value: session),
            ChangeNotifierProvider<UserAdminProvider>.value(
              value: UserAdminProvider(_FakeAuthRepository(), session),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              // 照 _RosterList 的做法從 provider 讀，卡片才會跟著新資料重建 ——
              // 直接把 roster 物件塞進去的話，交換完畫面永遠是舊的。
              body: Consumer<RosterProvider>(
                builder: (context, p, _) => ListView(
                  children: [
                    RosterCard(
                      key: const ValueKey('a'),
                      roster: p
                          .getRostersByType(ServiceType.sundayService)
                          .first,
                      initiallyExpanded: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return provider;
    }

    /// 走使用者真的會走的路徑：點服事列開編輯視窗，再按「與其他日期交換」。
    /// ⇄ 不再直接掛在列上 —— 那顆按鈕佔掉的寬度會把三個名字擠成兩行。
    Future<void> openSwapSheet(WidgetTester tester) async {
      await tester.tap(find.text('破冰'));
      await tester.pumpAndSettle();
      expect(find.text('與其他日期交換'), findsOneWidget, reason: '編輯視窗裡要有交換入口');
      await tester.tap(find.text('與其他日期交換'));
      await tester.pumpAndSettle();
    }

    testWidgets('選一天按下交換，兩筆一次寫完並回到卡片上', (tester) async {
      final repo = _FakeRosterRepository(
        rosters: [
          _roster(
            id: 'a',
            day: 4,
            duties: [
              _duty(['芳伶']),
            ],
          ),
          _roster(
            id: 'b',
            day: 11,
            duties: [
              _duty(['小明']),
            ],
          ),
        ],
      );
      await pumpCard(tester, repo);

      await openSwapSheet(tester);

      expect(find.text('交換服事'), findsOneWidget);
      // 候選清單是「日期 + 那天的人」，1/11 的小明應該在裡面。
      expect(find.text('01/11 (日)'), findsOneWidget);

      await tester.tap(find.text('01/11 (日)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '交換'));
      await tester.pumpAndSettle();

      expect(repo.atomicBatches, hasLength(1));
      expect(find.text('交換服事'), findsNothing);
      // 卡片上的名字換過來了。
      expect(find.text('小明'), findsOneWidget);
    });

    testWidgets('自己那天已經有的人不會出現在候選清單裡', (tester) async {
      final repo = _FakeRosterRepository(
        rosters: [
          _roster(
            id: 'a',
            day: 4,
            duties: [
              _duty(['芳伶', '小明']),
            ],
          ),
          _roster(
            id: 'b',
            day: 11,
            duties: [
              _duty(['小明']),
            ],
          ),
        ],
      );
      await pumpCard(tester, repo);

      await openSwapSheet(tester);

      // 1/11 只排了小明，而小明本來就在 1/4，換過來只會變成同一天兩個小明。
      expect(find.text('01/11 (日)'), findsNothing);
      expect(find.text('其他日期沒有可以交換的「破冰」'), findsOneWidget);
    });

    // 上面那條的反方向。候選清單是按「來源這天已經有誰」濾的，濾不掉「對方那天
    // 已經有要換過去的人」—— 那種交換會讓對方那天出現兩個同名，去重之後吃掉
    // 一個，結果是那一天平白少一個人，而且畫面上完全看不出來。
    testWidgets('對方那天已經有這個人時，那一天不會出現在候選清單裡', (tester) async {
      final repo = _FakeRosterRepository(
        rosters: [
          _roster(
            id: 'a',
            day: 4,
            duties: [
              _duty(['芳伶']),
            ],
          ),
          _roster(
            id: 'b',
            day: 11,
            duties: [
              _duty(['芳伶', '阿德']),
            ],
          ),
        ],
      );
      await pumpCard(tester, repo);

      await openSwapSheet(tester);

      // 拿 1/4 的芳伶去換 1/11 的阿德：芳伶已經在 1/11 了，換完那天只剩芳伶
      // 一個人。
      expect(find.text('01/11 (日)'), findsNothing);
      expect(find.text('其他日期沒有可以交換的「破冰」'), findsOneWidget);
    });

    testWidgets('換掉「要換誰」之後，候選清單跟著重算', (tester) async {
      final repo = _FakeRosterRepository(
        rosters: [
          _roster(
            id: 'a',
            day: 4,
            duties: [
              _duty(['芳伶', '小明']),
            ],
          ),
          _roster(
            id: 'b',
            day: 11,
            duties: [
              _duty(['小明', '阿德']),
            ],
          ),
        ],
      );
      await pumpCard(tester, repo);

      await openSwapSheet(tester);

      // 預設要換的是芳伶，她不在 1/11，所以阿德可以選。
      expect(find.text('01/11 (日)'), findsOneWidget);

      // 改成換小明 —— 他已經在 1/11 了，同一個選項就不能再出現。
      await tester.tap(find.widgetWithText(ChoiceChip, '小明'));
      await tester.pumpAndSettle();

      expect(find.text('01/11 (日)'), findsNothing);
      expect(find.text('其他日期沒有可以交換的「破冰」'), findsOneWidget);
    });

    testWidgets('選好之後才換「要換誰」，不會拿舊的索引去換錯人', (tester) async {
      final repo = _FakeRosterRepository(
        rosters: [
          _roster(
            id: 'a',
            day: 4,
            duties: [
              _duty(['芳伶', '小明']),
            ],
          ),
          _roster(
            id: 'b',
            day: 11,
            duties: [
              _duty(['阿德']),
            ],
          ),
          _roster(
            id: 'c',
            day: 18,
            duties: [
              _duty(['小美']),
            ],
          ),
        ],
      );
      await pumpCard(tester, repo);

      await openSwapSheet(tester);

      await tester.tap(find.text('01/18 (日)'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('01/04 (日) 芳伶'),
        findsOneWidget,
        reason: '選好之後有預覽',
      );

      // 換人之後選取要清掉：清單可能重算，同一個索引指到的已經是別人了。
      await tester.tap(find.widgetWithText(ChoiceChip, '小明'));
      await tester.pumpAndSettle();

      expect(find.textContaining('⇄'), findsNothing, reason: '沒有選取就不該有預覽');
      await tester.tap(find.text('交換'));
      await tester.pumpAndSettle();
      expect(repo.atomicBatches, isEmpty, reason: '沒有選取就按不動');
    });

    // 交換會重寫這一項的人，帶不過去 —— 但也不能就這樣把使用者剛勾的東西
    // 靜靜丟掉。
    testWidgets('編輯視窗有未存的改動時，去交換前先問一聲', (tester) async {
      final repo = _FakeRosterRepository(
        rosters: [
          _roster(
            id: 'a',
            day: 4,
            duties: [
              _duty(['芳伶']),
            ],
          ),
          _roster(
            id: 'b',
            day: 11,
            duties: [
              _duty(['小明']),
            ],
          ),
        ],
      );
      await pumpCard(tester, repo);

      await tester.tap(find.text('破冰'));
      await tester.pumpAndSettle();
      // 勾掉原本的人 —— 這就是還沒存的改動。
      await tester.tap(find.widgetWithText(CheckboxListTile, '芳伶'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('與其他日期交換'));
      await tester.pumpAndSettle();
      expect(find.text('尚未儲存'), findsOneWidget);

      // 選擇留下：編輯視窗還在，改動也還在。
      await tester.tap(find.text('留在這裡'));
      await tester.pumpAndSettle();
      expect(find.text('交換服事'), findsNothing);
      expect(find.widgetWithText(FilledButton, '儲存'), findsOneWidget);

      // 再按一次並確認丟掉，才進交換。
      await tester.tap(find.text('與其他日期交換'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('丟掉並交換'));
      await tester.pumpAndSettle();
      expect(find.text('交換服事'), findsOneWidget);
      // 丟掉的意思是真的沒寫進去。
      expect(repo.singleWriteCount, 0);
    });

    testWidgets('沒改過就按交換，不會多跳一個確認', (tester) async {
      final repo = _FakeRosterRepository(
        rosters: [
          _roster(
            id: 'a',
            day: 4,
            duties: [
              _duty(['芳伶']),
            ],
          ),
          _roster(
            id: 'b',
            day: 11,
            duties: [
              _duty(['小明']),
            ],
          ),
        ],
      );
      await pumpCard(tester, repo);

      await openSwapSheet(tester);

      expect(find.text('尚未儲存'), findsNothing);
      expect(find.text('交換服事'), findsOneWidget);
    });

    // 待定是「還沒排人」的佔位符，不是使用者剛改的東西 —— 拿它當改動會讓
    // 每個空的服事項目按交換都先被問一次。
    testWidgets('還沒排人的項目按交換，不會被問有沒有未存的改動', (tester) async {
      final repo = _FakeRosterRepository(
        rosters: [
          _roster(
            id: 'a',
            day: 4,
            duties: [
              _duty(['待定']),
            ],
          ),
          _roster(
            id: 'b',
            day: 11,
            duties: [
              _duty(['小明']),
            ],
          ),
        ],
      );
      await pumpCard(tester, repo);

      await openSwapSheet(tester);

      expect(find.text('尚未儲存'), findsNothing);
      expect(find.text('交換服事'), findsOneWidget);
    });

    testWidgets('寫入失敗時留在 sheet 上顯示錯誤', (tester) async {
      final repo = _FakeRosterRepository(
        rosters: [
          _roster(
            id: 'a',
            day: 4,
            duties: [
              _duty(['芳伶']),
            ],
          ),
          _roster(
            id: 'b',
            day: 11,
            duties: [
              _duty(['小明']),
            ],
          ),
        ],
      )..failAtomicWrites = true;
      await pumpCard(tester, repo);

      await openSwapSheet(tester);
      await tester.tap(find.text('01/11 (日)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '交換'));
      await tester.pumpAndSettle();

      expect(find.text('交換服事'), findsOneWidget);
      expect(find.textContaining('交換失敗'), findsOneWidget);
    });
  });
}
