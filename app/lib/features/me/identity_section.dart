import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/components.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/church_writes.dart';
import '../../state/providers.dart';
import '../common/errors.dart';
import '../common/labels.dart';

/// A member's 身分 (#82), on their page, for an admin: what each lets them
/// do in a sentence, one more added from a short list, one taken away with
/// 復原. Holding none, they are a 同工, and the footer says what that is.
///
/// An admin cannot take away what makes themself an admin (the rules
/// refuse it too), so that row offers no removal on their own page.
class IdentitySection extends ConsumerWidget {
  const IdentitySection({super.key, required this.member, required this.self});

  final Member member;
  final bool self;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final services = ref.watch(servicesProvider).value;
    final ministries = ref.watch(ministriesProvider).value;
    final smallGroups = ref.watch(smallGroupsProvider).value ?? const <SmallGroupDetails>[];
    final held = member.identities;
    String label(Identity i) =>
        identityLabel(l10n, i, services: services, ministries: ministries, smallGroups: smallGroups);
    return ListSection(
      header: l10n.role,
      footer: held.isEmpty ? l10n.canStaff : null,
      children: [
        for (final i in held)
          ListRow(
            title: label(i),
            subtitle: identityCan(l10n, i, services: services, ministries: ministries, smallGroups: smallGroups),
            chevron: false,
            // Taken away at once, with 復原 (docs/design-principles.md).
            trailing: _removable(i)
                ? RowButton(
                    label: l10n.removeShort,
                    semanticsLabel: l10n.removeIdentityLabel(label(i)),
                    onPressed: () => _set(context, ref, [...held]..remove(i), l10n.identityRemoved(label(i))),
                  )
                : null,
          ),
        ListRow(
          title: held.isEmpty ? l10n.addIdentity : l10n.addAnotherIdentity,
          leading: const Icon(Symbols.add_rounded),
          chevron: false,
          onTap: () async {
            final added = await _pick(context, ref, held);
            if (added != null && context.mounted) {
              await _set(context, ref, _with(held, added), l10n.identityAdded(label(added)));
            }
          },
        ),
      ],
    );
  }

  /// Whether [i] may be taken away here: not, on their own page, the last
  /// thing that makes them an admin.
  bool _removable(Identity i) => !self || member.withIdentities([...member.identities]..remove(i)).isAdmin;

  /// [held] with [added]: a second service for a 牧者 joins the first.
  static List<Identity> _with(List<Identity> held, Identity added) {
    if (added case PastorIdentity(services: final more?)) {
      for (final (n, i) in held.indexed) {
        if (i case PastorIdentity(services: final some?)) {
          return [...held]..[n] = PastorIdentity({...some, ...more}.toList());
        }
      }
    }
    return [
      for (final i in held)
        if (!(added is PastorIdentity && i is PastorIdentity)) i,
      added,
    ];
  }

  Future<void> _set(BuildContext context, WidgetRef ref, List<Identity> next, String done) async {
    final l10n = L10n.of(context);
    final write = ref.read(churchWritesProvider).member(member, member.withIdentities(next));
    try {
      await write.done;
    } catch (e) {
      if (context.mounted) showToast(context, saveErrorText(l10n, e));
      return;
    }
    if (context.mounted) showToast(context, done, onUndo: write.undo);
  }

  /// A 身分 to add: its kind, then where it applies.
  Future<Identity?> _pick(BuildContext context, WidgetRef ref, List<Identity> held) async {
    final l10n = L10n.of(context);
    final services = ref.read(servicesProvider).value?.enabled ?? const <Service>[];
    final ministries = ref.read(ministriesProvider).value?.ministries ?? const <Ministry>[];
    final led = {
      for (final i in held)
        if (i case ServiceLead(:final service)) service,
    };
    final leadsMinistry = {
      for (final i in held)
        if (i case MinistryLead(:final ministry)) ministry,
    };
    final smallGroups = ref.read(smallGroupsProvider).value ?? const <SmallGroupDetails>[];
    final leadsSmallGroup = {
      for (final i in held)
        if (i case SmallGroupLead(:final smallGroup)) smallGroup,
    };
    final kind = await _choose<String>(context, l10n.addIdentity, [
      if (!held.contains(const AdminIdentity())) ('admin', l10n.roleAdmin, l10n.canAdmin),
      if (!held.contains(const OfficeIdentity())) ('office', l10n.identityOffice, l10n.canOffice),
      ('pastor', l10n.identityPastor, null),
      if (services.any((s) => !led.contains(s.id))) ('service', l10n.identityServiceLead, null),
      if (ministries.any((m) => !leadsMinistry.contains(m.id))) ('ministry', l10n.identityMinistryLead, null),
      if (smallGroups.any((g) => !leadsSmallGroup.contains(g.id))) ('small', l10n.identitySmallGroupLead, null),
    ]);
    if (kind == null || !context.mounted) return null;
    switch (kind) {
      case 'admin':
        return const AdminIdentity();
      case 'office':
        return const OfficeIdentity();
      case 'pastor':
        final id = await _choose<String>(context, l10n.pickPastorScope, [
          ('', l10n.wholeChurch, l10n.canAdmin),
          for (final s in services) (s.id, s.name, null),
        ]);
        return id == null ? null : PastorIdentity(id.isEmpty ? null : [id]);
      case 'service':
        final id = await _choose<String>(context, l10n.pickService, [
          for (final s in services)
            if (!led.contains(s.id)) (s.id, s.name, null),
        ]);
        return id == null ? null : ServiceLead(id);
      case 'small':
        final id = await _choose<String>(context, l10n.pickSmallGroup, [
          for (final g in smallGroups)
            if (!leadsSmallGroup.contains(g.id))
              (g.id, g.name, ref.read(servicesProvider).value?.byId(g.service)?.name),
        ]);
        return id == null ? null : SmallGroupLead(id);
      default:
        final id = await _choose<String>(context, l10n.pickMinistry, [
          for (final m in ministries)
            if (!leadsMinistry.contains(m.id)) (m.id, m.name, null),
        ]);
        return id == null ? null : MinistryLead(id);
    }
  }

  /// One of [options] (value, title, what it means), picked in a sheet.
  static Future<T?> _choose<T>(BuildContext context, String header, List<(T, String, String?)> options) =>
      showAppSheet<T>(
        context,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            child: ListSection(
              header: header,
              children: [
                for (final (value, title, subtitle) in options)
                  ListRow(title: title, subtitle: subtitle, onTap: () => Navigator.pop(context, value)),
              ],
            ),
          ),
        ),
      );
}

/// The 事工 a member is a 同工 of (#82), switched on and off by an admin.
/// Nothing while the church has none.
class MinistriesSection extends ConsumerWidget {
  const MinistriesSection({super.key, required this.member});

  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final ministries = ref.watch(ministriesProvider).value?.ministries ?? const <Ministry>[];
    if (ministries.isEmpty) return const SizedBox.shrink();
    return ListSection(
      header: l10n.ministries,
      children: [
        for (final m in ministries)
          SwitchRow(
            title: m.name,
            value: member.ministries.contains(m.id),
            onChanged: (on) async {
              final write = ref
                  .read(churchWritesProvider)
                  .member(member, member.inGroupAs(MinistryGroup(m.id), member: on));
              try {
                await write.done;
              } catch (e) {
                if (context.mounted) showToast(context, saveErrorText(l10n, e));
              }
            },
          ),
      ],
    );
  }
}
