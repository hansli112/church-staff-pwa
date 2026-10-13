import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';

/// The churches I am the only admin of (not counting deleted ones), which
/// block deleting my account: the same rule the backend enforces. A church
/// whose members cannot be read (closed) is left to the backend to judge.
final soleAdminChurchesProvider = FutureProvider.autoDispose<List<Church>>((ref) async {
  final memberships = await ref.watch(membershipsProvider.future);
  final backend = ref.watch(backendProvider);
  final blocking = <Church>[];
  for (final m in memberships) {
    if (!m.member.isAdmin) continue;
    try {
      final data = backend.church(m.churchId);
      final church = await data.church().first;
      if (church == null || church.status == ChurchStatus.deleted) continue;
      final members = await data.members().first;
      if (members.where((x) => x.isAdmin).length <= 1) blocking.add(church);
    } catch (_) {
      continue;
    }
  }
  return blocking;
});

/// Deleting my account (App Store 5.1.1(v)). The page says what deleting
/// does; the confirmation only asks. The only admin of a church is told so
/// on arrival, with the way to hand it over, and cannot delete yet.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _delete() async {
    final l10n = L10n.of(context);
    final ok = await confirmDestructive(
      context,
      title: l10n.deleteAccountTitle,
      action: l10n.deleteAccount,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final backend = ref.read(backendProvider);
    try {
      await backend.auth.prepareToDelete();
      await backend.cloud.deleteAccount();
      await backend.auth.signOut();
    } catch (e) {
      // Closing Apple's sheet has nothing to say.
      final text = errorText(l10n, e);
      if (mounted) setState(() => _error = text.isEmpty ? null : text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// To the members of the first church to hand over, switching to it.
  void _toMembers(Church church) {
    if (ref.read(currentChurchIdProvider) != church.id) {
      ref.read(selectedChurchProvider.notifier).select(church.id);
    }
    context.go('/me/members');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final check = ref.watch(soleAdminChurchesProvider);
    final blocking = check.value ?? const <Church>[];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.deleteAccount)),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          if (blocking.isEmpty)
            BalancedText(
              l10n.deleteAccountBody,
              textAlign: TextAlign.start,
              style: AppText.body.copyWith(color: c.secondaryLabel),
            )
          else ...[
            BalancedText(
              l10n.deleteAccountLastAdmin(blocking.map((ch) => ch.name).join(l10n.churchListSeparator)),
              textAlign: TextAlign.start,
              style: AppText.body.copyWith(color: c.label),
            ),
            const SizedBox(height: Space.m),
            PrimaryButton(label: l10n.goToMembers, onPressed: () => _toMembers(blocking.first)),
          ],
          const SizedBox(height: Space.l),
          if (_error != null) ...[
            Text(
              _error!,
              style: AppText.subheadline.copyWith(color: c.destructive),
            ),
            const SizedBox(height: Space.m),
          ],
          SecondaryButton(
            label: l10n.deleteAccount,
            destructive: true,
            expand: true,
            // Waits for the check, so the only admin never gets as far as
            // the confirmation to be refused.
            onPressed: _busy || check.isLoading || blocking.isNotEmpty ? null : _delete,
          ),
        ],
      ),
    );
  }
}
