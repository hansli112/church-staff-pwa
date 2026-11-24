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

  test('the server answering at once goes straight through', () {
    fakeAsync((async) {
      final input = StreamController<_Snap>();
      final got = <String>[];
      serverFirst(input.stream, fromCache: (s) => s.cache).listen((s) => got.add(s.value));
      input.add((value: 'fresh', cache: false));
      async.flushMicrotasks();
      expect(got, ['fresh']);
      async.elapse(const Duration(seconds: 3));
      expect(got, ['fresh'], reason: 'no cached value afterwards');
    });
  });

  test('an error comes through, and the cache waiting is not dropped', () {
    fakeAsync((async) {
      final input = StreamController<_Snap>();
      final got = <String>[];
      final errors = <Object>[];
      serverFirst(input.stream, fromCache: (s) => s.cache).listen((s) => got.add(s.value), onError: errors.add);
      input.add((value: 'a', cache: true));
      input.addError('refused');
      async.flushMicrotasks();
      expect(errors, ['refused']);
      async.elapse(const Duration(seconds: 2));
      expect(got, ['a']);
    });
  });

  test('closed with only the cache, the cache comes out first', () {
    fakeAsync((async) {
      final input = StreamController<_Snap>();
      final got = <String>[];
      var done = false;
      serverFirst(
        input.stream,
        fromCache: (s) => s.cache,
      ).listen((s) => got.add(s.value), onDone: () => done = true);
      input.add((value: 'a', cache: true));
      unawaited(input.close());
      async.flushMicrotasks();
      expect(got, ['a']);
      expect(done, isTrue);
    });
  });

  test('cancelled while waiting, nothing comes later', () {
    fakeAsync((async) {
      final input = StreamController<_Snap>();
      final got = <String>[];
      final sub = serverFirst(input.stream, fromCache: (s) => s.cache).listen((s) => got.add(s.value));
      input.add((value: 'a', cache: true));
      async.flushMicrotasks();
      unawaited(sub.cancel());
      async.elapse(const Duration(seconds: 3));
      expect(got, isEmpty);
      expect(input.hasListener, isFalse);
    });
  });
}
