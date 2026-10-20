import 'phrase_models.dart' deferred as models;

// The web build: the models are a part of their own. Native builds use
// phrase_code_native.dart.

Future<void> loadPhraseModels() => models.loadLibrary();

Map<String, Map<String, int>> get zhHantModel => models.zhHant;
Map<String, Map<String, int>> get zhHansModel => models.zhHans;
Map<String, Map<String, int>> get jaModel => models.ja;
