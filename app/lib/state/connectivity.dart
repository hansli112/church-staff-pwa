import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

final connectivityProvider = StreamProvider<bool>((ref) => ref.watch(backendProvider).connectivity.watch());

/// A transport hint, never inferred from Firestore's normal cache snapshots.
final onlineProvider = Provider<bool>(
  (ref) => ref.watch(connectivityProvider).value ?? ref.watch(backendProvider).connectivity.online,
);
