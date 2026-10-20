import 'phrase_models.dart' as models;

// iOS and Android: in the app, not deferred, for the reason in
// page_code_native.dart. The web build uses phrase_code_web.dart.

Future<void> loadPhraseModels() async {}

Map<String, Map<String, int>> get zhHantModel => models.zhHant;
Map<String, Map<String, int>> get zhHansModel => models.zhHans;
Map<String, Map<String, int>> get jaModel => models.ja;
