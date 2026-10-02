import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Which backend this build talks to, from `--dart-define=MARTHA_ENV=…`.
///
/// - `emulator` (default): the local Firebase emulators, project
///   `demo-martha`. No real project needed.
/// - `dev`, `prod`: the real Firebase projects.
/// - `demo`: everything in memory with sample data; no network at all.
enum Env {
  emulator,
  dev,
  prod,
  demo;

  static Env get current {
    const name = String.fromEnvironment('MARTHA_ENV', defaultValue: 'emulator');
    return Env.values.firstWhere(
      (e) => e.name == name,
      orElse: () => Env.emulator,
    );
  }

  bool get usesFirebase => this != Env.demo;

  /// Show developer-only screens (the component gallery).
  bool get isDevelopment => this != Env.prod;
}

/// Host the emulators listen on. The Android emulator reaches the host
/// machine at 10.0.2.2.
String get emulatorHost {
  const host = String.fromEnvironment('EMULATOR_HOST');
  if (host.isNotEmpty) return host;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return '10.0.2.2';
  }
  return 'localhost';
}

/// Ports from firebase.json.
abstract final class EmulatorPorts {
  static const firestore = 8181;
  static const auth = 9199;
  static const functions = 5001;
  static const storage = 9299;
}

FirebaseOptions firebaseOptionsFor(Env env) {
  switch (env) {
    case Env.emulator:
    case Env.demo:
      // A demo- project ID makes the emulators accept any credentials and
      // never touch a real project.
      return const FirebaseOptions(
        apiKey: 'demo-key',
        appId: '1:000000000000:web:0000000000000000',
        messagingSenderId: '000000000000',
        projectId: 'demo-martha',
        storageBucket: 'demo-martha.appspot.com',
        authDomain: 'demo-martha.firebaseapp.com',
      );
    case Env.dev:
    case Env.prod:
      // Filled in by `scripts/firebase-project.sh` once the projects exist;
      // see docs/firebase-setup.md.
      throw UnsupportedError(
        'Firebase options for ${env.name} are not configured yet. '
        'Run with --dart-define=MARTHA_ENV=emulator.',
      );
  }
}
