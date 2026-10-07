import '../../data/backend.dart';
import '../../l10n/app_localizations.dart';

/// What to tell the user about [error]: how to fix it, no technical detail.
String errorText(L10n l10n, Object error) {
  if (error is AuthException) {
    return switch (error.code) {
      AuthErrorCode.cancelled => '',
      AuthErrorCode.invalidCredential => l10n.errInvalidCredential,
      AuthErrorCode.emailInUse => l10n.errEmailInUse,
      AuthErrorCode.weakPassword => l10n.errWeakPassword,
      AuthErrorCode.invalidEmail => l10n.errInvalidEmail,
      AuthErrorCode.needsLink => l10n.errNeedsLink,
      AuthErrorCode.tooManyRequests => l10n.errTooMany,
      AuthErrorCode.network => l10n.errNetwork,
      AuthErrorCode.unknown => l10n.errUnknown,
    };
  }
  if (error is CloudException) {
    return switch (error.code) {
      CloudErrorCode.churchClosed => l10n.errChurchClosed,
      CloudErrorCode.unverifiedEmail => l10n.createChurchVerifyFirst,
      CloudErrorCode.duplicateName => l10n.errDuplicateName,
      CloudErrorCode.inviteInvalid => l10n.errInviteInvalid,
      CloudErrorCode.inviteExpired => l10n.errInviteExpired,
      CloudErrorCode.permissionDenied => l10n.noPermission,
      CloudErrorCode.unavailable => l10n.errNetwork,
      CloudErrorCode.lastAdmin => l10n.errUnknown,
      CloudErrorCode.notFound => l10n.churchNotFound,
      CloudErrorCode.moveInvalid => l10n.errMoveInvalid,
      CloudErrorCode.moveTooLarge => l10n.errMoveTooLarge,
      CloudErrorCode.quotaExceeded => l10n.errUnknown,
      CloudErrorCode.unknown => l10n.errUnknown,
    };
  }
  return l10n.errUnknown;
}

/// Where people report a squatted church name or ask for help.
const supportUrl = 'https://github.com/hansli112/church-staff-pwa/issues/new';
