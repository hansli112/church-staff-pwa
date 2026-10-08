import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Done once the web build has the fonts for the app's own text, which
/// `main` starts fetching (lib/core/fonts.dart). Done at once elsewhere.
final fontsReadyProvider = Provider<Future<void>>((_) => Future.value());
