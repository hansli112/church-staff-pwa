import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../church/links.dart';
import '../common/time_zones.dart';

final _invitesProvider = StreamProvider.autoDispose<List<Invite>>(
  (ref) => openChurch(ref).invites(),
);

/// The invites that still work. One leaves the list when it expires.
final _liveInvitesProvider = Provider.autoDispose<List<Invite>>((ref) {
  final invites = ref.watch(_invitesProvider).value ?? const <Invite>[];
  final now = ref.watch(clockProvider)();
  final live = [
    for (final i in invites)
      if (i.usableAt(now)) i,
  ];
  for (final i in live) {
    rebuildAt(ref, i.expiresAt, now);
  }
  return live;
});

/// Admins make invite links (7 or 30 days, 7 unless they choose 30), share
/// them, and revoke them.
/// A link can put the people who join with it in some 牧區 at once.
class InvitesScreen extends ConsumerStatefulWidget {
  const InvitesScreen({super.key});

  @override
  ConsumerState<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends ConsumerState<InvitesScreen> {
  bool _busy = false;

  /// The 牧區 the next invite joins, as service IDs.
  final _zones = <String>{};

  /// How long the next invite works.
  int _days = 7;

  Future<void> _create(int days) async {
    final l10n = L10n.of(context);
    setState(() => _busy = true);
    final Invite invite;
    try {
      final services = ref.read(servicesProvider).value?.enabled ?? const <Service>[];
      invite = await ref.churchData.createInvite(
        validFor: Duration(days: days),
        zoneTypes: [
          for (final s in services)
            if (_zones.contains(s.id)) s.id,
        ],
      );
    } catch (_) {
      if (mounted) showToast(context, l10n.saveFailed);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // Each invite picks its own 牧區.
    if (mounted) setState(_zones.clear);
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
              leading: const Icon(Symbols.ios_share_rounded),
              onTap: () => Navigator.pop(context, 'share'),
            ),
            ListRow(
              title: l10n.inviteCopy,
              leading: const Icon(Symbols.content_copy_rounded),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListRow(
              title: l10n.inviteRevoke,
              destructive: true,
              leading: const Icon(Symbols.block_rounded),
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
        await ref.churchData.revokeInvite(invite.code);
        if (mounted) showToast(context, l10n.inviteRevoked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final live = ref.watch(_liveInvitesProvider);
    final services = ref.watch(servicesProvider).value;
    final enabled = services?.enabled ?? const <Service>[];
    final clock = ChurchClock.of(context, ref);
    String? zonesOf(Invite i) {
      final names = [for (final t in i.zoneTypes) ?services?.byId(t)?.name];
      return names.isEmpty ? null : names.join(l10n.listSeparator);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.invites)),
      body: ListView(
        children: [
          // Any number of 牧區: an empty circle says it can be ticked.
          if (enabled.isNotEmpty)
            ListSection(
              header: l10n.inviteZones,
              children: [
                for (final s in enabled)
                  Semantics(
                    selected: _zones.contains(s.id),
                    child: ListRow(
                      title: s.name,
                      leading: _zones.contains(s.id)
                          ? Icon(Symbols.check_circle_rounded, fill: 1, color: c.accent)
                          : const Icon(Symbols.circle_rounded),
                      chevron: false,
                      onTap: () {
                        Haptics.selection();
                        setState(() => _zones.contains(s.id) ? _zones.remove(s.id) : _zones.add(s.id));
                      },
                    ),
                  ),
              ],
            ),
          // How long it works is a choice; the button says what happens.
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final days in [7, 30]) ButtonSegment(value: days, label: Text(l10n.inviteDays(days))),
                  ],
                  selected: {_days},
                  onSelectionChanged: (v) {
                    Haptics.selection();
                    setState(() => _days = v.first);
                  },
                ),
                const SizedBox(height: Space.m),
                PrimaryButton(
                  label: l10n.inviteCreate,
                  icon: const Icon(Symbols.link_rounded),
                  busy: _busy,
                  onPressed: () => _create(_days),
                ),
              ],
            ),
          ),
          if (live.isNotEmpty)
            ListSection(
              children: [
                for (final i in live)
                  ListRow(
                    title: i.code,
                    subtitle: zonesOf(i),
                    value: l10n.inviteExpiresOn(clock.day(i.expiresAt)),
                    onTap: () => _actions(i),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
