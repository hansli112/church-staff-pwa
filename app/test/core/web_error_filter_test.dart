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

  test('at most 20 reports a page load', () {
    final f = WebErrorFilter();
    final sent = [for (var i = 0; i < 30; i++) f.admit(Exception('$i'))].nonNulls;
    expect(sent, hasLength(20));
  });
}
