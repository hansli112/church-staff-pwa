import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/church_writes.dart';
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

  /// Writes [next] over [member] as shown; false, and says so, when it
  /// failed (someone else changed the member meanwhile, say).
  Future<bool> _save(BuildContext context, WidgetRef ref, Member member, Member next) async {
    try {
      await ref.read(churchWritesProvider).member(member, next).done;
      return true;
    } catch (e) {
      if (context.mounted) showToast(context, saveErrorText(L10n.of(context), e));
      return false;
    }
  }

  /// Takes [member] out of [service]'s 牧區, which clears its duties too,
  /// and offers 「復原」, refused once someone has changed the member since.
  Future<void> _leaveZone(BuildContext context, WidgetRef ref, Member member, Service service) async {
    final index = member.zones.indexWhere((z) => z.serviceType == service.id);
    if (index < 0) return;
    final l10n = L10n.of(context);
    final write = ref
        .read(churchWritesProvider)
        .member(member, member.copyWith(zones: [...member.zones]..removeAt(index)));
    try {
      await write.done;
    } catch (e) {
      if (context.mounted) showToast(context, saveErrorText(l10n, e));
      return;
    }
    if (context.mounted) showToast(context, l10n.zoneLeft(service.name), onUndo: write.undo);
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
                    onTap: () => _save(context, ref, member, member.copyWith(role: role)),
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
                      member,
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
              onSave: (m) => _save(context, ref, member, m),
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
        if (zone != null) ...[
          ListRow(
            title: L10n.of(context).memberSmallGroups,
            subtitle: zone.smallGroups.isEmpty ? null : zone.smallGroups.join(L10n.of(context).listSeparator),
            onTap: () async {
              final groups = await showAppSheet<List<String>>(
                context,
                builder: (_) => _SmallGroupsEditor(groups: zone.smallGroups),
              );
              if (groups != null && context.mounted) onSave(withZone(zone.copyWith(smallGroups: groups)));
            },
          ),
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
      ],
    );
  }
}

class _SmallGroupsEditor extends StatefulWidget {
  const _SmallGroupsEditor({required this.groups});

  final List<String> groups;

  @override
  State<_SmallGroupsEditor> createState() => _SmallGroupsEditorState();
}

class _SmallGroupsEditorState extends State<_SmallGroupsEditor> {
  late final _groups = TextEditingController(text: widget.groups.join('\n'));

  @override
  void dispose() {
    _groups.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(Space.m, 0, Space.m, MediaQuery.viewInsetsOf(context).bottom + Space.l),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(L10n.of(context).memberSmallGroups, style: AppText.title3)),
              SecondaryButton(
                label: L10n.of(context).save,
                onPressed: () => Navigator.pop(
                  context,
                  {
                    for (final line in _groups.text.split('\n'))
                      if (line.trim().isNotEmpty) line.trim(),
                  }.toList(),
                ),
              ),
            ],
          ),
          TextField(
            controller: _groups,
            autofocus: true,
            keyboardType: TextInputType.multiline,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(hintText: L10n.of(context).memberSmallGroupsHint),
          ),
        ],
      ),
    ),
  );
}
