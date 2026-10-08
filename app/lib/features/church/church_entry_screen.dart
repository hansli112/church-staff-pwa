import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import 'church_logo.dart';

/// Where a church URL (/c/ID) lands for someone who is not a member of
/// that church: which church it is and how to join. Members never see it;
/// the router opens their church straight away (router.dart).
///
/// A home-screen shortcut opens the church URL every launch, so the
/// shortcut's church is the one shown; switching in the app works as usual
/// afterwards.
class ChurchEntryScreen extends ConsumerWidget {
  const ChurchEntryScreen({super.key, required this.churchId});

  final String churchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberships = ref.watch(membershipsProvider);
    if (!memberships.hasValue && !memberships.hasError) return const Scaffold(body: SizedBox.expand());
    return _NotMember(churchId: churchId, hasChurch: (memberships.value ?? const []).isNotEmpty);
  }
}

class _NotMember extends ConsumerWidget {
  const _NotMember({required this.churchId, required this.hasChurch});

  final String churchId;
  final bool hasChurch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final preview = ref.watch(churchPreviewProvider(churchId));
    // Somewhere to go next: home for members of another church, the invite
    // code page for everyone else.
    final next = hasChurch
        ? SecondaryButton(label: l10n.goHome, expand: true, onPressed: () => context.go('/home'))
        : PrimaryButton(label: l10n.enterInviteCode, onPressed: () => context.go('/welcome/join'));
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: preview.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => EmptyState(
            message: e is CloudException && e.code == CloudErrorCode.notFound
                ? l10n.churchNotFound
                : errorText(l10n, e),
            actionLabel: l10n.goHome,
            onAction: () => context.go('/home'),
          ),
          data: (church) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(Space.l),
                  children: [
                    ChurchLogo(url: church.logoUrl),
                    BalancedText(church.name, style: AppText.title),
                    const SizedBox(height: Space.s),
                    BalancedText(l10n.churchEntryNotMember, style: AppText.body.copyWith(color: c.secondaryLabel)),
                    const SizedBox(height: Space.xl),
                    next,
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
