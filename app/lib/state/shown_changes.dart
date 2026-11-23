import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/echoing_church_data.dart';

/// Changes made here that a backend call writes, shown at once (2026-11-23),
/// as [EchoingChurchData] shows its writes: each by its key, until refused,
/// or once written for [EchoingChurchData.linger], the backend's copy by
/// then having it.
class ShownChanges<T> extends Notifier<Map<String, T>> {
  final _timers = <Timer>{};

  @override
  Map<String, T> build() {
    ref.onDispose(() {
      for (final t in _timers) {
        t.cancel();
      }
    });
    return const {};
  }

  /// [value] shown for [key] while [write] writes it. Refused, it is no
  /// longer shown, and [write]'s error is thrown.
  Future<void> show(String key, T value, Future<void> Function() write) async {
    state = {...state, key: value};
    void drop() {
      if (ref.mounted && state.containsKey(key) && state[key] == value) state = {...state}..remove(key);
    }

    try {
      await write();
    } catch (_) {
      drop();
      rethrow;
    }
    late final Timer timer;
    timer = Timer(EchoingChurchData.linger, () {
      _timers.remove(timer);
      drop();
    });
    _timers.add(timer);
  }
}
