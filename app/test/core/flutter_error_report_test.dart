import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/telemetry.dart';

/// A browser error whose JavaScript stack is gone: printing it throws.
class _BrokenStack implements StackTrace {
  @override
  String toString() => throw TypeError();
}

class _Recorded extends NoTelemetry {
  final errors = <(Object, String)>[];

  @override
  void recordError(Object error, StackTrace stack, {bool fatal = false, String? during, String? library}) =>
      errors.add((error, stackText(stack)));
}

void main() {
  test('an error is reported even when printing it to the console throws', () {
    final telemetry = _Recorded();
    final report = flutterErrorReporter(telemetry, present: (_) => throw TypeError());
    final error = StateError('the one that started it');
    report(FlutterErrorDetails(exception: error, stack: _BrokenStack()));
    expect(telemetry.errors.single.$1, error);
    expect(telemetry.errors.single.$2, '', reason: 'a stack that cannot be read is left out, not the error');
  });
}
