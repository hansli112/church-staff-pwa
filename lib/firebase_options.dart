// File generated manually based on user input
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are not supported for this platform.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: "AIzaSyDmxsNwAosSggaB-NvCyv2DS5OPbsTzRb8",
    authDomain: "church-staff-pwa.firebaseapp.com",
    projectId: "church-staff-pwa",
    storageBucket: "church-staff-pwa.firebasestorage.app",
    messagingSenderId: "190764228437",
    appId: "1:190764228437:web:2e21123171fd47065819dc",
    measurementId: "G-XVHTMHB7BV",
  );
}
