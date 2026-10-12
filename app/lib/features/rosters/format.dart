import 'package:intl/intl.dart';

import '../../domain/day.dart';
import '../../l10n/app_localizations.dart';

/// 「10月4日 週日」 (Sun, Oct 4); with the year when it is not this year;
/// with 「今天」 or 「明天」 in front when it applies.
String dayLabel(L10n l10n, Day day, Day today) {
  final date = DateTime(day.year, day.month, day.day);
  final base = (day.year == today.year ? DateFormat.MMMEd() : DateFormat.yMMMEd()).format(date);
  final diff = today.daysUntil(day);
  if (diff == 0) return '${l10n.today} · $base';
  if (diff == 1) return '${l10n.tomorrow} · $base';
  return base;
}
