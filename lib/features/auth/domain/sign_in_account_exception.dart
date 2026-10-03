/// A staff member's sign-in could not be created or removed, for a reason the
/// admin can read and act on. [message] is shown as is; [helpUrl], when set,
/// is the page where the admin can fix it.
class SignInAccountException implements Exception {
  const SignInAccountException(this.message, {this.helpUrl});

  final String message;
  final String? helpUrl;

  @override
  String toString() => message;
}
