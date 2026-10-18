import 'package:intl/intl.dart';

import '../../domain/day.dart';
import '../../l10n/app_localizations.dart';

/// 「10月4日 週日」 (Sun, Oct 4); with the year when it is not this year;
/// with 「今天」 or 「明天」 in front when it applies.
String dayLabel(L10n l10n, Day day, Day today) {
  final base = (day.year == today.year ? DateFormat.MMMEd() : DateFormat.yMMMEd()).format(day.midnight);
  final diff = today.daysUntil(day);
  if (diff == 0) return '${l10n.today} · $base';
  if (diff == 1) return '${l10n.tomorrow} · $base';
  return base;
}

/// What [dayLabel] says beside a [dayBlock], which shows the month and
/// date: 「週日」, 「今天 · 週日」, 「2027年 · 週日」.
String dayBesideBlock(L10n l10n, Day day, Day today) {
  final diff = today.daysUntil(day);
  return [
    if (diff == 0) l10n.today else if (diff == 1) l10n.tomorrow,
    if (day.year != today.year) DateFormat.y().format(day.midnight),
    DateFormat.E().format(day.midnight),
  ].join(' · ');
}
