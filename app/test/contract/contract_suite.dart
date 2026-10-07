/// The contract both [Backend] adapters keep, written once against the
/// interface.
///
/// memory_contract_test.dart runs it on MemoryBackend (the widget tests'
/// and the demo's fake), firebase_contract_test.dart on FirebaseBackend
/// against the emulators, in Chrome. A rule MemoryBackend enforces belongs
/// here, so the fake cannot drift from firestore.rules, storage.rules and
/// the Cloud Functions. What the fake scripts instead (a move file's
/// contents, fetched pages, webhook deliveries, Google Calendar, photo
/// recognition, the funding target) stays out.
///
/// A refusal is always [CloudErrorCode.permissionDenied], whether the
/// security rules refused a direct read or write or a function refused.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/staff_order.dart';

import 'world.dart';

const sunday = Service(
  id: 'sunday',
  name: '主日崇拜',
  weekday: DateTime.sunday,
  duties: ['司會', '司琴', '招待'],
  events: [EventTag(name: '聖餐', color: 0)],
);
const youth = Service(id: 'youth', name: '青年崇拜', weekday: DateTime.saturday, duties: ['司會']);

/// Somewhere nothing listens: fetching it fails at once, the same way
/// everywhere.
const unreachable = 'https://127.0.0.1:9/feed.json';

/// 恩典堂 with Sunday and youth services: 王牧師 its admin, 林同工 a roster
/// editor for Sunday, 李美玉 on staff. Signed in as 王牧師.
class Grace {
  Grace._(this.w);

  final ContractWorld w;
  late final String cid;
  late final String pastor;
  late final String editor;
  late final String mei;

  static const pastorEmail = 'pastor@example.com';
  static const editorEmail = 'editor@example.com';
  static const meiEmail = 'mei@example.com';

  CloudApi get cloud => w.backend.cloud;
  ChurchData get church => w.backend.church(cid);

  static Future<Grace> open(ContractWorld w) async {
    final g = Grace._(w);
    g.pastor = await w.signUp(pastorEmail, name: '王牧師');
    g.cid = await g.cloud.createChurch('恩典堂');
    await g.church.saveServices(const [sunday, youth]);
    final invite = await g.church.createInvite(validFor: const Duration(days: 7));
    g.editor = await w.signUp(editorEmail, name: '林同工');
    await g.cloud.redeemInvite(invite.code);
    g.mei = await w.signUp(meiEmail, name: '李美玉');
    await g.cloud.redeemInvite(invite.code);
    await w.signIn(pastorEmail);
    await g.church.saveMember(
      Member(
        uid: g.editor,
        name: '林同工',
        groups: const {Group.rosterEditors},
        zones: const [
          Zone(serviceType: 'sunday', duties: ['司會']),
        ],
      ),
    );
    return g;
  }

  /// Suspends the church as a platform operator, then signs in as [as].
  Future<void> suspend({String as = pastorEmail}) async {
    await w.signUp('operator@example.com');
    await w.makeOperator('operator@example.com');
    await cloud.adminSetStatus(cid, ChurchStatus.suspended);
    await w.signIn(as);
  }
}

Roster sundayOn(int day, {List<Duty> duties = const [], List<EventTag> events = const []}) =>
    Roster(type: 'sunday', day: Day(2026, 10, day), duties: duties, events: events);

/// A 1×1 PNG.
const png = [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
  0x89, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
];

Matcher fails(CloudErrorCode code, [Object? detail]) {
  var m = isA<CloudException>().having((e) => e.code, 'code', code);
  if (detail != null) m = m.having((e) => e.detail, 'detail', detail);
  return throwsA(m);
}

/// Refused for lack of permission, by the rules or by a function.
Matcher denied() => fails(CloudErrorCode.permissionDenied);

Matcher authFails(AuthErrorCode code) => throwsA(isA<AuthException>().having((e) => e.code, 'code', code));

/// Registers the contract's tests; [open] gives a fresh, empty world for
/// each one.
void contractTests(Future<ContractWorld> Function() open) {
  late ContractWorld w;
  setUp(() async => w = await open());

  AuthGateway auth() => w.backend.auth;
  CloudApi cloud() => w.backend.cloud;

  group('accounts', () {
    test('a password account needs a valid email, 6 characters and an unused email', () async {
      await expectLater(
        auth().registerWithEmail('A', 'not-an-email', contractPassword),
        authFails(AuthErrorCode.invalidEmail),
      );
      await expectLater(auth().registerWithEmail('A', 'a@example.com', '12345'), authFails(AuthErrorCode.weakPassword));
      await w.signUp('a@example.com');
      await w.signOut();
      await expectLater(
        auth().registerWithEmail('A', 'a@example.com', contractPassword),
        authFails(AuthErrorCode.emailInUse),
      );
    });

    test('a wrong password or an unknown email is an invalid credential', () async {
      final uid = await w.signUp('a@example.com');
      await w.signOut();
      await expectLater(
        auth().signInWithEmail('a@example.com', 'wrong-password'),
        authFails(AuthErrorCode.invalidCredential),
      );
      await expectLater(
        auth().signInWithEmail('b@example.com', contractPassword),
        authFails(AuthErrorCode.invalidCredential),
      );
      await auth().signInWithEmail(' a@example.com ', contractPassword);
      expect(auth().currentUser?.uid, uid);
    });

    test('a password account is unverified until the link is clicked, and cannot open a church', () async {
      await w.signUp('a@example.com', verified: false);
      expect(auth().currentUser!.verified, isFalse);
      await expectLater(cloud().createChurch('恩典堂'), fails(CloudErrorCode.unverifiedEmail));
      await w.verify('a@example.com');
      await auth().reload();
      expect(auth().currentUser!.verified, isTrue);
      expect(await cloud().createChurch('恩典堂'), isNotEmpty);
    });

    test('the operator claim', () async {
      await w.signUp('op@example.com');
      expect(await auth().isOperator(), isFalse);
      await w.makeOperator('op@example.com');
      expect(await auth().isOperator(), isTrue);
    });

    test('a profile is made once and kept; saving changes it', () async {
      final uid = await w.signUp('a@example.com');
      final profiles = w.backend.profiles;
      await profiles.ensure(UserProfile(uid: uid, name: '小明', email: 'a@example.com'));
      await profiles.ensure(UserProfile(uid: uid, name: 'Google 名字', email: 'a@example.com'));
      expect((await profiles.watch(uid).first)!.name, '小明');
      await profiles.save(UserProfile(uid: uid, name: '王小明', email: 'a@example.com', locale: 'zh-Hant'));
      final saved = (await profiles.watch(uid).first)!;
      expect((saved.name, saved.locale), ('王小明', 'zh-Hant'));
    });

    test('a profile name holds 40 characters; far past it is refused', () async {
      // Between 40 characters and 160 UTF-16 units the rules let it through
      // and the app stops it; outside that band both say the same.
      final uid = await w.signUp('a@example.com');
      final profiles = w.backend.profiles;
      await profiles.save(UserProfile(uid: uid, name: '🙏' * 40, email: 'a@example.com'));
      expect((await profiles.watch(uid).first)!.name, '🙏' * 40);
      await expectLater(profiles.save(UserProfile(uid: uid, name: 'A' * 161, email: 'a@example.com')), denied());
    });

    test('the only admin of a church cannot delete their account', () async {
      final g = await Grace.open(w);
      await expectLater(cloud().deleteAccount(), fails(CloudErrorCode.lastAdmin, ['恩典堂']));
      await g.church.saveMember(Member(uid: g.editor, name: '林同工', role: Role.admin));
      await cloud().deleteAccount();
      await expectLater(
        auth().signInWithEmail(Grace.pastorEmail, contractPassword),
        authFails(AuthErrorCode.invalidCredential),
      );
      await w.signIn(Grace.editorEmail);
      expect((await g.church.members().first).map((m) => m.uid), unorderedEquals([g.editor, g.mei]));
    });

    test('a deleted church does not hold its admin back', () async {
      final g = await Grace.open(w);
      await g.church.deleteChurch();
      await cloud().deleteAccount();
      await expectLater(
        auth().signInWithEmail(Grace.pastorEmail, contractPassword),
        authFails(AuthErrorCode.invalidCredential),
      );
    });
  });

  group('refusals', () {
    test('a direct read or write the rules refuse fails as a function refusing does', () async {
      final g = await Grace.open(w);
      await w.signIn(Grace.meiEmail);
      await expectLater(g.church.webhookSave(url: 'https://hook.example/x'), denied(), reason: 'a function');
      await expectLater(g.church.saveRoster(sundayOn(4)), denied(), reason: 'a write');
      await expectLater(g.church.saveRosters([sundayOn(4), sundayOn(11)]), denied(), reason: 'a batch');
      await expectLater(
        g.church.updateStaffOrder('sunday', {
          '司會': ['李美玉'],
        }),
        denied(),
        reason: 'a transaction',
      );
      await expectLater(
        g.church.saveMember(Member(uid: g.mei, name: '李美玉', role: Role.admin)),
        denied(),
        reason: 'an update',
      );
      await expectLater(
        g.church.createInvite(validFor: const Duration(days: 7)),
        denied(),
        reason: 'outside the church',
      );
      await expectLater(g.church.uploadLogo(png), denied(), reason: 'Storage');
      await expectLater(g.church.allMembers(), denied(), reason: 'a one-off read');
      await expectLater(g.church.members().first, denied(), reason: 'a listener');
    });

    test('a stranger\'s direct write fails the same way', () async {
      final g = await Grace.open(w);
      await w.signUp('outsider@example.com');
      await expectLater(g.church.saveRoster(sundayOn(4)), denied());
      await expectLater(g.church.removeMember(g.mei), denied());
      await expectLater(g.church.photoQuota(), denied());
    });
  });

  group('churches', () {
    test('the creator is the admin, with the default services; it is in their memberships', () async {
      final uid = await w.signUp('a@example.com', name: '王牧師');
      final cid = await cloud().createChurch('  恩典堂 ');
      final church = w.backend.church(cid);
      final c = (await church.church().first)!;
      expect((c.name, c.status), ('恩典堂', ChurchStatus.active));
      final me = (await church.member(uid).first)!;
      expect((me.name, me.role), ('王牧師', Role.admin));
      final services = (await church.services().first).services;
      expect(services.map((s) => (s.id, s.duties.join('、'))), [('sunday', '司會、敬拜、司琴、音控、投影、招待')]);
      final mine = await w.backend.memberships.watchMine(uid).first;
      expect(mine.map((m) => (m.churchId, m.member.role)), [(cid, Role.admin)]);
    });

    test('church names are unique, ignoring spaces, width and case', () async {
      await w.signUp('a@example.com');
      await cloud().createChurch('Grace Church');
      await w.signUp('b@example.com');
      await expectLater(cloud().createChurch('ＧＲＡＣＥ　church'), fails(CloudErrorCode.duplicateName));
      await expectLater(cloud().createChurch('gracechurch'), fails(CloudErrorCode.duplicateName));
    });

    test('a church name is 1 to 60 characters as a person counts them', () async {
      await w.signUp('a@example.com');
      await expectLater(cloud().createChurch('   '), fails(CloudErrorCode.unknown));
      await expectLater(cloud().createChurch('🙏' * 61), fails(CloudErrorCode.unknown));
      expect(await cloud().createChurch('🙏' * 60), isNotEmpty, reason: '60 characters in 120 UTF-16 units');
    });

    test('only members read the church', () async {
      final g = await Grace.open(w);
      await w.signUp('outsider@example.com');
      await expectLater(g.church.church().first, denied());
      await expectLater(g.church.services().first, denied());
      await expectLater(g.church.rosters(from: Day(2026, 1, 1)).first, denied());
    });

    test('anyone may preview an open church by its ID', () async {
      final g = await Grace.open(w);
      await w.signOut();
      expect((await cloud().churchPreview(g.cid)).name, '恩典堂');
      await expectLater(cloud().churchPreview('nosuchchurch'), fails(CloudErrorCode.notFound));
      await g.suspend();
      await expectLater(cloud().churchPreview(g.cid), fails(CloudErrorCode.notFound));
    });

    // 9 to 32 UTF-16 units is the app's to stop: the rules only guard
    // against 8 × 4 (firestore.rules), MemoryBackend counts characters.
    test('the home-screen name: admins, 1 to 8 characters, null for the church name', () async {
      final g = await Grace.open(w);
      await expectLater(g.church.setHomeName(''), denied());
      await expectLater(g.church.setHomeName('A' * 33), denied());
      await g.church.setHomeName('👍🏽' * 8);
      expect((await g.church.church().first)!.homeName, '👍🏽' * 8);
      await g.church.setHomeName('恩典');
      expect((await g.church.church().first)!.homeName, '恩典');
      await g.church.setHomeName(null);
      expect((await g.church.church().first)!.homeName, isNull);
      await w.signIn(Grace.meiEmail);
      await expectLater(g.church.setHomeName('美玉堂'), denied());
    });

    test('only admins upload the logo', () async {
      final g = await Grace.open(w);
      await g.church.uploadLogo(png);
      await w.signIn(Grace.meiEmail);
      await expectLater(g.church.uploadLogo(png), denied());
    });

    test('an admin deletes an open church and restores it', () async {
      final g = await Grace.open(w);
      await w.signIn(Grace.meiEmail);
      await expectLater(g.church.deleteChurch(), denied());
      await w.signIn(Grace.pastorEmail);
      await g.church.deleteChurch();
      final deleted = (await g.church.church().first)!;
      expect(deleted.status, ChurchStatus.deleted);
      expect(deleted.deletedAt, isNotNull);
      await g.church.restoreChurch();
      expect((await g.church.church().first)!.status, ChurchStatus.active);
      await g.church.restoreChurch();
      expect((await g.church.church().first)!.status, ChurchStatus.active, reason: 'an open church stays open');
    });

    test('a church deleted over 30 days ago cannot be restored', () async {
      final g = await Grace.open(w);
      await g.church.deleteChurch();
      await w.backdateDeletion(g.cid, const Duration(days: 31));
      await expectLater(g.church.restoreChurch(), fails(CloudErrorCode.churchClosed));
      expect((await g.church.church().first)!.status, ChurchStatus.deleted);
    });

    test('a deleted church: its members are told it is closed, its admin may only restore it', () async {
      final g = await Grace.open(w);
      await g.church.deleteChurch();
      await expectLater(g.church.deleteChurch(), fails(CloudErrorCode.churchClosed));
      await expectLater(g.church.webhookSave(url: 'https://hook.example/x'), fails(CloudErrorCode.churchClosed));
      await w.signIn(Grace.meiEmail);
      await expectLater(g.church.restoreChurch(), denied());
      await expectLater(g.church.photoQuota(), fails(CloudErrorCode.churchClosed));
      await w.signUp('outsider@example.com');
      await expectLater(g.church.photoQuota(), denied());
      await w.signIn(Grace.pastorEmail);
      await g.church.restoreChurch();
      expect((await g.church.photoQuota()).limit, 30);
    });
  });

  group('a suspended church', () {
    test('its members see only its status, and may leave', () async {
      final g = await Grace.open(w);
      await g.suspend(as: Grace.meiEmail);
      expect((await g.church.church().first)!.status, ChurchStatus.suspended);
      await expectLater(g.church.services().first, denied());
      await expectLater(g.church.setNotificationPrefs(g.mei, {NotificationKind.reminder}), denied());
      await g.church.removeMember(g.mei);
      await expectLater(g.church.church().first, denied());
    });

    test('its admin can change nothing, and the functions say why', () async {
      final g = await Grace.open(w);
      await g.church.saveChurchLink(const ChurchLink(title: '官網', url: 'https://grace.example'));
      await w.addPending(g.cid, const PendingMember(id: 'old-1', name: '舊同工'));
      await g.suspend();
      await expectLater(g.church.createInvite(validFor: const Duration(days: 7)), denied());
      await expectLater(g.church.saveRoster(sundayOn(4)), denied());
      final closed = fails(CloudErrorCode.churchClosed);
      await expectLater(g.church.deleteChurch(), closed);
      await expectLater(g.church.restoreChurch(), closed);
      await expectLater(g.church.mergePending('old-1', g.mei), closed);
      await expectLater(g.church.setLinkSource(unreachable, 300), closed);
      await expectLater(g.church.webhookSave(url: 'https://hook.example/x'), closed);
      await expectLater(g.church.calendarAuthUrl(), closed);
      await expectLater(g.church.photoQuota(), closed);
      expect((await g.church.church().first)!.status, ChurchStatus.suspended);
    });

    test('its members are told it is closed, whatever they may do; strangers are refused', () async {
      final g = await Grace.open(w);
      await g.suspend(as: Grace.editorEmail);
      final closed = fails(CloudErrorCode.churchClosed);
      const photo = [PhotoInput(mimeType: 'image/png', bytes: png)];
      await expectLater(g.church.recognizeRoster('sunday', photo), closed);
      await expectLater(g.church.calendarEvents('2026-10'), closed);
      await w.signIn(Grace.meiEmail);
      await expectLater(g.church.photoQuota(), closed);
      await expectLater(g.church.webhookSave(url: 'https://hook.example/x'), closed);
      await w.signUp('outsider@example.com');
      await expectLater(g.church.photoQuota(), denied());
      await expectLater(g.church.calendarEvents('2026-10'), denied());
    });

    test('its invites stop working', () async {
      final g = await Grace.open(w);
      final invite = await g.church.createInvite(validFor: const Duration(days: 7));
      await g.suspend();
      await w.signUp('new@example.com');
      await expectLater(cloud().previewInvite(invite.code), fails(CloudErrorCode.inviteInvalid));
      await expectLater(cloud().redeemInvite(invite.code), fails(CloudErrorCode.inviteInvalid));
    });
  });

  group('members', () {
    test('admins and roster editors read the member list; staff do not', () async {
      final g = await Grace.open(w);
      expect((await g.church.members().first).map((m) => m.uid), unorderedEquals([g.pastor, g.editor, g.mei]));
      await w.signIn(Grace.editorEmail);
      expect(await g.church.members().first, hasLength(3));
      expect(await g.church.allMembers(), hasLength(3));
      expect(await g.church.allPendingMembers(), isEmpty);
      await w.signIn(Grace.meiEmail);
      expect((await g.church.member(g.mei).first)!.role, Role.staff);
      await expectLater(g.church.members().first, denied());
      await expectLater(g.church.pendingMembers().first, denied());
      await expectLater(g.church.allMembers(), denied());
    });

    test('an admin edits members, but never demotes themself', () async {
      final g = await Grace.open(w);
      final edited = Member(
        uid: g.mei,
        name: '李美玉',
        role: Role.leader,
        groups: const {Group.calendarEditors},
        zones: const [
          Zone(serviceType: 'sunday', duties: ['司琴', '招待']),
        ],
      );
      await g.church.saveMember(edited);
      final mei = (await g.church.member(g.mei).first)!;
      expect(mei.role, edited.role);
      expect(mei.groups, edited.groups);
      expect(mei.zones, edited.zones);
      expect((await g.church.member(g.editor).first)!.canEditRosters('sunday'), isTrue);
      await expectLater(g.church.saveMember(Member(uid: g.pastor, name: '王牧師')), denied());
      await w.signIn(Grace.meiEmail);
      await expectLater(g.church.saveMember(Member(uid: g.mei, name: '李美玉', role: Role.admin)), denied());
    });

    test('a member name holds 40 characters; far past it is refused', () async {
      final g = await Grace.open(w);
      await g.church.saveMember(Member(uid: g.mei, name: '🙏' * 40, role: Role.staff));
      expect((await g.church.member(g.mei).first)!.name, '🙏' * 40);
      await expectLater(g.church.saveMember(Member(uid: g.mei, name: 'A' * 161, role: Role.staff)), denied());
    });

    test('members leave on their own; only another admin removes someone', () async {
      final g = await Grace.open(w);
      await expectLater(g.church.removeMember(g.pastor), denied());
      await w.signIn(Grace.meiEmail);
      await expectLater(g.church.removeMember(g.editor), denied());
      await g.church.removeMember(g.mei);
      expect(await w.backend.memberships.watchMine(g.mei).first, isEmpty);
      await w.signIn(Grace.pastorEmail);
      await g.church.removeMember(g.editor);
      expect((await g.church.members().first).map((m) => m.uid), [g.pastor]);
    });

    test('notification settings are each member\'s own', () async {
      final g = await Grace.open(w);
      await w.signIn(Grace.meiEmail);
      await g.church.setNotificationPrefs(g.mei, {NotificationKind.reminder});
      expect((await g.church.member(g.mei).first)!.mutedNotifications, {NotificationKind.reminder});
      await expectLater(g.church.setNotificationPrefs(g.editor, {NotificationKind.reminder}), denied());
    });
  });

  group('rosters', () {
    test('saved rosters come back from a day on, oldest first', () async {
      final g = await Grace.open(w);
      final first = sundayOn(
        4,
        events: const [EventTag(name: '聖餐', color: 0)],
        duties: const [
          Duty(role: '司會', people: ['林同工'], uids: {'林同工': 'editor'}),
          Duty(role: '招待', people: ['陳志豪', '訪客'], uids: {'陳志豪': 'hao'}),
        ],
      );
      final second = sundayOn(11, duties: const [Duty(role: '司琴')]);
      final old = Roster(type: 'sunday', day: Day(2026, 9, 27));
      await g.church.saveRosters([second, first, old]);
      expect(await g.church.rosters(from: Day(2026, 10, 1)).first, [first, second]);
      expect(await g.church.allRosters(), unorderedEquals([old, first, second]));
      await g.church.deleteRoster(first);
      expect(await g.church.rosters(from: Day(2026, 10, 1)).first, [second]);
    });

    test('roster editors edit only their services; staff read', () async {
      final g = await Grace.open(w);
      await w.signIn(Grace.editorEmail);
      await g.church.saveRoster(sundayOn(4));
      await expectLater(g.church.saveRoster(Roster(type: 'youth', day: Day(2026, 10, 3))), denied());
      await w.signIn(Grace.meiEmail);
      expect(await g.church.rosters(from: Day(2026, 10, 1)).first, [sundayOn(4)]);
      await expectLater(g.church.saveRoster(sundayOn(11)), denied());
      await expectLater(g.church.deleteRoster(sundayOn(4)), denied());
      await w.signIn(Grace.editorEmail);
      await g.church.deleteRoster(sundayOn(4));
    });

    test('nobody writes a roster for a service the church does not have', () async {
      final g = await Grace.open(w);
      await expectLater(g.church.saveRoster(Roster(type: 'ghost', day: Day(2026, 10, 4))), denied());
    });

    test('the staff order is kept per duty by that service\'s editors', () async {
      final g = await Grace.open(w);
      await w.signIn(Grace.editorEmail);
      await g.church.updateStaffOrder('sunday', {
        '司會': ['林同工', '王牧師'],
        '招待': ['李美玉'],
      });
      await g.church.updateStaffOrder('sunday', {'招待': null});
      final order = StaffOrder({
        '司會': ['林同工', '王牧師'],
      });
      expect(await g.church.staffOrder('sunday').first, order);
      expect(await g.church.allStaffOrders(), {'sunday': order});
      await expectLater(
        g.church.updateStaffOrder('youth', {
          '司會': ['林同工'],
        }),
        denied(),
      );
    });

    test('admins save the services, never none; IDs once used stay valid', () async {
      final g = await Grace.open(w);
      await expectLater(g.church.saveServices(const []), denied());
      const renamed = Service(id: 'sunday', name: '主日', weekday: DateTime.sunday, duties: ['司會'], enabled: false);
      await g.church.saveServices(const [renamed]);
      final settings = await g.church.services().first;
      expect(settings.services, const [renamed]);
      expect(settings.ids, containsAll(['sunday', 'youth']));
      await g.church.saveRoster(Roster(type: 'youth', day: Day(2026, 10, 3)));
      await w.signIn(Grace.meiEmail);
      await expectLater(g.church.saveServices(const [sunday]), denied());
    });
  });

  group('invites', () {
    test('admins make, list and revoke invites, good for under 31 days', () async {
      final g = await Grace.open(w);
      await expectLater(g.church.createInvite(validFor: const Duration(days: 32)), denied());
      final invite = await g.church.createInvite(validFor: const Duration(days: 30));
      expect((invite.churchId, invite.churchName), (g.cid, '恩典堂'));
      expect((await g.church.invites().first).map((i) => (i.code, i.revoked)), contains((invite.code, false)));
      await g.church.revokeInvite(invite.code);
      expect((await g.church.invites().first).map((i) => (i.code, i.revoked)), contains((invite.code, true)));
      await w.signIn(Grace.meiEmail);
      await expectLater(g.church.createInvite(validFor: const Duration(days: 7)), denied());
      await expectLater(g.church.invites().first, denied());
    });

    test('an invite joins its church as staff, once, until it expires or is revoked', () async {
      final g = await Grace.open(w);
      final invite = await g.church.createInvite(validFor: const Duration(days: 7));
      final expired = await g.church.createInvite(validFor: const Duration(minutes: -1));
      final revoked = await g.church.createInvite(validFor: const Duration(days: 7));
      await g.church.revokeInvite(revoked.code);
      await w.signOut();
      expect(await cloud().invitedChurchName(invite.code), '恩典堂');

      final uid = await w.signUp('new@example.com', name: '新朋友');
      expect((await cloud().previewInvite(invite.code.toLowerCase())).churchId, g.cid);
      expect(await cloud().redeemInvite(invite.code), g.cid);
      expect(await cloud().redeemInvite(invite.code), g.cid, reason: 'joining twice is a no-op');
      final me = (await g.church.member(uid).first)!;
      expect((me.name, me.role), ('新朋友', Role.staff));

      await expectLater(cloud().previewInvite('NOPE2345'), fails(CloudErrorCode.inviteInvalid));
      await expectLater(cloud().redeemInvite(revoked.code), fails(CloudErrorCode.inviteInvalid));
      await expectLater(cloud().redeemInvite(expired.code), fails(CloudErrorCode.inviteExpired));
    });
  });

  group('church link', () {
    // Between the limit and limit × 4 UTF-16 units is the app's to stop, as
    // for the home-screen name.
    test('admins save it within its limits; members read it', () async {
      final g = await Grace.open(w);
      for (final bad in [
        const ChurchLink(title: '', url: 'https://grace.example'),
        ChurchLink(title: 'T' * 121, url: 'https://grace.example'),
        ChurchLink(title: '官網', body: 'b' * 481, url: 'https://grace.example'),
        const ChurchLink(title: '官網', url: 'http://grace.example'),
      ]) {
        await expectLater(g.church.saveChurchLink(bad), denied(), reason: '${bad.title} ${bad.url}');
      }
      final link = ChurchLink(title: '👍🏽' * 30, body: '👍🏽' * 120, url: 'https://grace.example/give');
      await g.church.saveChurchLink(link);
      await w.signIn(Grace.meiEmail);
      expect(await g.church.churchLink().first, link);
      await expectLater(g.church.saveChurchLink(null), denied());
      await w.signIn(Grace.pastorEmail);
      await g.church.saveChurchLink(null);
      expect(await g.church.churchLink().first, isNull);
    });

    test('its content source: admins, https, a link first; a failed fetch is kept and said', () async {
      final g = await Grace.open(w);
      await expectLater(g.church.setLinkSource(unreachable, 300), fails(CloudErrorCode.unknown, 'noLink'));
      await g.church.saveChurchLink(const ChurchLink(title: '官網', url: 'https://grace.example'));
      await expectLater(
        g.church.setLinkSource('http://feed.example', 300),
        fails(CloudErrorCode.unknown, 'notHttps'),
      );

      final result = await g.church.setLinkSource(unreachable, 300);
      expect(result.error, LinkFetchError.network);
      final link = (await g.church.churchLink().first)!;
      expect((link.source, link.fetchMinute), (unreachable, 300));
      final content = (await g.church.linkContent().first)!;
      expect((content.source, content.error), (unreachable, LinkFetchError.network));
      expect(content.fetchedAt, isNull);

      // Saving the link keeps the source: that is the backend's.
      await g.church.saveChurchLink(const ChurchLink(title: '教會官網', url: 'https://grace.example'));
      expect((await g.church.churchLink().first)!.source, unreachable);

      await g.church.setLinkSource(null, 300);
      expect((await g.church.churchLink().first)!.source, isNull);
      expect(await g.church.linkContent().first, isNull);

      await w.signIn(Grace.meiEmail);
      await expectLater(g.church.setLinkSource(unreachable, 300), denied());
    });
  });

  group('webhook', () {
    test('admins set it up: https, a secret of 16 or more, made and shown once', () async {
      final g = await Grace.open(w);
      const url = 'https://127.0.0.1:9/hook';
      await expectLater(
        g.church.webhookSave(url: 'http://hook.example'),
        fails(CloudErrorCode.unknown, 'notHttps'),
      );
      await expectLater(g.church.webhookSave(url: url, secret: 'short'), fails(CloudErrorCode.unknown, 'secret'));
      await expectLater(g.church.webhookRotateSecret(), fails(CloudErrorCode.unknown), reason: 'nothing set up');

      final secret = await g.church.webhookSave(url: url, calendar: true);
      expect(secret, startsWith('whsec_'));
      expect(await g.church.webhook().first, const WebhookSettings(url: url, calendar: true));
      expect(await g.church.webhookSave(url: url, roster: true), isNull, reason: 'the secret stays');
      expect(await g.church.webhook().first, const WebhookSettings(url: url, roster: true));

      final next = await g.church.webhookRotateSecret();
      expect(next, allOf(startsWith('whsec_'), isNot(secret)));
      expect(await g.church.webhookRotateSecret(secret: 'our-shared-secret-2026'), isNull);

      final delivery = await g.church.webhookTest();
      final last = (await g.church.webhook().first)!.lastDelivery!;
      expect((last.ok, last.event), (delivery.ok, 'ping'));

      expect(await g.church.webhookSave(url: null), isNull);
      expect(await g.church.webhook().first, isNull);
    });

    test('is the admins\' alone', () async {
      final g = await Grace.open(w);
      await w.signIn(Grace.meiEmail);
      await expectLater(g.church.webhook().first, denied());
      await expectLater(g.church.webhookSave(url: 'https://hook.example/x'), denied());
      await expectLater(g.church.webhookTest(), denied());
    });
  });

  group('pending members', () {
    const pid = 'old-mei';
    const pending = PendingMember(
      id: pid,
      name: '美玉',
      email: 'Mei.Old@Example.com',
      role: Role.leader,
      groups: {Group.rosterEditors},
      zones: [
        Zone(serviceType: 'sunday', duties: ['司琴']),
      ],
    );
    final hers = sundayOn(
      4,
      duties: const [
        Duty(role: '司琴', people: ['美玉'], uids: {'美玉': pid}),
      ],
    );

    Future<Grace> moved() async {
      final g = await Grace.open(w);
      await g.church.saveRoster(hers);
      await w.addPending(g.cid, pending, rosterIds: [hers.id]);
      return g;
    }

    test('wait for their verified email, in open churches', () async {
      final g = await moved();
      await w.signIn(Grace.editorEmail);
      expect(await g.church.pendingMembers().first, [pending]);
      await w.signUp('mei.old@example.com', verified: false);
      expect(await cloud().pendingClaims(), isEmpty);
      await expectLater(cloud().claimPending(g.cid, pid), fails(CloudErrorCode.unverifiedEmail));
      await w.verify('mei.old@example.com');
      await auth().reload();
      final claims = await cloud().pendingClaims();
      expect(claims.map((c) => (c.churchId, c.churchName, c.pendingId, c.name)), [(g.cid, '恩典堂', pid, '美玉')]);
      await w.signIn(Grace.meiEmail);
      expect(await cloud().pendingClaims(), isEmpty);
      await expectLater(cloud().claimPending(g.cid, pid), denied());
    });

    test('a closed church cannot be claimed into', () async {
      final g = await moved();
      await g.suspend();
      await w.signUp('mei.old@example.com');
      expect(await cloud().pendingClaims(), isEmpty);
      await expectLater(cloud().claimPending(g.cid, pid), fails(CloudErrorCode.churchClosed));
    });

    test('claiming one makes them a member and gives their rosters back', () async {
      final g = await moved();
      final uid = await w.signUp('mei.old@example.com');
      await expectLater(cloud().claimPending(g.cid, 'nobody'), fails(CloudErrorCode.notFound));
      expect(await cloud().claimPending(g.cid, pid), g.cid);
      final me = (await g.church.member(uid).first)!;
      expect((me.name, me.role), ('美玉', pending.role));
      expect(me.groups, pending.groups);
      expect(me.zones, pending.zones);
      final roster = (await g.church.rosters(from: Day(2026, 10, 1)).first).single;
      expect(roster.duties.single.uids, {'美玉': uid});
      expect(await cloud().claimPending(g.cid, pid), g.cid, reason: 'a retry by the same person');
      expect(await cloud().pendingClaims(), isEmpty);
      expect(await g.church.pendingMembers().first, isEmpty);
    });

    test('an admin merges one into a member, who keeps their role and gains the rest', () async {
      final g = await moved();
      await g.church.saveMember(
        Member(
          uid: g.mei,
          name: '李美玉',
          groups: const {Group.calendarEditors},
          zones: const [
            Zone(serviceType: 'sunday', duties: ['招待']),
            Zone(serviceType: 'youth', duties: ['司會']),
          ],
        ),
      );
      await expectLater(g.church.mergePending('nobody', g.mei), fails(CloudErrorCode.notFound));
      await g.church.mergePending(pid, g.mei);
      final mei = (await g.church.member(g.mei).first)!;
      expect(mei.role, Role.staff);
      expect(mei.groups, {Group.calendarEditors, Group.rosterEditors});
      expect(mei.zones, const [
        Zone(serviceType: 'sunday', duties: ['招待', '司琴']),
        Zone(serviceType: 'youth', duties: ['司會']),
      ]);
      expect((await g.church.rosters(from: Day(2026, 10, 1)).first).single.duties.single.uids, {'美玉': g.mei});
      expect(await g.church.pendingMembers().first, isEmpty);
    });

    test('only admins merge or delete them', () async {
      final g = await moved();
      await w.signIn(Grace.editorEmail);
      await expectLater(g.church.mergePending(pid, g.mei), denied());
      await expectLater(g.church.deletePendingMember(pid), denied());
      await w.signIn(Grace.pastorEmail);
      await g.church.deletePendingMember(pid);
      expect(await g.church.pendingMembers().first, isEmpty);
    });
  });

  group('calendar', () {
    test('admins connect it, calendar editors write, members read', () async {
      final g = await Grace.open(w);
      expect((await g.church.calendarAuthUrl()).host, 'accounts.google.com');
      await w.signIn(Grace.meiEmail);
      expect((await g.church.calendarSettings().first).connected, isFalse);
      await expectLater(g.church.calendarAuthUrl(), denied());
      await expectLater(g.church.calendarList(), denied());
      await expectLater(g.church.calendarDisconnect(), denied());
      final event = CalendarEvent(title: '同工會', start: DateTime(2026, 10, 4, 14), end: DateTime(2026, 10, 4, 15));
      await expectLater(g.church.calendarSave(event), denied());
      await w.signUp('outsider@example.com');
      await expectLater(g.church.calendarEvents('2026-10'), denied());
    });
  });

  group('photos', () {
    test('members see the quota; a new church has all 30 photos', () async {
      final g = await Grace.open(w);
      await w.signIn(Grace.meiEmail);
      final quota = await g.church.photoQuota();
      expect((quota.remaining, quota.limit, quota.platformOpen), (30, 30, true));
      await w.signUp('outsider@example.com');
      await expectLater(g.church.photoQuota(), denied());
    });

    test('only editors of a service the church has recognize photos for it', () async {
      final g = await Grace.open(w);
      const photo = [PhotoInput(mimeType: 'image/png', bytes: png)];
      await expectLater(g.church.recognizeRoster('retreat', photo), denied());
      await w.signIn(Grace.editorEmail);
      await expectLater(g.church.recognizeRoster('youth', photo), denied());
      await w.signIn(Grace.meiEmail);
      await expectLater(g.church.recognizeRoster('sunday', photo), denied());
      await w.signUp('outsider@example.com');
      await expectLater(g.church.recognizeRoster('sunday', photo), denied());
    });
  });

  group('operator', () {
    test('operator calls refuse everyone else', () async {
      final g = await Grace.open(w);
      await expectLater(cloud().adminSearchChurches(''), denied());
      await expectLater(cloud().adminChurchMembers(g.cid), denied());
      await expectLater(cloud().adminSetStatus(g.cid, ChurchStatus.suspended), denied());
      await expectLater(cloud().adminStats(), denied());
      await expectLater(cloud().adminFunding(), denied());
    });

    test('finds a church, renames it and hands it to a member', () async {
      final g = await Grace.open(w);
      await w.signUp('op@example.com');
      await cloud().createChurch('Other Church');
      await w.makeOperator('op@example.com');
      final found = (await cloud().adminSearchChurches('恩典')).single;
      expect((found.id, found.name, found.status, found.memberCount), (g.cid, '恩典堂', ChurchStatus.active, 3));
      expect(found.admins.map((a) => a.uid), [g.pastor]);
      expect((await cloud().adminSearchChurches(g.cid)).single.id, g.cid);
      expect((await cloud().adminChurchMembers(g.cid)).map((m) => m.uid), unorderedEquals([g.pastor, g.editor, g.mei]));
      await expectLater(cloud().adminRenameChurch(g.cid, 'other church'), fails(CloudErrorCode.duplicateName));
      await cloud().adminRenameChurch(g.cid, '恩典教會');
      expect((await cloud().adminSearchChurches(g.cid)).single.name, '恩典教會');
      await cloud().adminTransferAdmin(g.cid, g.mei);
      expect(
        (await cloud().adminSearchChurches(g.cid)).single.admins.map((a) => a.uid),
        unorderedEquals([g.pastor, g.mei]),
      );
      expect(await cloud().adminStats(), isEmpty);
    });

    test('suspends and reopens a church, never a deleted one', () async {
      final g = await Grace.open(w);
      await g.suspend(as: 'operator@example.com');
      expect((await cloud().adminSearchChurches(g.cid)).single.status, ChurchStatus.suspended);
      await cloud().adminSetStatus(g.cid, ChurchStatus.active);
      await w.signIn(Grace.meiEmail);
      expect(await g.church.services().first, isNotNull, reason: 'open again');
      await w.signIn(Grace.pastorEmail);
      await g.church.deleteChurch();
      await w.signIn('operator@example.com');
      await expectLater(cloud().adminSetStatus(g.cid, ChurchStatus.active), fails(CloudErrorCode.churchClosed));
    });
  });

  group('platform', () {
    test('no funding until the backend publishes it; errors are logged quietly', () async {
      await w.signUp('a@example.com');
      expect(await w.backend.platform.funding().first, isNull);
      await cloud().logError(message: 'contract', stack: '');
    });
  });
}
