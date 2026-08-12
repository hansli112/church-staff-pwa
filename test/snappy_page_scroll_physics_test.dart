import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_staff_pwa/core/utils/snappy_page_scroll_physics.dart';

/// 服事表左右滑換分頁之後，如果馬上想往下滑，手勢會被 TabBarView 吃掉 ——
/// 那是 Flutter 既定的「接住滑行中的分頁」行為，關不掉，只能縮短窗口。
/// 這組測試把窗口大小釘住，避免有人改回慢的 physics 而沒人發現。
Widget _app(ScrollPhysics? physics) => MaterialApp(
  home: DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        bottom: const TabBar(
          tabs: [
            Tab(text: 'A'),
            Tab(text: 'B'),
            Tab(text: 'C'),
          ],
        ),
      ),
      body: TabBarView(
        physics: physics,
        children: [
          for (var tab = 0; tab < 3; tab++)
            ListView.builder(
              key: ValueKey('list$tab'),
              itemExtent: 100,
              itemCount: 100,
              itemBuilder: (context, i) => Text('tab$tab item$i'),
            ),
        ],
      ),
    ),
  ),
);

/// 甩一頁之後要幾幀才完全靜止 —— 這段時間內垂直手勢都會被吃掉。
Future<int> _framesToSettle(WidgetTester tester, ScrollPhysics? physics) async {
  await tester.pumpWidget(_app(physics));
  await tester.pumpAndSettle();
  await tester.fling(find.byType(TabBarView), const Offset(-400, 0), 1200);
  return tester.pumpAndSettle();
}

void main() {
  testWidgets('比預設 physics 更快靜止', (tester) async {
    final snappy = await _framesToSettle(
      tester,
      const SnappyPageScrollPhysics(),
    );
    final defaultPhysics = await _framesToSettle(tester, null);

    expect(snappy, lessThan(defaultPhysics), reason: '收尾越久，換分頁後手勢沒反應的時間就越長');
    // 量到的是 6 幀 vs 11 幀；留點餘裕避免 Flutter 版本微調就壞掉。
    expect(snappy, lessThanOrEqualTo(8));
  });

  testWidgets('分頁吸附感還在：甩一下就是換一頁，不會停在中間', (tester) async {
    await tester.pumpWidget(_app(const SnappyPageScrollPhysics()));
    await tester.pumpAndSettle();
    expect(find.text('tab0 item0'), findsOneWidget);

    await tester.fling(find.byType(TabBarView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('tab1 item0'), findsOneWidget);
    expect(find.text('tab0 item0'), findsNothing);
  });

  testWidgets('靜止之後垂直捲動正常', (tester) async {
    await tester.pumpWidget(_app(const SnappyPageScrollPhysics()));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(TabBarView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();

    final listFinder = find.descendant(
      of: find.byKey(const ValueKey('list1')),
      matching: find.byType(Scrollable),
    );
    final before = tester.state<ScrollableState>(listFinder).position.pixels;
    await tester.drag(listFinder, const Offset(0, -300));
    await tester.pump();

    expect(
      tester.state<ScrollableState>(listFinder).position.pixels,
      greaterThan(before),
    );
    await tester.pumpAndSettle();
  });
}
