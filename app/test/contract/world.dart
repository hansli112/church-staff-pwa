import 'package:martha/data/backend.dart';
import 'package:martha/domain/models.dart';

/// What a contract test may do besides calling the [Backend]: make
/// accounts and sign in as them, and set up what only the backend or the
/// platform writes. One per adapter: memory_world.dart and
/// firebase_world.dart.
abstract interface class ContractWorld {
  Backend get backend;

  /// Registers a password account and leaves it signed in, verified unless
  /// [verified] is false. Returns its uid.
  Future<String> signUp(String email, {String name = '', bool verified = true});

  /// Signs in as an account made by [signUp].
  Future<void> signIn(String email);

  Future<void> signOut();

  /// Marks the email verified, as clicking the link does. The app sees it
  /// after [AuthGateway.reload].
  Future<void> verify(String email);

  /// Gives the account the platform operator claim and signs in as it.
  Future<void> makeOperator(String email);

  /// Adds a pending member, as a move does; [rosterIds] are the days that
  /// name them.
  Future<void> addPending(String churchId, PendingMember pending, {List<String> rosterIds = const []});

  /// Moves the church's deletion [ago] into the past.
  Future<void> backdateDeletion(String churchId, Duration ago);

  /// Whether [error] is the backend refusing for lack of permission.
  bool isDenied(Object error);
}

/// The password every contract account uses.
const contractPassword = 'secret123';
