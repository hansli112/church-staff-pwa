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

/// TabBarView 內部疊在使用者 physics 之上的那一份。
ScrollPhysics _asTabBarViewWouldCompose(ScrollPhysics physics) =>
    const PageScrollPhysics()
        .applyTo(
          const ClampingScrollPhysics(parent: RangeMaintainingScrollPhysics()),
        )
        .applyTo(physics);

void main() {
  test('spring 會沿著 TabBarView 疊上去的 physics 鏈傳上來', () {
    // TabBarView 拿自己的分頁 physics 去 applyTo 我們這一份，我們只是 parent。
    // 中間任何一環把 spring 攔下來，手感就悄悄退回慢的，畫面上看不出來。
    const snappy = SnappyPageScrollPhysics();
    final composed = _asTabBarViewWouldCompose(snappy);

    expect(composed.spring.mass, snappy.spring.mass);
    expect(composed.spring.stiffness, snappy.spring.stiffness);
    expect(composed.spring.damping, snappy.spring.damping);

    // 對照組：少了我們這份 parent 就是框架預設的 spring。
    expect(
      _asTabBarViewWouldCompose(const ScrollPhysics()).spring.stiffness,
      isNot(snappy.spring.stiffness),
    );

    // applyTo 必須回傳自己的型別。TabBarView 這條路徑上我們是鏈尾、不會被
    // 呼叫到，但只要有人把它當成中間一環（巢狀 Scrollable、ScrollBehavior），
    // 少了這個覆寫就會退化成一份普通 ScrollPhysics，spring 一起不見。
    expect(
      const SnappyPageScrollPhysics().applyTo(const ClampingScrollPhysics()),
      isA<SnappyPageScrollPhysics>(),
    );
  });

  test('鏈尾換掉 AlwaysScrollableScrollPhysics 之後，是否接受手勢跟框架預設一致', () {
    // 這份 physics 取代了原本掛在 TabBarView 上的 AlwaysScrollableScrollPhysics。
    // 那一份會無條件接受手勢；換掉之後判斷交還給框架預設，兩種情況都要對：
    // 多頁時照樣能滑，只有一頁時不接受（本來就沒地方可去）。
    final physics = _asTabBarViewWouldCompose(const SnappyPageScrollPhysics());
    ScrollMetrics pages(int count) => FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 800.0 * (count - 1),
      pixels: 0,
      viewportDimension: 800,
      axisDirection: AxisDirection.right,
      devicePixelRatio: 1,
    );

    expect(physics.shouldAcceptUserOffset(pages(3)), isTrue);
    expect(physics.shouldAcceptUserOffset(pages(1)), isFalse);
    // 與框架預設（沒傳 physics 的 TabBarView）逐字相同，沒有偷偷改行為。
    final frameworkDefault = _asTabBarViewWouldCompose(const ScrollPhysics());
    expect(
      physics.shouldAcceptUserOffset(pages(1)),
      frameworkDefault.shouldAcceptUserOffset(pages(1)),
    );
  });

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
