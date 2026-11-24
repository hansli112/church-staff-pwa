import 'dart:async';

/// [snapshots] (with metadata changes) whose first value is the server's,
/// not what the local cache answers at once. The cache can be stale: a
/// 找人代 someone else already took, a 不能服事 sent from another phone. On
/// 首頁 that showed for a moment and went away, so these wait for the
/// server instead. Offline, the server never answers: after [wait] the
/// cache's latest is used. Once one value is out, every later one follows.
Stream<T> serverFirst<T>(
  Stream<T> snapshots, {
  required bool Function(T snapshot) fromCache,
  Duration wait = const Duration(seconds: 2),
}) {
  late final StreamController<T> out;
  StreamSubscription<T>? sub;
  Timer? timer;
  var started = false;
  T? cached;
  var hasCached = false;

  void emit(T value) {
    started = true;
    timer?.cancel();
    out.add(value);
  }

  out = StreamController<T>(
    onListen: () {
      sub = snapshots.listen(
        (s) {
          if (started || !fromCache(s)) return emit(s);
          cached = s;
          hasCached = true;
          timer ??= Timer(wait, () {
            if (hasCached && !started) emit(cached as T);
          });
        },
        onError: out.addError,
        onDone: () {
          timer?.cancel();
          if (!started && hasCached) out.add(cached as T);
          unawaited(out.close());
        },
      );
    },
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    onCancel: () {
      timer?.cancel();
      unawaited(sub?.cancel());
    },
  );
  return out.stream;
}
