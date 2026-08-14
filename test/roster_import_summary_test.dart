import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/roster/presentation/screens/roster_import_summary.dart';

User _user({List<UserZoneInfo> zones = const []}) => User(
  id: 'u1',
  name: '王大明',
  email: 'a@b.c',
  username: 'daming',
  role: UserRole.staff,
  zones: zones,
);

List<String> _ministriesFor(User user, ServiceType type) =>
    user.zones.firstWhere((z) => z.serviceType == type).ministries;

void main() {
  group('addMinistriesToUser', () {
    test('該崇拜還沒有任何設定時，開一筆新的', () {
      final updated = addMinistriesToUser(_user(), ServiceType.youth, ['招待']);
      expect(_ministriesFor(updated, ServiceType.youth), ['招待']);
    });

    test('補上新服事時不覆蓋既有的，順序也不動', () {
      final before = _user(
        zones: const [
          UserZoneInfo(
            serviceType: ServiceType.youth,
            ministries: ['司琴', '領詩'],
          ),
        ],
      );
      final updated = addMinistriesToUser(before, ServiceType.youth, ['招待']);
      expect(_ministriesFor(updated, ServiceType.youth), ['司琴', '領詩', '招待']);
    });

    test('已經有的服事不會重複加一次', () {
      final before = _user(
        zones: const [
          UserZoneInfo(serviceType: ServiceType.youth, ministries: ['司琴']),
        ],
      );
      final updated = addMinistriesToUser(before, ServiceType.youth, [
        '司琴',
        '招待',
      ]);
      expect(_ministriesFor(updated, ServiceType.youth), ['司琴', '招待']);
    });

    test('不會動到他在其他崇拜的設定', () {
      final before = _user(
        zones: const [
          UserZoneInfo(
            serviceType: ServiceType.sundayService,
            ministries: ['司琴'],
            smallGroups: ['一組'],
          ),
          UserZoneInfo(serviceType: ServiceType.youth, ministries: ['領詩']),
        ],
      );
      final updated = addMinistriesToUser(before, ServiceType.youth, ['招待']);

      expect(_ministriesFor(updated, ServiceType.sundayService), ['司琴']);
      expect(
        updated.zones
            .firstWhere((z) => z.serviceType == ServiceType.sundayService)
            .smallGroups,
        ['一組'],
        reason: '補服事不該影響小組設定',
      );
      expect(_ministriesFor(updated, ServiceType.youth), ['領詩', '招待']);
    });

    test('不會就地改動傳進來的 user', () {
      final before = _user(
        zones: const [
          UserZoneInfo(serviceType: ServiceType.youth, ministries: ['領詩']),
        ],
      );
      addMinistriesToUser(before, ServiceType.youth, ['招待']);
      expect(_ministriesFor(before, ServiceType.youth), ['領詩']);
    });

    test('其他欄位原封不動帶過去', () {
      final updated = addMinistriesToUser(_user(), ServiceType.youth, ['招待']);
      expect(updated.id, 'u1');
      expect(updated.name, '王大明');
      expect(updated.username, 'daming');
      expect(updated.role, UserRole.staff);
    });
  });

  group('RosterImportSummary.hasIssues', () {
    RosterImportSummary summary({
      List<String> missingDates = const [],
      List<String> notInRoster = const [],
      Map<String, List<String>> mismatch = const {},
      List<String> other = const [],
      List<String> notInCatalog = const [],
    }) => RosterImportSummary(
      updated: 3,
      missingDates: missingDates,
      notInRosterNames: notInRoster,
      roleMismatchDetails: mismatch,
      otherNames: other,
      notInEventCatalog: notInCatalog,
    );

    test('全部乾淨時為 false', () {
      expect(summary().hasIssues, isFalse);
    });

    test('任何一類非空都為 true', () {
      expect(summary(missingDates: ['2026-01-04']).hasIssues, isTrue);
      expect(summary(notInRoster: ['郁苹']).hasIssues, isTrue);
      expect(
        summary(
          mismatch: {
            '王大明': ['招待'],
          },
        ).hasIssues,
        isTrue,
      );
      expect(summary(other: ['家訓']).hasIssues, isTrue);
      expect(summary(notInCatalog: ['遇火重生營會']).hasIssues, isTrue);
    });
  });

  group('匯入結果視窗', () {
    Future<void> pump(
      WidgetTester tester,
      RosterImportSummary summary, {
      AddMinistryToUser? onAddMinistry,
      // 補設定寫的是 users/{uid}，那是 admin only。服事表編輯者進得來匯入
      // 流程，所以 onAddMinistry 可以是 null。
      bool canFix = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RosterImportSummaryDialog(
              summary: summary,
              type: ServiceType.youth,
              onAddMinistry: canFix
                  ? (onAddMinistry ?? (name, roles) async => Future.value())
                  : null,
            ),
          ),
        ),
      );
    }

    RosterImportSummary mismatchOnly() => const RosterImportSummary(
      updated: 13,
      missingDates: [],
      notInRosterNames: [],
      roleMismatchDetails: {
        '王大明': ['招待'],
      },
      otherNames: [],
      notInEventCatalog: [],
    );

    // 沒有權限的人看到一顆按下去必定失敗的按鈕，比看不到還糟：他會一直重試，
    // 而錯誤訊息只會是泛用的「操作失敗，請稍後再試」。
    testWidgets('沒有補設定權限時不給按鈕，改說要找誰', (tester) async {
      await pump(tester, mismatchOnly(), canFix: false);

      expect(find.text('新增服事至同工'), findsNothing);
      expect(find.text('要補進他的服事設定需要管理員。'), findsOneWidget);
      // 名字還是要列出來 —— 匯入結果不能因為沒權限就少報一項。
      expect(find.textContaining('王大明'), findsWidgets);
    });

    testWidgets('有補設定權限時不會冒出那句提示', (tester) async {
      await pump(tester, mismatchOnly());

      expect(find.text('新增服事至同工'), findsOneWidget);
      expect(find.text('要補進他的服事設定需要管理員。'), findsNothing);
    });

    testWidgets('未設定該服事的人有「新增服事至同工」按鈕，按下去帶著正確的姓名與服事', (tester) async {
      String? gotName;
      List<String>? gotRoles;
      await pump(
        tester,
        mismatchOnly(),
        onAddMinistry: (name, roles) async {
          gotName = name;
          gotRoles = roles;
        },
      );

      await tester.tap(find.text('新增服事至同工'));
      await tester.pumpAndSettle();

      expect(gotName, '王大明');
      expect(gotRoles, ['招待']);
      expect(find.text('已新增'), findsOneWidget);
      expect(find.text('新增服事至同工'), findsNothing, reason: '成功後不該還能再按一次');
    });

    testWidgets('一個人有多個服事時拆成獨立的列，各自一顆按鈕', (tester) async {
      // 同一個人被排到兩項時，可能只有其中一項該補進設定（另一項是臨時支援）。
      final calls = <List<String>>[];
      await pump(
        tester,
        const RosterImportSummary(
          updated: 1,
          missingDates: [],
          notInRosterNames: [],
          roleMismatchDetails: {
            '李小華': ['司琴', '領詩'],
          },
          otherNames: [],
          notInEventCatalog: [],
        ),
        onAddMinistry: (name, roles) async => calls.add(roles),
      );

      expect(find.text('・李小華：司琴'), findsOneWidget);
      expect(find.text('・李小華：領詩'), findsOneWidget);
      expect(find.text('新增服事至同工'), findsNWidgets(2));

      // 只按第一顆：另一項不該被一起加進去，按鈕也還要在。
      await tester.tap(find.text('新增服事至同工').first);
      await tester.pumpAndSettle();

      expect(calls, [
        ['司琴'],
      ]);
      expect(find.text('已新增'), findsOneWidget);
      expect(find.text('新增服事至同工'), findsOneWidget);
    });

    testWidgets('同一個人的兩顆按鈕連按不會互相覆蓋', (tester) async {
      // 每次新增都是「讀出這個人 → 加一項 → 整份寫回」。兩筆並行的話都會讀到
      // 修改前的資料，後寫的會蓋掉先寫的 —— 畫面顯示兩行都成功，實際只進去
      // 一項。這裡用一個共享的假資料庫把重疊直接測出來。
      final saved = <String>[];
      final gates = <Completer<void>>[];

      await pump(
        tester,
        const RosterImportSummary(
          updated: 1,
          missingDates: [],
          notInRosterNames: [],
          roleMismatchDetails: {
            '李小華': ['司琴', '領詩'],
          },
          otherNames: [],
          notInEventCatalog: [],
        ),
        onAddMinistry: (name, roles) async {
          final snapshot = List<String>.from(saved); // 讀
          final gate = Completer<void>();
          gates.add(gate);
          await gate.future; // 模擬網路來回
          saved
            ..clear()
            ..addAll([...snapshot, ...roles]); // 整份寫回
        },
      );

      // 這裡不能用 pumpAndSettle：等待中的那一列有 CircularProgressIndicator，
      // 動畫一直排新的 frame，settle 永遠等不到。
      await tester.tap(find.text('新增服事至同工').first);
      await tester.pump();
      await tester.tap(find.text('新增服事至同工').last);
      await tester.pump();

      expect(gates, hasLength(1), reason: '第二筆必須排隊，不能跟第一筆同時讀資料');

      gates.first.complete();
      await tester.pump();
      await tester.pump();
      expect(gates, hasLength(2), reason: '第一筆寫完之後第二筆才開始讀');

      gates.last.complete();
      await tester.pump();
      await tester.pump();

      expect(saved, ['司琴', '領詩'], reason: '兩項都要留下來，後寫的不能蓋掉先寫的');
      expect(find.text('已新增'), findsNWidgets(2));
    });

    testWidgets('排隊中有一筆失敗，不會把後面那筆一起卡死', (tester) async {
      final done = <String>[];
      await pump(
        tester,
        const RosterImportSummary(
          updated: 1,
          missingDates: [],
          notInRosterNames: [],
          roleMismatchDetails: {
            '李小華': ['司琴', '領詩'],
          },
          otherNames: [],
          notInEventCatalog: [],
        ),
        onAddMinistry: (name, roles) async {
          if (roles.single == '司琴') throw Exception('boom');
          done.add(roles.single);
        },
      );

      await tester.tap(find.text('新增服事至同工').first);
      await tester.pump();
      await tester.tap(find.text('新增服事至同工').last);
      await tester.pumpAndSettle();

      expect(done, ['領詩']);
      expect(find.text('重試'), findsOneWidget);
      expect(find.text('已新增'), findsOneWidget);
    });

    testWidgets('補設定失敗時顯示原因並可重試', (tester) async {
      var attempts = 0;
      await pump(
        tester,
        mismatchOnly(),
        onAddMinistry: (name, roles) async {
          attempts++;
          if (attempts == 1) throw Exception('boom');
        },
      );

      await tester.tap(find.text('新增服事至同工'));
      await tester.pumpAndSettle();
      expect(find.text('重試'), findsOneWidget);
      expect(find.text('已新增'), findsNothing);

      await tester.tap(find.text('重試'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('已新增'), findsOneWidget);
    });

    testWidgets('不在名單與同名多人只列出來，沒有一鍵按鈕', (tester) async {
      await pump(
        tester,
        const RosterImportSummary(
          updated: 13,
          missingDates: [],
          notInRosterNames: ['郁苹'],
          roleMismatchDetails: {},
          otherNames: ['家訓'],
          notInEventCatalog: [],
        ),
      );

      expect(find.text('・郁苹'), findsOneWidget);
      expect(find.text('・家訓'), findsOneWidget);
      expect(find.text('新增服事至同工'), findsNothing);
    });

    testWidgets('沒有具體服事可補時不顯示按鈕（按了也只是重寫同一份資料）', (tester) async {
      await pump(
        tester,
        const RosterImportSummary(
          updated: 1,
          missingDates: [],
          notInRosterNames: [],
          roleMismatchDetails: {'王大明': []},
          otherNames: [],
          notInEventCatalog: [],
        ),
      );

      expect(find.text('・王大明'), findsOneWidget);
      expect(find.text('新增服事至同工'), findsNothing);
    });

    testWidgets('開頭就說明這些人已經匯入了，而且只說一次', (tester) async {
      // 這句話是這次改動的重點：名字沒有被丟掉。每個區塊各講一遍會變成雜訊。
      await pump(
        tester,
        const RosterImportSummary(
          updated: 13,
          missingDates: [],
          notInRosterNames: ['郁苹'],
          roleMismatchDetails: {
            '王大明': ['招待'],
          },
          otherNames: ['家訓'],
          notInEventCatalog: [],
        ),
      );
      expect(find.text('已更新 13 筆服事表'), findsOneWidget);
      expect(find.text('下面的名字都已經排進表裡了。'), findsOneWidget);
    });

    testWidgets('文案不叫使用者去做事', (tester) async {
      // 臨時支援的人一年可能就來一次，把他們設成固定班底反而弄髒名單。
      // 要不要補設定是管理者當下的判斷，畫面只陳述事實，不下指令。
      await pump(
        tester,
        const RosterImportSummary(
          updated: 13,
          missingDates: ['2026-10-03'],
          notInRosterNames: ['郁苹'],
          roleMismatchDetails: {
            '王大明': ['招待'],
          },
          otherNames: ['家訓'],
          notInEventCatalog: ['遇火重生營會'],
        ),
      );

      final copy = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((s) => s != '新增服事至同工') // 按鈕本身是動作，不算祈使文案
          .join('\n');
      for (final imperative in ['請', '需要', '要補', '應該', '記得']) {
        expect(
          copy.contains(imperative),
          isFalse,
          reason: '文案裡出現了「$imperative」，變成在派工作：\n$copy',
        );
      }
    });

    /// 完整比對整句，不用 textContaining 抓片段。
    ///
    /// 這條原本寫成 `find.textContaining('下面的人')`，但畫面上的字是
    /// 「下面的名字都已經排進表裡了。」—— 兩者沒有子字串關係，所以不管那句
    /// 有沒有顯示都是綠的，等於什麼都沒保護。
    const promise = '下面的名字都已經排進表裡了。';

    testWidgets('只有日期或活動的問題時，不會冒出那句安撫', (tester) async {
      await pump(
        tester,
        const RosterImportSummary(
          updated: 12,
          missingDates: ['2026-10-03'],
          notInRosterNames: [],
          roleMismatchDetails: {},
          otherNames: [],
          notInEventCatalog: ['遇火重生營會'],
        ),
      );
      expect(find.text(promise), findsNothing);
    });

    testWidgets('有日期沒匯入時不敢說「都排進去了」', (tester) async {
      // 未匹配的名單是整份 JSON 的統計，但找不到的日期那幾筆根本沒寫進去，
      // 名字照樣會出現在清單上。這時那句話可能是假的。
      await pump(
        tester,
        const RosterImportSummary(
          updated: 12,
          missingDates: ['2026-01-11'],
          notInRosterNames: ['陳訪客'],
          roleMismatchDetails: {},
          otherNames: [],
          notInEventCatalog: [],
        ),
      );
      expect(find.text('・陳訪客'), findsOneWidget);
      expect(find.text(promise), findsNothing);
    });

    testWidgets('一筆都沒更新時更不能說「都排進去了」', (tester) async {
      await pump(
        tester,
        const RosterImportSummary(
          updated: 0,
          missingDates: [],
          notInRosterNames: ['陳訪客'],
          roleMismatchDetails: {},
          otherNames: [],
          notInEventCatalog: [],
        ),
      );
      expect(find.text('已更新 0 筆服事表'), findsOneWidget);
      expect(find.text(promise), findsNothing);
    });

    testWidgets('同名多人那一段要講明沒有對到帳號', (tester) async {
      await pump(
        tester,
        const RosterImportSummary(
          updated: 1,
          missingDates: [],
          notInRosterNames: [],
          roleMismatchDetails: {},
          otherNames: ['大明'],
          notInEventCatalog: [],
        ),
      );
      expect(find.text('這一格沒有對到帳號，兩位都收不到服事提醒。'), findsOneWidget);
    });

    testWidgets('ImportFixException 的訊息原文顯示，不被壓成泛用字串', (tester) async {
      // 「有 2 位同工都叫王大明」這種訊息是唯一有用的資訊，被
      // mapErrorToUserMessage 換成「操作失敗，請稍後再試」的話，使用者只會
      // 一直按重試，永遠不知道要去帳號管理處理。
      await pump(
        tester,
        mismatchOnly(),
        onAddMinistry: (name, roles) async {
          throw const ImportFixException('有 2 位同工都叫「王大明」，請到帳號管理手動設定');
        },
      );

      await tester.tap(find.text('新增服事至同工'));
      await tester.pumpAndSettle();

      expect(find.text('有 2 位同工都叫「王大明」，請到帳號管理手動設定'), findsOneWidget);
      expect(find.textContaining('操作失敗'), findsNothing);
    });

    testWidgets('寫入卡住時會逾時，不會整份永遠轉圈', (tester) async {
      // PWA 斷線時 Firestore 的寫入 future 不會 resolve。沒有逾時的話佇列
      // 的 Completer 永遠不 complete，後面每一列都卡在等待、連錯誤都沒有。
      var started = 0;
      await pump(
        tester,
        const RosterImportSummary(
          updated: 1,
          missingDates: [],
          notInRosterNames: [],
          roleMismatchDetails: {
            '李小華': ['司琴', '領詩'],
          },
          otherNames: [],
          notInEventCatalog: [],
        ),
        onAddMinistry: (name, roles) {
          started++;
          if (roles.single == '司琴') return Completer<void>().future; // 永不完成
          return Future<void>.value();
        },
      );

      await tester.tap(find.text('新增服事至同工').first);
      await tester.pump();
      await tester.tap(find.text('新增服事至同工').last);
      await tester.pump();
      expect(started, 1, reason: '第二筆還在排隊');

      await tester.pump(fixTimeout + const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(started, 2, reason: '第一筆逾時之後佇列要放行，第二筆才跑得到');
      expect(find.text('重試'), findsOneWidget);
      expect(find.text('已新增'), findsOneWidget);
    });

    testWidgets('不出現工程術語', (tester) async {
      // 使用者是同工不是工程師。uid / JSON / Firestore 這種字出現在畫面上
      // 就是 bug —— 第一版真的寫了「沒有帳號就沒有 uid」。
      await pump(
        tester,
        const RosterImportSummary(
          updated: 13,
          missingDates: ['2026-10-03'],
          notInRosterNames: ['郁苹'],
          roleMismatchDetails: {
            '王大明': ['招待'],
          },
          otherNames: ['家訓'],
          notInEventCatalog: ['遇火重生營會'],
        ),
      );

      final shown = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      for (final jargon in ['uid', 'UID', 'JSON', 'Firestore', 'null', 'id']) {
        expect(
          shown.contains(jargon),
          isFalse,
          reason: '畫面上出現了「$jargon」：\n$shown',
        );
      }
    });
  });
}
