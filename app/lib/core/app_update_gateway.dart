import 'app_update_gateway_stub.dart' if (dart.library.js_interop) 'app_update_gateway_web.dart' as platform;

class AppUpdateCheck {
  const AppUpdateCheck({required this.available, required this.version});
  final bool available;
  final String version;
}

/// Activation and reload are deliberately separate so the Dart state layer
/// can recheck drafts, pending writes, route and identity after the SW replies.
abstract interface class AppUpdateGateway {
  String get runningVersion;
  bool get supported;
  Future<AppUpdateCheck> check();
  Future<void> activate();
  void setEditing(bool editing);
  void reload();
}

AppUpdateGateway createAppUpdateGateway() => platform.createGateway();
