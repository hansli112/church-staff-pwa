import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_update_gateway.dart';
import '../router.dart';
import 'providers.dart';

enum UpdateRejection { editing, scopeChanged, unsafeRoute, noUpdate }

class UpdateRejected implements Exception {
  const UpdateRejected(this.reason);
  final UpdateRejection reason;
}

enum AppUpdatePhase { idle, checking, current, ready, applying, failed }

class AppUpdateState {
  const AppUpdateState({
    required this.runningVersion,
    required this.supported,
    this.phase = AppUpdatePhase.idle,
    this.availableVersion,
    this.error,
  });
  final String runningVersion;
  final bool supported;
  final AppUpdatePhase phase;
  final String? availableVersion;
  final Object? error;
  bool get busy => phase == AppUpdatePhase.checking || phase == AppUpdatePhase.applying;
}

final appUpdateGatewayProvider = Provider<AppUpdateGateway>((ref) => createAppUpdateGateway());
final appUpdateLocationProvider = Provider<String Function()>(
  (ref) =>
      () => ref.read(routerProvider).routerDelegate.currentConfiguration.uri.path,
);
final appUpdateProvider = NotifierProvider<AppUpdateController, AppUpdateState>(AppUpdateController.new);
typedef _UpdateIdentity = ({String? uid, String? cid, String? memberUid, bool active});

class AppUpdateController extends Notifier<AppUpdateState> {
  _UpdateIdentity? _checkedIdentity;
  @override
  AppUpdateState build() {
    final gateway = ref.watch(appUpdateGatewayProvider);
    return AppUpdateState(runningVersion: gateway.runningVersion, supported: gateway.supported);
  }

  _UpdateIdentity _identity() => (
    uid: ref.read(uidProvider),
    cid: ref.read(churchDataProvider)?.churchId,
    memberUid: ref.read(meProvider).value?.uid,
    active: ref.read(churchOpenProvider),
  );
  void _set(AppUpdatePhase phase, {String? availableVersion, Object? error}) => state = AppUpdateState(
    runningVersion: state.runningVersion,
    supported: state.supported,
    phase: phase,
    availableVersion: availableVersion ?? state.availableVersion,
    error: error,
  );
  bool get _locked =>
      ref.read(updateEditLockProvider).locked || ref.read(backendProvider).connectivity.pendingWrites > 0;
  void _safe() {
    if (_locked) throw const UpdateRejected(UpdateRejection.editing);
    if (_identity() != _checkedIdentity) throw const UpdateRejected(UpdateRejection.scopeChanged);
    if (!RegExp(r'^/(?:c/[^/]+/)?me(?:/about)?/?$').hasMatch(ref.read(appUpdateLocationProvider)())) {
      throw const UpdateRejected(UpdateRejection.unsafeRoute);
    }
  }

  Future<void> check() async {
    if (state.busy) return;
    final identity = _identity();
    _set(AppUpdatePhase.checking);
    try {
      final result = await ref.read(appUpdateGatewayProvider).check();
      if (!ref.mounted || identity != _identity()) throw const UpdateRejected(UpdateRejection.scopeChanged);
      _checkedIdentity = identity;
      state = AppUpdateState(
        runningVersion: state.runningVersion,
        supported: state.supported,
        phase: result.available ? AppUpdatePhase.ready : AppUpdatePhase.current,
        availableVersion: result.available ? result.version : null,
      );
    } catch (error) {
      if (ref.mounted) _set(AppUpdatePhase.failed, error: error);
      rethrow;
    }
  }

  Future<void> apply() async {
    final gateway = ref.read(appUpdateGatewayProvider);
    try {
      if (state.availableVersion == null || state.busy) throw const UpdateRejected(UpdateRejection.noUpdate);
      _safe();
      _set(AppUpdatePhase.applying);
      gateway.setEditing(_locked);
      await gateway.activate();
      if (!ref.mounted) throw const UpdateRejected(UpdateRejection.scopeChanged);
      _safe();
      gateway.setEditing(_locked);
      gateway.reload(); // no await between the last safety check and refresh
    } catch (error) {
      if (ref.mounted) _set(AppUpdatePhase.failed, error: error);
      rethrow;
    }
  }
}

/// Synchronous safety count; notifications are asynchronous so acquiring a
/// route/widget lease during initState never modifies providers during build.
class UpdateEditLock {
  int _count = 0;
  final _changes = StreamController<int>.broadcast();
  bool get locked => _count > 0;
  Stream<int> watch() async* {
    yield _count;
    yield* _changes.stream;
  }

  void Function() begin() {
    _changes.add(++_count);
    var released = false;
    return () {
      if (!released) {
        released = true;
        _changes.add(--_count);
      }
    };
  }

  Future<T> during<T>(Future<T> Function() work) async {
    final release = begin();
    try {
      return await work();
    } finally {
      release();
    }
  }
}

final updateEditLockProvider = Provider<UpdateEditLock>((ref) => UpdateEditLock());
final _editCountProvider = StreamProvider<int>((ref) => ref.watch(updateEditLockProvider).watch());
final _writeCountProvider = StreamProvider<int>((ref) => ref.watch(backendProvider).connectivity.watchPendingWrites());
final updateBlockedProvider = Provider<bool>((ref) {
  ref.watch(_editCountProvider);
  ref.watch(_writeCountProvider);
  return ref.watch(updateEditLockProvider).locked || ref.watch(backendProvider).connectivity.pendingWrites > 0;
});

void Function() beginEdit(Ref ref) => ref.read(updateEditLockProvider).begin();
Future<T> withEditLock<T>(Ref ref, Future<T> Function() work) => ref.read(updateEditLockProvider).during(work);

/// A retained editor route stays protected even when another indexed-stack
/// tab is showing. Pending mutations take independent leases through finally.
class UpdateEditGuard extends ConsumerStatefulWidget {
  const UpdateEditGuard({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<UpdateEditGuard> createState() => _UpdateEditGuardState();
}

class _UpdateEditGuardState extends ConsumerState<UpdateEditGuard> {
  late final void Function() _release;
  @override
  void initState() {
    super.initState();
    _release = ref.read(updateEditLockProvider).begin();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

bool isUpdateEditorRoute(String path) =>
    path == '/account' ||
    path == '/account/sign-in' ||
    path.startsWith('/welcome/create') ||
    path.startsWith('/welcome/move') ||
    path.startsWith('/admin') && path != '/admin/stats' ||
    path.startsWith('/rosters/import/') ||
    const {
      '/me/profile/name',
      '/me/language',
      '/me/link',
      '/me/webhook',
      '/me/calendar',
      '/me/notifications',
      '/me/invites',
    }.contains(path) ||
    RegExp(r'^/me/(?:members|services)/[^/]+$').hasMatch(path);
