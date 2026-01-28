import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'features/roster/data/repositories/firestore_roster_repository.dart';
import 'features/roster/presentation/providers/roster_provider.dart';
import 'features/auth/data/repositories/firebase_auth_repository.dart';
import 'features/auth/data/repositories/firestore_group_settings_repository.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/providers/group_settings_provider.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'presentation/screens/main_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_TW', null);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(const ChurchApp());
}

class ChurchApp extends StatelessWidget {
  const ChurchApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => RosterProvider(FirestoreRosterRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(FirebaseAuthRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => GroupSettingsProvider(FirestoreGroupSettingsRepository()),
        ),
      ],
      child: MaterialApp(
        title: '竹圍靈糧福音中心',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: colorScheme,
          inputDecorationTheme: InputDecorationTheme(
            hintStyle: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.35),
            ),
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
        ),
        locale: const Locale('zh', 'TW'),
        home: const AuthWrapper(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isRestoring) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        if (!auth.isAuthenticated) {
          return const LoginScreen();
        }
        return const MainScaffold();
      },
    );
  }
}
