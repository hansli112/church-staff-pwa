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

import '../core/languages.dart';
import '../domain/day.dart';
import '../domain/models.dart';
import '../domain/staff_order.dart';
import 'roster_change.dart';

export 'roster_change.dart';

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

  /// Opens [group] (one with no id) or changes it: admins, or its
  /// service's 負責人 and 牧者 (Member.mayEditSmallGroup). With [leads]
  /// (uids), they and nobody else are its 小組長. Returns its id.
  Future<String> saveSmallGroup(SmallGroupDetails group, {List<String>? leads});

  /// Closes 小組 [id], taking it off its 小組長 and 同工; its 人數 stay.
  Future<void> deleteSmallGroup(String id);

  /// Group [key]'s 回報人數 (#85): its pause and each meeting's 人數 filled
  /// in. For those who see them (Member.readsAttendance).
  Stream<AttendanceRecord> attendance(String key);

  /// Fills in [day]'s 人數 of group [key] (Member.writesAttendance), or with
  /// null clears it.
  Future<void> setAttendance(String key, Day day, AttendanceDay? value);

  /// Pauses group [key]'s 回報人數, or with null asks again.
  Future<void> setAttendancePause(String key, AttendancePause? pause);

  /// Turns 回報人數 on from [since] (admins), or with null off.
  Future<void> setAttendanceSince(Day? since);

  /// Saved rosters from [from] on, of every service, oldest first, and
  /// events' rosters still on at [from] (a retreat begun the day before).
  Stream<List<Roster>> rosters({required Day from});

  /// Every event's roster, past ones too, newest first, to copy duties
  /// from (沿用). Not one cancelled with its event.
  Future<List<Roster>> eventRosters();

  Stream<StaffOrder> staffOrder(String serviceType);

  /// Everyone in the church, read once from the server when online (export).
  Future<List<Member>> allMembers();

  /// Pending members, read once (export). Admins.
  Future<List<PendingMember>> allPendingMembers();

  /// Every saved roster, past ones too, read once (export).
  Future<List<Roster>> allRosters();

  /// Every service's staff order, read once (export).
  Future<Map<String, StaffOrder>> allStaffOrders();

  /// Writes [change] atomically, only if every document it names still
  /// matches [RosterChange.before]; otherwise [CloudErrorCode.conflict]
  /// with nothing written.
  Future<void> compareAndSetRosters(RosterChange change);

  /// [change] by a 事工's 負責人 who arranges only some duties of its days
  /// (Member.ledDuties): compared like [compareAndSetRosters], refused
  /// with [CloudErrorCode.permissionDenied] if it touches anything else on
  /// them. No staff order or service change goes with it.
  Future<void> compareAndSetLedDuties(RosterChange change);

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

  /// 加為同工 ([member] true; for a service with the [duties] they serve and
  /// their [smallGroups] there) or 移出 [group]: by an admin, or by its
  /// 負責人 for a plain 同工 (Member.mayMove). Changes nothing else on
  /// member [uid].
  Future<void> setGroupMember(
    String uid,
    ChurchGroup group, {
    required bool member,
    List<String> duties = const [],
    List<String> smallGroups = const [],
  });

  /// Gives member [uid] [duty] in [serviceType], applied to the member as
  /// they are when written (admins): nothing else on them changes.
  Future<void> grantDuty(String uid, String serviceType, String duty);

  /// Takes [duty] in [serviceType] off member [uid], the same way (admins).
  Future<void> revokeDuty(String uid, String serviceType, String duty);

  /// Removes [uid] from the church: an admin removing someone, or a member
  /// leaving.
  Future<void> removeMember(String uid);

  /// Which notifications member [uid] (only themself) turned off here.
  Future<void> setNotificationPrefs(String uid, Set<NotificationKind> muted);

  /// When member [uid] (only themself) is reminded of their duties here.
  Future<void> setReminderTiming(String uid, ReminderTiming timing);

  Stream<List<Invite>> invites();

  /// A new invite. Members who join with it belong to [zoneTypes].
  Future<Invite> createInvite({required Duration validFor, List<String> zoneTypes = const []});
  Future<void> revokeInvite(String code);

  Stream<CalendarSettings> calendarSettings();

  /// The church link, or null when the admin has not set one.
  Stream<ChurchLink?> churchLink();

  /// Sets the whole church link, its content source and fetch time
  /// included (admins only); null removes it. A new source is fetched at
  /// once and the result returned; a bad source URL is
  /// [CloudErrorCode.unknown] with [CloudReason.notHttps].
  Future<LinkSourceResult> setChurchLink(ChurchLink? link);

  /// Admin-only retry of the currently configured source. Does not rewrite
  /// the static link or resurrect content from an earlier source/date.
  Future<LinkSourceResult> refreshChurchLink();

  /// What the backend last fetched from the church link's content source.
  Stream<LinkContent?> linkContent();

  /// The church's webhook, or null when it has none. Admins only.
  Stream<WebhookSettings?> webhook();

  /// Sets the home-screen name (admins only); null goes back to the church
  /// name.
  Future<void> setHomeName(String? name);

  /// Sets the church's time zone (admins). Rosters keep their dates; the
  /// calendar's times are then shown on the new clock.
  Future<void> setTimeZone(ChurchTimeZone timeZone);

  /// Uploads [bytes] (already a 512px PNG) as the church logo.
  Future<void> uploadLogo(List<int> bytes);

  /// Deletes the church while it is open (admins); restorable for 30 days.
  Future<void> deleteChurch();

  /// Reopens the church its admin deleted under 30 days ago; an open church
  /// stays open. A suspended one, or one deleted longer ago, is
  /// [CloudErrorCode.churchClosed].
  Future<void> restoreChurch();

  /// Merges a pending member into a member (admins).
  Future<void> mergePending(String pendingId, String uid);

  /// Sets the webhook URL and which events it gets (admins); a null [url]
  /// turns it off. The first time, [secret] is used or one is made and
  /// returned: the only time it is shown.
  Future<String?> webhookSave({
    required String? url,
    bool calendar = false,
    bool roster = false,
    String? secret,
  });

  /// Replaces the secret with [secret], or a new one that is returned.
  Future<String?> webhookRotateSecret({String? secret});

  /// Sends a test notice now.
  Future<WebhookDelivery> webhookTest();

  // Google Calendar, proxied by the backend. Admins connect it, calendar
  // editors write, members read.
  Future<Uri> calendarAuthUrl();

  Future<List<CalendarChoice>> calendarList();
  Future<void> calendarSelect(String calendarId, String calendarName);
  Future<void> calendarDisconnect();

  /// Events of [month] (`YYYY-MM`).
  Future<List<CalendarEvent>> calendarEvents(String month);

  /// [previous] is the event before editing, so a move to another month
  /// refreshes both months. The event's roster follows a change of title or
  /// days. [restoreRosterOf] undoes deleting that event: its cancelled
  /// roster moves to [event], made again.
  Future<CalendarEvent> calendarSave(CalendarEvent event, {CalendarEvent? previous, String? restoreRosterOf});

  /// Deletes [event] and cancels its roster, kept a while for undo.
  Future<void> calendarDelete(CalendarEvent event);

  /// Photos the church may still recognize this month.
  Future<PhotoQuota> photoQuota();

  /// Recognizes photos of a paper roster into import rows (JSON objects).
  Future<List<dynamic>> recognizeRoster(String serviceType, List<PhotoInput> images);

  /// The prompt [recognizeRoster] gives the AI, for an editor to use with
  /// an AI of their own. Counts no photo.
  Future<String> photoPrompt(String serviceType);
}

/// A calendar the admin may pick, with its own time zone (an IANA id, when
/// Google says).
typedef CalendarChoice = ({String id, String name, String? timeZone});

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
  const FundingCost({required this.name, required this.perMonth, this.yearly = false});

  final String name;

  /// NT\$ a month; a twelfth of a yearly one.
  final int perMonth;

  /// Paid once a year.
  final bool yearly;
}

enum CostPeriod { month, year }

/// The currencies a cost can be entered in.
enum Currency {
  twd,
  usd
  ;

  /// `TWD`, `USD`: what the backend stores.
  String get code => name.toUpperCase();

  static Currency? fromCode(String code) => values.where((c) => c.code == code).firstOrNull;
}

/// One line of the platform's costs, entered by the operator.
class CostItem {
  const CostItem({required this.name, required this.amount, required this.currency, required this.per});

  final String name;
  final num amount;
  final Currency currency;
  final CostPeriod per;

  @override
  bool operator ==(Object other) =>
      other is CostItem &&
      other.name == name &&
      other.amount == amount &&
      other.currency == currency &&
      other.per == per;

  @override
  int get hashCode => Object.hash(name, amount, currency, per);
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

class FundingOverview {
  const FundingOverview({required this.costs, required this.months, required this.funding});

  final List<CostItem> costs;

  /// The last 12 months, newest first.
  final List<FundingMonth> months;
  final Funding? funding;
}

class PhotoInput {
  const PhotoInput({required this.mimeType, required this.bytes});

  final String mimeType;
  final List<int> bytes;
}

/// What anyone opening a church URL may see of an active church.
class ChurchPreview {
  const ChurchPreview({required this.id, required this.name, this.logoUrl});

  final String id;
  final String name;
  final String? logoUrl;
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

  // Platform operator only.
  Future<List<ChurchSummary>> adminSearchChurches(String query);
  Future<void> adminRenameChurch(String churchId, String name);
  Future<List<Member>> adminChurchMembers(String churchId);
  Future<void> adminTransferAdmin(String churchId, String uid);
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

  /// Reports an uncaught error. Never throws.
  Future<void> logError({
    required String message,
    required String stack,
    String? churchId,
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
enum WarmUp { calendarWrite, serviceEdit, joinChurch, createChurch, photoImport, timeZone, backOffice }
