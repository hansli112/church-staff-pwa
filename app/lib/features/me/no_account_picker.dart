import 'package:flutter/material.dart';

import '../../core/design/components.dart';
import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../domain/text.dart';
import '../../l10n/app_localizations.dart';

/// What one of the 同工 without an account is known by: their 小組, then
/// what they serve, 「喜樂小組 · 主日崇拜・招待、司琴」.
String noAccountDetails(L10n l10n, PendingMember p, ServiceSettings? services, List<SmallGroupDetails> smallGroups) {
  final groups = p.asMember(smallGroups).smallGroups;
  return [
    for (final g in smallGroups)
      if (groups.contains(g.id)) g.name,
    for (final z in p.zones)
      if (services?.byId(z.serviceType)?.name case final service?)
        z.duties.isEmpty ? service : l10n.claimServe(service, z.duties.join(l10n.listSeparator)),
  ].join(l10n.dotSeparator);
}

/// The same for one a member may be: their 小組, then the duties the
/// backend gave, each once, 「喜樂小組 · 主日崇拜・招待」.
String candidateDetails(L10n l10n, ClaimCandidate c) => [
  ...c.smallGroups,
  ...{for (final s in c.serves) l10n.claimServe(s.service, s.duty)},
].join(l10n.dotSeparator);

/// A sheet headed [title] to pick one of [people] (同工 without an
/// account): those named like [name] first (the same name, then one inside
/// the other, 小明 and 王小明), each with its [details], and a search over
/// what [searched] gives.
class NoAccountPicker<T> extends StatefulWidget {
  const NoAccountPicker({
    super.key,
    required this.title,
    required this.name,
    required this.people,
    required this.nameOf,
    required this.details,
    required this.searched,
  });

  final String title;
  final String name;
  final List<T> people;
  final String Function(T) nameOf;
  final String Function(T) details;
  final List<String> Function(T) searched;

  @override
  State<NoAccountPicker<T>> createState() => _NoAccountPickerState<T>();
}

class _NoAccountPickerState<T> extends State<NoAccountPicker<T>> {
  String _query = '';

  late final List<T> _ordered = () {
    int rank(T p) => nameMatch(widget.nameOf(p), widget.name).index;
    return [...widget.people]..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : widget.nameOf(a).compareTo(widget.nameOf(b));
    });
  }();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final shown = [
      for (final p in _ordered)
        if (widget.searched(p).any((t) => matchesSearch(t, _query))) p,
    ];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: Text(widget.title, style: AppText.headline),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.s),
            child: SearchField(hint: l10n.searchMembers, onChanged: (q) => setState(() => _query = q)),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: ListSection(
                children: [
                  for (final p in shown)
                    ListRow(
                      title: widget.nameOf(p),
                      subtitle: switch (widget.details(p)) {
                        '' => null,
                        final d => d,
                      },
                      onTap: () => Navigator.pop(context, p),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
