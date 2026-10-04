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
  demo
  ;

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

  /// Where invite links point. On the web it is wherever the app is served;
  /// native apps link to the hosted web app, which opens the app when it is
  /// installed.
  String get webOrigin {
    const override = String.fromEnvironment('WEB_ORIGIN');
    if (override.isNotEmpty) return override;
    if (kIsWeb) return Uri.base.origin;
    return switch (this) {
      Env.prod => 'https://marthasit.web.app',
      _ => 'https://marthasit-dev.web.app',
    };
  }
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
  static const storage = 9399;
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
      // From --dart-define-from-file=config/<env>.json, which
      // scripts/firebase-project.sh writes. These values identify the
      // project; they are not secrets (the security rules are the boundary).
      const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
      if (projectId.isEmpty) {
        throw UnsupportedError(
          'No Firebase config for ${env.name}: build with --dart-define-from-file=config/${env.name}.json '
          '(docs/firebase-setup.md).',
        );
      }
      final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      return FirebaseOptions(
        apiKey: const String.fromEnvironment('FIREBASE_API_KEY'),
        appId: android
            ? const String.fromEnvironment('FIREBASE_ANDROID_APP_ID')
            : ios
            ? const String.fromEnvironment('FIREBASE_IOS_APP_ID')
            : const String.fromEnvironment('FIREBASE_WEB_APP_ID'),
        messagingSenderId: const String.fromEnvironment('FIREBASE_SENDER_ID'),
        projectId: projectId,
        storageBucket: const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
        authDomain: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
        measurementId: const String.fromEnvironment('FIREBASE_MEASUREMENT_ID'),
        iosBundleId: ios ? 'app.marthasit' : null,
      );
  }
}
