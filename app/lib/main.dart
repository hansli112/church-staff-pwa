import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/backend.dart';
import 'data/firebase/firebase_backend.dart';
import 'data/memory/demo_data.dart';
import 'env.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_TW');
  final env = Env.current;
  final prefs = await SharedPreferences.getInstance();
  final Backend backend = env.usesFirebase ? await _firebase(env) : demoBackend();

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
  final firestore = FirebaseFirestore.instance;
  // Offline cache: screens show the last data at once and update in the
  // background (docs/design.md, 效能).
  firestore.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  final functions = FirebaseFunctions.instanceFor(region: functionsRegion);
  if (env == Env.emulator) {
    final host = emulatorHost;
    firestore.useFirestoreEmulator(host, EmulatorPorts.firestore);
    await FirebaseAuth.instance.useAuthEmulator(host, EmulatorPorts.auth);
    functions.useFunctionsEmulator(host, EmulatorPorts.functions);
    await FirebaseStorage.instance.useStorageEmulator(
      host,
      EmulatorPorts.storage,
    );
  }
  return FirebaseBackend(functions: functions);
}
