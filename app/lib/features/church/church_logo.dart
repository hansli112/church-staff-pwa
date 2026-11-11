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
/// that welcome someone to the church ([ChurchLogo]). Its room is kept
/// from the start, while the logo is looked up and loaded, so the name
/// does not move when it comes; it fades in.
class ChurchTitle extends StatelessWidget {
  const ChurchTitle({super.key, required this.church});

  final Church church;

  @override
  Widget build(BuildContext context) {
    final logo = church.logoUrl;
    final room = ColoredBox(color: AppColors.of(context).fill, child: const SizedBox.square(dimension: 32));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (church.hasLogo) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.s),
            child: logo == null || !logo.startsWith('http')
                ? room
                : Image.network(
                    logo,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    semanticLabel: church.name,
                    frameBuilder: (_, image, frame, loadedAtOnce) => loadedAtOnce
                        ? image
                        : Stack(
                            children: [
                              room,
                              AnimatedOpacity(
                                opacity: frame == null ? 0 : 1,
                                duration: const Duration(milliseconds: 200),
                                child: image,
                              ),
                            ],
                          ),
                    errorBuilder: (_, _, _) => room,
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
