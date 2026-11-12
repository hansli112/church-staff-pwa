import 'package:flutter/material.dart';

import '../../core/design/components.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';

/// One person as one of [service]'s 同工 (#94): the duties they serve
/// there and their 小組 in it, each ticked in a menu, and, with [onLeave],
/// 移出. How each saves is the caller's: an admin writes the member, a
/// 負責人 asks the backend. [header] is the service's name, or on a page of
/// one service the person's.
class ServiceStaffSection extends StatelessWidget {
  const ServiceStaffSection({
    super.key,
    required this.person,
    required this.service,
    required this.smallGroups,
    required this.header,
    required this.onDuty,
    required this.onSmallGroup,
    this.onLeave,
  });

  final Member person;
  final Service service;

  /// The service's 小組 (#85).
  final List<SmallGroupDetails> smallGroups;
  final String header;
  final Future<bool> Function(String duty, bool on) onDuty;
  final Future<bool> Function(SmallGroupDetails group, bool on) onSmallGroup;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final serves = person.zones.where((z) => z.serviceType == service.id).firstOrNull?.duties ?? const <String>[];
    // A duty gone from the service since stays until it is unticked.
    final duties = {...service.duties, ...serves}.toList();
    return ListSection(
      header: header,
      children: [
        if (duties.isNotEmpty)
          MultiSelectRow<String>(
            title: l10n.staffDuties,
            options: duties,
            selected: serves.toSet(),
            label: (d) => d,
            none: l10n.noneChosen,
            onChanged: onDuty,
          ),
        if (smallGroups.isNotEmpty)
          MultiSelectRow<String>(
            title: l10n.smallGroups,
            options: [for (final g in smallGroups) g.id],
            selected: person.smallGroups,
            label: (id) => smallGroups.firstWhere((g) => g.id == id).name,
            none: l10n.noneChosen,
            onChanged: (id, on) => onSmallGroup(smallGroups.firstWhere((g) => g.id == id), on),
          ),
        if (onLeave != null) ListRow(title: l10n.leaveService(service.name), destructive: true, onTap: onLeave),
      ],
    );
  }
}
