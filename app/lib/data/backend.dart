/// The seams between the app and its backend.
///
/// Screens and state talk only to these interfaces. Firestore and Cloud
/// Functions implement them in `firebase/`; `memory/` implements them in
/// memory for widget tests and the offline demo.
///
/// The interfaces follow the domain, not the storage: everything done in
/// one church, whether a Firestore read or write or a Cloud Function, is on
/// that church's [ChurchData], so a screen never passes a church ID and a
/// path outside `churches/{cid}` cannot be built by accident. [CloudApi]
/// keeps what is not about a church the caller is in: making or joining
/// one, the account, the platform operator. Every refusal, from Firestore,
/// Storage or a function, is a [CloudException].
library;

import 'dart:typed_data';

import '../core/languages.dart';
import '../domain/day.dart';
import '../domain/family.dart';
import '../domain/models.dart';
import '../domain/staff_order.dart';
import '../domain/swap.dart';
import 'roster_change.dart';

export 'roster_change.dart';

part 'church_calls.dart';

/// A way to sign in to an account.
enum SignInMethod { password, google, apple }

/// One of an account's ways to sign in, and the email it goes by: a linked
/// Google or Apple account may have another email than the account's own.
class SignIn {
  const SignIn(this.method, this.email);

  final SignInMethod method;
  final String email;

  /// Google and Apple vouch for their email; a password does not.
  bool get vouches => method != SignInMethod.password;
}

/// The signed-in account, as far as the app needs to know.
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.email,
    required this.emailVerified,
    this.displayName,
    this.usesPassword = false,
    this.signIns = const [],
  });

  final String uid;

  /// The account's own email, whichever way it signs in.
  final String email;
  final bool emailVerified;
  final String? displayName;

  /// Its own email comes from email and password alone, with no Google or
  /// Apple account under the same email to vouch for it.
  final bool usesPassword;

  /// Every way it signs in, oldest first.
  final List<SignIn> signIns;

  /// Google and Apple accounts count as verified; only password accounts
  /// must click the link in the verification email.
  bool get verified => emailVerified || !usesPassword;

  /// A password account with nothing to vouch for whoever made it: the app
  /// asks for the email to be verified before anything else. A Google or
  /// Apple account linked under another email vouches enough to go on.
  bool get mustVerify => !verified && !signIns.any((s) => s.vouches);

  /// The emails member data moved from self-host can be claimed with: its
  /// own once verified, and those of the Google and Apple accounts linked
  /// to it (functions/src/pendingMembers.ts, callerKeys).
  List<String> get claimEmails => {
    if (verified && email.isNotEmpty) email.trim().toLowerCase(),
    for (final s in signIns)
      if (s.vouches && s.email.isNotEmpty) s.email.trim().toLowerCase(),
  }.toList();
}

enum AuthErrorCode {
  cancelled,
  invalidCredential,
  emailInUse,
  weakPassword,
  invalidEmail,

  /// The email already has an account that signs in another way. Signing in
  /// that way next links the pending sign-in method to it.
  needsLink,

  /// Linking: that Google or Apple account is already an account of its own.
  credentialInUse,
  tooManyRequests,
  network,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.code, [this.email]);

  final AuthErrorCode code;
  final String? email;

  @override
  String toString() => 'AuthException($code)';
}

abstract interface class AuthGateway {
  Stream<AuthUser?> authState();
  AuthUser? get currentUser;

  Future<void> signInWithGoogle();

  /// Whether this build can sign in with Apple: always on Apple's own
  /// platforms, elsewhere once the project has Apple's Services ID.
  bool get offersApple;

  /// Sign in with Apple (App Store 4.8). The email may be Apple's relay
  /// address; the name only comes the first time.
  Future<void> signInWithApple();
  Future<void> signInWithEmail(String email, String password);

  /// Links the Google account the person picks to the signed-in one, so
  /// either signs in to it, whatever its email. [AuthErrorCode.credentialInUse]
  /// when that Google account is already an account of its own: this
  /// version does not merge accounts.
  Future<void> linkGoogle();

  /// As [linkGoogle], with the Apple account the person signs in with; only
  /// where [offersApple]. Its email may be Apple's relay address.
  Future<void> linkApple();

  /// Stops [method] signing in to this account. Never the last one: the
  /// caller only offers it while there is another.
  Future<void> unlink(SignInMethod method);

  /// Creates the account and sends its verification email in [language],
  /// as [sendEmailVerification] and [sendPasswordReset] send theirs.
  Future<void> registerWithEmail(String name, String email, String password, AppLanguage language);
  Future<void> sendEmailVerification(AppLanguage language);
  Future<void> sendPasswordReset(String email, AppLanguage language);

  /// Re-reads the account, e.g. after the user clicked the verification
  /// link, and pushes the result through [authState].
  Future<void> reload();
  Future<void> signOut();

  /// Before the backend deletes the account: an account that signs in with
  /// Apple has its Apple tokens revoked (App Store 5.1.1(v)), which asks
  /// the user to confirm with Apple once more. Closing that is
  /// [AuthErrorCode.cancelled], and nothing should be deleted.
  Future<void> prepareToDelete();

  /// Whether the signed-in account holds the platform operator claim.
  Future<bool> isOperator();
}

abstract interface class ProfileRepository {
  Stream<UserProfile?> watch(String uid);

  /// Creates or updates users/{uid}, keeping its [UserProfile.appLocale]
  /// and [UserProfile.photoAiConsent].
  Future<void> save(UserProfile profile);

  /// Records the language the app shows (an [AppLanguage] tag) on an
  /// existing users/{uid}.
  Future<void> setAppLocale(String uid, String tag);

  /// Records on users/{uid} that its owner agreed to photo recognition
  /// sending photos and the member list to Google's Gemini.
  Future<void> agreeToPhotoAi(String uid);

  /// Creates users/{uid} on first sign-in. Leaves an existing profile
  /// alone, so a name the user changed is not reset to the Google name.
  Future<void> ensure(UserProfile profile);

  /// [uid]'s 通知列表 (#89), every church's, newest first. Only they read it.
  Stream<List<NotificationItem>> notifications(String uid);

  /// Records on users/{uid} that its owner has seen church [churchId]'s
  /// notifications up to [upTo], the newest shown: they are read, there and
  /// on the app icon ([UserProfile.notificationsSeen]).
  ///
  /// [onlyForward]: not when they are seen further already, maybe on another
  /// device since; online only.
  Future<void> markNotificationsSeen(String uid, String churchId, DateTime upTo, {bool onlyForward = false});
}

abstract interface class MembershipRepository {
  /// Every church [uid] belongs to (collection-group query on members).
  Stream<List<Membership>> watchMine(String uid);
}

/// Everything done in one church: its data, and the work the backend does
/// for it (fetching the church link's source, the webhook, Google Calendar,
/// photo recognition, deleting and restoring it). Whether an operation is a
/// Firestore read or write or a Cloud Function is the adapter's business.
///
/// Every failure is a [CloudException]. A refusal is
/// [CloudErrorCode.permissionDenied]: a non-member, a member without the
/// role, or (for Firestore's reads and writes) a closed church. What the
/// Cloud Functions do in a suspended or deleted church is refused with
/// [CloudErrorCode.churchClosed] instead (functions/src/access.ts).
abstract interface class ChurchData {
  String get churchId;

  // The church's parts that stand on their own, each its own interface.
  // EchoingChurchData shows none of them early.

  CalendarData get calendar;

  ChurchLinkData get churchLink;

  WebhookData get webhook;

  PhotoData get photos;

  AttendanceData get attendance;

  RosterNoteData get rosterNotes;

  ReadOnceData get readOnce;

  UnavailableData get unavailable;

  SwapData get swaps;

  ClaimData get claims;

  /// 家人 (functions/src/family.ts).
  FamilyData get family;

  JoiningData get joining;

  /// Makes [call] (one of the callables, [ChurchCall]), answering what it
  /// answers. [ChurchCalls] names each.
  Future<R> run<R>(ChurchCall<R> call);

  Stream<Church?> church();

  /// The member doc of [uid]: role, groups, zones.
  Stream<Member?> member(String uid);

  /// Everyone in the church. Only admins and roster editors may read this.
  Stream<List<Member>> members();

  /// Members moved from self-host who have not signed in yet. Admins and
  /// roster editors.
  Stream<List<PendingMember>> pendingMembers();

  /// Drops a pending member (admins). Their names stay on the rosters.
  Future<void> deletePendingMember(String id);

  Stream<ServiceSettings> services();

  /// The church's 事工 (#82); none until an admin makes one.
  Stream<MinistrySettings> ministries();

  /// Writes the 事工 list (admins) only if it is still [before];
  /// otherwise [CloudErrorCode.conflict]. Their IDs are kept for good.
  Future<void> compareAndSetMinistries({required List<Ministry> before, required List<Ministry> after});

  /// The church's 小組 (#85), in no order.
  Stream<List<SmallGroupDetails>> smallGroups();

  /// Opens [group] (one with no id) or changes it, keeping where it is
  /// ([SmallGroupDetails.order]): admins, or its service's 負責人 and 牧者
  /// (Member.mayEditSmallGroup). With [leads]
  /// (uids), they and nobody else are its 小組長. Returns its id. Given
  /// what it was made over, [before] (the 小組 as shown) or [leadsBefore]
  /// (its 小組長 as shown), it is refused ([CloudErrorCode.conflict]) once
  /// that has changed: an undo overwrites no one.
  Future<String> saveSmallGroup(
    SmallGroupDetails group, {
    SmallGroupDetails? before,
    List<String>? leads,
    List<String>? leadsBefore,
  });

  /// Saved rosters from [from] on, of every service, oldest first, and
  /// events' rosters still on at [from] (a retreat begun the day before).
  Stream<List<Roster>> rosters({required Day from});

  /// Saved rosters dated from [from] up to the day before [before], of
  /// every service and event, read once: how duties were arranged lately.
  Future<List<Roster>> pastRosters({required Day from, required Day before});

  /// The latest saved roster of [serviceType] dated before [before], or
  /// null when there is none: how a past day is read, only to look at.
  Future<Roster?> rosterBefore({required String serviceType, required Day before});

  /// Every event's roster, past ones too, newest first, to copy duties
  /// from (沿用). Not one cancelled with its event.
  Future<List<Roster>> eventRosters();

  Stream<StaffOrder> staffOrder(String serviceType);

  /// Writes [change] atomically, only if every document it names still
  /// matches [RosterChange.before]; otherwise [CloudErrorCode.conflict]
  /// with nothing written.
  Future<void> compareAndSetRosters(RosterChange change);

  /// [change] by a 事工's 負責人 who arranges only some duties of its days
  /// (Member.ledDuties): compared like [compareAndSetRosters], refused
  /// with [CloudErrorCode.permissionDenied] if it touches anything else on
  /// them. No staff order or service change goes with it.
  Future<void> compareAndSetLedDuties(RosterChange change);

  /// Whether changes made in 安排服事 (#90, [RosterChange.via] `plan`) to
  /// days of [serviceType] still wait for 通知同工: nobody was told of
  /// them yet. For those who read the member list.
  Stream<bool> plannedNews(String serviceType);

  /// Replaces the whole list of services (adding one, reordering), only
  /// if it is still [before]; otherwise [CloudErrorCode.conflict]. Never
  /// none; IDs once used stay valid.
  Future<void> compareAndSetServiceList({required List<Service> before, required List<Service> after});

  /// Updates one unchanged service, preserving every other service. A duty
  /// rename also moves members'/pending members' zone duties and staff order
  /// atomically; historical rosters are never rewritten.
  Future<void> compareAndSetService({
    required Service before,
    required Service after,
    ({String from, String to})? dutyRename,
  });

  /// Writes what an admin sets on a member ([Member.sameAdminFields]) only
  /// if it is still [before]; otherwise [CloudErrorCode.conflict]. The
  /// member's own notification settings are left alone.
  Future<void> compareAndSetMember({required Member before, required Member after});

  /// Removes [uid] from the church: an admin removing someone, or a member
  /// leaving.
  Future<void> removeMember(String uid);

  /// Which notifications member [uid] (only themself) turned off here.
  Future<void> setNotificationPrefs(String uid, Set<NotificationKind> muted);

  /// When member [uid] (only themself) is reminded of their duties here.
  Future<void> setReminderTiming(String uid, ReminderTiming timing);

  /// Sets the home-screen name (admins only); null goes back to the church
  /// name.
  Future<void> setHomeName(String? name);

  /// Uploads [bytes] (already a 512px PNG) as the church logo.
  Future<void> uploadLogo(List<int> bytes);
}

/// 不能服事的日子 (#91).
abstract interface class UnavailableData {
  /// [uid]'s 不能服事的日子 (#91): their own, or anyone's for whoever
  /// arranges rosters (Member.arrangesRosters).
  Stream<UnavailableDays> of(String uid);

  /// Everyone's 不能服事的日子 who has any, by uid: for whoever arranges
  /// rosters.
  Stream<Map<String, UnavailableDays>> everyones();

  /// Keeps [days] as the caller's own: no one else writes them. At most
  /// [Limits.unavailableSpans] stretches, each note at most
  /// [TextLimits.unavailableNote] characters.
  Future<void> saveMine(UnavailableDays days);

  /// Keeps that the caller sent theirs now (送出, or 都可以服事): it answers
  /// what they were asked so far.
  Future<void> send();

  /// What 通知同工填 asked of the caller, if ever, and when they last sent.
  Stream<UnavailableAsked?> askedOfMe();

  /// [serviceType]'s last 通知同工填, if ever, with who has sent since: for
  /// whoever arranges rosters.
  Stream<UnavailableRound?> round(String serviceType);
}

/// 找人代／交換 (#92). Asking and answering are [ChurchCall]s.
abstract interface class SwapData {
  /// 找人代／交換 (#92) I asked for that are still open.
  Stream<List<SwapRequest>> mineOpen();

  /// 找人代／交換 (#92) still open that ask me: a cover I am among those
  /// asked, a swap to me. By day.
  Stream<List<SwapRequest>> toMe();

  /// Request [id], for who asked and whoever it asks; null when there is
  /// none.
  Stream<SwapRequest?> request(String id);
}

/// 家人 (functions/src/family.ts). Adding, answering and 移出 are
/// [ChurchCall]s.
abstract interface class FamilyData {
  /// The families I am in: one, or several when one of them without an
  /// account was in another's too before signing in.
  Stream<List<Household>> mine();

  /// The families asking me in, not answered yet.
  Stream<List<Household>> asking();

  /// Everyone in the church but me, to add.
  Future<List<FamilyCandidate>> addable();

  /// The families [id] (a uid, or a pending member's ID) is in, for an
  /// admin on their page.
  Stream<List<Household>> householdsOf(String id);
}

/// 認領 (claiming to be one of the pending members). Asking and answering
/// are [ChurchCall]s.
abstract interface class ClaimData {
  /// 認領申請 waiting for an answer (admins): who says they are which of
  /// the pending members.
  Stream<List<ClaimAsk>> asks();

  /// What member [uid] (only themself, or an admin) asked, if anything.
  Stream<ClaimAsk?> askOf(String uid);

  /// The pending members with a name, for a member to find themself among.
  Future<List<ClaimCandidate>> candidates();
}

/// How people join: invites, and requests to join (申請加入, #88).
abstract interface class JoiningData {
  /// Requests to join (申請加入, #88), answered or not; ones
  /// [JoinRequest.days] old may linger a day. Admins only.
  Stream<List<JoinRequest>> requests();

  /// Whether someone with the church URL may ask to join (admins).
  Future<void> setTakesRequests(bool on);

  Stream<List<Invite>> invites();

  /// A new invite. Members who join with it belong to [zoneTypes].
  Future<Invite> createInvite({required Duration validFor, List<String> zoneTypes = const []});

  /// [code], still working, good for [validFor] from now instead: the
  /// same link again. Neither a revoked nor an expired one comes back.
  Future<Invite> renewInvite(String code, {required Duration validFor});
  Future<void> revokeInvite(String code);
}

/// The church's Google Calendar (行事曆), proxied by the backend: admins
/// connect it, calendar editors write, members read.
abstract interface class CalendarData {
  Stream<CalendarSettings> settings();

  Future<Uri> authUrl();

  Future<List<CalendarChoice>> choices();

  Future<void> select(String calendarId, String calendarName);

  Future<void> disconnect();

  /// Events of [month] (`YYYY-MM`).
  Future<List<CalendarEvent>> events(String month);

  /// [previous] is the event before editing, so a move to another month
  /// refreshes both months. The event's roster follows a change of title or
  /// days. [restoreRosterOf] undoes deleting that event: its cancelled
  /// roster moves to [event], made again.
  Future<CalendarEvent> save(CalendarEvent event, {CalendarEvent? previous, String? restoreRosterOf});

  /// Deletes [event] and cancels its roster, kept a while for undo.
  Future<void> delete(CalendarEvent event);
}

/// The 教會連結 at the top of 首頁, and what its content source gives today.
abstract interface class ChurchLinkData {
  /// The church link, or null when the admin has not set one.
  Stream<ChurchLink?> watch();

  /// Sets the whole church link, its content source and fetch time
  /// included (admins only); null removes it. A new source is fetched at
  /// once and the result returned; a bad source URL is
  /// [CloudErrorCode.unknown] with [CloudReason.notHttps].
  Future<LinkSourceResult> save(ChurchLink? link);

  /// Admin-only retry of the currently configured source. Does not rewrite
  /// the static link or resurrect content from an earlier source/date.
  Future<LinkSourceResult> refresh();

  /// What the backend last fetched from the church link's content source.
  Stream<LinkContent?> content();
}

/// The church's 外部通知 (webhook).
abstract interface class WebhookData {
  /// The church's webhook, or null when it has none. Admins only.
  Stream<WebhookSettings?> watch();

  /// Sets the webhook URL and which events it gets (admins); a null [url]
  /// turns it off. The first time, [secret] is used or one is made and
  /// returned: the only time it is shown.
  Future<String?> save({
    required String? url,
    bool calendar = false,
    bool roster = false,
    String? secret,
  });

  /// Replaces the secret with [secret], or a new one that is returned.
  Future<String?> rotateSecret({String? secret});

  /// Sends a test notice now.
  Future<WebhookDelivery> test();
}

/// 備註 of each day's roster, and its files.
abstract interface class RosterNoteData {
  /// Every roster's 備註 in the church, by roster ID. Everyone reads them.
  Stream<Map<String, RosterNote>> watch();

  /// Uploads a file picked for roster [rosterId]'s 備註, telling
  /// [onProgress] how far (0 to 1). It is the note's once [save] keeps it.
  /// For whoever arranges rosters.
  Future<NoteFile> upload(
    String rosterId, {
    required String name,
    required String type,
    required Uint8List bytes,
    void Function(double done)? onProgress,
  });

  /// Takes back [file], uploaded and then not kept.
  Future<void> discard(String rosterId, NoteFile file);

  /// Keeps [note] as roster [rosterId]'s 備註, for whoever arranges any of
  /// it; an empty one deletes it. Its new files must be [upload]ed first.
  Future<void> save(String rosterId, RosterNote note);
}

/// Reading rosters from photos (匯入).
abstract interface class PhotoData {
  /// Photos the church may still recognize this month.
  Future<PhotoQuota> quota();

  /// Recognizes photos of a paper roster into import rows (JSON objects).
  Future<List<dynamic>> recognize(String serviceType, List<PhotoInput> images);

  /// The prompt [recognize] gives the AI, for an editor to use with
  /// an AI of their own. Counts no photo.
  Future<String> prompt(String serviceType);
}

/// 回報人數 (#85): each meeting's 人數, by group key (`service:<id>`,
/// `small:<id>`, `gathering:<id>`), and the 其他聚會.
abstract interface class AttendanceData {
  /// Group [key]'s 回報人數 (#85): its pauses, who else fills them in, a
  /// service's 聚會時間, and each meeting's 人數 filled in. For those who
  /// see them (Member.readsAttendance).
  Stream<AttendanceRecord> watch(String key);

  /// The keys of the groups that asked me to fill in their 人數 (負責回報,
  /// AttendanceRecord.fillers).
  Stream<Set<String>> mine();

  /// Fills in [day]'s 人數 of group [key] (Member.fillsAttendance), or with
  /// null clears it.
  Future<void> save(String key, Day day, AttendanceDay? value);

  /// Sets who else fills in group [key]'s 人數, by uid (負責回報), by who
  /// sets it (Member.writesAttendance).
  Future<void> saveFillers(String key, List<String> fillers);

  /// The church's 其他聚會, in the order dragged (byOrder).
  Stream<List<Gathering>> gatherings();

  /// Makes [gathering] (its id empty) or changes it (admins and 行政),
  /// keeping where it is ([Gathering.order]). Returns its id.
  Future<String> saveGathering(Gathering gathering);

  /// Puts the 其他聚會 in the order of [ids], every one of them (admins
  /// and 行政); refused ([CloudErrorCode.conflict]) once they are not [ids].
  Future<void> orderGatherings(List<String> ids);

  /// Deletes 其他聚會 [id] (admins and 行政); its 人數 stay.
  Future<void> deleteGathering(String id);

  /// Fills in [day]'s 人數 of 小組 [key], met with the 小組 [value]
  /// names (AttendanceDay.together, 聯合小組, #93): each in the same
  /// service, meeting that day, and with nothing filled in
  /// (CloudReason.togetherFilled otherwise); those it no longer names are
  /// cleared. Through the backend, which writes the others' too.
  Future<void> saveTogether(String key, Day day, AttendanceDay value);

  /// Sets group [key]'s pauses: its 回報人數 turned off for a while is one
  /// open to AttendancePause.forever (pausesTurned); older apps set some
  /// to a day.
  Future<void> savePauses(String key, List<AttendancePause> pauses);

  /// 提醒 on 人數總覽 (#93), by who fills in group [key]'s 人數
  /// (Member.writesAttendance): asks whoever is reminded of them
  /// (Member.remindedAttendance) for [day]'s, still without them; once a
  /// day each group (CloudReason.remindedToday).
  /// Returns how many people.
  Future<int> remind(String key, Day day);

  /// Turns 回報人數 on from [since] (admins), or with null off.
  Future<void> saveSince(Day? since);
}

/// Everything of a kind in the church, read once from the server when
/// online: for 匯出資料, and wherever every day ever saved is needed.
abstract interface class ReadOnceData {
  /// Everyone in the church. Admins and roster editors.
  Future<List<Member>> members();

  /// Pending members. Admins and roster editors.
  Future<List<PendingMember>> pendingMembers();

  /// Every saved roster, past ones too.
  Future<List<Roster>> rosters();

  /// Every service's staff order.
  Future<Map<String, StaffOrder>> staffOrders();
}

/// A calendar the admin may pick, with its own time zone (an IANA id, when
/// Google says). The account's own calendar is [primary], its id the
/// account's email.
typedef CalendarChoice = ({String id, String name, String? timeZone, bool primary});

/// What 通知同工 did: how many [people] it told, or, in quiet hours
/// ([later]), will tell at 7:00.
typedef PlannedNotice = ({int people, bool later});

enum CloudErrorCode {
  /// The church is suspended or deleted (教會停用): its members can see that,
  /// and do nothing else there.
  churchClosed,
  unverifiedEmail,
  duplicateName,
  inviteInvalid,
  inviteExpired,
  lastAdmin,
  moveInvalid,
  moveTooLarge,
  notFound,
  permissionDenied,
  quotaExceeded,
  conflict,
  unavailable,
  unknown,
}

/// What a function refused more precisely than its [CloudErrorCode]:
/// the `detail` string the functions send (functions/src/*.ts `fail`).
enum CloudReason {
  /// An online-only operation could not reach the backend. It is not queued
  /// and must be deliberately tried again after reconnecting.
  offlineReadOnly,

  /// An atomic bulk edit exceeds the backend's transaction write bound.
  tooManyChanges,

  /// A URL that is not https (church link source, webhook).
  notHttps,

  /// A content source set before the church link.
  noLink,

  /// The church link has no configured content source to retry.
  noSource,

  /// No Google Calendar connected yet.
  noCalendar,
  notConnected,

  /// The connected Google account no longer lets the platform in.
  reconnect,

  /// A webhook secret of the wrong length.
  secret,

  /// A photo over the size the function takes.
  tooLarge,

  /// What Gemini gave back could not be read as a roster.
  unparseable,

  /// [CloudErrorCode.quotaExceeded]: the platform turned photo import off…
  platform,

  /// …or the church used this month's photos.
  church,

  /// The church takes no requests to join (申請加入, #88)…
  requestsClosed,

  /// …or the one answered is no longer waiting.
  requestGone,

  /// The request answered is no longer open (#92): taken, taken back, or
  /// void now that the roster changed.
  swapClosed,

  /// One of Google's own events (CalendarEvent.googleOnly), changed only
  /// in Google Calendar.
  googleOnly,

  /// 提醒 on 人數總覽 (#93): that group was already reminded today.
  remindedToday,

  /// 聯合小組 (#93): a 小組 picked already has that day's 人數.
  togetherFilled,

  /// 找一位同工代 (#92): the one asked marked that day as one they cannot
  /// serve.
  away,
}

class CloudException implements Exception {
  const CloudException(this.code, {this.reason, this.churches = const []});

  final CloudErrorCode code;
  final CloudReason? reason;

  /// For [CloudErrorCode.lastAdmin]: the churches where the caller is the
  /// only admin.
  final List<String> churches;

  @override
  String toString() => 'CloudException($code, $reason)';
}

/// A church as the platform operator sees it.
class ChurchSummary {
  const ChurchSummary({
    required this.id,
    required this.name,
    required this.status,
    required this.memberCount,
    required this.admins,
  });

  final String id;
  final String name;
  final ChurchStatus status;
  final int memberCount;
  final List<Member> admins;
}

class DailyStats {
  const DailyStats({required this.day, required this.values});

  final Day day;

  /// users, churches_active, members, rosters, reads, writes, …
  final Map<String, num> values;
}

class PhotoQuota {
  const PhotoQuota({required this.remaining, required this.limit, required this.platformOpen});

  final int remaining;
  final int limit;

  /// False once the platform's monthly budget is spent.
  final bool platformOpen;
}

/// 雲端費用進度 for this month, in NT\$, the same for everyone. Payments
/// are added by the backend as the stores report them.
class Funding {
  const Funding({
    required this.month,
    required this.target,
    required this.received,
    required this.carried,
    required this.monthsLeft,
    this.costs = const [],
  });

  /// `YYYY-MM`.
  final String month;

  /// What the platform costs a month; 0 until the operator sets the costs.
  final int target;

  /// Paid in this month.
  final int received;

  /// Left over from earlier months (a shortfall is not carried).
  final int carried;

  /// Whole months beyond this one that the money covers.
  final int monthsLeft;

  /// Where the money goes: [target] is what these add up to.
  final List<FundingCost> costs;

  int get available => received + carried;
}

/// One of the platform's costs as everyone sees it.
class FundingCost {
  const FundingCost({required this.name, this.names = const {}, required this.perMonth, this.yearly = false});

  /// In Traditional Chinese.
  final String name;

  /// In the other languages, those the operator filled in ([CostItem.names]).
  final Map<AppLanguage, String> names;

  /// Its name for [language]: Simplified Chinese without one in
  /// Traditional, the others in English, or without that too in
  /// Traditional, as the website's support page (CostNames in
  /// functions/src/funding.ts).
  String nameIn(AppLanguage language) => switch (language) {
    AppLanguage.zhHant => name,
    AppLanguage.zhHans => names[language] ?? name,
    _ => names[language] ?? names[AppLanguage.en] ?? name,
  };

  /// NT\$ a month; a twelfth of a yearly one.
  final int perMonth;

  /// Paid once a year.
  final bool yearly;
}

enum CostPeriod { month, year }

/// The currencies a cost can be entered in.
enum Currency {
  twd,
  usd;

  /// `TWD`, `USD`: what the backend stores.
  String get code => name.toUpperCase();

  static Currency? fromCode(String code) => values.where((c) => c.code == code).firstOrNull;
}

/// One line of the platform's costs, entered by the operator.
class CostItem {
  const CostItem({
    required this.name,
    this.names = const {},
    required this.amount,
    required this.currency,
    required this.per,
  });

  /// In Traditional Chinese.
  final String name;

  /// Its name in the other languages the operator filled in, for the
  /// support pages ([FundingCost.nameIn]); none in Traditional Chinese.
  final Map<AppLanguage, String> names;
  final num amount;
  final Currency currency;
  final CostPeriod per;

  @override
  bool operator ==(Object other) =>
      other is CostItem &&
      other.name == name &&
      other.names.length == names.length &&
      names.entries.every((e) => other.names[e.key] == e.value) &&
      other.amount == amount &&
      other.currency == currency &&
      other.per == per;

  @override
  int get hashCode =>
      Object.hash(name, Object.hashAllUnordered(names.entries.map((e) => (e.key, e.value))), amount, currency, per);
}

/// A month's totals in NT\$, for the operator.
class FundingMonth {
  const FundingMonth({required this.month, required this.received, required this.target});

  final String month;
  final int received;
  final int target;
}

/// A 線上支持 payment of NT\$[amount], counted in [month] (YYYY-MM);
/// [alreadyRefunded] when it had been taken off before.
typedef OnlinePayment = ({int amount, String month, bool alreadyRefunded});

/// Where a 支持 was paid: App Store, Google Play, or 線上支持 (ECPay).
enum PaymentStore { apple, google, ecpay }

/// One 支持 (functions/src/funding.ts `fundingPayments`), for 支持紀錄: no
/// name or account, which is not kept. [amount] in [currency] (`TWD`,
/// `MYR`…), as the store paid it; [amountTwd] counted towards 雲端費用,
/// less [refundedTwd]; [month] (YYYY-MM, UTC+8) it counts in.
class SupportPayment {
  const SupportPayment({
    required this.store,
    required this.productId,
    required this.amount,
    required this.currency,
    required this.amountTwd,
    this.refundedTwd = 0,
    required this.month,
    required this.at,
  });

  final PaymentStore store;
  final String productId;
  final num amount;
  final String currency;
  final int amountTwd;
  final int refundedTwd;
  final String month;
  final DateTime at;

  /// 每月支持 (a subscription's payment, first or renewed), not 一次性.
  bool get monthly => productId.startsWith('supporter_monthly');

  bool get refunded => refundedTwd > 0;

  /// What it counts towards 雲端費用 now.
  int get netTwd => amountTwd - refundedTwd;
}

class FundingOverview {
  const FundingOverview({required this.costs, required this.months, required this.funding, this.payments = const []});

  final List<CostItem> costs;

  /// The last 12 months, newest first.
  final List<FundingMonth> months;
  final Funding? funding;

  /// The payments, newest first (支持紀錄).
  final List<SupportPayment> payments;
}

class PhotoInput {
  const PhotoInput({required this.mimeType, required this.bytes});

  final String mimeType;
  final List<int> bytes;
}

/// What anyone opening a church URL may see of an active church.
class ChurchPreview {
  const ChurchPreview({
    required this.id,
    required this.name,
    this.logoUrl,
    this.takesJoinRequests = false,
    this.joinRequest,
  });

  final String id;
  final String name;
  final String? logoUrl;

  /// Whether one may ask to join (申請加入, #88).
  final bool takesJoinRequests;

  /// How the signed-in person's request stands; null when they have none.
  final JoinRequestState? joinRequest;
}

/// The result of fetching a content source right after setting it.
class LinkSourceResult {
  const LinkSourceResult({this.content, this.error, this.status});

  final LinkContent? content;
  final LinkFetchError? error;
  final int? status;

  bool get ok => error == null;
}

/// What is not about a church the caller is in: making a church, joining
/// one (invites, pending members, the church preview), the account, the
/// platform operator, error reports. Done by Cloud Functions.
///
/// One that acts in a church the caller is joining says
/// [CloudErrorCode.churchClosed] for a suspended or deleted church, except
/// invites ([CloudErrorCode.inviteInvalid]) and the church preview
/// [CloudErrorCode.notFound].
abstract interface class CloudApi {
  /// Returns the new church ID. [timeZone] is its time zone; its services
  /// start in [language], its maker's (without one, the language their app
  /// last showed, users/{uid}.appLocale).
  Future<String> createChurch(String name, {ChurchTimeZone timeZone = ChurchTimeZone.fallback, AppLanguage? language});

  Future<Invite> previewInvite(String code);

  /// The church an invite is for, by name only; works signed out, for the
  /// login page an invite link opens.
  Future<String> invitedChurchName(String code);

  /// Returns the church ID joined.
  Future<String> redeemInvite(String code);

  Future<void> deleteAccount();

  /// Uploads a move file for [movePreview] and [moveCommit]; returns its
  /// storage path, which only the uploader can read.
  Future<String> uploadMoveFile(List<int> bytes);

  /// What the move file at [path] would bring.
  Future<MovePreview> movePreview(String path);

  /// Creates church [churchName] in [timeZone] from the move file with the
  /// caller as its admin; [me] is the person in the file the caller takes
  /// over; [language] is the caller's, as for [createChurch]. Returns the
  /// church ID.
  Future<String> moveCommit(
    String path, {
    required String churchName,
    String? me,
    ChurchTimeZone timeZone = ChurchTimeZone.fallback,
    AppLanguage? language,
  });

  /// Pending members (moved from self-host) under the caller's verified
  /// email. Empty for an unverified email.
  Future<List<PendingClaim>> pendingClaims();

  /// Joins the caller to the church as that pending member. Returns the
  /// church ID.
  Future<String> claimPending(String churchId, String pendingId);

  /// Name and logo of an active church, for someone who is not a member.
  /// Throws [CloudErrorCode.notFound] for an unknown or closed church.
  Future<ChurchPreview> churchPreview(String churchId);

  /// Asks to join [churchId] (申請加入, #88), telling its admins; [note] is
  /// for them. Asking again while waiting changes nothing. An unverified
  /// email is [CloudErrorCode.unverifiedEmail]; a church taking none,
  /// [CloudReason.requestsClosed].
  Future<void> requestToJoin(String churchId, {String note = ''});

  /// Takes back the request to join [churchId], if there is one.
  Future<void> withdrawJoinRequest(String churchId);

  // Platform operator only.
  Future<List<ChurchSummary>> adminSearchChurches(String query);
  Future<void> adminRenameChurch(String churchId, String name);
  Future<List<Member>> adminChurchMembers(String churchId);

  /// Makes [uid] an admin of [churchId]: with 管理員, or with [identities],
  /// what [adminRevokeAdmin] took (its 復原).
  Future<void> adminTransferAdmin(String churchId, String uid, {List<Identity> identities});

  /// Takes away what makes [uid] an admin of [churchId] (管理員, a whole
  /// church's 牧者), never its last, and returns what it took.
  Future<List<Identity>> adminRevokeAdmin(String churchId, String uid);
  Future<void> adminSetStatus(String churchId, ChurchStatus status);
  Future<List<DailyStats>> adminStats({int days = 30});
  Future<FundingOverview> adminFunding();

  /// Replaces the cost list; this month's target follows.
  Future<void> adminSetFundingCosts(List<CostItem> items);

  /// 線上支持 refunded in ECPay's back office, which tells the backend
  /// nothing: takes the payment with order number [orderNo] (特店訂單編號)
  /// off 雲端費用進度, or puts it back when [refunded] is false. Throws
  /// [CloudErrorCode.notFound] when no such payment came in.
  Future<OnlinePayment> adminRefundOnlineSupport(String orderNo, {required bool refunded});

  /// Reports an uncaught error, signed in or not. Never throws. [screen]:
  /// the page up, by its route's pattern; [during] and [library]: where the
  /// framework caught it; [fatal]: nothing caught it; [agent]: the browser's
  /// user agent, as an error can be its engine's; [trail]: the last pages
  /// up and how long before the error each came up; [memory]: how much
  /// memory the page uses, as an engine can fail once it runs short.
  Future<void> logError({
    required String message,
    required String stack,
    String? churchId,
    String? screen,
    String? during,
    String? library,
    bool fatal = false,
    String? agent,
    String? trail,
    String? memory,
  });
}

/// Platform-wide data everyone signed in may read.
abstract interface class PlatformData {
  /// Null until the backend has published anything.
  Stream<Funding?> funding();

  /// The oldest store builds still allowed to run (`platform/app`). Readable
  /// signed out too: an old app asks for the update before anything else.
  Stream<MinimumBuilds> minimumBuilds();
}

/// The lowest build number (pubspec's `+N`) each store app may run; an
/// older one asks for the update. 0, or unset, lets every build run.
class MinimumBuilds {
  const MinimumBuilds({this.android = 0, this.ios = 0});

  final int android;
  final int ios;
}

/// Transport hints, not authorization or proof that a cached snapshot is
/// current. Failed online operations mark offline; successful ones restore it.
abstract interface class BackendConnectivity {
  bool get online;
  Stream<bool> watch();

  /// Outstanding online mutations, including a Future whose initiating
  /// screen was disposed. Safe PWA refresh must wait for these to finish.
  int get pendingWrites;
  Stream<int> watchPendingWrites();
}

/// Everything the app needs from a backend.
abstract interface class Backend {
  BackendConnectivity get connectivity;

  /// What time it is for every decision that depends on it: whether an
  /// invite still works, whether the church link's fetched content is
  /// still fresh, what day today is. The device clock, or a test's.
  /// Screens and state read it through `clockProvider`.
  DateTime Function() get clock;

  AuthGateway get auth;
  ProfileRepository get profiles;
  MembershipRepository get memberships;
  CloudApi get cloud;
  PlatformData get platform;
  ChurchData church(String churchId);

  /// Starts the backend for [what] when a page that will ask for it opens,
  /// so that call does not wait for it to start (about 3 s, when nobody
  /// has used it for a while). Never fails.
  void warmUp(WarmUp what);
}

/// What a page that just opened is likely to ask the backend for.
enum WarmUp {
  calendarWrite,

  /// 行事曆設定: connecting, then the list of calendars and picking one.
  calendarSettings,
  serviceEdit,

  /// A 小組's page: renaming it, when it meets, its 小組長.
  smallGroupEdit,

  /// A duty's page (#94): who is on its list, a tap away.
  dutyList,

  /// 安排服事 (#90): 完成 tells who was put on or taken off.
  planWeeks,

  /// Where a 事工's 負責人 arranges (#82): the backend checks each change
  /// is only to the duties it leads.
  ledDuties,

  /// 找人代／交換 (#92), as its menu opens.
  swapAsk,

  /// A request I was asked (#92): 我來／接受 or 不方便.
  swapAnswer,

  /// A service's 同工 (#94): 加入同工, 加為同工, 移出.
  groupStaff,

  /// 同工 with a request to join waiting (#88): 允許.
  joinAnswer,

  /// 同工, or one of them, with 同工 without an account to merge: 合併.
  mergePending,

  /// 回報人數 (#93): 提醒.
  attendanceRemind,

  /// 填寫人數 for a 小組 that may have met with others (聯合小組, #93).
  attendanceTogether,
  joinChurch,
  askToJoin,
  createChurch,
  photoImport,
  timeZone,
  backOffice,
}
