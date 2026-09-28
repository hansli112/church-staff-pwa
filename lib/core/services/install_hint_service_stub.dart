import 'install_hint_service.dart';

// 非 web（測試環境、未來若有原生版）：本來就是 App，沒有主畫面要加。

InstallHint readInstallHint() => const InstallHint(
  platform: InstallPlatform.other,
  isStandalone: true,
  canPrompt: false,
);

Future<String> promptInstall() async => 'unavailable';
