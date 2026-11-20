import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/telemetry.dart';

void main() {
  test('errors that differ only in the render object they name are reported once', () {
    final f = WebErrorFilter();
    expect(
      f.admit(StateError('RenderBox was not laid out: minified:Class746#20b19')),
      'Bad state: RenderBox was not laid out: a render object',
    );
    expect(f.admit(StateError('RenderBox was not laid out: minified:Class684#d2052')), isNull);
    expect(f.admit(StateError('RenderBox was not laid out: RenderPadding#4f631')), isNull);
    expect(f.admit(Exception('Aborted()')), 'Exception: Aborted()');
    expect(f.admit(Exception('Aborted()')), isNull);
  });

  test("what the framework was doing, without a widget's arguments", () {
    String? phase(DiagnosticsNode? context) =>
        errorPhase(FlutterErrorDetails(exception: Exception('x'), context: context));
    expect(phase(ErrorDescription('while dispatching a pointer event')), 'while dispatching a pointer event');
    expect(phase(ErrorDescription('during performLayout()')), 'during performLayout()');
    expect(phase(ErrorDescription('building Text("王小明", inherit: true)')), 'building Text');
    expect(phase(ErrorDescription('building _Row-[<\'uid1\'>]')), 'building _Row-');
    expect(phase(ErrorDescription('building RenderParagraph#1a2b3')), 'building RenderParagraph');
    expect(phase(ErrorDescription('notifying listeners for ValueNotifier<String>: 王小明')), 'notifying listeners for ValueNotifier<String>');
    expect(phase(ErrorDescription('while handling\na gesture')), 'while handling');
    expect(phase(ErrorDescription('x' * 150)), hasLength(100));
    expect(phase(null), isNull);
    expect(phase(ErrorDescription('(')), isNull);
  });

  test('at most 20 reports a page load', () {
    final f = WebErrorFilter();
    final sent = [for (var i = 0; i < 30; i++) f.admit(Exception('$i'))].nonNulls;
    expect(sent, hasLength(20));
  });
}
