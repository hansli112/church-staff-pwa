import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'phrases.dart';

/// The longest text, in UTF-16 units, kept whole by phrase: some four lines
/// on a phone.
const phraseLimit = 80;

/// Text whose lines break where a reader would. In Chinese or Japanese,
/// text up to [phraseLimit] breaks only between phrases ([PhraseModel]):
/// 「請教會的管理員／給你邀請連結」, not 「…管理／員…」. Centered (the default), its
/// lines come out even, as CSS's `text-wrap: balance` does, instead of a
/// full line and a word or two left over below it; where it can, every line
/// but the last ends on a punctuation mark, so a phrase stays whole, and a
/// comma that ends a line is left out, the line break being pause enough:
/// 「接下來沒有你的服事／排到你時會出現在這裡」, not 「…排到你時會出現在／這裡」.
/// Aligned to the start, a paragraph takes a little less than its width
/// where that splits no 「quoted term」, leaves no line of one or two
/// characters, or ends lines on punctuation, and a line that would still end
/// inside a phrase ends at its last punctuation mark instead when the rest
/// fits in as many lines. Text that fits on one line is left alone. Screen
/// readers read [text] as it is.
class BalancedText extends StatefulWidget {
  const BalancedText(this.text, {super.key, this.style, this.textAlign = TextAlign.center});

  final String text;
  final TextStyle? style;

  /// [TextAlign.center] or [TextAlign.start].
  final TextAlign textAlign;

  @override
  State<BalancedText> createState() => _BalancedTextState();
}

class _BalancedTextState extends State<BalancedText> {
  /// What to show once laid out: centered, the text with the commas that end
  /// its lines left out; aligned to the start, the text as given when it
  /// fits on one line (quoted terms need no joining), else with lines that
  /// end at a phrase ([phraseBreaks]).
  /// With what it was worked out from: the text, or the language, may have
  /// changed since.
  ({String from, String shown})? _laidOut;

  @override
  Widget build(BuildContext context) {
    final centered = widget.textAlign == TextAlign.center;
    final model = PhraseModel.of(Localizations.maybeLocaleOf(context));
    // Phrases only in short text, as Android's phrase breaking: in a long
    // paragraph the ragged edge costs more than a split word.
    final text = model != null && widget.text.length <= phraseLimit
        ? model.keepWhole(widget.text)
        : centered
        ? widget.text
        : keepQuotesWhole(widget.text);
    // Until laid out, the text as given: most text fits on one line, and a
    // first frame that wraps is not painted.
    final laidOut = _laidOut;
    final shown = laidOut != null && laidOut.from == text ? laidOut.shown : widget.text;
    return _Balanced(
      text: text,
      plain: widget.text,
      shown: shown,
      // Laid out, then gone in the same frame (a row scrolled away, a toast
      // replaced): nothing to show.
      onShown: (s) {
        if (mounted) {
          setState(() => _laidOut = (from: text, shown: s));
        }
      },
      style: DefaultTextStyle.of(context).style.merge(widget.style),
      textScaler: MediaQuery.textScalerOf(context),
      direction: Directionality.of(context),
      centered: centered,
      child: Text(shown, style: widget.style, textAlign: widget.textAlign, semanticsLabel: widget.text),
    );
  }
}

/// [text] with the commas (，) at the [ends] of its lines, but the last,
/// turned into line breaks; one before a line break of [text] itself just
/// goes, so it leaves no empty line.
String dropLineEndCommas(String text, List<int> ends) {
  final chars = text.split('');
  for (final end in ends.take(ends.length - 1)) {
    var i = end - 1;
    while (i >= 0 && chars[i].trim().isEmpty) {
      i--;
    }
    if (i >= 0 && chars[i] == '，') {
      chars[i] = i + 1 < chars.length && chars[i + 1] == '\n' ? '' : '\n';
    }
  }
  return chars.join();
}

/// Joins the characters inside each 「」 or 『』 with an invisible WORD
/// JOINER (U+2060), so a line never breaks inside a quoted term such as
/// 「前往」. One longer than a line still breaks where it must.
String keepQuotesWhole(String text) {
  final out = StringBuffer();
  var depth = 0;
  String? previous;
  for (final c in text.characters) {
    if (depth > 0 &&
        previous != null &&
        previous != '「' &&
        previous != '『' &&
        previous != '\u2060' &&
        c != '」' &&
        c != '』' &&
        c != '\u2060') {
      out.write('\u2060');
    }
    if (c == '「' || c == '『') depth++;
    if ((c == '」' || c == '』') && depth > 0) depth--;
    out.write(c);
    previous = c;
  }
  return out.toString();
}

/// Lays its text out at [balancedWidth] (centered) or [paragraphWidth], in
/// the width it is given.
/// A render object rather than a LayoutBuilder, so parents that measure
/// their children first (SliverFillRemaining) can.
class _Balanced extends SingleChildRenderObjectWidget {
  const _Balanced({
    required this.text,
    required this.plain,
    required this.shown,
    required this.onShown,
    required this.style,
    required this.textScaler,
    required this.direction,
    required this.centered,
    required super.child,
  });

  /// What to lay out by.
  final String text;

  /// The text as given, before quoted terms were joined.
  final String plain;

  /// What the child shows now: [text], or what [onShown] asks for once it
  /// is laid out (see _RenderBalanced._waiting).
  final String shown;
  final ValueChanged<String>? onShown;
  final TextStyle style;
  final TextScaler textScaler;
  final TextDirection direction;
  final bool centered;

  @override
  _RenderBalanced createRenderObject(BuildContext context) =>
      _RenderBalanced(text, style, textScaler, direction, centered)
        ..plain = plain
        ..shown = shown
        ..onShown = onShown;

  @override
  void updateRenderObject(BuildContext context, _RenderBalanced renderObject) {
    renderObject
      ..text = text
      ..plain = plain
      ..shown = shown
      ..onShown = onShown
      ..style = style
      ..textScaler = textScaler
      ..direction = direction
      ..centered = centered
      ..markNeedsLayout();
  }
}

class _RenderBalanced extends RenderShiftedBox {
  _RenderBalanced(this.text, this.style, this.textScaler, this.direction, this.centered) : super(null);

  String text;
  String plain = '';
  String shown = '';
  ValueChanged<String>? onShown;
  TextStyle style;
  TextScaler textScaler;
  TextDirection direction;
  bool centered;

  /// Not painted for the one frame until the child shows what its layout
  /// wants: [text] without the commas that end its lines, [plain], or [text]
  /// with [phraseBreaks].
  bool _waiting = false;

  // Measured by the text as given, not as shown: a parent that sizes to
  // its child (a dialog) would otherwise shrink to the shown lines, and the
  // lines would change again for the new width.
  double _intrinsic(bool max) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: textScaler,
    )..layout();
    try {
      return max ? painter.maxIntrinsicWidth : painter.minIntrinsicWidth;
    } finally {
      painter.dispose();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) => _intrinsic(false);

  @override
  double computeMaxIntrinsicWidth(double height) => _intrinsic(true);

  double? _width(BoxConstraints constraints) => constraints.hasBoundedWidth
      ? (centered ? balancedWidth : paragraphWidth)(
          text,
          style: style,
          textScaler: textScaler,
          direction: direction,
          maxWidth: constraints.maxWidth,
        )
      : null;

  BoxConstraints _inner(double? width, BoxConstraints constraints) =>
      BoxConstraints(maxWidth: width ?? constraints.maxWidth, maxHeight: constraints.maxHeight);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(child.getDryLayout(_inner(_width(constraints), constraints)));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    final width = _width(constraints);
    final onShown = this.onShown;
    if (onShown != null) {
      final wanted = !centered
          ? _startAligned(width)
          : width == null
          ? plain
          : _withoutLineEndCommas(width);
      _waiting = wanted != shown;
      if (_waiting) SchedulerBinding.instance.addPostFrameCallback((_) => onShown(wanted));
    }
    child.layout(_inner(width, constraints), parentUsesSize: true);
    size = constraints.constrain(child.size);
    final spare = size.width - child.size.width;
    (child.parentData! as BoxParentData).offset = Offset(
      centered ? spare / 2 : (direction == TextDirection.rtl ? spare : 0),
      (size.height - child.size.height) / 2,
    );
  }

  /// Aligned to the start: [plain] on one line; otherwise [text] with lines
  /// that would end inside a phrase ending at a punctuation mark.
  String _startAligned(double? width) {
    if (!constraints.hasBoundedWidth) return text;
    final lines = _Lines(text, style, textScaler, direction);
    try {
      if (lines.endsAt(constraints.maxWidth).length <= 1) return plain;
    } finally {
      lines.dispose();
    }
    return phraseBreaks(
      text,
      style: style,
      textScaler: textScaler,
      direction: direction,
      maxWidth: width ?? constraints.maxWidth,
    );
  }

  String _withoutLineEndCommas(double width) {
    final lines = _Lines(text, style, textScaler, direction);
    try {
      return dropLineEndCommas(text, lines.endsAt(width));
    } finally {
      lines.dispose();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_waiting) super.paint(context, offset);
  }
}

/// Where a line may end and still read as a whole phrase.
const _phraseEnds = '，、。：；！？）」』,.;:!?)';

/// Where the lines of [painter]'s laid-out text end, as offsets into it.
/// Asked of each line's far end: the web engine's getLineBoundary gives the
/// first line again for the start of the next.
List<int> lineEnds(TextPainter painter) => [
  for (final line in painter.computeLineMetrics())
    painter.getPositionForOffset(Offset(painter.width + 1000, line.baseline - line.ascent / 2)).offset,
];

/// Where [text]'s lines end at a given width.
class _Lines {
  _Lines(this.text, TextStyle style, TextScaler textScaler, TextDirection direction)
    : _painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: textScaler,
      );

  final String text;
  final TextPainter _painter;

  List<int> endsAt(double width) {
    _painter.layout(maxWidth: width);
    return lineEnds(_painter);
  }

  void dispose() => _painter.dispose();
}

/// The width [text] should get within [maxWidth] for even lines, as a
/// centered [BalancedText] lays it out; null when it fits on one line.
double? balancedWidth(
  String text, {
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection direction,
  required double maxWidth,
}) {
  final lines = _Lines(text, style, textScaler, direction);
  try {
    final count = lines.endsAt(maxWidth).length;
    if (count <= 1) return null;

    // The narrowest width that still takes no more lines.
    var lo = 0.0, hi = maxWidth;
    while (hi - lo > 1) {
      final mid = (lo + hi) / 2;
      if (lines.endsAt(mid).length > count) {
        lo = mid;
      } else {
        hi = mid;
      }
    }

    // From there, the first width whose lines all end on a phrase.
    final step = textScaler.scale(style.fontSize ?? 14) / 2;
    for (var width = hi; width <= maxWidth; width += step) {
      final ends = lines.endsAt(width);
      if (ends.length != count) continue;
      final whole = ends
          .take(ends.length - 1)
          .every((end) => _phraseEnds.contains(text.substring(0, end).trimRight().characters.last));
      if (whole) return width;
    }
    return hi;
  } finally {
    lines.dispose();
  }
}

/// The width [text] should get within [maxWidth], as a start-aligned
/// [BalancedText] lays it out; null for [maxWidth] itself. Of the widths a
/// few characters narrower, the one whose lines read best: in order, no
/// line ending inside 「」 or 『』, no last line of one or two characters, no
/// more lines than needed, lines ending on punctuation; then the widest.
double? paragraphWidth(
  String text, {
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection direction,
  required double maxWidth,
}) {
  final lines = _Lines(text, style, textScaler, direction);
  bool insideQuote(int end) {
    final before = text.substring(0, end);
    int count(String c) => c.allMatches(before).length;
    return count('「') > count('」') || count('『') > count('』');
  }

  final char = textScaler.scale(style.fontSize ?? 14);
  try {
    final full = lines.endsAt(maxWidth);
    if (full.length <= 1) return null;
    double score(List<int> ends, double width) {
      final inner = ends.take(ends.length - 1);
      final last = text.substring(ends[ends.length - 2]).replaceAll('\u2060', '').trim().characters.length;
      return 10.0 * inner.where(insideQuote).length +
          (last <= 2 ? 5 : 0) +
          8.0 * (ends.length - full.length) +
          2.0 * inner.where((end) => !_phraseEnds.contains(text.substring(0, end).trimRight().characters.last)).length +
          0.1 * (maxWidth - width) / char;
    }

    var best = maxWidth;
    var bestScore = score(full, maxWidth);
    final narrowest = maxWidth - 8 * char > maxWidth / 2 ? maxWidth - 8 * char : maxWidth / 2;
    for (var width = maxWidth - char / 2; width >= narrowest; width -= char / 2) {
      final ends = lines.endsAt(width);
      if (ends.length <= 1) continue;
      final s = score(ends, width);
      if (s < bestScore) {
        best = width;
        bestScore = s;
      }
    }
    return best == maxWidth ? null : best;
  } finally {
    lines.dispose();
  }
}

/// [text] laid out in [maxWidth] with a line that would end inside a phrase
/// ending at the last punctuation mark in its second half instead, where
/// the rest still fits in as many lines: 「…要退出，／先把另一位同工設成管理員，…」,
/// not 「…先把另一位同工設成管理／員，…」. The break is a line break in the
/// text returned; [text] itself when nothing moves.
String phraseBreaks(
  String text, {
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection direction,
  required double maxWidth,
}) {
  List<int> endsOf(String s) {
    final lines = _Lines(s, style, textScaler, direction);
    try {
      return lines.endsAt(maxWidth);
    } finally {
      lines.dispose();
    }
  }

  var shown = text;
  var ends = endsOf(shown);
  var start = 0;
  for (var i = 0; i < ends.length - 1; i++) {
    final end = ends[i];
    final raw = shown.substring(start, end);
    final line = raw.trimRight();
    // Ends at a break of its own, or on a phrase already.
    if (line.isEmpty || raw.endsWith('\n') || _phraseEnds.contains(line.characters.last)) {
      start = end;
      continue;
    }
    var at = -1;
    final half = line.replaceAll('\u2060', '').length ~/ 2;
    for (var k = line.length - 1; k >= 0 && line.substring(0, k).replaceAll('\u2060', '').length >= half; k--) {
      // Not inside a quoted term, which the joiners keep whole.
      if (line[k] == '\u2060' || (k + 1 < line.length && line[k + 1] == '\u2060')) continue;
      // Every mark in _phraseEnds is one UTF-16 unit. A Western one ends a
      // phrase only before a space: not 26.5 or 2,000.
      final western = line.codeUnitAt(k) < 0x80;
      if (_phraseEnds.contains(line[k]) &&
          (!western || (k + 1 < shown.length - start && shown[start + k + 1] == ' '))) {
        at = start + k + 1;
        break;
      }
    }
    if (at > start) {
      final candidate = '${shown.substring(0, at)}\n${shown.substring(at).trimLeft()}';
      final candidateEnds = endsOf(candidate);
      if (candidateEnds.length <= ends.length) {
        shown = candidate;
        ends = candidateEnds;
        start = at + 1;
        continue;
      }
    }
    start = end;
  }
  return shown;
}
