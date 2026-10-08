import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import 'add_to_home.dart';
import 'church_logo.dart';

final _invitePreviewProvider = FutureProvider.autoDispose.family<Invite, String>(
  (ref, code) => ref.watch(backendProvider).cloud.previewInvite(code),
);

/// Where an invite link (/c/CHURCH/join/CODE) or a typed code
/// (/welcome/join/CODE) lands, after sign-in if needed. Shows
/// which church it is before joining, or that I am already in it.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _join(Invite invite) async {
    final l10n = L10n.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cid = await ref.read(backendProvider).cloud.redeemInvite(widget.code);
      ref.read(selectedChurchProvider.notifier).select(cid);
      Haptics.success();
      if (!mounted) return;
      showToast(context, l10n.joined(invite.churchName));
      goAfterJoining(context, ref, cid);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final preview = ref.watch(
      _invitePreviewProvider(widget.code.toUpperCase()),
    );
    final memberships = ref.watch(membershipsProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: preview.when(
          loading: () => const Center(child: CircularProgressIndicator.adaptive()),
          // A typed code goes back to be fixed; a link, to another code
          // or home.
          error: (e, _) => context.canPop()
              ? EmptyState(
                  message: errorText(l10n, e),
                  actionLabel: l10n.enterInviteCode,
                  onAction: () => context.pop(),
                )
              : EmptyState(
                  message: errorText(l10n, e),
                  actionLabel: memberships.isEmpty ? l10n.enterInviteCode : l10n.tabHome,
                  onAction: () => context.go(memberships.isEmpty ? '/welcome/join' : '/home'),
                ),
          data: (invite) {
            // The logo is a nicety: shown once it comes, never waited for.
            final logo = ref.watch(churchPreviewProvider(invite.churchId)).value?.logoUrl;
            final already = memberships.any(
              (m) => m.churchId == invite.churchId,
            );
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(Space.l),
                  children: [
                    ChurchLogo(url: logo),
                    BalancedText(
                      already ? invite.churchName : l10n.joinTitle(invite.churchName),
                      style: AppText.title,
                    ),
                    if (already) ...[
                      const SizedBox(height: Space.s),
                      BalancedText(
                        l10n.alreadyMember(invite.churchName),
                        style: AppText.body.copyWith(color: c.secondaryLabel),
                      ),
                    ],
                    const SizedBox(height: Space.xl),
                    if (already)
                      PrimaryButton(
                        label: l10n.tabHome,
                        onPressed: () {
                          ref.read(selectedChurchProvider.notifier).select(invite.churchId);
                          context.go('/home');
                        },
                      )
                    else
                      PrimaryButton(
                        label: l10n.join,
                        busy: _busy,
                        onPressed: () => _join(invite),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: Space.m),
                      BalancedText(
                        _error!,
                        style: AppText.subheadline.copyWith(
                          color: c.destructive,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
