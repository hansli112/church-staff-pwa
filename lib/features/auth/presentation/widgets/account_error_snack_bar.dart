import 'package:flutter/material.dart';

import '../../../../core/services/external_link_service.dart';
import '../../../../core/utils/error_messages.dart';
import '../../domain/sign_in_account_exception.dart';
import '../providers/user_admin_provider.dart';

/// The SnackBar for a failed add, edit or delete on the account screens.
///
/// Messages written for the admin are shown as they are; anything else goes
/// through [mapErrorToUserMessage] behind [prefix]. When the fix is on another
/// page (the Firebase console), the SnackBar links to it and stays long
/// enough to read.
SnackBar accountErrorSnackBar(Object error, {required String prefix}) {
  final helpUrl = error is SignInAccountException ? error.helpUrl : null;
  return SnackBar(
    content: Text(switch (error) {
      AccountSafetyException(:final message) => message,
      SignInAccountException(:final message) => message,
      _ => '$prefix${mapErrorToUserMessage(error)}',
    }),
    duration: helpUrl == null
        ? const Duration(seconds: 4)
        : const Duration(seconds: 20),
    action: helpUrl == null
        ? null
        : SnackBarAction(
            label: '開啟 Firebase',
            onPressed: () => openExternalLink(helpUrl),
          ),
  );
}
