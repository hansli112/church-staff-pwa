import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/session_provider.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/user_admin_provider.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/domain/roster_import.dart';
import 'package:church_staff_pwa/features/roster/domain/staff_order.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';
import 'package:church_staff_pwa/features/roster/presentation/widgets/roster_card.dart';

import 'support/in_memory_roster_repository.dart';
import 'support/signed_in_auth_repository.dart';

/// 同工排序：每一天的名字照「這個服事項目誰是主要同工」排，而不是照那一天
/// 當初怎麼存。
///
/// 以前每一天各存一份順序，交換是就地頂替 —— 主要同工換到別天就排到第二個。
/// 這組測試守的是：不管名字是匯入、勾選還是交換進來的，排出來都一樣。

const _type = ServiceType.sundayService;

ServiceRoster _roster(String id, int day, Map<String, List<String>> duties) {
  return ServiceRoster(
    id: id,
    date: DateTime(2026, 1, day),
    type: _type,
    serviceName: '主日崇拜',
    duties: [
      for (final entry in duties.entries)
        RosterEntry(role: entry.key, people: entry.value),
    ],
  );
}

List<String> _peopleOf(RosterProvider provider, String id, [int duty = 0]) =>
    provider.rosters.firstWhere((r) => r.id == id).duties[duty].people;

RosterImportReady _importReady(
  List<ServiceRoster> updates,
  StaffOrder staffOrder,
) => RosterImportReady(
  updates: updates,
  staffOrder: staffOrder,
  summary: RosterImportSummary(
    updated: updates.length,
    missingDates: const [],
    notInRosterNames: const [],
    roleMismatchDetails: const {},
    otherNames: const [],
    nearMatchSuggestions: const {},
    notInEventCatalog: const [],
  ),
);

Future<RosterProvider> _loaded(InMemoryRosterRepository repo) async {
  final provider = RosterProvider(repo);
  await provider.fetchInitialData();
  return provider;
}

void main() {
  group('StaffOrder.sort', () {
    final order = StaffOrder({
      '招待': ['志豪', '美玉', '小明'],
    });

    test('照排序排，不看原本的先後', () {
      expect(order.sort('招待', ['小明', '志豪']), ['志豪', '小明']);
    });

    test('排序裡沒有的人接在後面，彼此維持原本的先後', () {
      expect(order.sort('招待', ['外請乙', '小明', '外請甲', '志豪']), [
        '志豪',
        '小明',
        '外請乙',
        '外請甲',
      ]);
    });

    test('已經排好時回傳同一個 List', () {
      final people = ['志豪', '小明'];
      expect(identical(order.sort('招待', people), people), isTrue);
    });

    test('沒排過的服事項目原樣回傳', () {
      final people = ['小明', '志豪'];
      expect(identical(order.sort('司琴', people), people), isTrue);
    });

    test('名字前後有空白也認得', () {
      expect(order.sort('招待', ['小明 ', ' 志豪']), [' 志豪', '小明 ']);
    });
  });

  group('StaffOrder.learnFrom', () {
    test('照平均位置排：一次寫反不會蓋掉其他幾週', () {
      final learned = StaffOrder.learnFrom([
        _roster('1', 4, {
          'Vocal': ['雅婷', '阿華'],
        }),
        _roster('2', 11, {
          'Vocal': ['阿華', '雅婷'],
        }),
        _roster('3', 18, {
          'Vocal': ['阿華', '雅婷'],
        }),
      ]);
      expect(learned.rankingOf('Vocal'), ['阿華', '雅婷']);
    });

    test('沒有直接同一天過的人也排得出前後', () {
      // 圖片上的招待：負責人每次都寫第一個，其他人兩兩出現。
      final learned = StaffOrder.learnFrom([
        _roster('1', 4, {
          '招待': ['志豪', '美玉', '小明'],
        }),
        _roster('2', 11, {
          '招待': ['美玉', '阿德'],
        }),
        _roster('3', 18, {
          '招待': ['志豪', '阿德'],
        }),
      ]);
      final ranking = learned.rankingOf('招待');
      expect(ranking.first, '志豪');
      expect(ranking.indexOf('美玉'), lessThan(ranking.indexOf('小明')));
    });

    test('只有一個人或待定的那幾天不算', () {
      final learned = StaffOrder.learnFrom([
        _roster('1', 4, {
          '司琴': ['美玉'],
          '鼓': ['待定'],
        }),
      ]);
      expect(learned.isEmpty, isTrue);
    });
  });

  group('StaffOrder 的組合', () {
    test('mergedWith：新的照新的排，沒提到的人留在原位', () {
      // 主要同工甲這一季請假、不在圖片上。擠到最後的話他回來那天就排在新人
      // 後面。
      final stored = StaffOrder({
        '招待': ['志豪', '美玉', '小明', '阿德'],
        '司琴': ['雅婷', '阿華'],
      });
      final next = stored.mergedWith(
        StaffOrder({
          '招待': ['阿德', '美玉', '小明'],
        }),
      );
      expect(next.rankingOf('招待'), ['志豪', '阿德', '美玉', '小明']);
      expect(next.rankingOf('司琴'), ['雅婷', '阿華']);
    });

    test('mergedWith：新面孔插在圖片上他前一位的後面', () {
      final stored = StaffOrder({
        '招待': ['志豪', '美玉', '小明'],
      });
      final next = stored.mergedWith(
        StaffOrder({
          '招待': ['美玉', '新人', '小明'],
        }),
      );
      expect(next.rankingOf('招待'), ['志豪', '美玉', '新人', '小明']);
    });

    test('mergedWith：新面孔排第一時插在後面第一個認得的人前面', () {
      final stored = StaffOrder({
        '招待': ['志豪', '美玉', '小明'],
      });
      final next = stored.mergedWith(
        StaffOrder({
          '招待': ['新人', '小明'],
        }),
      );
      expect(next.rankingOf('招待'), ['志豪', '美玉', '新人', '小明']);
    });

    test('mergedWith：原本沒排過的服事項目直接照新的', () {
      final next = StaffOrder().mergedWith(
        StaffOrder({
          '招待': ['美玉', '小明'],
        }),
      );
      expect(next.rankingOf('招待'), ['美玉', '小明']);
    });

    test('changesTo 只列有變的服事項目，拿掉的給 null', () {
      final before = StaffOrder({
        '招待': ['美玉', '小明'],
        '司琴': ['雅婷'],
        '鼓': ['阿華'],
      });
      final after = StaffOrder({
        '招待': ['小明', '美玉'],
        '司琴': ['雅婷'],
        '敬拜': ['阿德'],
      });
      final changes = before.changesTo(after);
      expect(changes, {
        '招待': ['小明', '美玉'],
        '敬拜': ['阿德'],
        '鼓': null,
      });
      expect(before.withChanges(changes), after);
    });

    test('where 只留認得的人', () {
      final order = StaffOrder({
        '講道': ['外請甲', '志豪'],
      }).where((name) => name != '外請甲');
      expect(order.rankingOf('講道'), ['志豪']);
    });

    test('withRolesRenamed 把排序搬到新名字', () {
      final renamed = StaffOrder({
        '招待': ['美玉', '小明'],
      }).withRolesRenamed({'招待': '接待'});
      expect(renamed.rankingOf('招待'), isEmpty);
      expect(renamed.rankingOf('接待'), ['美玉', '小明']);
    });

    test('toJson / fromJson 來回一樣', () {
      final order = StaffOrder({
        '招待': ['美玉', '小明'],
      });
      expect(StaffOrder.fromJson(order.toJson()), order);
    });

    test('fromJson 丟掉不是字串的東西與待定', () {
      final order = StaffOrder.fromJson({
        'roles': {
          '招待': ['美玉', 3, '待定', '小明'],
          '壞掉': 'not a list',
        },
      });
      expect(order.rankingOf('招待'), ['美玉', '小明']);
      expect(order.rankingOf('壞掉'), isEmpty);
    });
  });

  group('RosterProvider', () {
    test('讀進來的服事表照存著的排序排', () async {
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            '招待': ['小明', '志豪'],
          }),
        ],
        staffOrders: {
          _type: StaffOrder({
            '招待': ['志豪', '小明'],
          }),
        },
      );
      final provider = await _loaded(repo);

      expect(_peopleOf(provider, 'a'), ['志豪', '小明']);
    });

    test('沒存過排序時照服事表上多數的先後排', () async {
      // 這個功能上線前的資料沒有排序可讀，照圖片匯進來的順序學。
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            'Vocal': ['雅婷', '阿華'],
          }),
          _roster('b', 11, {
            'Vocal': ['阿華', '雅婷'],
          }),
          _roster('c', 18, {
            'Vocal': ['阿華', '雅婷'],
          }),
        ],
      );
      final provider = await _loaded(repo);

      expect(_peopleOf(provider, 'a'), ['阿華', '雅婷']);
    });

    test('交換之後主要同工還是排第一個', () async {
      // 1/4 的志豪（主要）跟 1/11 排第二的阿德交換。就地頂替的話志豪到了
      // 1/11 會排在美玉後面，阿德則跑到 1/4 的第一個。
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            '招待': ['志豪', '小明'],
          }),
          _roster('b', 11, {
            '招待': ['美玉', '阿德'],
          }),
        ],
        staffOrders: {
          _type: StaffOrder({
            '招待': ['志豪', '美玉', '小明', '阿德'],
          }),
        },
      );
      final provider = await _loaded(repo);

      await provider.swapDutyPeople(
        sourceRosterId: 'a',
        sourceDutyIndex: 0,
        sourcePerson: '志豪',
        targetRosterId: 'b',
        targetDutyIndex: 0,
        targetPerson: '阿德',
      );

      expect(_peopleOf(provider, 'a'), ['小明', '阿德']);
      expect(_peopleOf(provider, 'b'), ['志豪', '美玉']);
      // 寫進去的也是排好的，不是只有畫面上排。
      final written = repo.atomicBatches.single;
      expect(written.firstWhere((r) => r.id == 'b').duties.first.people, [
        '志豪',
        '美玉',
      ]);
    });

    test('updateRoster 寫進去之前先排好', () async {
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            '招待': ['志豪'],
          }),
        ],
        staffOrders: {
          _type: StaffOrder({
            '招待': ['志豪', '美玉', '小明'],
          }),
        },
      );
      final provider = await _loaded(repo);

      await provider.updateRoster(
        _roster('a', 4, {
          '招待': ['小明', '志豪'],
        }),
      );

      expect(repo.rosters.single.duties.first.people, ['志豪', '小明']);
      expect(_peopleOf(provider, 'a'), ['志豪', '小明']);
    });

    test('updateStaffRanking 重排每一天並存起來', () async {
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            '招待': ['志豪', '小明'],
          }),
          _roster('b', 11, {
            '招待': ['志豪', '美玉'],
          }),
        ],
        staffOrders: {
          _type: StaffOrder({
            '招待': ['志豪', '美玉', '小明'],
          }),
        },
      );
      final provider = await _loaded(repo);

      await provider.updateStaffRanking(
        _type,
        const StaffRanking('招待', ['小明', '美玉', '志豪']),
      );

      expect(_peopleOf(provider, 'a'), ['小明', '志豪']);
      expect(_peopleOf(provider, 'b'), ['美玉', '志豪']);
      expect(repo.staffOrders[_type]!.rankingOf('招待'), ['小明', '美玉', '志豪']);
    });

    test('updateStaffRanking 失敗時往上丟，畫面不動', () async {
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            '招待': ['志豪', '小明'],
          }),
        ],
        staffOrders: {
          _type: StaffOrder({
            '招待': ['志豪', '小明'],
          }),
        },
      );
      final provider = await _loaded(repo);
      repo.failStaffOrderWrite = Exception('permission-denied');

      await expectLater(
        provider.updateStaffRanking(
          _type,
          const StaffRanking('招待', ['小明', '志豪']),
        ),
        throwsException,
      );
      expect(_peopleOf(provider, 'a'), ['志豪', '小明']);
      expect(provider.staffOrderFor(_type).rankingOf('招待'), ['志豪', '小明']);
    });

    test('讀不到排序時拖一次，不會把其他服事項目存過的排序刪掉', () async {
      // 例如 rules 還沒部署、或載入那一下剛好斷線：本機以為什麼都沒存過。
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            '招待': ['志豪', '小明'],
          }),
        ],
        staffOrders: {
          _type: StaffOrder({
            '敬拜': ['雅婷', '阿華'],
            '招待': ['志豪', '小明'],
          }),
        },
      )..failStaffOrderRead = Exception('unavailable');
      final provider = await _loaded(repo);

      await provider.updateStaffRanking(
        _type,
        const StaffRanking('招待', ['小明', '志豪']),
      );

      expect(repo.staffOrders[_type]!.rankingOf('敬拜'), ['雅婷', '阿華']);
      expect(repo.staffOrders[_type]!.rankingOf('招待'), ['小明', '志豪']);
    });

    test('updateRoster 帶排序：排序存失敗時這一天也不寫', () async {
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            '招待': ['志豪'],
          }),
        ],
      )..failStaffOrderWrite = Exception('permission-denied');
      final provider = await _loaded(repo);

      await expectLater(
        provider.updateRoster(
          _roster('a', 4, {
            '招待': ['志豪', '小明'],
          }),
          ranking: const StaffRanking('招待', ['小明', '志豪']),
        ),
        throwsException,
      );
      expect(repo.singleWriteCount, 0);
      expect(_peopleOf(provider, 'a'), ['志豪']);
    });

    test('applyRosterImport：圖片上的人照圖片排，沒出現的主要同工留在原位', () async {
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            '招待': ['志豪'],
          }),
        ],
        staffOrders: {
          _type: StaffOrder({
            '招待': ['志豪', '小明', '美玉'],
          }),
        },
      );
      final provider = await _loaded(repo);

      await provider.applyRosterImport(
        _type,
        _importReady(
          [
            _roster('a', 4, {
              '招待': ['美玉', '小明'],
            }),
          ],
          StaffOrder({
            '招待': ['美玉', '小明'],
          }),
        ),
      );

      expect(repo.staffOrders[_type]!.rankingOf('招待'), ['志豪', '美玉', '小明']);
      expect(_peopleOf(provider, 'a'), ['美玉', '小明']);
      expect(repo.rosters.single.duties.first.people, ['美玉', '小明']);
    });

    test('applyRosterImport：排序沒變就不寫排序', () async {
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            '招待': ['志豪'],
          }),
        ],
        staffOrders: {
          _type: StaffOrder({
            '招待': ['志豪', '小明'],
          }),
        },
      );
      final provider = await _loaded(repo);

      await provider.applyRosterImport(
        _type,
        _importReady(
          [
            _roster('a', 4, {
              '招待': ['志豪', '小明'],
            }),
          ],
          StaffOrder({
            '招待': ['志豪', '小明'],
          }),
        ),
      );
      expect(repo.staffOrderWrites, 0);
    });

    test('applyRosterImport：排序寫失敗時一張服事表都不寫', () async {
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            '招待': ['志豪'],
          }),
        ],
      )..failStaffOrderWrite = Exception('permission-denied');
      final provider = await _loaded(repo);

      await expectLater(
        provider.applyRosterImport(
          _type,
          _importReady(
            [
              _roster('a', 4, {
                '招待': ['美玉', '小明'],
              }),
            ],
            StaffOrder({
              '招待': ['美玉', '小明'],
            }),
          ),
        ),
        throwsException,
      );
      expect(repo.singleWriteCount, 0);
      expect(_peopleOf(provider, 'a'), ['志豪']);
    });

    test('服事項目改名時排序跟著搬', () async {
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            '招待': ['小明', '志豪'],
          }),
        ],
        templates: {
          _type: ['招待'],
        },
        staffOrders: {
          _type: StaffOrder({
            '招待': ['志豪', '小明'],
          }),
        },
      );
      final provider = await _loaded(repo);

      await provider.updateTemplates(
        {
          _type: ['接待'],
        },
        renamedRolesByType: {
          _type: {'招待': '接待'},
        },
      );

      expect(repo.staffOrders[_type]!.rankingOf('接待'), ['志豪', '小明']);
      expect(_peopleOf(provider, 'a'), ['志豪', '小明']);
    });
  });

  group('選人視窗', () {
    setUpAll(() => initializeDateFormatting('zh_TW'));

    testWidgets('拖曳順序後儲存：存成整個服事項目的排序', (tester) async {
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            '招待': ['志豪', '小明'],
          }),
          _roster('b', 11, {
            '招待': ['志豪', '美玉'],
          }),
        ],
        templates: {
          _type: ['招待'],
        },
        staffOrders: {
          _type: StaffOrder({
            '招待': ['志豪', '美玉', '小明'],
          }),
        },
      );
      final provider = await _pumpCard(tester, repo);

      await tester.tap(find.text('招待'));
      await tester.pumpAndSettle();
      expect(find.text('選擇同工（拖曳排序會套用到每一週）'), findsOneWidget);

      // 把小明拖到最上面（待定的上面就是頂，待定本身拖不動）。
      final sheet = find.byType(ReorderableListView);
      await _drag(tester, sheet, '小明', '志豪');
      final options = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .map((t) => (t.title as Text).data)
          .toList();
      expect(options, ['待定', '小明', '志豪', '美玉'], reason: '拖曳沒生效');

      await tester.tap(find.widgetWithText(FilledButton, '儲存'));
      await tester.pumpAndSettle();

      expect(repo.staffOrders[_type]!.rankingOf('招待').first, '小明');
      // 另一天沒打開過，也照新的排序重排。
      expect(_peopleOf(provider, 'a'), ['小明', '志豪']);
      expect(_peopleOf(provider, 'b').first, '志豪');
      expect(
        repo.staffOrders[_type]!.rankingOf('招待').indexOf('志豪'),
        lessThan(repo.staffOrders[_type]!.rankingOf('招待').indexOf('美玉')),
      );
    });

    testWidgets('名單外的人拖不動，也不會寫進排序', (tester) async {
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            '招待': ['志豪', '外請甲'],
          }),
        ],
        templates: {
          _type: ['招待'],
        },
        staffOrders: {
          _type: StaffOrder({
            '招待': ['志豪', '美玉', '小明'],
          }),
        },
      );
      await _pumpCard(tester, repo);

      await tester.tap(find.text('招待'));
      await tester.pumpAndSettle();
      final sheet = find.byType(ReorderableListView);
      List<String?> options() => tester
          .widgetList<CheckboxListTile>(
            find.descendant(of: sheet, matching: find.byType(CheckboxListTile)),
          )
          .map((t) => (t.title as Text).data)
          .toList();
      final before = options();
      expect(before.last, '外請甲');

      await _drag(tester, sheet, '外請甲', '志豪');
      expect(options(), before, reason: '外請甲不該被拖動');

      // 拖一個名單上的人，排序才會寫；寫進去的也不含外請甲。
      await _drag(tester, sheet, '小明', '志豪');
      await tester.tap(find.widgetWithText(FilledButton, '儲存'));
      await tester.pumpAndSettle();

      final ranking = repo.staffOrders[_type]!.rankingOf('招待');
      expect(ranking.first, '小明');
      expect(ranking, isNot(contains('外請甲')));
    });

    testWidgets('只改勾選、沒拖過就不寫排序', (tester) async {
      final repo = InMemoryRosterRepository(
        rosters: [
          _roster('a', 4, {
            '招待': ['志豪', '小明'],
          }),
        ],
        templates: {
          _type: ['招待'],
        },
        staffOrders: {
          _type: StaffOrder({
            '招待': ['志豪', '美玉', '小明'],
          }),
        },
      );
      await _pumpCard(tester, repo);

      await tester.tap(find.text('招待'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ReorderableListView),
          matching: find.text('小明'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '儲存'));
      await tester.pumpAndSettle();

      expect(repo.staffOrderWrites, 0);
      expect(repo.rosters.single.duties.first.people, ['志豪']);
    });
  });
}

const _kEditor = User(
  id: 'u1',
  name: '編輯者',
  email: 'a@b.c',
  username: 'editor',
  role: UserRole.admin,
  groups: {},
  zones: [],
);

User _staff(String id, String name) => User(
  id: id,
  name: name,
  email: '$id@example.com',
  username: id,
  role: UserRole.staff,
  zones: const [
    UserZoneInfo(serviceType: _type, ministries: ['招待']),
  ],
);

/// 志豪、美玉、小明在同工名單上；外請甲不在。
SignedInAuthRepository _auth() => SignedInAuthRepository(
  _kEditor,
  users: [
    _kEditor,
    _staff('u-hao', '志豪'),
    _staff('u-yu', '美玉'),
    _staff('u-ming', '小明'),
  ],
);

/// 在 [sheet] 裡長按 [name] 拖到 [onto] 的上方。
Future<void> _drag(
  WidgetTester tester,
  Finder sheet,
  String name,
  String onto,
) async {
  final from = tester.getCenter(
    find.descendant(of: sheet, matching: find.text(name)),
  );
  final to =
      tester.getCenter(find.descendant(of: sheet, matching: find.text(onto))) -
      const Offset(0, 20);
  final gesture = await tester.startGesture(from);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  for (var i = 1; i <= 10; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// 掛第一天那張卡片，已經在編輯模式。
Future<RosterProvider> _pumpCard(
  WidgetTester tester,
  InMemoryRosterRepository repo,
) async {
  final provider = await _loaded(repo);
  provider.toggleEditMode();

  // session 要先還原完，UserAdminProvider.getUsers() 才過得了 canEditRoster。
  final session = SessionProvider(_auth());
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
          value: UserAdminProvider(_auth(), session),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer<RosterProvider>(
            builder: (context, p, _) => ListView(
              children: [
                RosterCard(
                  key: const ValueKey('a'),
                  roster: p.getRostersByType(_type).first,
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
