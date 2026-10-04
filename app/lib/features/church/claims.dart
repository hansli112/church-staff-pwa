import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';

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
/// the email is verified, never joined without a yes.
final pendingClaimsProvider = FutureProvider<List<PendingClaim>>((ref) async {
  final verified = ref.watch(authUserProvider.select((u) => u.value?.verified ?? false));
  final uid = ref.watch(uidProvider);
  if (uid == null || !verified) return const [];
  // A church joined in the meantime may have been one of them.
  ref.watch(membershipsProvider.select((m) => m.value?.length));
  final declined = ref.watch(declinedClaimsProvider);
  final all = await ref.watch(backendProvider).cloud.pendingClaims();
  return [
    for (final c in all)
      if (!declined.contains(c.key)) c,
  ];
});

/// 「〈恩典堂〉的同工資料已經搬過來了，要加入嗎？」, one per claim, inline at
/// the top of the welcome and home pages (never a dialog on launch).
class PendingClaimsCard extends ConsumerStatefulWidget {
  const PendingClaimsCard({super.key});

  @override
  ConsumerState<PendingClaimsCard> createState() => _PendingClaimsCardState();
}

class _PendingClaimsCardState extends ConsumerState<PendingClaimsCard> {
  String? _busy;

  Future<void> _join(PendingClaim claim) async {
    final l10n = L10n.of(context);
    setState(() => _busy = claim.key);
    try {
      final cid = await ref.read(backendProvider).cloud.claimPending(claim.churchId, claim.pendingId);
      ref.read(selectedChurchProvider.notifier).select(cid);
      ref.invalidate(pendingClaimsProvider);
      Haptics.success();
      if (!mounted) return;
      showToast(context, l10n.joined(claim.churchName));
      context.go('/home');
    } catch (e) {
      if (mounted) showToast(context, errorText(l10n, e));
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
                    Text(l10n.claimPrompt(claim.churchName), style: AppText.body),
                    const SizedBox(height: Space.m),
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: l10n.claimDecline,
                            expand: true,
                            onPressed: _busy != null
                                ? null
                                : () => ref.read(declinedClaimsProvider.notifier).decline(claim),
                          ),
                        ),
                        const SizedBox(width: Space.s),
                        Expanded(
                          child: PrimaryButton(
                            label: l10n.claimJoin,
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
