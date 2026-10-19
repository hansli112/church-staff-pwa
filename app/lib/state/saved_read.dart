import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../data/cache/saved_reads.dart';
import '../env.dart' show deviceCacheProject;
import 'calendar_months.dart' show CalendarReadStatus;
import 'providers.dart';

final _savedReadsStoreProvider = Provider<SavedReads>((ref) => SavedReads(ref.watch(prefsProvider)));

/// The signed-in account's saved answers; none while signed out, which
/// drops them (watched by the app, so that happens at once). Restoring a
/// session at launch neither keeps nor drops them.
final savedReadsProvider = Provider<SavedReads?>((ref) {
  final store = ref.watch(_savedReadsStoreProvider);
  final uid = ref.watch(uidProvider);
  if (uid == null && ref.watch(authUserProvider.select((a) => a.isLoading))) return null;
  store.select(uid == null ? null : '${deviceCacheProject()}:$uid');
  return uid == null ? null : store;
});

/// What a [SavedRead] shows: the server's answer, or until it comes
/// ([fresh] false) the one this device kept from the last read.
class Saved<T> {
  const Saved(this.value, {required this.readAt, this.fresh = true, this.refreshError});

  final T value;
  final DateTime readAt;
  final bool fresh;

  /// Why reading again failed, with the kept answer still shown.
  final Object? refreshError;

  /// For [CalendarReadNotice]: labelled only once reading again failed.
  CalendarReadStatus get status =>
      CalendarReadStatus(cached: refreshError != null, fetchedAt: readAt, refreshError: refreshError);
}

/// A page's server read that shows at once from the answer this device kept
/// last time, while it reads again behind it, as 行事曆 does. Until the new
/// answer comes, [Saved.fresh] is false: what would act on the answer
/// waits. A failed read keeps the kept answer on screen; a refusal drops
/// it. With nothing kept it is an ordinary read.
class SavedRead<T> extends AsyncNotifier<Saved<T>> {
  SavedRead(
    this._key, {
    required Future<T> Function(Ref ref) read,
    required Object? Function(T value) encode,
    required T Function(Map<Object?, Object?> json) decode,
  }) : _readServer = read,
       _encode = encode,
       _decode = decode;

  final String _key;
  final Future<T> Function(Ref ref) _readServer;
  final Object? Function(T value) _encode;
  final T Function(Map<Object?, Object?> json) _decode;

  /// The latest read: an earlier one's answer comes too late to show.
  int _reads = 0;

  @override
  FutureOr<Saved<T>> build() {
    // The store is the same for every account: another one reads anew.
    ref.watch(uidProvider);
    final store = ref.watch(savedReadsProvider);
    final reading = _read(store);
    final kept = _kept(store);
    if (kept == null) return reading.answer;
    final current = ref;
    reading.answer.then(
      (answer) {
        if (current.mounted && reading.id == _reads) state = AsyncData(answer);
      },
      onError: (Object error, StackTrace stack) {
        if (!current.mounted || reading.id != _reads) return;
        state = _refused(error)
            ? AsyncError(error, stack)
            : AsyncData(Saved(kept.value, readAt: kept.readAt, fresh: false, refreshError: error));
      },
    );
    return kept;
  }

  /// Reads again with what shows staying until the answer, which it then
  /// shows (after a change made here, so the kept answer is out of date).
  /// If that read fails, what shows is no longer the server's: it is
  /// labelled, and what acts on it waits for another reload.
  Future<void> reload() async {
    final reading = _read(ref.read(savedReadsProvider));
    final current = ref;
    try {
      final answer = await reading.answer;
      if (current.mounted && reading.id == _reads) state = AsyncData(answer);
    } catch (error, stack) {
      if (!current.mounted || reading.id != _reads) rethrow;
      final shown = state.hasError ? null : state.value;
      if (_refused(error) || shown == null) {
        state = AsyncError(error, stack);
      } else {
        state = AsyncData(Saved(shown.value, readAt: shown.readAt, fresh: false, refreshError: error));
      }
      rethrow;
    }
  }

  ({int id, Future<Saved<T>> answer}) _read(SavedReads? store) {
    final clock = ref.read(clockProvider);
    final id = ++_reads;
    final scope = store?.scope;
    Future<Saved<T>> answer() async {
      try {
        final value = await _readServer(ref);
        final readAt = clock();
        // A later read keeps its own answer: this one would be older.
        if (scope != null && id == _reads) unawaited(store?.save(scope, _key, _encode(value), readAt: readAt));
        return Saved(value, readAt: readAt);
      } catch (error) {
        if (_refused(error)) unawaited(store?.forget(_key));
        rethrow;
      }
    }

    return (id: id, answer: answer());
  }

  Saved<T>? _kept(SavedReads? store) {
    final saved = store?.read(_key);
    if (saved == null || saved.json is! Map) return null;
    try {
      return Saved(_decode(saved.json! as Map), readAt: saved.readAt, fresh: false);
    } catch (_) {
      // What no longer reads back is not shown.
      return null;
    }
  }
}

/// No longer allowed to see it, or it is gone: nothing kept may show.
bool _refused(Object error) =>
    error is CloudException && (error.code == CloudErrorCode.permissionDenied || error.code == CloudErrorCode.notFound);
