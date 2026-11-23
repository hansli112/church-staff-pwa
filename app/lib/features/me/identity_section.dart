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

/// A member's 身分 (#82), on their page, for an admin: each by its name,
/// which says what it is, one more added from a short list (行政 saying
/// what it is, which its name does not), one taken away with 復原. Only the
/// church-wide ones are added here: a 負責人 or 小組長 on the page of what
/// they lead (2026-11-23), listed here too.
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
    final groups = ref.watch(smallGroupsProvider).value;
    final smallGroups = groups ?? const <SmallGroupDetails>[];
    final held = member.identities;
    String label(Identity i) =>
        identityLabel(l10n, i, services: services, ministries: ministries, smallGroups: smallGroups);
    return ListSection(
      header: l10n.role,
      children: [
        // Not one of a deleted service: it comes back with 復原.
        for (final i in held)
          if (identityStands(i, services: services, smallGroups: groups))
            ListRow(
              title: label(i),
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
          title: l10n.addIdentity,
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

  /// A 身分 to add: 管理員, 行政, or 牧者 and where they shepherd.
  Future<Identity?> _pick(BuildContext context, WidgetRef ref, List<Identity> held) async {
    final l10n = L10n.of(context);
    final services = ref.read(servicesProvider).value?.services ?? const <Service>[];
    final kind = await _choose<String>(context, l10n.addIdentity, [
      if (!held.contains(const AdminIdentity())) ('admin', l10n.roleAdmin, null),
      if (!held.contains(const OfficeIdentity())) ('office', l10n.identityOffice, l10n.canOffice),
      ('pastor', l10n.identityPastor, null),
    ], footer: l10n.addIdentityLeadsElsewhere);
    if (kind == null || !context.mounted) return null;
    switch (kind) {
      case 'admin':
        return const AdminIdentity();
      case 'office':
        return const OfficeIdentity();
      default:
        final id = await _choose<String>(context, l10n.pickPastorScope, [
          ('', l10n.wholeChurch, null),
          for (final s in services) (s.id, s.name, null),
        ]);
        return id == null ? null : PastorIdentity(id.isEmpty ? null : [id]);
    }
  }

  /// One of [options] (value, title, what it means), picked in a sheet,
  /// [footer] under them.
  static Future<T?> _choose<T>(
    BuildContext context,
    String header,
    List<(T, String, String?)> options, {
    String? footer,
  }) => showAppSheet<T>(
    context,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: ListSection(
          header: header,
          footer: footer,
          children: [
            for (final (value, title, subtitle) in options)
              ListRow(title: title, subtitle: subtitle, onTap: () => Navigator.pop(context, value)),
          ],
        ),
      ),
    ),
  );
}
