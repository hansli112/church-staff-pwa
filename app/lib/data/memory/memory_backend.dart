import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals, mapEquals, setEquals;

import '../../core/languages.dart';
import '../../domain/day.dart';
import '../../domain/event_roster.dart';
import '../../domain/family.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../domain/service_changes.dart';
import '../../domain/roster_news.dart';
import '../../domain/staff_order.dart';
import '../../domain/swap.dart';
import '../../domain/text.dart';
import '../backend.dart';
import '../connectivity.dart';

part 'church_data.dart';
part 'small_groups.dart';
part 'rosters.dart';
part 'unavailable.dart';
part 'swaps.dart';
part 'service_settings.dart';
part 'group_members.dart';
part 'invites.dart';
part 'church.dart';
part 'claim.dart';
part 'family.dart';
part 'auth.dart';
part 'calendar.dart';
part 'roster_notes.dart';
part 'photos.dart';
part 'attendance.dart';
part 'read_once.dart';
part 'cloud.dart';

/// An in-memory [Backend] for widget tests and the offline demo: a verified
/// fake.
///
/// It keeps only the rules the screens depend on (who may read or write
/// what, invites, the last admin, an unverified email, a closed church),
/// and every one of them is checked against the real backend by the
/// contract tests in test/contract, which run the same cases on this class
/// and on the Firebase emulators. Whatever the backend computes beyond that
/// (reading a move file, fetching a church link's source, sending a
/// webhook, Google Calendar, photo recognition, the funding target) is not
/// imitated: those answers are scripted through the fields below.
class MemoryBackend implements Backend {
  MemoryBackend({DateTime Function()? clock}) : clock = clock ?? DateTime.now {
    auth = MemoryAuth();
    profiles = _Profiles(this);
    memberships = _Memberships(this);
    cloud = MemoryCloud(this);
    platform = _Platform(this);
  }

  @override
  final TransportConnectivity connectivity = TransportConnectivity();

  /// Whether the simulated network reaches the backend. What the app last
  /// observed ([connectivity]) can lag behind it, as on a phone.
  bool _network = true;

  void setOnline(bool online) {
    _network = online;
    connectivity.observe(online);
  }

  /// Like a real request: refused while the network is down, and a reply
  /// tells the app it is online again.
  void requireNetwork() {
    if (!_network) {
      connectivity.observe(false);
      throw offlineReadOnly;
    }
    connectivity.observe(true);
  }

  @override
  final DateTime Function() clock;

  @override
  late final MemoryAuth auth;
  @override
  late final ProfileRepository profiles;
  @override
  late final MembershipRepository memberships;
  @override
  late final MemoryCloud cloud;
  @override
  late final PlatformData platform;

  /// What the backend last published for the support page.
  Funding? funding;

  /// The oldest store builds still allowed to run.
  MinimumBuilds minimumBuilds = const MinimumBuilds();

  /// How many times the app started reading [minimumBuilds].
  int minimumBuildsReads = 0;

  /// The operator's cost list.
  List<CostItem> fundingCosts = [];

  /// Scripted: what the backend publishes once the operator changes the
  /// costs. Null leaves [funding] as it is.
  Funding Function(List<CostItem> costs)? publishFunding;

  /// 線上支持 payments by order number, and those the operator took off.
  final onlinePayments = <String, ({int amount, String month})>{};
  final refundedOnline = <String>{};

  final churches = <String, Church>{};

  /// Each query the back office searched churches for, as the backend
  /// scans every church for each one.
  final adminSearches = <String>[];
  final members = <String, Map<String, Member>>{};
  final services = <String, ServiceSettings>{};

  /// settings/ministries per church (#82); none until an admin makes one.
  final ministries = <String, MinistrySettings>{};

  /// churches/{cid}/smallGroups per church (#85), by id.
  final smallGroups = <String, Map<String, SmallGroupDetails>>{};

  /// 回報人數 per church and group key (#85).
  final attendance = <String, Map<String, AttendanceRecord>>{};

  /// 提醒 on 人數總覽 (#93) per church and group key: the day it was last
  /// reminded, the meeting it was about, and whom it told.
  final attendanceReminders = <String, Map<String, ({Day on, Day day, List<String> told})>>{};
  var _smallGroupIds = 0;

  /// churches/{cid}/gatherings per church: the 其他聚會, by id.
  final gatherings = <String, Map<String, Gathering>>{};
  var _gatheringIds = 0;
  final rosters = <String, Map<String, Roster>>{};

  /// 備註 per church, by roster ID; and files uploaded for them, by
  /// `rosterId/id`, kept or not.
  final rosterNotes = <String, Map<String, RosterNote>>{};
  final noteUploads = <String, Map<String, NoteFile>>{};

  /// Who uploaded each of [noteUploads], by church, then rosterId/id.
  final _noteUploaders = <String, Map<String, String>>{};
  var _noteFileIds = 0;

  /// 安排服事 (#90): per church, by `rosterId/uid`, someone put on or taken
  /// off a day there and not told yet: the service, and what they had on
  /// the day before (functions/src/rosterChange.ts, plannedPushes).
  final planned = <String, Map<String, ({String service, List<String> roles})>>{};

  /// 不能服事的日子 (#91) per church, by uid.
  final unavailable = <String, Map<String, UnavailableDays>>{};

  /// 通知同工填 (#91) per church, by service: when last asked, the months
  /// asked for, and whom it told.
  final unavailableAsks = <String, Map<String, ({DateTime at, Day from, Day to, List<String> told})>>{};

  /// What 通知同工填 (#91) asked of each, per church, by uid; and when each
  /// last sent theirs.
  final unavailableAsked = <String, Map<String, ({DateTime at, Day from, Day to})>>{};
  final unavailableSentAt = <String, Map<String, DateTime>>{};

  /// 找人代／交換 (#92) per church, by id, and when each was taken.
  final swapRequests = <String, Map<String, SwapRequest>>{};
  final swapTakenAt = <String, DateTime>{};
  var _swapIds = 0;
  final staffOrders = <String, Map<String, StaffOrder>>{};
  final invites = <String, Invite>{};
  final users = <String, UserProfile>{};

  /// Each person's 通知列表 (#89), by uid, in the order sent.
  final notifications = <String, List<NotificationItem>>{};
  final calendars = <String, CalendarSettings>{};

  /// What the Google account offers to pick from (calendarList).
  List<CalendarChoice> calendarChoices = const [
    (id: 'cal-1', name: '教會行事曆', timeZone: 'Asia/Taipei', primary: false),
    (id: 'cal-2', name: '青年行事曆', timeZone: 'Asia/Taipei', primary: false),
  ];
  final churchLinks = <String, ChurchLink>{};
  final linkContents = <String, LinkContent>{};

  /// Pending members per church, by ID.
  final pendingMembers = <String, Map<String, PendingMember>>{};

  /// Requests to join (申請加入, #88) per church, by uid.
  final joinRequests = <String, Map<String, JoinRequest>>{};

  /// 認領申請 per church, by the uid of who asked.
  final claimAsks = <String, Map<String, ClaimAsk>>{};

  /// 家人 per church, by ID (functions/src/family.ts).
  final households = <String, Map<String, Household>>{};
  var _familyIds = 0;

  /// How [uid]'s request to church [cid] stands now.
  JoinRequestState? joinRequestState(String cid, String uid) => joinRequests[cid]?[uid]?.stateAt(clock());

  /// The rosters a move recorded naming each pending member, per church:
  /// the only days a claim or a merge points at the member instead.
  final pendingRosterIds = <String, Map<String, List<String>>>{};

  /// Uploaded move files by path.
  final moveFiles = <String, List<int>>{};

  /// Scripted: what reading any uploaded move file gives, a [MovePreview]
  /// or the [CloudException] the backend would throw.
  Object moveAnswer = const CloudException(CloudErrorCode.moveInvalid);
  final webhooks = <String, WebhookSettings>{};

  /// The webhook secret per church: only the backend has it.
  final webhookSecrets = <String, String>{};

  /// Scripted: what the receiver does with the next notices.
  WebhookDelivery webhookAnswer = const WebhookDelivery(ok: true, status: 200);

  /// Notices sent, as (church, event).
  final webhookSent = <(String, String)>[];

  /// Scripted: what fetching each content source URL gives, a
  /// [LinkContent] (its title, body and link) or a [LinkFetchError].
  /// Unknown URLs fail with [LinkFetchError.network].
  final linkSourceAnswers = <String, Object>{};

  /// One explicit source-fetch reply, used by the next set/retry operation.
  LinkSourceResult? nextLinkResult;

  /// Sources fetched by [ChurchLinkData.save], in order.
  final linkSourceFetches = <String>[];

  /// Scripted: while set, the link content stream delivers nothing until
  /// this completes, as on a slow network. Completing it with an error
  /// fails the stream instead.
  Completer<void>? linkContentHeld;

  /// Scripted: while set, a member's own 不能服事的日子 come back changed
  /// only once this completes: the backend keeps them through a function,
  /// and the snapshot follows its answer, sometimes after it.
  Completer<void>? unavailableEchoHeld;

  /// Scripted Google Calendar: the events per church, and its calendars
  /// ([connectCalendar] stands in for the OAuth callback).
  final calendarEvents = <String, List<CalendarEvent>>{};

  /// Scripted: while set, reading a month's events waits for this to
  /// complete, as on a slow network. Completing it with an error fails it.
  Completer<void>? calendarEventsHeld;

  /// Scripted: while set, saving an event waits for this to complete, as
  /// on a slow network.
  Completer<void>? calendarSaveHeld;

  /// Scripted: while set, picking a calendar waits for this to complete, as
  /// on a cold start.
  Completer<void>? calendarSelectHeld;

  /// Scripted: while set, previewing an invite waits for this to complete,
  /// as on a slow network.
  Completer<void>? invitePreviewHeld;

  /// Scripted: while set, opening or changing a 小組 waits for this to
  /// complete, as on a slow network or a cold start.
  Completer<void>? smallGroupSaveHeld;

  /// Scripted: while set, 合併 (mergePending) waits for this to complete,
  /// as it takes seconds on the real backend.
  Completer<void>? mergeHeld;

  /// Scripted: while set, the back office's stats and costs wait for this
  /// to complete, as on a slow network.
  Completer<void>? backOfficeReadsHeld;

  /// Scripted: while set, the back office's 設為管理員 and 取消管理員 wait
  /// for this to complete, as on a slow network or a cold start.
  Completer<void>? adminChangeHeld;

  /// Scripted: while set, an account's memberships deliver nothing until
  /// this completes, as on a slow network.
  Completer<void>? membershipsHeld;

  /// Scripted: while set, a claim makes the member, then waits for this
  /// before pointing the rosters at them and dropping the pending member,
  /// as the backend does over a slow network.
  Completer<void>? claimRepointHeld;

  /// Pending members said yes to, by church, the rosters still being
  /// pointed at whoever claimed them (the backend's claimedFrom).
  final claiming = <String, Set<String>>{};

  /// Scripted: photos used this month per church, the limit, whether the
  /// platform's budget is left, and what recognition returns.
  final photosUsed = <String, int>{};
  int photoLimit = Limits.photosPerMonth;
  bool photoPlatformOpen = true;
  List<dynamic> recognized = const [];

  /// Scripted: photo recognition answers once this completes.
  Future<void>? recognizing;

  /// Scripted: what recognition fails with (Gemini down), the photo given back.
  Object? recognizeFailure;

  /// Set to make the next write fail, to test error handling.
  Object? failNextWrite;

  /// Simulated latency for every write.
  Duration writeDelay = Duration.zero;

  final _changes = StreamController<void>.broadcast(sync: true);

  void notify() => _changes.add(null);

  /// A stream of [read]'s value now and after every change, without
  /// repeats. A read that throws emits the error.
  Stream<T> watch<T>(T Function() read, {bool Function(T a, T b)? equals}) {
    late StreamController<T> controller;
    StreamSubscription<void>? sub;
    var hasLast = false;
    T? last;
    void emit() {
      try {
        final value = read();
        final same = hasLast && (equals != null ? equals(last as T, value) : last == value);
        if (same) return;
        hasLast = true;
        last = value;
        controller.add(value);
      } catch (e, st) {
        hasLast = false;
        controller.addError(e, st);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        scheduleMicrotask(emit);
        sub = _changes.stream.listen((_) => emit());
      },
      // Not awaited: `first` would wait on it, and fake-async tests never
      // finish that future.
      onCancel: () {
        sub?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> write(void Function() change) async {
    final release = connectivity.beginWrite();
    try {
      requireNetwork();
      final uid = auth.currentUser?.uid;
      if (writeDelay > Duration.zero) await Future<void>.delayed(writeDelay);
      requireNetwork();
      if (auth.currentUser?.uid != uid) throw const CloudException(CloudErrorCode.permissionDenied);
      final failure = failNextWrite;
      if (failure != null) {
        failNextWrite = null;
        throw failure;
      }
      change();
      notify();
    } finally {
      release();
    }
  }

  @override
  ChurchData church(String churchId) => MemoryChurchData(this, churchId);

  /// What pages have warmed up, oldest first. Nothing here needs starting.
  final warmedUp = <WarmUp>[];

  @override
  void warmUp(WarmUp what) => warmedUp.add(what);

  // Seeding helpers for tests and the demo.

  String addChurch(
    String name, {
    String? id,
    ChurchStatus status = ChurchStatus.active,
    ChurchTimeZone timeZone = ChurchTimeZone.fallback,
  }) {
    final cid = id ?? 'c${churches.length + 1}';
    churches[cid] = Church(id: cid, name: name, status: status, timeZone: timeZone);
    members[cid] = {};
    rosters[cid] = {};
    staffOrders[cid] = {};
    services[cid] = const ServiceSettings(services: [], ids: []);
    notify();
    return cid;
  }

  void addMember(String cid, Member member) {
    members[cid]![member.uid] = member;
    notify();
  }

  /// A push the backend sent [uid], in their 通知列表 (#89).
  void addNotification(String uid, NotificationItem n) {
    (notifications[uid] ??= []).add(n);
    notify();
  }

  /// A member moved from self-host who has not signed in yet, named on the
  /// rosters [rosterIds] (what a move records).
  void addPending(String cid, PendingMember pending, {List<String> rosterIds = const []}) {
    (pendingMembers[cid] ??= {})[pending.id] = pending;
    (pendingRosterIds[cid] ??= {})[pending.id] = rosterIds;
    notify();
  }

  void setServices(String cid, List<Service> list) {
    services[cid] = (services[cid] ?? const ServiceSettings(services: [])).withServices(list);
    notify();
  }

  Member? memberOf(String cid, String? uid) => uid == null ? null : members[cid]?[uid];

  bool isActiveMember(String cid, String? uid) =>
      memberOf(cid, uid) != null && churches[cid]?.status == ChurchStatus.active;

  /// The signed-in member of [cid], which must be open.
  Member requireMember(String cid) {
    final uid = auth.currentUser?.uid;
    if (!isActiveMember(cid, uid)) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    return memberOf(cid, uid)!;
  }

  /// The signed-in admin of [cid], which must be open.
  Member requireAdmin(String cid) {
    final me = requireMember(cid);
    if (!me.isAdmin) throw const CloudException(CloudErrorCode.permissionDenied);
    return me;
  }

  /// The caller's access to [cid], decided as functions/src/access.ts does
  /// for every function that acts in a church: a non-member is refused, a
  /// member of a closed church is told it is closed, then [allowed] decides.
  /// [anyone] lets in non-members (claiming a pending member), [allowClosed]
  /// a closed church (restoring it).
  Member? functionAccess(
    String cid, {
    bool Function(Member me)? allowed,
    bool anyone = false,
    bool allowClosed = false,
  }) {
    requireNetwork();
    final uid = auth.currentUser?.uid;
    if (uid == null) throw const CloudException(CloudErrorCode.permissionDenied);
    final church = churches[cid];
    final me = memberOf(cid, uid);
    if (anyone) {
      if (church == null) throw const CloudException(CloudErrorCode.notFound);
    } else if (me == null) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    if (!(church?.isActive ?? false) && !allowClosed) {
      throw const CloudException(CloudErrorCode.churchClosed);
    }
    if (allowed != null && (me == null || !allowed(me))) {
      throw const CloudException(CloudErrorCode.permissionDenied);
    }
    return me;
  }

  int _calendarRevision = 0;

  /// Simulates Google Calendar's OAuth callback for [cid].
  void connectCalendar(String cid, {String? calendarName, String? calendarId}) {
    calendars[cid] = CalendarSettings(
      connected: true,
      calendarName: calendarName,
      calendarId: calendarName == null ? null : (calendarId ?? 'cal-$cid'),
      revision: 'memory:${++_calendarRevision}',
    );
    notify();
  }

  int _secrets = 0;
  String newWebhookSecret() => 'whsec_memory${++_secrets}';

  int _events = 0;
  String newEventId() => 'ev${++_events}';
}

/// A person's name, on a profile or a member: refused past
/// [TextLimits.profileName] as firestore.rules refuses past its guard.
void _checkName(String name) {
  if (!withinTextLimit(name, TextLimits.profileName)) throw const CloudException(CloudErrorCode.permissionDenied);
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

final _random = Random();
const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String _randomCode() => List.generate(
  8,
  (_) => _alphabet[_random.nextInt(_alphabet.length)],
).join();

/// Moved data in [cid] waiting for [email] becomes [uid], new to the
/// church, as a claim does (claim.ts takeWaiting); whether there was one.
bool _takeWaiting(MemoryBackend b, String cid, String uid, String email) {
  final key = email.trim().toLowerCase();
  if (key.isEmpty) return false;
  final p = b.pendingMembers[cid]?.values.where((p) => p.email.trim().toLowerCase() == key).firstOrNull;
  if (p == null) return false;
  b.members[cid]![uid] = _withClaimedLeads(
    Member(
      uid: uid,
      name: p.name,
      email: email,
      role: p.role,
      zones: p.zones,
      smallGroups: p.smallGroups,
      mutedNotifications: p.mutedNotifications,
      joinedAt: b.clock(),
    ),
    p,
  );
  _settlePending(b, cid, p.id, uid);
  b.notify();
  return true;
}

/// Points the rosters the move recorded for pending member [pid] at [uid]
/// instead, and drops [pid]; as functions/src/claim.ts does.
void _settlePending(MemoryBackend b, String cid, String pid, String uid) {
  b.pendingMembers[cid]!.remove(pid);
  b.pendingRosterIds[cid]?.remove(pid);
  b.claimAsks[cid]?.removeWhere((_, a) => a.pendingId == pid);
  _repointFamily(b, cid, pid, uid, b.members[cid]?[uid]?.name ?? '');
  final rosters = b.rosters[cid]!;
  // The days the move recorded, and any they were put on since.
  for (final key in [...rosters.keys]) {
    final value = rosters[key]!;
    if (!value.duties.any((d) => d.uids.containsValue(pid))) continue;
    rosters[key] = value.copyWith(
      duties: [
        for (final d in value.duties)
          d.copyWith(uids: {for (final e in d.uids.entries) e.key: e.value == pid ? uid : e.value}),
      ],
    );
  }
}

/// [value] trimmed, if it is 1 to [max] characters; what `text()` in
/// functions/src/common.ts takes.
String _text(String value, int max) {
  final t = value.trim();
  if (t.isEmpty || !withinTextLimit(t, max)) throw const CloudException(CloudErrorCode.unknown);
  return t;
}

/// A webhook secret the admin typed, as functions/src/webhook.ts takes it.
void _checkSecret(String? secret) {
  if (secret != null && (secret.length < Limits.webhookSecretMin || secret.length > Limits.webhookSecretMax)) {
    throw const CloudException(CloudErrorCode.unknown, reason: CloudReason.secret);
  }
}

/// A pending member's old permission groups as 身分 (#82), as
/// claimedGroups in functions/src/claim.ts: calendar-editors folds into
/// 行政; roster-editors alone, their 牧區's rosters in self-host, makes them
/// 負責人 of the services they are in.
List<Identity> _claimedLeads(PendingMember p) {
  if (p.groups.contains(Group.calendarEditors)) return const [OfficeIdentity()];
  if (!p.groups.contains(Group.rosterEditors)) return const [];
  return [
    for (final type in {for (final z in p.zones) z.serviceType}) ServiceLead(type),
  ];
}

/// [m] also holding the 身分 pending member [p]'s groups give.
Member _withClaimedLeads(Member m, PendingMember p) => m.withIdentities([...m.identities, ..._claimedLeads(p)]);

/// [m] with the groups, zones and leads of pending member [p] added.
Member _absorb(Member m, PendingMember p) => _withClaimedLeads(m, p).copyWith(
  mutedNotifications: {...m.mutedNotifications, ...p.mutedNotifications},
  smallGroups: {...m.smallGroups, ...p.smallGroups},
  zones: [
    for (final type in {...m.zoneTypes, for (final z in p.zones) z.serviceType})
      Zone(
        serviceType: type,
        duties: {
          for (final z in [...m.zones, ...p.zones])
            if (z.serviceType == type) ...z.duties,
        }.toList(),
        smallGroups: {
          for (final z in [...m.zones, ...p.zones])
            if (z.serviceType == type) ...z.smallGroups,
        }.toList(),
      ),
  ],
);

/// Someone in a self-host export, [source] their user document (null when
/// it has none), as the move makes them a pending member: what
/// mapMember in functions/src/importer.ts does
/// (testdata/church_rules.json, movedMembers).
PendingMember movedMember({
  required String id,
  required String name,
  required String email,
  Map<dynamic, dynamic>? source,
}) {
  List<String> strings(Object? values) => [
    if (values is List)
      for (final value in values)
        if (value is String) value,
  ];
  final prefs = source?['notificationPrefs'];
  final muted = prefs is Map ? strings(prefs['muted']) : const <String>[];
  return PendingMember(
    id: id,
    name: name,
    email: email,
    role: source == null
        ? Role.staff
        : Role.values.where((role) => role.name == source['role']).firstOrNull ?? Role.member,
    groups: {for (final id in strings(source?['groups'])) ?Group.byId(id)},
    zones: [
      if (source?['zones'] is List)
        for (final zone in source!['zones'] as List)
          if (zone is Map && zone['serviceType'] is String)
            Zone(
              serviceType: zone['serviceType'] as String,
              duties: strings(zone['ministries']),
              smallGroups: strings(zone['smallGroups']),
            ),
    ],
    mutedNotifications: {
      for (final kind in NotificationKind.values)
        if (muted.contains(kind.name)) kind,
      if (prefs is Map && prefs['weeklyRosterReminder'] == false) NotificationKind.reminder,
    },
  );
}

/// The services a new church starts with, in its maker's language. The
/// Cloud Function seeds the same lists (functions/src/languages.ts;
/// testdata/church_rules.json).
const defaultServices = {
  AppLanguage.zhHant: [
    Service(
      id: 'sunday',
      name: '主日崇拜',
      weekdays: [DateTime.sunday],
      duties: ['司會', '敬拜', '司琴', '音控', '投影', '招待'],
      events: [
        EventTag(name: '聖餐', color: 0),
        EventTag(name: '浸禮', color: 4),
      ],
    ),
  ],
  AppLanguage.zhHans: [
    Service(
      id: 'sunday',
      name: '主日崇拜',
      weekdays: [DateTime.sunday],
      duties: ['领会', '敬拜主领', '司琴', '音控', '投影', '招待'],
      events: [
        EventTag(name: '圣餐', color: 0),
        EventTag(name: '浸礼', color: 4),
      ],
    ),
  ],
  AppLanguage.en: [
    Service(
      id: 'sunday',
      name: 'Sunday Service',
      weekdays: [DateTime.sunday],
      duties: ['Host', 'Worship Leader', 'Piano', 'Sound', 'Slides', 'Usher'],
      events: [
        EventTag(name: 'Communion', color: 0),
        EventTag(name: 'Baptism', color: 4),
      ],
    ),
  ],
  AppLanguage.ja: [
    Service(
      id: 'sunday',
      name: '主日礼拝',
      weekdays: [DateTime.sunday],
      duties: ['司会', '賛美リード', '奏楽', '音響', 'スライド', '受付'],
      events: [
        EventTag(name: '聖餐式', color: 0),
        EventTag(name: '洗礼式', color: 4),
      ],
    ),
  ],
  AppLanguage.ko: [
    Service(
      id: 'sunday',
      name: '주일예배',
      weekdays: [DateTime.sunday],
      duties: ['사회', '찬양 인도', '반주', '음향', '자막', '안내'],
      events: [
        EventTag(name: '성찬', color: 0),
        EventTag(name: '세례', color: 4),
      ],
    ),
  ],
};

/// Church [c] as deleting it leaves it, at [at].
Church _deleted(Church c, DateTime at) => Church(
  id: c.id,
  name: c.name,
  status: ChurchStatus.deleted,
  logoUrl: c.logoUrl,
  homeName: c.homeName,
  deletedAt: at,
  timeZone: c.timeZone,
  attendanceSince: c.attendanceSince,
);

/// A few of [p]'s duties, as functions/src/claim.ts finds them.
List<ClaimServe> _servesOfPending(MemoryBackend b, String cid, PendingMember p) {
  final names = {for (final s in b.services[cid]?.services ?? const <Service>[]) s.id: s.name};
  final today = b.churches[cid]!.timeZone.today(b.clock());
  final days = [
    for (final key in b.pendingRosterIds[cid]?[p.id] ?? const <String>[])
      if (b.rosters[cid]?[key] case final r? when r.forEvent == null)
        if (r.duties.where((d) => d.uids.values.contains(p.id)).firstOrNull case final d?)
          ClaimServe(day: r.day, service: names[r.type] ?? '', duty: d.role),
  ]..sort((a, b) => a.day!.compareTo(b.day!));
  final ahead = [
    for (final s in days)
      if (!s.day!.isBefore(today)) s,
  ];
  final shown = ahead.isNotEmpty ? ahead : days.reversed.toList();
  if (shown.isNotEmpty) return shown.take(3).toList();
  return [
    for (final z in p.zones)
      for (final duty in z.duties) ClaimServe(service: names[z.serviceType] ?? '', duty: duty),
  ].take(3).toList();
}
