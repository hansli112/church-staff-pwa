import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'features/roster/data/repositories/mock_roster_repository.dart';
import 'features/roster/presentation/providers/roster_provider.dart';
import 'presentation/screens/main_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_TW', null);
  
  runApp(const ChurchApp());
}

class ChurchApp extends StatelessWidget {
  const ChurchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => RosterProvider(MockRosterRepository()),
        ),
      ],
      child: MaterialApp(
        title: '教會同工助手',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
        ),
        locale: const Locale('zh', 'TW'),
        home: const MainScaffold(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}