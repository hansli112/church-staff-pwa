import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/server_first.dart';

typedef _Snap = ({String value, bool cache});

void main() {
  test('the cache answering first waits for the server', () {
    fakeAsync((async) {
      final input = StreamController<_Snap>();
      final got = <String>[];
      serverFirst(input.stream, fromCache: (s) => s.cache).listen((s) => got.add(s.value));
      input.add((value: 'stale', cache: true));
      async.elapse(const Duration(milliseconds: 500));
      expect(got, isEmpty);
      input.add((value: 'fresh', cache: false));
      async.flushMicrotasks();
      expect(got, ['fresh']);
      input.add((value: 'later', cache: true));
      async.flushMicrotasks();
      expect(got, ['fresh', 'later']);
    });
  });

  test('offline, the cache shows after a while', () {
    fakeAsync((async) {
      final input = StreamController<_Snap>();
      final got = <String>[];
      serverFirst(input.stream, fromCache: (s) => s.cache).listen((s) => got.add(s.value));
      input.add((value: 'a', cache: true));
      input.add((value: 'b', cache: true));
      async.elapse(const Duration(seconds: 2));
      expect(got, ['b']);
      input.add((value: 'c', cache: false));
      async.flushMicrotasks();
      expect(got, ['b', 'c']);
    });
  });
}
