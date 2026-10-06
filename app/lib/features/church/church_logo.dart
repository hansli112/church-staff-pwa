import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';

/// Name and logo of a church I may not belong to yet.
final churchPreviewProvider = FutureProvider.autoDispose.family<ChurchPreview, String>(
  (ref, churchId) => ref.watch(backendProvider).cloud.churchPreview(churchId),
);

/// The church name, with its logo in front when it has one. Used in the
/// home tab's title only; elsewhere the logo shows large, on the pages
/// that welcome someone to the church ([ChurchLogo]).
class ChurchTitle extends StatelessWidget {
  const ChurchTitle({super.key, required this.church});

  final Church church;

  @override
  Widget build(BuildContext context) {
    final logo = church.logoUrl;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (logo != null && logo.startsWith('http')) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.s),
            child: Image.network(
              logo,
              width: 32,
              height: 32,
              fit: BoxFit.cover,
              semanticLabel: church.name,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: Space.s),
        ],
        Flexible(
          child: Text(
            church.name,
            overflow: TextOverflow.ellipsis,
            style: AppText.title3,
          ),
        ),
      ],
    );
  }
}

/// The church's logo, large, above its name on the pages that welcome
/// someone to it. Nothing when it has none.
class ChurchLogo extends StatelessWidget {
  const ChurchLogo({super.key, required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final logo = url;
    if (logo == null || !logo.startsWith('http')) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.m),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.l),
          child: Image.network(
            logo,
            width: 96,
            height: 96,
            fit: BoxFit.cover,
            semanticLabel: L10n.of(context).churchLogo,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
