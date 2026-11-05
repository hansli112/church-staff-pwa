import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dates.dart';
import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../../state/session.dart';

/// Claims declined on this device, per account.
class DeclinedClaims extends Notifier<Set<String>> {
  String get _key => 'declined_claims_${ref.read(uidProvider)}';

  @override
  Set<String> build() {
    ref.watch(uidProvider);
    return (ref.read(prefsProvider).getStringList(_key) ?? const []).toSet();
  }

  void decline(PendingClaim c) {
    state = {...state, c.key};
    ref.read(prefsProvider).setStringList(_key, state.toList());
  }
}

final declinedClaimsProvider = NotifierProvider<DeclinedClaims, Set<String>>(DeclinedClaims.new);

/// Member data moved from self-host waiting for this account: asked once
/// the email is verified, or a Google or Apple account linked, never joined
/// without a yes.
final pendingClaimsProvider = FutureProvider<List<PendingClaim>>((ref) async {
  ref.watch(authUserProvider.select((u) => u.value?.claimEmails.join(' ') ?? ''));
  final uid = ref.watch(uidProvider);
  if (uid == null) return const [];
  // A church joined in the meantime may have been one of them; joined by
  // invite, one may be theirs by name.
  ref.watch(membershipsProvider.select((m) => m.value?.length));
  final declined = ref.watch(declinedClaimsProvider);
  final all = await ref.watch(backendProvider).cloud.pendingClaims();
  return [
    for (final c in all)
      if (!declined.contains(c.key)) c,
  ];
});

/// 「加入〈恩典堂〉？」, one per claim, inline at the top of the welcome and
/// home pages (never a dialog on launch); by name, on home only,
/// 「服事表上的「黃鎮台」是你嗎？」.
class PendingClaimsCard extends ConsumerStatefulWidget {
  const PendingClaimsCard({super.key});

  @override
  ConsumerState<PendingClaimsCard> createState() => _PendingClaimsCardState();
}

class _PendingClaimsCardState extends ConsumerState<PendingClaimsCard> {
  String? _busy;

  Future<void> _join(PendingClaim claim) async {
    final l10n = L10n.of(context);
    // The member is made before the rosters point at them: the app goes into
    // the church meanwhile, this card gone with the welcome page. What
    // follows is said from above it.
    final container = ProviderScope.containerOf(context, listen: false);
    final root = Navigator.of(context, rootNavigator: true).context;
    setState(() => _busy = claim.key);
    try {
      final cid = await container.read(backendProvider).cloud.claimPending(claim.churchId, claim.pendingId);
      container.read(telemetryProvider).logEvent('join_group', {'method': 'claim'});
      container.read(selectedChurchProvider.notifier).select(cid);
      container.invalidate(pendingClaimsProvider);
      Haptics.success();
      if (!root.mounted) return;
      showToast(root, claim.byName ? l10n.claimByNameDone(claim.name) : l10n.joined(claim.churchName));
      GoRouter.of(root).go('/home');
    } catch (e) {
      if (root.mounted) showToast(root, errorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final claims = ref.watch(pendingClaimsProvider).value ?? const [];
    if (claims.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final claim in claims)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.s),
            child: Material(
              color: AppColors.of(context).surface,
              borderRadius: BorderRadius.circular(Radii.m),
              child: Padding(
                padding: const EdgeInsets.all(Space.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BalancedText(
                      claim.byName ? l10n.claimByNameTitle(claim.name) : l10n.claimTitle(claim.churchName),
                      textAlign: TextAlign.start,
                      style: AppText.headline,
                    ),
                    if (claim.serves.isNotEmpty) ...[
                      const SizedBox(height: Space.s),
                      _Serves(claim.serves),
                    ],
                    const SizedBox(height: Space.s),
                    BalancedText(
                      claim.byName ? l10n.claimByNameBody(claim.name) : l10n.claimBody,
                      textAlign: TextAlign.start,
                      style: AppText.subheadline.copyWith(color: AppColors.of(context).secondaryLabel),
                    ),
                    const SizedBox(height: Space.m),
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: claim.byName ? l10n.claimByNameNo : l10n.claimDecline,
                            expand: true,
                            onPressed: _busy != null
                                ? null
                                : () => ref.read(declinedClaimsProvider.notifier).decline(claim),
                          ),
                        ),
                        const SizedBox(width: Space.s),
                        Expanded(
                          child: PrimaryButton(
                            label: claim.byName ? l10n.claimByNameYes : l10n.claimJoin,
                            busy: _busy == claim.key,
                            onPressed: _busy != null ? null : () => _join(claim),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A few of their duties to know them by: 「11/8　主日崇拜・招待」, the days
/// in a column of their own; or with no days, 「主日崇拜・招待」.
class _Serves extends StatelessWidget {
  const _Serves(this.serves);

  final List<ClaimServe> serves;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final format = shortMonthDay(l10n);
    final dated = serves.first.day != null;
    Widget cell(String text, {double end = 0}) => Padding(
      padding: EdgeInsetsDirectional.only(end: end, bottom: Space.xs),
      child: Text(text, style: AppText.subheadline),
    );
    return Table(
      columnWidths: dated ? const {0: IntrinsicColumnWidth()} : null,
      children: [
        for (final s in serves)
          TableRow(
            children: [
              if (dated) cell(s.day == null ? '' : format.format(s.day!.midnight), end: Space.m),
              cell(l10n.claimServe(s.service, s.duty)),
            ],
          ),
      ],
    );
  }
}
