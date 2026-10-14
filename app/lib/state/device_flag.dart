import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Something done once on this device, such as a reminder dismissed. Starts
/// false; once [mark]ed it stays true here for good.
class DeviceFlag extends Notifier<bool> {
  DeviceFlag(this._key);

  final String _key;

  @override
  bool build() => ref.watch(prefsProvider).getBool(_key) ?? false;

  void mark() {
    state = true;
    ref.read(prefsProvider).setBool(_key, true);
  }
}
