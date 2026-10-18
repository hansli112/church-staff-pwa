import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';

/// 「儲存中…」 in an app bar while a change, already shown, is still on its
/// way to the backend. Nothing otherwise.
class SavingIndicator extends ConsumerWidget {
  const SavingIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(savingProvider).value ?? false)) return const SizedBox.shrink();
    final c = AppColors.of(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: Space.s, end: Space.s),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator.adaptive(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(c.secondaryLabel),
              ),
            ),
            const SizedBox(width: Space.xs),
            Text(L10n.of(context).saving, style: AppText.footnote.copyWith(color: c.secondaryLabel)),
          ],
        ),
      ),
    );
  }
}
