/// Which church the app is in and whether it is open: the one place that
/// decides it. Everything about the current church, read or written, gets
/// it from here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backend.dart';
import '../domain/models.dart';
import 'providers.dart';

/// The church the user picked last, remembered on this device.
class SelectedChurch extends Notifier<String?> {
  static const _key = 'selected_church';

  @override
  String? build() {
    // Re-read when the account changes; sign-out clears the key.
    ref.watch(uidProvider);
    return ref.watch(prefsProvider).getString(_key);
  }

  void select(String churchId) {
    state = churchId;
    ref.read(prefsProvider).setString(_key, churchId);
  }

  /// On sign-out: the next account starts from its own first church. The
  /// church on screen stays until the account changes, so nothing loads
  /// another church on the way out.
  Future<void> forget() => ref.read(prefsProvider).remove(_key);
}

final selectedChurchProvider = NotifierProvider<SelectedChurch, String?>(
  SelectedChurch.new,
);

/// The church every screen shows: the one picked last if still a member,
/// otherwise the first membership. Null while loading or with no church.
final currentChurchIdProvider = Provider<String?>((ref) {
  final memberships = ref.watch(membershipsProvider).value;
  if (memberships == null || memberships.isEmpty) return null;
  final selected = ref.watch(selectedChurchProvider);
  for (final m in memberships) {
    if (m.churchId == selected) return selected;
  }
  final ids = memberships.map((m) => m.churchId).toList()..sort();
  return ids.first;
});

final churchDataProvider = Provider<ChurchData?>((ref) {
  final cid = ref.watch(currentChurchIdProvider);
  if (cid == null) return null;
  return ref.watch(backendProvider).church(cid);
});

final churchProvider = StreamProvider<Church?>((ref) {
  final data = ref.watch(churchDataProvider);
  if (data == null) return Stream.value(null);
  return data.church();
});

/// Whether the current church was deleted by its admin and can still be
/// restored. Turns false when [Church.restoreWindow] runs out.
final churchRestorableProvider = Provider<bool>((ref) {
  final until = ref.watch(churchProvider).value?.restorableUntil;
  if (until == null) return false;
  final now = ref.watch(clockProvider)();
  rebuildAt(ref, until.add(const Duration(milliseconds: 1)), now);
  return !now.isAfter(until);
});

/// Whether the current church is open. Church data is only requested when
/// it is, so a suspended church sends no reads that would be denied.
final churchOpenProvider = Provider<bool>(
  (ref) => ref.watch(churchProvider.select((c) => c.value?.isActive ?? false)),
);

/// The current church, for a provider that reads from it: every such
/// provider goes through here, so none reads from a church that is closed
/// (the reads would be denied) and each one starts over when the church
/// changes.
ChurchData openChurch(Ref ref) {
  if (!ref.watch(churchOpenProvider)) throw StateError('Church is not open');
  return ref.watch(churchDataProvider) ?? (throw StateError('No current church'));
}

/// The current church, for an action someone takes on a screen. Screens of
/// a church show only once it is loaded ([AppStage.ready]), or closed for
/// restoring it ([AppStage.churchClosed]).
extension CurrentChurchOfWidget on WidgetRef {
  ChurchData get churchData => read(churchDataProvider) ?? (throw StateError('No current church'));
}

/// [CurrentChurchOfWidget] for state outside a widget.
extension CurrentChurchOfRef on Ref {
  ChurchData get churchData => read(churchDataProvider) ?? (throw StateError('No current church'));
}
