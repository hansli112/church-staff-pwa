import 'dart:js_interop';

import 'app_update_gateway.dart';

@JS('marthaUpdate')
external _PageUpdate? get _pageUpdate;
extension type _PageUpdate(JSObject _) implements JSObject {
  external String get runningVersion;
  external bool get supported;
  external JSPromise<JSAny?> check();
  external JSPromise<JSAny?> activate();
  external void setEditing(bool editing);
  external void reload();
}

AppUpdateGateway createGateway() => _WebUpdates();

class _WebUpdates implements AppUpdateGateway {
  @override
  String get runningVersion => _pageUpdate?.runningVersion ?? 'development';
  @override
  bool get supported => _pageUpdate?.supported ?? false;
  @override
  Future<AppUpdateCheck> check() async {
    final page = _pageUpdate;
    if (page == null || !page.supported) throw UnsupportedError('This build does not support PWA updates');
    final result = (await page.check().toDart)?.dartify();
    if (result is! Map || result['available'] is! bool || result['version'] is! String) {
      throw const FormatException('Invalid update reply');
    }
    return AppUpdateCheck(available: result['available'] as bool, version: result['version'] as String);
  }

  @override
  Future<void> activate() async {
    await _pageUpdate!.activate().toDart;
  }

  @override
  void setEditing(bool editing) => _pageUpdate?.setEditing(editing);
  @override
  void reload() => _pageUpdate!.reload();
}
