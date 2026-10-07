/// The contract on FirebaseBackend, against the local emulators (auth,
/// firestore, functions, storage; project demo-martha). Runs in Chrome, the
/// Firebase plugins have no VM implementation:
///
///   scripts/check.sh contract
///
/// which starts the emulators and runs
/// `flutter test --platform chrome test/contract/firebase_contract_test.dart`.
@TestOn('browser')
@Timeout(Duration(minutes: 2))
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_functions_web/cloud_functions_web.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_web/firebase_auth_web.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_storage_web/firebase_storage_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:martha/data/firebase/firebase_backend.dart';
import 'package:martha/env.dart';

import 'contract_suite.dart';
import 'firebase_world.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // A test has no generated plugin registrant; without these,
  // Firebase.initializeApp never completes.
  FirebaseCoreWeb.registerWith(webPluginRegistrar);
  FirebaseAuthWeb.registerWith(webPluginRegistrar);
  FirebaseFirestoreWeb.registerWith(webPluginRegistrar);
  FirebaseFunctionsWeb.registerWith(webPluginRegistrar);
  FirebaseStorageWeb.registerWith(webPluginRegistrar);

  late FirebaseWorld world;
  setUpAll(() async {
    await Firebase.initializeApp(options: firebaseOptionsFor(Env.emulator));
    await FirebaseAuth.instance.useAuthEmulator('localhost', EmulatorPorts.auth);
    final firestore = FirebaseFirestore.instance;
    firestore.settings = const Settings(persistenceEnabled: false);
    firestore.useFirestoreEmulator('localhost', EmulatorPorts.firestore);
    final functions = FirebaseFunctions.instanceFor(region: functionsRegion);
    functions.useFunctionsEmulator('localhost', EmulatorPorts.functions);
    await FirebaseStorage.instance.useStorageEmulator('localhost', EmulatorPorts.storage);
    world = FirebaseWorld(FirebaseBackend(functions: functions, serverReads: true));
  });

  contractTests(() async {
    await world.reset();
    return world;
  });
}
