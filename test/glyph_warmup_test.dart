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
}
