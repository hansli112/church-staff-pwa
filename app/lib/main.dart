import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/backend.dart';
import 'data/firebase/firebase_backend.dart';
import 'data/memory/demo_data.dart';
import 'env.dart';
import 'core/fonts.dart';
import 'core/telemetry.dart';
import 'data/firebase/push_firebase.dart';
import 'state/fonts.dart';
import 'state/providers.dart';
import 'state/push.dart';
import 'state/session.dart';
import 'state/support.dart';

Future<void> main() async {
  // Real paths (/c/ID), not #/: church URLs and invite links must work as
  // plain URLs.
  usePathUrlStrategy();
  // Pages opened with push (a roster day, a settings page) show their own
  // URL, so a reload or a shared address lands on that page, not its tab.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything else, so the fonts download while the app starts.
  final fontsReady = kIsWeb ? warmUpFonts(bundle: rootBundle, systemFonts: PaintingBinding.instance.systemFonts) : null;
  final env = Env.current;
  final prefs = await SharedPreferences.getInstance();
  final Backend backend = env.usesFirebase
      ? await _firebase(env)
      : demoBackend(newUser: const bool.fromEnvironment('DEMO_NEW_USER'));

  // End-to-end tests drive the web build through the accessibility tree.
  if (const bool.fromEnvironment('E2E')) SemanticsBinding.instance.ensureSemantics();

  // Real projects report crashes and analytics. Against the emulators only
  // the web error log runs (to the logClientError emulator); FCM, Crashlytics
  // and GA4 have no emulator.
  final real = env == Env.dev || env == Env.prod;
  final Telemetry telemetry = real || (env == Env.emulator && kIsWeb)
      ? FirebaseTelemetry(cloud: backend.cloud, analytics: real)
      : const NoTelemetry();
  final PushService push = real ? FirebasePushService(prefs: prefs) : const NoPush();
  // Tips and the subscription exist only in the store apps; the web build
  // never shows them.
  final native = !kIsWeb && env != Env.demo;
  final SupportStore store = native ? StoreKitPlayStore() : const NoStore();
  final AppIconSwitcher icons = native ? ChannelIconSwitcher() : const NoIconSwitcher();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    telemetry.recordError(details.exception, details.stack ?? StackTrace.empty);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    telemetry.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(
    ProviderScope(
      overrides: [
        backendProvider.overrideWithValue(backend),
        prefsProvider.overrideWithValue(prefs),
        telemetryProvider.overrideWithValue(telemetry),
        pushServiceProvider.overrideWithValue(push),
        supportStoreProvider.overrideWithValue(store),
        appIconSwitcherProvider.overrideWithValue(icons),
        if (fontsReady != null) fontsReadyProvider.overrideWithValue(fontsReady),
      ],
      // Streams retry by reconnecting themselves; a provider retry would
      // only repeat a permission error.
      retry: (_, _) => null,
      child: const MarthaApp(),
    ),
  );
}

Future<Backend> _firebase(Env env) async {
  await Firebase.initializeApp(options: firebaseOptionsFor(env));
  if (env == Env.emulator) {
    // Auth first. Known limit: a release web build restores the saved
    // session during initializeApp, before this runs, so against the
    // emulators a page reload signs out (debug builds and real projects
    // are fine).
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, EmulatorPorts.auth);
  }
  final firestore = FirebaseFirestore.instance;
  // Offline cache: screens show the last data at once and update in the
  // background (docs/design.md, 效能).
  firestore.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED);
  final functions = FirebaseFunctions.instanceFor(region: functionsRegion);
  if (env == Env.emulator) {
    firestore.useFirestoreEmulator(emulatorHost, EmulatorPorts.firestore);
    functions.useFunctionsEmulator(emulatorHost, EmulatorPorts.functions);
    await FirebaseStorage.instance.useStorageEmulator(emulatorHost, EmulatorPorts.storage);
  }
  return FirebaseBackend(functions: functions);
}
