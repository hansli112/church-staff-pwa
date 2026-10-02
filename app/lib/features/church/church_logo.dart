import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../domain/models.dart';

/// The church name, with its logo in front when it has one. Used in the
/// home tab's title only; the logo does not repeat elsewhere.
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
