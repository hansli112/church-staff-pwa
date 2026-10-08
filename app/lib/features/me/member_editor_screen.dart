import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../common/labels.dart';

/// An admin editing one member: role, permission groups, and per service
/// whether they belong to its 牧區 and the duties they serve there. Every
/// change saves at once.
///
/// An admin cannot demote or remove themself (the rules forbid it too), so
/// those controls do not appear on their own page.
class MemberEditorScreen extends ConsumerWidget {
  const MemberEditorScreen({super.key, required this.uid});

  final String uid;

  /// Saves [next]; false, and says so, when it failed.
  Future<bool> _save(BuildContext context, WidgetRef ref, Member next) async {
    try {
      await ref.churchData.saveMember(next);
      return true;
    } catch (_) {
      if (context.mounted) showToast(context, L10n.of(context).saveFailed);
      return false;
    }
  }

  /// Takes [member] out of [service]'s 牧區, which clears its duties too,
  /// and offers 「復原」: the 牧區 comes back where it was, on the member as
  /// they are by then.
  Future<void> _leaveZone(BuildContext context, WidgetRef ref, Member member, Service service) async {
    final index = member.zones.indexWhere((z) => z.serviceType == service.id);
    if (index < 0) return;
    final zone = member.zones[index];
    // The toast outlives this page, so undo holds on to what it needs.
    final container = ProviderScope.containerOf(context, listen: false);
    final data = ref.churchData;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    if (!await _save(context, ref, member.copyWith(zones: [...member.zones]..removeAt(index)))) return;
    if (!context.mounted) return;
    showToast(
      context,
      l10n.zoneLeft(service.name),
      onUndo: () {
        // The member as they are now, which may not show the change yet.
        final now = container.read(membersProvider).value?.where((m) => m.uid == member.uid).firstOrNull ?? member;
        final rest = [
          for (final z in now.zones)
            if (z.serviceType != service.id) z,
        ];
        data.saveMember(now.copyWith(zones: rest..insert(index.clamp(0, rest.length), zone))).catchError((_) {
          messenger.showSnackBar(SnackBar(content: Text(l10n.saveFailed)));
        });
      },
    );
  }

  /// Picks a pending member and, once confirmed, merges it into [member].
  Future<void> _mergePending(BuildContext context, WidgetRef ref, Member member, List<PendingMember> pending) async {
    final l10n = L10n.of(context);
    final picked = await showAppSheet<PendingMember>(
      context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: ListSection(
            header: l10n.mergePendingPick,
            children: [
              for (final p in pending)
                ListRow(
                  title: p.name.isEmpty ? p.email : p.name,
                  subtitle: p.name.isEmpty || p.email.isEmpty ? null : p.email,
                  onTap: () => Navigator.pop(context, p),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    final name = picked.name.isEmpty ? picked.email : picked.name;
    final ok = await askChoice(
      context,
      title: l10n.mergePendingTitle(name, member.name),
      message: l10n.mergePendingBody(name),
      yes: l10n.mergePendingAction,
      no: l10n.cancel,
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.churchData.mergePending(picked.id, member.uid);
      Haptics.success();
      if (context.mounted) showToast(context, l10n.merged);
    } catch (e) {
      if (context.mounted) showToast(context, errorText(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final pending = ref.watch(pendingMembersProvider).value ?? const <PendingMember>[];
    final member = ref.watch(
      membersProvider.select(
        (v) => v.value?.where((m) => m.uid == uid).firstOrNull,
      ),
    );
    final services = ref.watch(servicesProvider).value;
    final self = ref.watch(uidProvider) == uid;
    if (member == null || services == null) return Scaffold(appBar: AppBar());

    final zoneTypes = member.zoneTypes.toSet();
    final shown = [
      for (final s in services.services)
        if (s.enabled || zoneTypes.contains(s.id)) s,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(member.name)),
      body: ListView(
        children: [
          if (!self)
            ListSection(
              header: l10n.role,
              children: [
                for (final role in Role.values)
                  ListRow(
                    title: roleLabel(l10n, role),
                    // The only role that grants anything; the rest are titles.
                    subtitle: role == Role.admin ? l10n.roleAdminCan : null,
                    selected: member.role == role,
                    onTap: () => _save(context, ref, member.copyWith(role: role)),
                  ),
              ],
            ),
          if (!member.isAdmin)
            ListSection(
              header: l10n.groups,
              children: [
                for (final g in Group.values)
                  SwitchRow(
                    title: groupLabel(l10n, g),
                    value: member.groups.contains(g),
                    onChanged: (on) => _save(
                      context,
                      ref,
                      member.copyWith(
                        groups: on ? {...member.groups, g} : ({...member.groups}..remove(g)),
                      ),
                    ),
                  ),
              ],
            ),
          for (final s in shown)
            _ZoneSection(
              member: member,
              service: s,
              onSave: (m) => _save(context, ref, m),
              onLeave: () => _leaveZone(context, ref, member, s),
            ),
          if (shown.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                l10n.zonesFooter,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (pending.isNotEmpty)
            ListSection(
              footer: l10n.mergePendingFooter,
              children: [
                ListRow(title: l10n.mergePending, onTap: () => _mergePending(context, ref, member, pending)),
              ],
            ),
          if (!self)
            ListSection(
              children: [
                ListRow(
                  title: l10n.removeMember,
                  destructive: true,
                  onTap: () => Navigator.of(context).pop('remove'),
                ),
              ],
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _ZoneSection extends StatelessWidget {
  const _ZoneSection({
    required this.member,
    required this.service,
    required this.onSave,
    required this.onLeave,
  });

  final Member member;
  final Service service;
  final ValueChanged<Member> onSave;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final zone = member.zones.where((z) => z.serviceType == service.id).firstOrNull;
    final duties = {...service.duties, ...?zone?.duties}.toList();
    Member withZone(Zone? next) => member.copyWith(
      zones: [
        for (final z in member.zones)
          if (z.serviceType != service.id) z,
        ?next,
      ],
    );
    return ListSection(
      header: service.name,
      children: [
        SwitchRow(
          title: L10n.of(context).zoneSwitch,
          value: zone != null,
          onChanged: (on) => on ? onSave(withZone(Zone(serviceType: service.id))) : onLeave(),
        ),
        if (zone != null)
          for (final d in duties)
            ListRow(
              title: d,
              selected: zone.duties.contains(d),
              onTap: () {
                Haptics.selection();
                onSave(
                  withZone(
                    zone.copyWith(
                      duties: zone.duties.contains(d)
                          ? [
                              for (final x in zone.duties)
                                if (x != d) x,
                            ]
                          : [...zone.duties, d],
                    ),
                  ),
                );
              },
            ),
      ],
    );
  }
}
