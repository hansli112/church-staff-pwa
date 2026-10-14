import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/backend.dart';
import '../env.dart';
import 'providers.dart';

/// Where a store app came from, and so where it is updated.
enum AppStore {
  googlePlay('Google Play'),
  appStore('App Store');

  const AppStore(this.label);

  /// The store's own name, the same in every language.
  final String label;

  /// The app's page in the store. The App Store's needs [appleAppId]; until
  /// it is set, the website, which links to the stores.
  Uri get page => switch (this) {
    googlePlay => Uri.https('play.google.com', '/store/apps/details', {'id': 'app.marthasit'}),
    appStore =>
      appleAppId.isEmpty ? Uri.parse(Env.current.webOrigin) : Uri.https('apps.apple.com', '/app/id$appleAppId'),
  };

  /// The lowest build of this store's app that may still run.
  int lowestIn(MinimumBuilds min) => switch (this) {
    googlePlay => min.android,
    appStore => min.ios,
  };
}

/// The app's Apple ID in the App Store (App Store Connect → App Information),
/// once it is listed there (#40). Set it before raising `minBuild.ios`.
const appleAppId = '';

/// The store app running: its store, its version (`1.0.0`) and build
/// number (pubspec's `+12`).
class AppBuild {
  const AppBuild({required this.store, required this.version, required this.number});

  final AppStore store;
  final String version;
  final int number;

  /// As 我的 shows it: `1.0.0 (12)`.
  String get label => '$version ($number)';

  /// This phone's, read once at start; null on the web, which updates itself,
  /// and if the phone will not say (then nothing is held back).
  static Future<AppBuild?> read() async {
    if (kIsWeb) return null;
    final store = switch (defaultTargetPlatform) {
      TargetPlatform.android => AppStore.googlePlay,
      TargetPlatform.iOS => AppStore.appStore,
      _ => null,
    };
    if (store == null) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final number = int.tryParse(info.buildNumber);
      return number == null ? null : AppBuild(store: store, version: info.version, number: number);
    } catch (_) {
      return null;
    }
  }
}

/// The store app running, set at start ([AppBuild.read]); null on the web,
/// in the demo and in tests that do not say.
final appBuildProvider = Provider<AppBuild?>((ref) => null);

/// The oldest builds the backend still lets run, live: raising it reaches
/// an open app too.
final minimumBuildsProvider = StreamProvider<MinimumBuilds>(
  (ref) => ref.watch(backendProvider).platform.minimumBuilds(),
);

/// This store app is older than its store's lowest allowed build, and must
/// be updated before anything else. Never on the web.
final updateRequiredProvider = Provider<bool>((ref) {
  final build = ref.watch(appBuildProvider);
  final min = ref.watch(minimumBuildsProvider).value;
  if (build == null || min == null) return false;
  return build.number < build.store.lowestIn(min);
});
