/// The web build signs in to Google through Firebase's popup, never through
/// google_sign_in (FirebaseBackend.signInWithGoogle), whose own web package
/// downloads Google's sign-in SDK as the app starts. This one stands in for
/// it: nothing to download, and any use is refused.
library;

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';

class UnusedGoogleSignIn extends GoogleSignInPlatform {
  static void registerWith(Registrar registrar) {
    GoogleSignInPlatform.instance = UnusedGoogleSignIn();
  }

  static Never _unused() => throw UnsupportedError('The web build signs in with Firebase, not google_sign_in');

  @override
  Future<void> init(InitParameters params) async => _unused();

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(AttemptLightweightAuthenticationParameters params) =>
      _unused();

  @override
  bool supportsAuthenticate() => false;

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) async => _unused();

  @override
  bool authorizationRequiresUserInteraction() => _unused();

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async => _unused();

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async => _unused();

  @override
  Future<void> clearAuthorizationToken(ClearAuthorizationTokenParams params) async => _unused();

  @override
  Future<void> signOut(SignOutParams params) async => _unused();

  @override
  Future<void> disconnect(DisconnectParams params) async => _unused();
}
