import 'package:flutter/widgets.dart';

import 'features/admin/admin_screens.dart' deferred as admin_screens;
import 'features/calendar/calendar_settings_screen.dart' deferred as calendar_settings;
import 'features/church/move_screen.dart' deferred as move_screen;
import 'features/me/church_info_screen.dart' deferred as church_info;
import 'features/rosters/import_screen.dart' deferred as roster_import;

// The web build: each page's code is a script of its own, downloaded when
// the page opens. Native builds use page_code_native.dart.

Future<void> loadAdmin() => admin_screens.loadLibrary();
Future<void> loadCalendarSettings() => calendar_settings.loadLibrary();
Future<void> loadChurchInfo() => church_info.loadLibrary();
Future<void> loadMove() => move_screen.loadLibrary();
Future<void> loadRosterImport() => roster_import.loadLibrary();

Widget adminScreen() => admin_screens.AdminScreen();
Widget adminStatsScreen() => admin_screens.AdminStatsScreen();
Widget adminFundingScreen() => admin_screens.AdminFundingScreen();
Widget calendarSettingsScreen(String? result) => calendar_settings.CalendarSettingsScreen(result: result);
Widget churchInfoScreen() => church_info.ChurchInfoScreen();
Widget moveScreen() => move_screen.MoveScreen();
Widget importScreen(String serviceType) => roster_import.ImportScreen(serviceType: serviceType);
