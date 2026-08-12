import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_staff_pwa/core/widgets/text_warmup.dart';

void main() {
  group('TextWarmup.uniqueStringsOf', () {
    test('去重且保留出現順序', () {
      final result = TextWarmup.uniqueStringsOf(['王小明', '李大華', '王小明']);
      expect(result, ['王小明', '李大華']);
    });

    test('去除前後空白後再比對', () {
      final result = TextWarmup.uniqueStringsOf(['王小明', ' 王小明 ']);
      expect(result, ['王小明']);
    });

    test('略過空字串與純空白', () {
      expect(TextWarmup.uniqueStringsOf(['', '   ', '\n']), isEmpty);
    });

    test('空輸入回傳空清單', () {
      expect(TextWarmup.uniqueStringsOf(const []), isEmpty);
    });
  });

  group('TextWarmup widget', () {
    Widget host(List<String> strings) => MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const SizedBox.expand(),
            TextWarmup(strings: strings),
          ],
        ),
      ),
    );

    testWidgets('分批排版，不會一次把全部塞進同一幀', (tester) async {
      // 60 個字串、每幀 24 個 → 至少要跨三幀才做得完
      final strings = [for (var i = 0; i < 60; i++) '名字$i'];
      await tester.pumpWidget(host(strings));

      // 第一幀還沒開始（要等 post-frame callback）
      expect(find.byType(Text), findsNothing);

      await tester.pump();
      expect(find.text('名字0'), findsOneWidget);
      expect(find.text('名字30'), findsNothing); // 還沒輪到

      await tester.pump();
      expect(find.text('名字30'), findsOneWidget);
      expect(find.text('名字0'), findsNothing); // 已排版過的就不留在樹上
    });

    testWidgets('全部做完之後把自己撤掉', (tester) async {
      await tester.pumpWidget(host(['王小明', '李大華']));
      await tester.pump();
      expect(find.text('王小明'), findsOneWidget);

      // 排完 + settle 時間
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('換一份字串就重新預熱', (tester) async {
      await tester.pumpWidget(host(['王小明']));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(Text), findsNothing);

      await tester.pumpWidget(host(['李大華']));
      await tester.pump();
      expect(find.text('李大華'), findsOneWidget);
    });

    testWidgets('空清單不放任何東西進樹裡', (tester) async {
      await tester.pumpWidget(host(const []));
      await tester.pump();
      expect(find.byType(Text), findsNothing);
    });
  });
}
