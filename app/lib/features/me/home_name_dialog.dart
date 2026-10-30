import 'package:flutter/material.dart';

import '../../core/design/components.dart';
import '../../domain/limits.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';

/// Asks for the home-screen name. Returns the trimmed name, '' to go back
/// to the church name, or null when cancelled.
Future<String?> askHomeName(BuildContext context, {required String churchName, String? current}) {
  final l10n = L10n.of(context);
  return promptText(
    context,
    title: l10n.homeName,
    hint: churchName,
    initial: current ?? '',
    maxLength: TextLimits.homeName,
    optional: true,
    helper: (text) =>
        text.trim().characters.length > Church.homeNameSafeLength ? l10n.homeNameMayBeCut : l10n.homeNameFooter,
  );
}
