import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Done once the web build has the initial page's fonts, which `main`
/// starts fetching (lib/core/fonts.dart). Done at once elsewhere.
final fontsReadyProvider = Provider<Future<void>>((_) => Future.value());

/// Releases background font warmup after the first usable page has drawn.
final onFirstPageDrawnProvider = Provider<void Function()>((_) => () {});
