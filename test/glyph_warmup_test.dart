import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_staff_pwa/core/widgets/glyph_warmup.dart';

void main() {
  group('GlyphWarmup.uniqueCharactersOf', () {
    test('去重且保留出現順序', () {
      final result = GlyphWarmup.uniqueCharactersOf(['王小明', '王大明']);
      expect(result, '王小明大');
    });

    test('略過空白與控制字元', () {
      final result = GlyphWarmup.uniqueCharactersOf(['敬拜 主領\n', '\t司琴']);
      expect(result, '敬拜主領司琴');
    });

    test('空輸入回傳空字串', () {
      expect(GlyphWarmup.uniqueCharactersOf(const []), '');
      expect(GlyphWarmup.uniqueCharactersOf(['', '  ']), '');
    });

    test('保留英數字（也需要字型，只是通常已內建）', () {
      expect(GlyphWarmup.uniqueCharactersOf(['abc', 'a1']), 'abc1');
    });

    test('emoji 這類 surrogate pair 不會被拆開', () {
      final result = GlyphWarmup.uniqueCharactersOf(['🙏🙏詩歌']);
      expect(result, '🙏詩歌');
    });
  });

  group('GlyphWarmup widget', () {
    Widget host(String characters) => MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const SizedBox.expand(),
            GlyphWarmup(characters: characters),
          ],
        ),
      ),
    );

    testWidgets('先排版，之後把自己撤掉（不常駐佔每一幀的成本）', (tester) async {
      await tester.pumpWidget(host('王小明敬拜'));
      expect(find.text('王小明敬拜'), findsOneWidget);

      // 給字型下載與重排的餘裕之後就該消失
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('王小明敬拜'), findsNothing);
    });

    testWidgets('字集換了要重新預熱一次', (tester) async {
      await tester.pumpWidget(host('王小明'));
      await tester.pump(const Duration(seconds: 6));
      expect(find.text('王小明'), findsNothing);

      await tester.pumpWidget(host('李大華'));
      expect(find.text('李大華'), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
      expect(find.text('李大華'), findsNothing);
    });

    testWidgets('空字集不放任何東西進樹裡', (tester) async {
      await tester.pumpWidget(host(''));
      expect(find.byType(Text), findsNothing);
    });
  });
}
