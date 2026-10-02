import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../data/backend.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';

/// Deleting my account (App Store 5.1.1(v)). The only admin of a church is
/// told which church to hand over first.
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
      message: l10n.deleteAccountBody,
      action: l10n.deleteAccount,
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(backendProvider).cloud.deleteAccount();
      await ref.read(backendProvider).auth.signOut();
    } on CloudException catch (e) {
      if (!mounted) return;
      final churches = e.detail;
      setState(
        () => _error = e.code == CloudErrorCode.lastAdmin && churches is List
            ? l10n.deleteAccountLastAdmin(churches.join('〉〈'))
            : errorText(l10n, e),
      );
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.deleteAccount)),
      body: ListView(
        padding: const EdgeInsets.all(Space.m),
        children: [
          Text(
            l10n.deleteAccountBody,
            style: AppText.body.copyWith(color: c.secondaryLabel),
          ),
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
            onPressed: _busy ? null : _delete,
          ),
        ],
      ),
    );
  }
}
