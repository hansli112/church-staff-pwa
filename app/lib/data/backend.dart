/// The seams between the app and its backend.
///
/// Screens and state talk only to these interfaces. Firestore and Cloud
/// Functions implement them in `firebase/`; `memory/` implements them in
/// memory for widget tests and the offline demo.
///
/// Every church-scoped read and write goes through a [ChurchData] for one
/// church ID, so a path outside `churches/{cid}` cannot be built by accident.
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
}

abstract interface class ProfileRepository {
  Stream<UserProfile?> watch(String uid);

  /// Creates or updates users/{uid}.
  Future<void> save(UserProfile profile);
}

abstract interface class MembershipRepository {
  /// Every church [uid] belongs to (collection-group query on members).
  Stream<List<Membership>> watchMine(String uid);
}

/// Reads and writes for one church.
abstract interface class ChurchData {
  String get churchId;

  Stream<Church?> church();

  /// The member doc of [uid]: role, groups, zones.
  Stream<Member?> member(String uid);

  /// Everyone in the church. Only admins and roster editors may read this.
  Stream<List<Member>> members();

  Stream<ServiceSettings> services();

  /// Saved rosters from [from] on, of every service, oldest first.
  Stream<List<Roster>> rosters({required Day from});

  Stream<StaffOrder> staffOrder(String serviceType);

  Future<void> saveRoster(Roster roster);

  /// Writes all of [rosters] at once, or none of them (swap, undo).
  Future<void> saveRosters(List<Roster> rosters);

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

  /// Uploads [bytes] (already a 512px PNG) as the church logo.
  Future<void> uploadLogo(List<int> bytes);
}

enum CloudErrorCode {
  unverifiedEmail,
  duplicateName,
  inviteInvalid,
  inviteExpired,
  lastAdmin,
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

/// Privileged operations, done by Cloud Functions.
abstract interface class CloudApi {
  /// Returns the new church ID.
  Future<String> createChurch(String name);

  Future<Invite> previewInvite(String code);

  /// Returns the church ID joined.
  Future<String> redeemInvite(String code);

  Future<void> deleteAccount();

  Future<void> deleteChurch(String churchId);
  Future<void> restoreChurch(String churchId);

  // Platform operator only.
  Future<List<ChurchSummary>> adminSearchChurches(String query);
  Future<void> adminRenameChurch(String churchId, String name);
  Future<void> adminTransferAdmin(String churchId, String uid);
  Future<void> adminSetStatus(String churchId, ChurchStatus status);
  Future<List<DailyStats>> adminStats({int days = 30});

  /// Reports an uncaught error. Never throws.
  Future<void> logError({
    required String message,
    required String stack,
    String? churchId,
  });
}

/// Everything the app needs from a backend.
abstract interface class Backend {
  AuthGateway get auth;
  ProfileRepository get profiles;
  MembershipRepository get memberships;
  CloudApi get cloud;
  ChurchData church(String churchId);
}
