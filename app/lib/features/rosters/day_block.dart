import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../domain/day.dart';

/// [day] as a calendar leaf, beside [dayBesideBlock]'s words. Screen readers
/// hear the date, with the year when it is not this year; the words beside
/// it say the rest. [color]: the event's beside it, one of [EventColors].
DateBlock dayBlock(Day day, Day today, {int? color}) => DateBlock(
  color: color,
  month: DateFormat.MMM().format(day.midnight),
  day: day.day,
  today: day == today,
  past: day.isBefore(today),
  semanticLabel: (day.year == today.year ? DateFormat.MMMd() : DateFormat.yMMMd()).format(day.midnight),
);
