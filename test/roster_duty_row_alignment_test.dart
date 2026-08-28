import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/domain/repositories/roster_repository.dart';
import 'package:church_staff_pwa/features/roster/presentation/providers/roster_provider.dart';
import 'package:church_staff_pwa/features/roster/presentation/widgets/duty_row.dart';
import 'package:church_staff_pwa/features/roster/presentation/widgets/roster_card.dart';
import 'package:church_staff_pwa/features/roster/presentation/widgets/roster_view_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

/// 檢視卡片與編輯卡片的服事列必須逐列等高。
///
/// 不等高的話，切換模式時同一天的卡片長度不一樣，底下所有日期整段位移 ——
/// 那正是「進到編輯服事表畫面就對不齊」的來源。編輯模式那兩顆按鈕的觸控目標
/// 是 48（給長輩按的），所以是檢視跟著編輯走，不是反過來把按鈕縮小。

class _FakeRepo implements RosterRepository {
  @override
  Future<List<ServiceRoster>> getUpcomingRostersFromCache() async => const [];
  @override
  Future<List<ServiceRoster>> getUpcomingRosters() async => const [];
  @override
  Future<void> ensureQuarterRosters(List<ServiceType> allowedTypes) async {}
  @override
  Future<void> updateRoster(ServiceRoster roster) async {}
  @override
  Future<void> updateRostersAtomically(List<ServiceRoster> rosters) async {}
  @override
  Future<Map<ServiceType, List<String>>> getServiceTemplates() async => const {};
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

ServiceRoster _roster() => ServiceRoster(
  id: 'r1',
  date: DateTime(2026, 1, 4),
  type: ServiceType.sundayService,
  serviceName: '主日崇拜',
  duties: [
    RosterEntry(role: '敬拜主領', people: const ['芳伶']),
    RosterEntry(role: '司琴', people: const ['王小明', '李大華']),
    RosterEntry(role: '招待', people: const ['王小明', '李大華', '陳美麗']),
    RosterEntry(
      role: '音控',
      people: const ['王小明', '李大華', '陳美麗', '張志豪'],
    ),
  ],
);

/// 掛一張卡片，回傳每一列服事的高度。
Future<List<double>> _rowHeights(
  WidgetTester tester, {
  required bool editMode,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final provider = RosterProvider(_FakeRepo());
  if (editMode) provider.toggleEditMode();

  await tester.pumpWidget(
    ChangeNotifierProvider<RosterProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              if (editMode)
                RosterCard(roster: _roster(), initiallyExpanded: true)
              else
                RosterViewCard(
                  roster: _roster(),
                  initiallyExpanded: true,
                  resolveEventColor: (_) => 0xFF000000,
                ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return tester
      .widgetList<DutyRow>(find.byType(DutyRow))
      .map((row) => tester.getSize(find.byWidget(row)).height)
      .toList();
}

/// 掛一張卡片，回傳某一個服事項目那一列「人名欄」的實際尺寸。
///
/// 人名不再是一整個 Text（見 [DutyRow]：一個名字一段，才不會從名字中間斷
/// 行），所以量的是包住那些段落的 Wrap。
Future<Size> _peopleColumnSize(
  WidgetTester tester, {
  required bool editMode,
  required String role,
}) async {
  await _rowHeights(tester, editMode: editMode);
  return tester.getSize(
    find.descendant(
      of: find.byWidgetPredicate((w) => w is DutyRow && w.role == role),
      matching: find.byType(Wrap),
    ),
  );
}

void main() {
  setUpAll(() async => initializeDateFormatting('zh_TW'));

  testWidgets('檢視與編輯的服事列逐列等高', (tester) async {
    final viewHeights = await _rowHeights(tester, editMode: false);
    final editHeights = await _rowHeights(tester, editMode: true);

    expect(viewHeights, hasLength(4));
    expect(editHeights, hasLength(4));
    expect(
      viewHeights,
      editHeights,
      reason: '兩邊列高一不同，切換模式時底下所有日期就會位移',
    );
    expect(
      viewHeights.every((h) => h >= kDutyRowMinHeight),
      isTrue,
      reason: '列高不能低於按鈕的觸控目標',
    );
  });

  // ⇄ 曾經直接掛在服事列上，名字欄因此只剩 142px，三個三字名字會被擠成兩行。
  // 交換入口移進編輯視窗之後，名字欄拿回那 44px。
  testWidgets('三個名字在編輯模式也排得下一行', (tester) async {
    final viewSize = await _peopleColumnSize(
      tester,
      editMode: false,
      role: '招待',
    );
    final editSize = await _peopleColumnSize(
      tester,
      editMode: true,
      role: '招待',
    );

    // 只比對兩邊相等不夠 —— 兩邊一起換行也會相等。拿單一名字那列當「一行」
    // 的基準，兩邊都必須是那個高度。
    final oneLine = await _peopleColumnSize(
      tester,
      editMode: true,
      role: '敬拜主領',
    );
    expect(
      editSize.height,
      oneLine.height,
      reason: '編輯模式的名字換行了：$editSize（一行應為 ${oneLine.height}）',
    );
    expect(
      viewSize.height,
      oneLine.height,
      reason: '檢視模式的名字換行了：$viewSize（一行應為 ${oneLine.height}）',
    );
  });

  // 欄寬不夠時中文預設會從任何一個字之間斷開，「陳美麗」被切成「陳美／麗」。
  // 一個名字一段就只剩名字之間可以斷。
  testWidgets('名字多到得換行時，不會從名字中間斷開', (tester) async {
    await _rowHeights(tester, editMode: true);

    // 每個名字各自是一段（最後一個之外都帶著頓號），所以不可能被切開。
    expect(find.text('王小明、'), findsWidgets);
    expect(find.text('李大華、'), findsWidgets);
    expect(find.text('陳美麗'), findsWidgets);

    final wide = await _peopleColumnSize(tester, editMode: true, role: '音控');
    final oneLine = await _peopleColumnSize(
      tester,
      editMode: true,
      role: '敬拜主領',
    );
    expect(
      wide.height,
      greaterThan(oneLine.height),
      reason: '四個名字在編輯模式的欄寬下本來就該換行，這條測試才有意義',
    );
  });
}
