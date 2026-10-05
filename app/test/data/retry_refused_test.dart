import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/retry_refused.dart';

class Refused implements Exception {}

/// A listener that is refused [refusals] times, then delivers [value].
Stream<int> Function() flaky(int refusals, {int value = 1}) {
  var opened = 0;
  return () {
    opened++;
    return opened <= refusals ? Stream.error(Refused()) : Stream.value(value);
  };
}

void main() {
  bool refused(Object e) => e is Refused;

  test('a listener refused right after sign-in is opened again and delivers', () {
    fakeAsync((time) {
      final got = <int>[];
      retryRefused(flaky(2), isRefused: refused).listen(got.add);
      time.elapse(const Duration(seconds: 5));
      expect(got, [1]);
    });
  });

  test('still refused after the retries: the error comes through', () {
    fakeAsync((time) {
      Object? error;
      retryRefused(flaky(99), isRefused: refused).listen((_) {}, onError: (Object e) => error = e);
      time.elapse(const Duration(seconds: 30));
      expect(error, isA<Refused>());
    });
  });

  test('other errors are not retried', () {
    fakeAsync((time) {
      var opened = 0;
      Object? error;
      retryRefused<int>(() {
        opened++;
        return Stream.error(StateError('offline'));
      }, isRefused: refused).listen((_) {}, onError: (Object e) => error = e);
      time.elapse(const Duration(seconds: 5));
      expect(error, isA<StateError>());
      expect(opened, 1);
    });
  });

  test('cancelling while waiting to retry opens nothing more', () {
    fakeAsync((time) {
      var opened = 0;
      final sub = retryRefused<int>(() {
        opened++;
        return Stream.error(Refused());
      }, isRefused: refused).listen((_) {}, onError: (_) {});
      time.flushMicrotasks();
      unawaited(sub.cancel());
      time.elapse(const Duration(seconds: 30));
      expect(opened, 1);
    });
  });
}
