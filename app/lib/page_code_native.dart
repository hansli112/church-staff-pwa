import 'package:flutter/widgets.dart';

import 'features/admin/admin_screens.dart';
import 'features/calendar/calendar_settings_screen.dart';
import 'features/church/move_screen.dart';
import 'features/me/church_info_screen.dart';
import 'features/rosters/import_screen.dart';

// iOS and Android: the pages are in the app, not deferred. On iOS a
// Shorebird patch that changed code in a deferred library made the app
// jump into the patch file, and iOS killed it (CODESIGNING, Invalid Page:
// the back office on 1.0.0+20, patch 6). The web build uses
// page_code_web.dart.

Future<void> loadAdmin() async {}
Future<void> loadCalendarSettings() async {}
Future<void> loadChurchInfo() async {}
Future<void> loadMove() async {}
Future<void> loadRosterImport() async {}

Widget adminScreen() => const AdminScreen();
Widget adminStatsScreen() => const AdminStatsScreen();
Widget adminFundingScreen() => const AdminFundingScreen();
Widget calendarSettingsScreen(String? result) => CalendarSettingsScreen(result: result);
Widget churchInfoScreen() => const ChurchInfoScreen();
Widget moveScreen() => const MoveScreen();
Widget importScreen(String serviceType) => ImportScreen(serviceType: serviceType);
