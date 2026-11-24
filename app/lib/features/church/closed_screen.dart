import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/connectivity.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../common/time_zones.dart';
import 'account_menu.dart';
import 'church_switcher.dart';
import 'claims.dart';

/// Shown instead of every other screen when the current church is
/// suspended or deleted. No church data is requested while it shows.
class ClosedScreen extends ConsumerStatefulWidget {
  const ClosedScreen({super.key});

  @override
  ConsumerState<ClosedScreen> createState() => _ClosedScreenState();
}

class _ClosedScreenState extends ConsumerState<ClosedScreen> {
  bool _busy = false;

  Future<void> _restore() async {
    final l10n = L10n.of(context);
    setState(() => _busy = true);
    try {
      await ref.churchData.restoreChurch();
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
    final restorable = ref.watch(churchRestorableProvider);
    // Never read on this device and no connection: not closed, only not
    // here yet. It opens by itself once online.
    final offline = church == null && !ref.watch(onlineProvider);

    final String title;
    final String body;
    if (offline) {
      title = l10n.churchOfflineTitle;
      body = l10n.churchOfflineBody;
    } else if (church == null) {
      title = l10n.churchUnavailable;
      body = '';
    } else if (church.status == ChurchStatus.deleted) {
      title = l10n.churchDeletedTitle(church.name);
      final until = church.restorableUntil;
      body = until == null
          ? ''
          : restorable
          ? l10n.churchDeletedBody(ChurchClock.of(context, ref).dayWithYear(until))
          : l10n.churchDeletedExpired;
    } else {
      title = l10n.churchSuspendedTitle(church.name);
      body = l10n.churchSuspendedBody;
    }
    final canRestore = restorable && (me?.isAdmin ?? false);

    return Scaffold(
      extendBodyBehindAppBar: true,
      // 登出 and 刪除帳號 under 帳號, as on the welcome page.
      appBar: accountBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Space.l),
              children: [
                // Data moved under my email to another church: the way in.
                if (claimsIn(ref, null).isNotEmpty) ...[const PendingClaimsCard(), const SizedBox(height: Space.l)],
                BalancedText(title, style: AppText.title2),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: Space.s),
                  BalancedText(body, style: AppText.body.copyWith(color: c.secondaryLabel)),
                ],
                // Without another church, the way out; its link may have
                // been tapped already.
                if (!offline) ...[
                  const SizedBox(height: Space.s),
                  BalancedText(l10n.closedJoinOther, style: AppText.body.copyWith(color: c.secondaryLabel)),
                ],
                const SizedBox(height: Space.xl),
                if (canRestore)
                  PrimaryButton(
                    label: l10n.restoreChurch,
                    busy: _busy,
                    onPressed: _restore,
                  ),
                if (multiple)
                  SecondaryButton(
                    label: l10n.switchChurch,
                    expand: true,
                    onPressed: () => showChurchSwitcher(context, ref),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
