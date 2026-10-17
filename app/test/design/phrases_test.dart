import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/design/balanced_text.dart';
import 'package:martha/core/design/phrases.dart';

List<String> phrases(String text, PhraseModel model) {
  final out = <String>[];
  var start = 0;
  for (final end in [...model.boundaries(text), text.length]) {
    out.add(text.substring(start, end));
    start = end;
  }
  return out;
}

void main() {
  // BudouX's own examples (its README).
  test('splits Traditional Chinese as BudouX does', () {
    expect(phrases('是今天的天氣。', PhraseModel.zhHant), ['是', '今天', '的', '天氣。']);
  });

  test('splits Simplified Chinese as BudouX does', () {
    expect(phrases('今天是晴天。', PhraseModel.zhHans), ['今天', '是', '晴天。']);
  });

  test('splits Japanese as BudouX does', () {
    expect(phrases('今日は天気です。', PhraseModel.ja), ['今日は', '天気です。']);
  });

  test('each language its model; none where words have spaces', () {
    expect(PhraseModel.of(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')), PhraseModel.zhHant);
    expect(PhraseModel.of(const Locale('zh', 'TW')), PhraseModel.zhHant);
    expect(PhraseModel.of(const Locale('zh')), PhraseModel.zhHans);
    expect(PhraseModel.of(const Locale('ja')), PhraseModel.ja);
    expect(PhraseModel.of(const Locale('zh', 'HK')), PhraseModel.zhHant);
    expect(
      PhraseModel.of(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW')),
      PhraseModel.zhHant,
    );
    expect(PhraseModel.of(const Locale('zh', 'CN')), PhraseModel.zhHans);
    expect(PhraseModel.of(const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')), PhraseModel.zhHans);
    expect(PhraseModel.of(const Locale('ko')), isNull);
    expect(PhraseModel.of(const Locale('en')), isNull);
  });

  testWidgets('screen readers hear the text as written, without joiners or breaks', (tester) async {
    const text = '管理員不能直接退出。要退出，先把另一位同工設成管理員，再請對方取消你的管理員。';
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('zh', 'TW'),
        delegates: const [DefaultWidgetsLocalizations.delegate],
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(width: 150, child: BalancedText(text, textAlign: TextAlign.start)),
          ),
        ),
      ),
    );
    await tester.pump();
    final shown = tester.widget<Text>(find.byType(Text)).data!;
    expect(shown, contains('\u2060'), reason: 'wrapped, phrases are joined');
    expect(find.bySemanticsLabel(text), findsOneWidget);
    handle.dispose();
  });

  test('a joiner never lands inside an emoji, quoted or not', () {
    final joined = PhraseModel.zhHant.keepWhole('「謝謝😀大家」辛苦了😀');
    expect(joined.replaceAll('\u2060', ''), '「謝謝😀大家」辛苦了😀');
    expect(joined, contains('😀'), reason: 'the pair stays whole');
  });

  test('々 and 〇 belong to the words around them', () {
    expect(PhraseModel.ja.keepWhole('人々が集まる'), startsWith('人\u2060々'));
  });

  test("the app's own terms stay whole, though the model would split them", () {
    final joined = PhraseModel.zhHant.keepWhole('匯出可以用 Excel 打開的服事表');
    expect(joined, contains('服\u2060事\u2060表'));
  });

  test('a phrase is joined so no line breaks inside it; Latin and spaces are left alone', () {
    const text = '可以用 Excel 打開的服事表';
    final joined = PhraseModel.zhHant.keepWhole(text);
    expect(joined.replaceAll('\u2060', ''), text, reason: 'nothing else changes');
    expect(joined, contains('打\u2060開'));
    expect(joined, contains('Excel'), reason: 'Latin words already break only at spaces');
  });

  test('wrapped, every line ends between two phrases', () {
    const text = '請教會的管理員給你邀請連結，加入後就能看到大家的服事表';
    final model = PhraseModel.zhHant;
    final boundaries = {...model.boundaries(text), text.length};
    for (var width = 60.0; width <= 200; width += 10) {
      final shown = model.keepWhole(text);
      final painter = TextPainter(
        text: TextSpan(text: shown, style: const TextStyle(fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      for (final end in lineEnds(painter)) {
        final plainEnd = shown.substring(0, end).replaceAll('\u2060', '').length;
        expect(boundaries, contains(plainEnd), reason: 'width $width: ${text.substring(0, plainEnd)}|');
      }
      painter.dispose();
    }
  });
}
