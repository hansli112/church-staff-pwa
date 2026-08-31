// 非 web（App 測試環境、未來若有原生版）：沒有 service worker，也就沒有這回事。

bool isUpdateCheckSupported() => false;

Future<String> checkForUpdate() async => 'unsupported';
