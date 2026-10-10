import 'dart:convert';

import 'package:flutter/services.dart';

/// Browser widget tests have no VM flutter/assets handler. Font behavior
/// uses this file-system fixture; release browser checks use the real ARB.
class UiStringsBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    utf8.encode('''
{
  "appName": "馬大別忙",
  "signInWithGoogle": "使用 Google 登入",
  "myServicesTitle": "我接下來的服事",
  "switchChurch": "切換教會",
  "statsCost": "估計費用（USD）",
  "photoRecognizing": "辨識中，大約需要一分鐘",
  "@appName": {"description": "placeholders are notes, not UI text"}
}
'''),
  );
}
