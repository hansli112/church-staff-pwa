import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/backend.dart';
import '../domain/church_link.dart';
import '../domain/day.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';
import '../domain/staff_order.dart';
import 'current_church.dart';

export 'current_church.dart';

/// Overridden in main() and in tests.
final backendProvider = Provider<Backend>(
  (ref) => throw UnimplementedError('backendProvider must be overridden'),
);

final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider must be overridden'),
);

/// The backend's clock: what time it is for anything that depends on it.
/// A test moves time by giving its backend a clock of its own.
final clockProvider = Provider<DateTime Function()>((ref) => ref.watch(backendProvider).clock);

/// Today on this device. Turns over at midnight while the app stays open.
final todayProvider = Provider<Day>((ref) {
  final now = ref.watch(clockProvider)();
  rebuildAt(ref, DateTime(now.year, now.month, now.day + 1), now);
  return Day.today(now);
});

/// Rebuilds the provider at [at], for what changes with time alone. Wakes
/// at least daily: a browser fires a timer over 24.8 days at once.
void rebuildAt(Ref ref, DateTime at, DateTime now) {
  if (!at.isAfter(now)) return;
  final wait = at.difference(now);
  final timer = Timer(wait < const Duration(days: 1) ? wait : const Duration(days: 1), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
}

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

/// My member doc in the current church.
final meProvider = StreamProvider<Member?>((ref) {
  final data = ref.watch(churchDataProvider);
  final uid = ref.watch(uidProvider);
  if (data == null || uid == null) return Stream.value(null);
  return data.member(uid);
});

final servicesProvider = StreamProvider<ServiceSettings>(
  (ref) => openChurch(ref).services(),
);

/// The church link at the top of the home page, or null.
final churchLinkProvider = StreamProvider<ChurchLink?>((ref) => openChurch(ref).churchLink());

/// What was last fetched from the church link's content source.
final linkContentProvider = StreamProvider<LinkContent?>((ref) => openChurch(ref).linkContent());

/// What the home page shows for the church link, or null when there is
/// none: the fetched content while fresh, then the fixed link.
final shownChurchLinkProvider = Provider<({String title, String body, String url})?>((ref) {
  // Watched directly so switching church marks this stale at once. Through
  // the link's streams alone, which pause while 首頁 is hidden, it would go
  // stale only when 首頁 shows again, mid-frame, and Riverpod would then
  // schedule its rebuild during a build.
  ref.watch(churchDataProvider);
  final link = ref.watch(churchLinkProvider).value;
  if (link == null) return null;
  final loaded = ref.watch(linkContentProvider);
  // Until a sourced link's content has come, show nothing rather than the
  // fixed link it may replace a moment later. If it fails, the fixed link.
  if (link.source != null && !loaded.hasValue && !loaded.hasError) return null;
  final content = loaded.value;
  final now = ref.watch(clockProvider)();
  final fetched = content?.fetchedAt;
  if (fetched != null) rebuildAt(ref, fetched.add(linkContentFresh), now);
  return shownChurchLink(link, content, now);
});

/// Saved rosters from today on, every service and event, and events'
/// rosters still on today (a retreat begun yesterday). Not an event's
/// roster cancelled with its event: the backend keeps it only for undo.
final savedRostersProvider = StreamProvider<List<Roster>>((ref) {
  final from = ref.watch(todayProvider);
  return openChurch(ref)
      .rosters(from: from)
      .map(
        (list) => [
          for (final r in list)
            if (!(r.forEvent?.cancelled ?? false)) r,
        ],
      );
});

/// Everyone in the church, read once per church and shared by every
/// screen. Only for admins and roster editors; others get an empty list.
final membersProvider = StreamProvider<List<Member>>((ref) {
  final canRead = ref.watch(
    meProvider.select((m) => m.value?.inGroup(Group.rosterEditors) ?? false),
  );
  if (!canRead) return Stream.value(const []);
  return openChurch(ref).members();
});

/// Members moved from self-host who have not signed in yet. Like
/// [membersProvider], only for admins and roster editors.
final pendingMembersProvider = StreamProvider<List<PendingMember>>((ref) {
  final canRead = ref.watch(
    meProvider.select((m) => m.value?.inGroup(Group.rosterEditors) ?? false),
  );
  if (!canRead) return Stream.value(const []);
  return openChurch(ref).pendingMembers();
});

final staffOrderProvider = StreamProvider.family<StaffOrder, String>(
  (ref, serviceType) => openChurch(ref).staffOrder(serviceType),
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
  // Watched directly so switching church marks this stale at once. Through
  // the saved rosters alone, it would go stale only when a newly built 首頁
  // (after joining or picking a church from an invite) first reads it, and
  // Riverpod would then schedule its rebuild during a build.
  ref.watch(churchDataProvider);
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
