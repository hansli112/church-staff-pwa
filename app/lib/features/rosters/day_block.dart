import 'package:intl/intl.dart';

import '../../core/design/components.dart';
import '../../domain/day.dart';

/// [day] as a calendar leaf, beside [dayBesideBlock]'s words. Screen readers
/// hear the date, with the year when it is not this year; the words beside
/// it say the rest.
DateBlock dayBlock(Day day, Day today) => DateBlock(
  month: DateFormat.MMM().format(day.midnight),
  day: day.day,
  today: day == today,
  semanticLabel: (day.year == today.year ? DateFormat.MMMd() : DateFormat.yMMMd()).format(day.midnight),
);
