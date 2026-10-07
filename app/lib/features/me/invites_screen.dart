import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../church/links.dart';

final _invitesProvider = StreamProvider.autoDispose<List<Invite>>(
  (ref) => ref.watch(churchDataProvider)!.invites(),
);

/// Admins make invite links (7 or 30 days), share them, and revoke them.
class InvitesScreen extends ConsumerStatefulWidget {
  const InvitesScreen({super.key});

  @override
  ConsumerState<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends ConsumerState<InvitesScreen> {
  bool _busy = false;

  Future<void> _create(int days) async {
    final l10n = L10n.of(context);
    setState(() => _busy = true);
    final Invite invite;
    try {
      invite = await ref.read(churchDataProvider)!.createInvite(validFor: Duration(days: days));
    } catch (_) {
      if (mounted) showToast(context, l10n.saveFailed);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // Saved: whatever happens to the share sheet, the invite is in the list.
    if (mounted) await _share(invite);
  }

  Future<void> _share(Invite invite) async {
    final l10n = L10n.of(context);
    final text = l10n.inviteMessage(invite.churchName, inviteLink(invite.churchId, invite.code));
    await shareText(context, text, copied: l10n.inviteCopied);
  }

  Future<void> _actions(Invite invite) async {
    final l10n = L10n.of(context);
    final choice = await showAppSheet<String>(
      context,
      builder: (context) => SafeArea(
        child: ListSection(
          header: invite.code,
          children: [
            ListRow(
              title: l10n.inviteShare,
              leading: const Icon(Icons.ios_share),
              onTap: () => Navigator.pop(context, 'share'),
            ),
            ListRow(
              title: l10n.inviteCopy,
              leading: const Icon(Icons.copy),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListRow(
              title: l10n.inviteRevoke,
              destructive: true,
              leading: const Icon(Icons.block),
              onTap: () => Navigator.pop(context, 'revoke'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'share':
        await _share(invite);
      case 'copy':
        await copyText(context, inviteLink(invite.churchId, invite.code), copied: l10n.inviteCopied);
      case 'revoke':
        await ref.read(churchDataProvider)!.revokeInvite(invite.code);
        if (mounted) showToast(context, l10n.inviteRevoked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final invites = ref.watch(_invitesProvider).value ?? const <Invite>[];
    final now = DateTime.now();
    final live = [
      for (final i in invites)
        if (i.usableAt(now)) i,
    ];
    final fmt = DateFormat.MMMd('zh_TW');
    return Scaffold(
      appBar: AppBar(title: Text(l10n.invites)),
      body: ListView(
        children: [
          ListSection(
            header: l10n.inviteCreate,
            children: [
              for (final days in [7, 30])
                ListRow(
                  title: l10n.inviteDays(days),
                  leading: const Icon(Icons.link),
                  onTap: _busy ? null : () => _create(days),
                ),
            ],
          ),
          if (live.isNotEmpty)
            ListSection(
              children: [
                for (final i in live)
                  ListRow(
                    title: i.code,
                    value: l10n.inviteExpiresOn(fmt.format(i.expiresAt)),
                    onTap: () => _actions(i),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
