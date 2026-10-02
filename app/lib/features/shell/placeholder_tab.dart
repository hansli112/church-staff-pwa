import 'package:flutter/material.dart';

import '../../core/design/components.dart';
import '../../l10n/app_localizations.dart';
import 'shell.dart';

/// A tab that is not built yet.
class PlaceholderTab extends StatelessWidget {
  const PlaceholderTab({super.key, required this.tab});

  final AppTab tab;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tabLabel(l10n, tab))),
      body: EmptyState(message: l10n.comingSoon),
    );
  }
}
