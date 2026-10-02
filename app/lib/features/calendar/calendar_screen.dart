import 'package:flutter/material.dart';

import '../shell/placeholder_tab.dart';
import '../shell/shell.dart';

/// 行事曆 tab. Filled in with the Google Calendar connection.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderTab(tab: AppTab.calendar);
}
