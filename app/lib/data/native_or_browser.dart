import 'package:google_sign_in/google_sign_in.dart';

/// Signs in natively, or in the browser when [useBrowser] says the native
/// error means the device cannot do it. [onFallback] hears why, so a fallback
/// that hides a real problem still shows up in the error reports. Any other
/// error, such as closing the sheet, comes through.
Future<T> nativeOrBrowser<T>({
  required Future<T> Function() native,
  required Future<T> Function() browser,
  required bool Function(Object error) useBrowser,
  required void Function(Object error, StackTrace stack) onFallback,
}) async {
  try {
    return await native();
  } catch (e, stack) {
    if (!useBrowser(e)) rethrow;
    onFallback(e, stack);
    return browser();
  }
}

/// Native Google sign-in failed because of the device, not our setup: no
/// Google account on it, or Play services without Credential Manager
/// support (google_sign_in_android reports these as unknownError and
/// providerConfigurationError). A wrong client ID, cancelling, or anything
/// after the sheet is not worked around.
bool nativeGoogleUnavailable(Object error) =>
    error is GoogleSignInException &&
    (error.code == GoogleSignInExceptionCode.unknownError ||
        error.code == GoogleSignInExceptionCode.providerConfigurationError);
