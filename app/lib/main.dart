import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/backend.dart';
import 'data/firebase/firebase_backend.dart';
import 'data/memory/demo_data.dart';
import 'env.dart';
import 'state/providers.dart';

Future<void> main() async {
  // Real paths (/join/CODE), not #/: invite links must work as plain URLs.
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_TW');
  final env = Env.current;
  final prefs = await SharedPreferences.getInstance();
  final Backend backend = env.usesFirebase ? await _firebase(env) : demoBackend();

  // End-to-end tests drive the web build through the accessibility tree.
  if (const bool.fromEnvironment('E2E')) SemanticsBinding.instance.ensureSemantics();

  runApp(
    ProviderScope(
      overrides: [
        backendProvider.overrideWithValue(backend),
        prefsProvider.overrideWithValue(prefs),
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
