import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../church/links.dart';
import '../common/errors.dart';
import '../common/time_zones.dart';
import '../../state/session.dart';
import '../common/saving_indicator.dart';

final _invitesProvider = StreamProvider.autoDispose<List<Invite>>(
  (ref) => openChurch(ref).joining.invites(),
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

/// Admins make invite links, good for 30 days, share them, and revoke them.
/// A link can put the people who join with it in some 聚會 at once. 建立
/// with the 聚會 of a link that still works shares that link again, its 30
/// days counted from now: the list has one link for each set of 聚會. Under
/// them, the other way in: 申請加入 from the church URL (#88), and the URL,
/// named for what it is for there: the link to ask to join.
class InvitesScreen extends ConsumerStatefulWidget {
  const InvitesScreen({super.key});

  @override
  ConsumerState<InvitesScreen> createState() => _InvitesScreenState();
}

/// How long an invite works, from when it is made or made again.
const _validFor = Duration(days: 30);

class _InvitesScreenState extends ConsumerState<InvitesScreen> {
  bool _busy = false;

  /// The 牧區 the next invite joins, as service IDs, once the admin has
  /// ticked or unticked one; until then [_zonesOf] decides.
  Set<String>? _picked;

  /// The 牧區 the next invite joins: what was picked, or with nothing
  /// picked, a church's only service, which nearly every invite wants.
  Set<String> _zonesOf(List<Service> services) => _picked ?? {if (services.length == 1) services.single.id};

  Future<void> _create() async {
    final l10n = L10n.of(context);
    setState(() => _busy = true);
    final Invite invite;
    try {
      final services = ref.read(servicesProvider).value?.services ?? const <Service>[];
      final zones = _zonesOf(services);
      final ids = {for (final s in services) s.id};
      final existing = ref.read(_liveInvitesProvider).where((i) => i.joinsJust(zones, ids)).firstOrNull;
      invite = existing != null
          ? await ref.churchData.joining.renewInvite(existing.code, validFor: _validFor)
          : await ref.churchData.joining.createInvite(
              validFor: _validFor,
              zoneTypes: [
                for (final s in services)
                  if (zones.contains(s.id)) s.id,
              ],
            );
    } catch (_) {
      if (mounted) showToast(context, l10n.saveFailed);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // Each invite picks its own 牧區.
    if (mounted) setState(() => _picked = null);
    // Saved: whatever happens to the share sheet, the invite is in the list.
    if (mounted) await _share(invite);
  }

  Future<void> _share(Invite invite) async {
    final l10n = L10n.of(context);
    final text = l10n.inviteMessage(invite.churchName, inviteLink(invite.churchId, invite.code));
    ref.read(telemetryProvider).logEvent('share', {'content_type': 'invite', 'method': 'share'});
    await shareText(context, text, copied: l10n.inviteCopied);
  }

  Future<void> _actions(Invite invite, {required String header}) async {
    final l10n = L10n.of(context);
    final choice = await showAppSheet<String>(
      context,
      builder: (context) => SafeArea(
        child: ListSection(
          header: header,
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
        ref.read(telemetryProvider).logEvent('share', {'content_type': 'invite', 'method': 'copy'});
        await copyText(context, inviteLink(invite.churchId, invite.code), copied: l10n.inviteCopied);
      case 'revoke':
        await ref.churchData.joining.revokeInvite(invite.code);
        if (mounted) showToast(context, l10n.inviteRevoked);
    }
  }

  Future<void> _churchUrlActions(String url) async {
    final l10n = L10n.of(context);
    final choice = await showAppSheet<String>(
      context,
      builder: (context) => SafeArea(
        child: ListSection(
          header: displayUrl(url),
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
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'share':
        await shareText(context, url, copied: l10n.joinRequestLinkCopied);
      case 'copy':
        await copyText(context, url, copied: l10n.joinRequestLinkCopied);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final c = AppColors.of(context);
    final church = ref.watch(churchProvider).value;
    final live = ref.watch(_liveInvitesProvider);
    final services = ref.watch(servicesProvider).value;
    final all = services?.services ?? const <Service>[];
    final zones = _zonesOf(all);
    final clock = ChurchClock.of(context, ref);
    String? zonesOf(Invite i) {
      final names = [for (final t in i.zoneTypes) ?services?.byId(t)?.name];
      return names.isEmpty ? null : names.join(l10n.listSeparator);
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.invites), actions: const [SavingIndicator()]),
      body: ListView(
        children: [
          // Any number of 牧區: an empty circle says it can be ticked.
          if (all.isNotEmpty)
            ListSection(
              header: l10n.inviteZones,
              footer: l10n.inviteZonesFooter,
              children: [
                for (final s in all)
                  Semantics(
                    selected: zones.contains(s.id),
                    child: ListRow(
                      title: s.name,
                      leading: zones.contains(s.id)
                          ? Icon(Symbols.check_circle_rounded, fill: 1, color: c.accent)
                          : const Icon(Symbols.circle_rounded),
                      chevron: false,
                      onTap: () {
                        Haptics.selection();
                        setState(() => _picked = {...zones}..toggle(s.id));
                      },
                    ),
                  ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.m),
            child: PrimaryButton(
              label: l10n.inviteCreate,
              icon: const Icon(Symbols.link_rounded),
              // Waits for the links there are, to share one again.
              busy: _busy || ref.watch(_invitesProvider).isLoading,
              onPressed: _create,
            ),
          ),
          if (live.isNotEmpty)
            ListSection(
              header: l10n.inviteLinks,
              children: [
                // What it joins and when it ends; the code is the link's.
                for (final (invite, joins) in [for (final i in live) (i, zonesOf(i) ?? l10n.inviteChurchOnly)])
                  ListRow(
                    title: joins,
                    value: l10n.inviteExpiresOn(clock.day(invite.expiresAt)),
                    onTap: () => _actions(invite, header: joins),
                  ),
              ],
            ),
          if (church != null)
            ListSection(
              footer: l10n.takesJoinRequestsFooter,
              children: [
                SwitchRow(
                  title: l10n.takesJoinRequests,
                  value: church.takesJoinRequests,
                  onChanged: (on) async {
                    try {
                      await ref.churchData.joining.setTakesRequests(on);
                    } catch (e) {
                      if (context.mounted) showToast(context, saveErrorText(l10n, e));
                    }
                  },
                ),
                if (church.takesJoinRequests)
                  ListRow(
                    title: l10n.joinRequestLink,
                    subtitle: displayUrl(churchUrl(church.id)),
                    chevron: false,
                    onTap: () => _churchUrlActions(churchUrl(church.id)),
                  ),
              ],
            ),
          SizedBox(height: Space.l + MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}

extension on Set<String> {
  /// Adds [id], or takes it out if in.
  void toggle(String id) => remove(id) || add(id);
}
