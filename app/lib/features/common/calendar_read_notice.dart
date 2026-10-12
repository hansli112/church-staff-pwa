import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../state/calendar.dart';
import 'time_zones.dart';

/// For content from an earlier read: says so, with when it was read. A
/// fresh read needs no label.
String? calendarReadLabel(L10n l10n, CalendarReadStatus status, ChurchClock clock) {
  if (!status.cached) return null;
  final fetched = status.fetchedAt;
  final readAt = fetched == null ? null : l10n.calendarReadAt(clock.moment(fetched));
  return [l10n.calendarCached, ?readAt].join(l10n.dotSeparator);
}

class CalendarReadNotice extends ConsumerWidget {
  const CalendarReadNotice({super.key, required this.status, this.month});

  final CalendarReadStatus status;
  final String? month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = calendarReadLabel(L10n.of(context), status, ChurchClock.of(context, ref));
    if (label == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.xs),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          month == null ? label : '$month${L10n.of(context).dotSeparator}$label',
          style: AppText.footnote.copyWith(color: AppColors.of(context).secondaryLabel),
        ),
      ),
    );
  }
}
