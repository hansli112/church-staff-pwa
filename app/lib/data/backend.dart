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

import '../domain/day.dart';
import '../domain/models.dart';
import '../domain/staff_order.dart';

/// The signed-in account, as far as the app needs to know.
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.email,
    required this.emailVerified,
    this.displayName,
    this.usesPassword = false,
  });

  final String uid;
  final String email;
  final bool emailVerified;
  final String? displayName;

  /// Signed up with email and password (as opposed to Google or Apple).
  final bool usesPassword;

  /// Google and Apple accounts count as verified; only password accounts
  /// must click the link in the verification email.
  bool get verified => emailVerified || !usesPassword;
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
  Future<void> signInWithEmail(String email, String password);
  Future<void> registerWithEmail(String name, String email, String password);
  Future<void> sendEmailVerification();
  Future<void> sendPasswordReset(String email);

  /// Re-reads the account, e.g. after the user clicked the verification
  /// link, and pushes the result through [authState].
  Future<void> reload();
  Future<void> signOut();

  /// Whether the signed-in account holds the platform operator claim.
  Future<bool> isOperator();
}

abstract interface class ProfileRepository {
  Stream<UserProfile?> watch(String uid);

  /// Creates or updates users/{uid}.
  Future<void> save(UserProfile profile);

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

  /// Saved rosters from [from] on, of every service, oldest first.
  Stream<List<Roster>> rosters({required Day from});

  Stream<StaffOrder> staffOrder(String serviceType);

  /// Everyone in the church, read once from the server when online (export).
  Future<List<Member>> allMembers();

  /// Pending members, read once (export). Admins.
  Future<List<PendingMember>> allPendingMembers();

  /// Every saved roster, past ones too, read once (export).
  Future<List<Roster>> allRosters();

  /// Every service's staff order, read once (export).
  Future<Map<String, StaffOrder>> allStaffOrders();

  Future<void> saveRoster(Roster roster);

  /// Writes all of [rosters] at once, or none of them (swap, undo).
  ///
  /// [via] marks where the change came from; `import` tells the backend
  /// not to send a push for every day.
  Future<void> saveRosters(List<Roster> rosters, {String via = 'app'});

  Future<void> deleteRoster(Roster roster);

  /// Writes only the duties in [changes]; null removes that duty's ranking.
  Future<void> updateStaffOrder(
    String serviceType,
    Map<String, List<String>?> changes,
  );

  Future<void> saveServices(List<Service> services);

  Future<void> saveMember(Member member);

  /// Removes [uid] from the church: an admin removing someone, or a member
  /// leaving.
  Future<void> removeMember(String uid);

  Future<void> setNotificationPrefs(String uid, Set<NotificationKind> muted);

  Stream<List<Invite>> invites();
  Future<Invite> createInvite({required Duration validFor});
  Future<void> revokeInvite(String code);

  Stream<CalendarSettings> calendarSettings();

  /// The church link, or null when the admin has not set one.
  Stream<ChurchLink?> churchLink();

  /// Saves the church link's title, body and URL (admins only); null
  /// removes it. Its content source is set with [setLinkSource].
  Future<void> saveChurchLink(ChurchLink? link);

  /// What the backend last fetched from the church link's content source.
  Stream<LinkContent?> linkContent();

  /// The church's webhook, or null when it has none. Admins only.
  Stream<WebhookSettings?> webhook();

  /// Sets the home-screen name (admins only); null goes back to the church
  /// name.
  Future<void> setHomeName(String? name);

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

  /// Sets the church link's content source and daily fetch time (admins);
  /// a null [source] removes it. A new source is fetched at once.
  Future<LinkSourceResult> setLinkSource(String? source, int fetchMinute);

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
  Future<List<({String id, String name})>> calendarList();
  Future<void> calendarSelect(String calendarId, String calendarName);
  Future<void> calendarDisconnect();

  /// Events of [month] (`YYYY-MM`).
  Future<List<CalendarEvent>> calendarEvents(String month);

  /// [previous] is the event before editing, so a move to another month
  /// refreshes both months.
  Future<CalendarEvent> calendarSave(CalendarEvent event, {CalendarEvent? previous});
  Future<void> calendarDelete(CalendarEvent event);

  /// Photos the church may still recognize this month.
  Future<PhotoQuota> photoQuota();

  /// Recognizes photos of a paper roster into import rows (JSON objects).
  Future<List<dynamic>> recognizeRoster(String serviceType, List<PhotoInput> images);
}

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
  unavailable,
  unknown,
}

class CloudException implements Exception {
  const CloudException(this.code, [this.detail]);

  final CloudErrorCode code;

  /// Extra data from the function, e.g. the churches where the caller is the
  /// only admin.
  final Object? detail;

  @override
  String toString() => 'CloudException($code, $detail)';
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

  int get available => received + carried;
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

/// The result of fetching a content source right after saving it.
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
  /// Returns the new church ID.
  Future<String> createChurch(String name);

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

  /// Creates church [churchName] from the move file with the caller as its
  /// admin; [me] is the person in the file the caller takes over. Returns
  /// the church ID.
  Future<String> moveCommit(String path, {required String churchName, String? me});

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
}

/// Everything the app needs from a backend.
abstract interface class Backend {
  AuthGateway get auth;
  ProfileRepository get profiles;
  MembershipRepository get memberships;
  CloudApi get cloud;
  PlatformData get platform;
  ChurchData church(String churchId);
}
