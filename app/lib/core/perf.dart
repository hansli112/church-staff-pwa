import 'package:flutter/widgets.dart';

/// `--dart-define=PERF_MARKS=true` prints `[perf] <name>` once per name,
/// after the frame that shows it, so tools/e2e/perf.mjs can time screens
/// without the accessibility tree (which itself costs time on the web).
const perfMarksEnabled = bool.fromEnvironment('PERF_MARKS');

final _seen = <String>{};

void perfMark(String name, {bool repeat = false}) {
  if (!perfMarksEnabled) return;
  if (!repeat && !_seen.add(name)) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // ignore: avoid_print
    print('[perf] $name');
  });
}
