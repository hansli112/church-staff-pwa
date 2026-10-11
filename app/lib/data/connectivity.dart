import 'dart:async';

import 'backend.dart';
import 'connectivity_platform_stub.dart' if (dart.library.js_interop) 'connectivity_platform_web.dart' as platform;

/// Native transport availability is learned from real online operations;
/// browser network events supply an additional hint. Cache metadata never
/// changes this status: cached → server is a normal, healthy startup.
class TransportConnectivity implements BackendConnectivity {
  TransportConnectivity({bool browserHints = false}) : _online = browserHints ? platform.online : true {
    if (browserHints) _platform = platform.changes.listen(observe);
  }

  bool _online;
  StreamSubscription<bool>? _platform;
  final _changes = StreamController<bool>.broadcast(sync: true);
  final _writes = StreamController<int>.broadcast();
  int _pendingWrites = 0;

  @override
  int get pendingWrites => _pendingWrites;

  @override
  Stream<int> watchPendingWrites() async* {
    yield _pendingWrites;
    yield* _writes.stream;
  }

  void Function() beginWrite() {
    _writes.add(++_pendingWrites);
    var released = false;
    return () {
      if (released) return;
      released = true;
      _writes.add(--_pendingWrites);
    };
  }

  @override
  bool get online => _online;

  @override
  Stream<bool> watch() async* {
    yield _online;
    yield* _changes.stream;
  }

  void observe(bool online) {
    if (_online == online) return;
    _online = online;
    _changes.add(online);
  }

  /// Only a browser's explicit offline hint prevents trying a request.
  /// A previous transport failure must not block a deliberate native retry.
  void requireBrowserOnline() {
    if (!platform.online) throw offlineReadOnly;
  }

  Future<void> close() async {
    await _platform?.cancel();
    await _changes.close();
    await _writes.close();
  }
}

const offlineReadOnly = CloudException(CloudErrorCode.unavailable, reason: CloudReason.offlineReadOnly);
