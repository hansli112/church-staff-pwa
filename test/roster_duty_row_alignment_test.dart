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

/// 服事列在兩個模式各自該有的高度。
///
/// 編輯模式撐到 48（刪除鈕的觸控目標，給長輩按的，不能縮）；檢視模式沒有按
/// 鈕，列高跟著文字走 —— 這個畫面是拿來讀的，一頁看得到幾天比每列多 25px 留
/// 白重要。切換模式的位移是靠錨定日期修的（見 roster_scroll_anchor_test），
/// 不靠兩邊列高一樣。

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

  testWidgets('編輯模式的服事列撐到按鈕的觸控目標', (tester) async {
    final editHeights = await _rowHeights(tester, editMode: true);

    expect(editHeights, hasLength(4));
    expect(
      editHeights.every((h) => h >= kDutyRowMinHeight),
      isTrue,
      reason: '列高低於 $kDutyRowMinHeight 的話刪除鈕就不好按了：$editHeights',
    );
  });

  testWidgets('檢視模式的服事列跟著文字高度走', (tester) async {
    final viewHeights = await _rowHeights(tester, editMode: false);
    final editHeights = await _rowHeights(tester, editMode: true);

    expect(viewHeights, hasLength(4));
    // 前三列的名字都排得下一行，列高就該是一行文字的高度，不是 48。
    for (final height in viewHeights.take(3)) {
      expect(
        height,
        lessThan(kDutyRowMinHeight),
        reason: '檢視模式又被撐高了（$viewHeights），一頁看得到的天數會變少',
      );
    }
    // 第四列（音控，四個名字）會換行，本來就比一行高 —— 但仍不該吃到那個下限
    // 才叫「跟著文字走」。
    expect(viewHeights[3], lessThan(editHeights[3]));
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
