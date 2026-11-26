import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/design/tokens.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../../state/providers.dart';

/// The 小組 of the church, by id: a duty given to one shows it so; one
/// gone is just its name.
Set<String> churchSmallGroupIds(WidgetRef ref) => ref
    .watch(
      smallGroupsProvider.select((s) => {for (final g in s.value ?? const <SmallGroupDetails>[]) g.id}.join('\u0000')),
    )
    .split('\u0000')
    .toSet();

/// [duty]'s people as a line: each name, and after a 小組 given the duty
/// (服事交給小組, one of [groupIds]) its icon, so the names still start
/// where every other row's do. [styleOf]: a name's own style, if any.
List<InlineSpan> dutyPeopleSpans(
  BuildContext context,
  Duty duty, {
  required Set<String> groupIds,
  TextStyle? Function(String name)? styleOf,
}) {
  final l10n = L10n.of(context);
  final c = AppColors.of(context);
  return [
    for (final (i, name) in duty.people.indexed) ...[
      if (i > 0) TextSpan(text: l10n.listSeparator),
      TextSpan(text: name, style: styleOf?.call(name)),
      if (duty.groupOf(name) case final id? when groupIds.contains(id))
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 2),
            child: Icon(Symbols.groups_rounded, size: 18, color: c.secondaryLabel, semanticLabel: l10n.smallGroups),
          ),
        ),
    ],
  ];
}
