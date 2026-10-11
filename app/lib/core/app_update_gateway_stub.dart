import 'app_update_gateway.dart';

AppUpdateGateway createGateway() => _NativeUpdates();

class _NativeUpdates implements AppUpdateGateway {
  @override
  String get runningVersion => 'native';
  @override
  bool get supported => false;
  @override
  Future<AppUpdateCheck> check() => Future.error(UnsupportedError('Use the app store to check native updates'));
  @override
  Future<void> activate() => Future.error(UnsupportedError('Native updates cannot reload the PWA'));
  @override
  void setEditing(bool editing) {}
  @override
  void reload() => throw UnsupportedError('Native updates cannot reload the PWA');
}
