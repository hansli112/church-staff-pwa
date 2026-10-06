import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/backend.dart';
import '../domain/day.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';
import '../domain/staff_order.dart';

/// Overridden in main() and in tests.
final backendProvider = Provider<Backend>(
  (ref) => throw UnimplementedError('backendProvider must be overridden'),
);

final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider must be overridden'),
);

/// Today on this device. Overridden in tests.
final todayProvider = Provider<Day>((ref) => Day.today());

final authUserProvider = StreamProvider<AuthUser?>(
  (ref) => ref.watch(backendProvider).auth.authState(),
);

/// The signed-in uid, or null. Changes only when the account changes, not
/// when the token refreshes.
final uidProvider = Provider<String?>(
  (ref) => ref.watch(authUserProvider.select((u) => u.value?.uid)),
);

final profileProvider = StreamProvider<UserProfile?>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(backendProvider).profiles.watch(uid);
});

/// The church name of an invite code; works signed out.
final invitedChurchProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, code) => ref.watch(backendProvider).cloud.invitedChurchName(code),
);

final membershipsProvider = StreamProvider<List<Membership>>((ref) {
  // Not "no churches" while the saved session is still being restored: that
  // empty list outlived the restore and sent a reload of /rosters to the
  // welcome page.
  if (ref.watch(authUserProvider.select((u) => u.isLoading && !u.hasValue))) return const Stream.empty();
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(backendProvider).memberships.watchMine(uid);
});

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

ChurchData _requireChurch(Ref ref) {
  final data = ref.watch(churchDataProvider);
  if (data == null) throw StateError('No current church');
  return data;
}

final churchProvider = StreamProvider<Church?>((ref) {
  final data = ref.watch(churchDataProvider);
  if (data == null) return Stream.value(null);
  return data.church();
});

/// Whether the current church is open. Church data is only requested when
/// it is, so a suspended church sends no reads that would be denied.
final churchOpenProvider = Provider<bool>(
  (ref) => ref.watch(churchProvider.select((c) => c.value?.isActive ?? false)),
);

ChurchData _requireOpenChurch(Ref ref) {
  if (!ref.watch(churchOpenProvider)) throw StateError('Church is not open');
  return _requireChurch(ref);
}

/// My member doc in the current church.
final meProvider = StreamProvider<Member?>((ref) {
  final data = ref.watch(churchDataProvider);
  final uid = ref.watch(uidProvider);
  if (data == null || uid == null) return Stream.value(null);
  return data.member(uid);
});

final servicesProvider = StreamProvider<ServiceSettings>(
  (ref) => _requireOpenChurch(ref).services(),
);

/// The church link at the top of the home page, or null.
final churchLinkProvider = StreamProvider<ChurchLink?>((ref) => _requireOpenChurch(ref).churchLink());

/// What was last fetched from the church link's content source.
final linkContentProvider = StreamProvider<LinkContent?>((ref) => _requireOpenChurch(ref).linkContent());

/// Saved rosters from today on, every service.
final savedRostersProvider = StreamProvider<List<Roster>>((ref) {
  final from = ref.watch(todayProvider);
  return _requireOpenChurch(ref).rosters(from: from);
});

/// Everyone in the church, read once per church and shared by every
/// screen. Only for admins and roster editors; others get an empty list.
final membersProvider = StreamProvider<List<Member>>((ref) {
  final canRead = ref.watch(
    meProvider.select((m) => m.value?.inGroup(Group.rosterEditors) ?? false),
  );
  if (!canRead) return Stream.value(const []);
  return _requireOpenChurch(ref).members();
});

/// Members moved from self-host who have not signed in yet. Like
/// [membersProvider], only for admins and roster editors.
final pendingMembersProvider = StreamProvider<List<PendingMember>>((ref) {
  final canRead = ref.watch(
    meProvider.select((m) => m.value?.inGroup(Group.rosterEditors) ?? false),
  );
  if (!canRead) return Stream.value(const []);
  return _requireOpenChurch(ref).pendingMembers();
});

final staffOrderProvider = StreamProvider.family<StaffOrder, String>(
  (ref, serviceType) => _requireOpenChurch(ref).staffOrder(serviceType),
);

/// How many weeks ahead the roster tab shows.
const rosterWeeks = 13;

/// The rosters of one service to show: saved days plus drafts for the
/// other weeks. Computed here, not in build, and only when its inputs
/// change.
final serviceRostersProvider = Provider.family<AsyncValue<List<Roster>>, String>((ref, serviceType) {
  final settings = ref.watch(servicesProvider);
  final saved = ref.watch(savedRostersProvider);
  final today = ref.watch(todayProvider);
  if (settings.hasError) {
    return AsyncError(settings.error!, settings.stackTrace!);
  }
  if (saved.hasError) return AsyncError(saved.error!, saved.stackTrace!);
  final service = settings.value?.byId(serviceType);
  final rosters = saved.value;
  if (service == null || rosters == null) return const AsyncLoading();
  return AsyncData(
    upcomingRosters(
      service: service,
      saved: rosters,
      from: today,
      weeks: rosterWeeks,
    ),
  );
});

/// The days I serve, soonest first.
final myServicesProvider = Provider<AsyncValue<List<MyService>>>((ref) {
  final saved = ref.watch(savedRostersProvider);
  final me = ref.watch(meProvider).value;
  final uid = ref.watch(uidProvider);
  if (saved.hasError) return AsyncError(saved.error!, saved.stackTrace!);
  final rosters = saved.value;
  if (rosters == null || uid == null) return const AsyncLoading();
  return AsyncData(myServices(rosters, uid: uid, name: me?.name ?? ''));
});

/// Where the app is, which decides the screen the router shows.
enum AppStage { loading, signedOut, noChurch, churchClosed, ready }

final appStageProvider = Provider<AppStage>((ref) {
  final user = ref.watch(authUserProvider);
  if (user.isLoading && !user.hasValue) return AppStage.loading;
  if (user.value == null) return AppStage.signedOut;
  final memberships = ref.watch(membershipsProvider);
  if (!memberships.hasValue) {
    return memberships.hasError ? AppStage.noChurch : AppStage.loading;
  }
  if (memberships.value!.isEmpty) return AppStage.noChurch;
  final church = ref.watch(churchProvider);
  if (!church.hasValue) {
    return church.hasError ? AppStage.churchClosed : AppStage.loading;
  }
  final c = church.value;
  if (c == null || !c.isActive) return AppStage.churchClosed;
  return AppStage.ready;
});

/// The web build (PWA) rather than a store app. Overridden in tests.
final isWebProvider = Provider<bool>((ref) => kIsWeb);

/// Whether I am the platform operator (custom claim, checked again by every
/// back-office function).
final isOperatorProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(uidProvider) == null) return false;
  return ref.watch(backendProvider).auth.isOperator();
});
