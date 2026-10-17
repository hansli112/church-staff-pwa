import 'dart:async';

import 'package:martha/core/design/phrases.dart';

/// Every test runs with the phrase models loaded, as the app is once it
/// starts (main.dart).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await PhraseModel.load();
  await testMain();
}
