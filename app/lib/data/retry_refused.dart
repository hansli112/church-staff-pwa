import 'dart:async';

/// Listens to [open], and when the listener is refused ([isRefused]) opens it
/// again after a short wait, a few times, before letting the error through.
///
/// Right after sign-in, or when a page loads with a signed-in user, Firestore
/// can receive a listener before the new ID token. The rules then refuse it
/// with permission-denied and the listener stops for good, so the app looked
/// empty until a reload. A refusal that lasts (removed from a church) still
/// arrives, about three seconds later.
Stream<T> retryRefused<T>(
  Stream<T> Function() open, {
  required bool Function(Object error) isRefused,
  int retries = 4,
  Duration wait = const Duration(milliseconds: 300),
}) {
  late final StreamController<T> out;
  StreamSubscription<T>? sub;
  Timer? timer;
  var tried = 0;

  void start() {
    sub = open().listen(
      out.add,
      onError: (Object e, StackTrace s) {
        if (isRefused(e) && tried < retries) {
          tried++;
          unawaited(sub?.cancel());
          timer = Timer(wait * tried, start);
        } else {
          out.addError(e, s);
        }
      },
      onDone: () {
        if (timer == null || !timer!.isActive) unawaited(out.close());
      },
    );
  }

  out = StreamController<T>(
    onListen: start,
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    // Not returning the cancel future: a pending Firestore cancel must not
    // hold up whoever stops listening.
    onCancel: () {
      timer?.cancel();
      unawaited(sub?.cancel());
    },
  );
  return out.stream;
}
