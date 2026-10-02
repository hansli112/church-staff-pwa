import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/components.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';
import '../common/labels.dart';

/// An admin editing one member: role, permission groups, and per service
/// the zone and the duties they serve. Every change saves at once.
///
/// An admin cannot demote or remove themself (the rules forbid it too), so
/// those controls do not appear on their own page.
class MemberEditorScreen extends ConsumerWidget {
  const MemberEditorScreen({super.key, required this.uid});

  final String uid;

  Future<void> _save(BuildContext context, WidgetRef ref, Member next) async {
    try {
      await ref.read(churchDataProvider)!.saveMember(next);
    } catch (_) {
      if (context.mounted) showToast(context, L10n.of(context).saveFailed);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
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
            ),
          if (shown.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                l10n.zonesFooter,
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
  });

  final Member member;
  final Service service;
  final ValueChanged<Member> onSave;

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
          onChanged: (on) => onSave(withZone(on ? Zone(serviceType: service.id) : null)),
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
