import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../common/errors.dart';
import 'church_switcher.dart';

/// Shown instead of every other screen when the current church is
/// suspended or deleted. No church data is requested while it shows.
class ClosedScreen extends ConsumerStatefulWidget {
  const ClosedScreen({super.key});

  @override
  ConsumerState<ClosedScreen> createState() => _ClosedScreenState();
}

class _ClosedScreenState extends ConsumerState<ClosedScreen> {
  bool _busy = false;

  Future<void> _restore(Church church) async {
    final l10n = L10n.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(backendProvider).cloud.restoreChurch(church.id);
      if (mounted) showToast(context, l10n.churchRestored);
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final church = ref.watch(churchProvider).value;
    final me = ref.watch(meProvider).value;
    final multiple = (ref.watch(membershipsProvider).value?.length ?? 0) > 1;

    final String title;
    final String body;
    if (church == null) {
      title = l10n.churchUnavailable;
      body = '';
    } else if (church.status == ChurchStatus.deleted) {
      title = l10n.churchDeletedTitle(church.name);
      final until = church.deletedAt?.add(const Duration(days: 30));
      body = until == null ? '' : l10n.churchDeletedBody(DateFormat.yMMMd('zh_TW').format(until));
    } else {
      title = l10n.churchSuspendedTitle(church.name);
      body = l10n.churchSuspendedBody;
    }
    final canRestore = church?.status == ChurchStatus.deleted && (me?.isAdmin ?? false);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Space.l),
              children: [
                Text(title, textAlign: TextAlign.center, style: AppText.title2),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: Space.s),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: AppText.body.copyWith(color: c.secondaryLabel),
                  ),
                ],
                const SizedBox(height: Space.xl),
                if (canRestore)
                  PrimaryButton(
                    label: l10n.restoreChurch,
                    busy: _busy,
                    onPressed: () => _restore(church!),
                  ),
                if (multiple)
                  SecondaryButton(
                    label: l10n.switchChurch,
                    expand: true,
                    onPressed: () => showChurchSwitcher(context, ref),
                  ),
                SecondaryButton(
                  label: l10n.signOut,
                  expand: true,
                  onPressed: () => signOut(ref),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
