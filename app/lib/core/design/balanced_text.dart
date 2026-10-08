import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Text whose lines break where a reader would. Centered (the default), its
/// lines come out even, as CSS's `text-wrap: balance` does, instead of a
/// full line and a word or two left over below it; where it can, every line
/// but the last ends on a punctuation mark, so a phrase stays whole, and a
/// comma that ends a line is left out, the line break being pause enough:
/// 「接下來沒有你的服事／排到你時會出現在這裡」, not 「…排到你時會出現在／這裡」.
/// Aligned to the start, a paragraph takes a little less than its width
/// where that splits no 「quoted term」, leaves no line of one or two
/// characters, or ends lines on punctuation. Text that fits on one line is
/// left alone. Screen readers read [text] as it is.
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
  /// The text with the commas that end its lines left out, once laid out.
  String? _withoutCommas;

  @override
  void didUpdateWidget(BalancedText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _withoutCommas = null;
  }

  @override
  Widget build(BuildContext context) {
    final centered = widget.textAlign == TextAlign.center;
    final text = centered ? widget.text : keepQuotesWhole(widget.text);
    final shown = centered ? (_withoutCommas ?? text) : text;
    return _Balanced(
      text: text,
      shown: shown,
      onShown: centered ? (s) => setState(() => _withoutCommas = s) : null,
      style: DefaultTextStyle.of(context).style.merge(widget.style),
      textScaler: MediaQuery.textScalerOf(context),
      direction: Directionality.of(context),
      centered: centered,
      child: Text(shown, style: widget.style, textAlign: widget.textAlign, semanticsLabel: widget.text),
    );
  }
}

/// [text] with the commas (，) at the [ends] of its lines, but the last,
/// turned into line breaks.
String dropLineEndCommas(String text, List<int> ends) {
  final chars = text.split('');
  for (final end in ends.take(ends.length - 1)) {
    var i = end - 1;
    while (i >= 0 && chars[i].trim().isEmpty) {
      i--;
    }
    if (i >= 0 && chars[i] == '，') chars[i] = '\n';
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
    if (depth > 0 && previous != null && previous != '「' && previous != '『' && c != '」' && c != '』') {
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

  /// What the child shows now: [text], or it without the commas that end
  /// its lines, which [onShown] asks for once it knows them.
  final String shown;
  final ValueChanged<String>? onShown;
  final TextStyle style;
  final TextScaler textScaler;
  final TextDirection direction;
  final bool centered;

  @override
  _RenderBalanced createRenderObject(BuildContext context) =>
      _RenderBalanced(text, style, textScaler, direction, centered)
        ..shown = shown
        ..onShown = onShown;

  @override
  void updateRenderObject(BuildContext context, _RenderBalanced renderObject) {
    renderObject
      ..text = text
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
  String shown = '';
  ValueChanged<String>? onShown;
  TextStyle style;
  TextScaler textScaler;
  TextDirection direction;
  bool centered;

  /// Not painted for the one frame until the child shows [text] without the
  /// commas that end its lines.
  bool _waiting = false;

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
      final wanted = width == null ? text : _withoutLineEndCommas(width);
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
      final last = text.substring(ends[ends.length - 2]).trim().characters.length;
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
