import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/design/balanced_text.dart';

/// Where [text]'s lines end when laid out [width] wide, in the test font,
/// where every character is as wide as the font is tall.
List<String> linesAt(String text, double width, {double fontSize = 10}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: fontSize),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  final lines = <String>[];
  var start = 0;
  for (final end in lineEnds(painter)) {
    lines.add(text.substring(start, end));
    start = end;
  }
  painter.dispose();
  return lines;
}

double? paragraph(String text, double maxWidth) => paragraphWidth(
  text,
  style: const TextStyle(fontSize: 10),
  textScaler: TextScaler.noScaling,
  direction: TextDirection.ltr,
  maxWidth: maxWidth,
);

double? balanced(String text, double maxWidth, {double scale = 1}) => balancedWidth(
  text,
  style: const TextStyle(fontSize: 10),
  textScaler: TextScaler.linear(scale),
  direction: TextDirection.ltr,
  maxWidth: maxWidth,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const empty = '接下來沒有你的服事，排到你時會出現在這裡';

  test('one character left over: the lines even out, ending on the comma', () {
    expect(linesAt(empty, 190), ['接下來沒有你的服事，排到你時會出現在這', '裡'], reason: 'the problem');
    final width = balanced(empty, 190)!;
    expect(linesAt(empty, width), ['接下來沒有你的服事，', '排到你時會出現在這裡']);
  });

  test('without a phrase to end on, the lines just even out', () {
    const text = '一二三四五六七八九十一二三四五六七八九十一';
    final width = balanced(text, 200)!;
    final lines = linesAt(text, width);
    expect(lines, hasLength(2));
    expect((lines.first.length - lines.last.length).abs(), lessThanOrEqualTo(1));
  });

  test('text on one line is left alone', () {
    expect(balanced('沒有服事', 190), isNull);
  });

  test('larger text takes more lines, still even', () {
    final width = balanced(empty, 190, scale: 2)!;
    final lines = linesAt(empty, width, fontSize: 20);
    expect(lines.length, 3);
    expect(lines.map((l) => l.length).reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(8));
  });

  Future<void> pumpAt(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: width,
            child: const BalancedText(empty, style: TextStyle(fontSize: 10)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a comma that ends a line is left out; screen readers still hear it', (tester) async {
    await pumpAt(tester, 190);
    expect(find.text('接下來沒有你的服事\n排到你時會出現在這裡'), findsOneWidget);
    expect(tester.getSize(find.byType(Text)).width, lessThanOrEqualTo(110));
    expect(tester.widget<Text>(find.byType(Text)).semanticsLabel, empty);
  });

  testWidgets('on one line, the comma stays', (tester) async {
    await pumpAt(tester, 300);
    expect(find.text(empty), findsOneWidget);
  });

  test('only commas that end a line go', () {
    expect(dropLineEndCommas('一，二，三', [2, 5]), '一\n二，三');
    expect(dropLineEndCommas('一。二', [2, 3]), '一。二', reason: 'other marks stay');
  });

  group('a paragraph', () {
    test('leaves no last line of one or two characters', () {
      const text = '你會退出所有教會，帳號與個人資料會刪除且無法復原';
      expect(linesAt(text, 230).last, '原', reason: 'the problem');
      final lines = linesAt(text, paragraph(text, 230)!);
      expect(lines, hasLength(2));
      expect(lines.last.length, greaterThan(2));
    });

    test('splits no quoted term', () {
      const text = '這是因為還在審核中，點「進階」→「前往」即可。只會讀寫你選的日曆';
      final at = linesAt(text, 180);
      expect(at.first, endsWith('「前'), reason: 'the problem');
      final lines = linesAt(text, paragraph(text, 180)!);
      expect(lines, hasLength(at.length));
      expect(lines.first, isNot(endsWith('「前')));
      expect(lines.first, endsWith('→'));
    });

    test('a paragraph that already reads well keeps its full width', () {
      expect(paragraph('一二三四五六七八九十一二三四五六七八九十一二三四五六', 200), isNull);
    });

    test('a short step breaks after its comma', () {
      const text = '點手機上的「恩典之家」圖示打開，再登入一次';
      expect(linesAt(text, 180), ['點手機上的「恩典之家」圖示打開，再登', '入一次'], reason: 'the problem');
      expect(linesAt(text, paragraph(text, 180)!), ['點手機上的「恩典之家」圖示打開，', '再登入一次']);
    });

    test('a long note splits none of its quoted terms', () {
      const text = '接下來 Google 會顯示「這個應用程式未經驗證」。這是因為馬大別忙還在審核中，點「進階」→「前往」即可。只會讀寫你選的那個日曆';
      final width = paragraph(text, 300);
      final lines = linesAt(text, width ?? 300);
      for (final line in lines.take(lines.length - 1)) {
        expect('「'.allMatches(line).length, '」'.allMatches(line).length, reason: line);
      }
    });
  });

  test('quoted terms are joined, so no line breaks inside them', () {
    const text = '點「進階」→「前往」即可';
    final joined = keepQuotesWhole(text);
    expect(joined.replaceAll('\u2060', ''), text, reason: 'nothing else changes');
    expect(joined, contains('進\u2060階'));
    expect(joined, contains('前\u2060往'));
    expect(joined, isNot(contains('「\u2060')));
    expect(joined, isNot(contains('\u2060」')));
    for (final line in linesAt(joined, 50)) {
      expect(line.replaceAll('\u2060', ''), isNot(anyOf(endsWith('進'), endsWith('前'))), reason: line);
    }
  });
}
