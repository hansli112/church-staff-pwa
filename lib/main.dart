import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'core/services/push_notification_service.dart';
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

  // Run independent inits in parallel to shave startup latency.
  await Future.wait([
    initializeDateFormatting('zh_TW', null),
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
  ]);

  // Force long polling on web instead of WebSocket. WebSocket transport is
  // unstable on Safari (iOS + macOS), causing dropped Firestore subscriptions
  // for our iPhone users. Long polling is slightly slower but reliable across
  // browsers. See commit 7d6b4e2.
  FirebaseFirestore.instance.settings = const Settings(
    webExperimentalForceLongPolling: true,
  );

  // PushNotificationService.initialize only registers stream listeners; we
  // don't need to block runApp on it.
  final pushNotificationService = PushNotificationService();
  unawaited(pushNotificationService.initialize());

  runApp(ChurchApp(pushNotificationService: pushNotificationService));
}

class ChurchApp extends StatelessWidget {
  const ChurchApp({super.key, required this.pushNotificationService});

  final PushNotificationService pushNotificationService;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.light,
    );
    return MultiProvider(
      providers: [
        Provider<PushNotificationService>.value(value: pushNotificationService),
        ChangeNotifierProvider(
          create: (_) => RosterProvider(FirestoreRosterRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(FirebaseAuthRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              GroupSettingsProvider(FirestoreGroupSettingsRepository()),
        ),
      ],
      child: MaterialApp(
        title: '竹圍靈糧福音中心',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: colorScheme,
          inputDecorationTheme: InputDecorationTheme(
            hintStyle: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
          appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        ),
        locale: const Locale('zh', 'TW'),
        home: AuthWrapper(pushNotificationService: pushNotificationService),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key, required this.pushNotificationService});

  final PushNotificationService pushNotificationService;

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  AuthProvider? _authProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextAuthProvider = context.read<AuthProvider>();
    if (_authProvider == nextAuthProvider) return;

    _authProvider?.removeListener(_onAuthChanged);
    _authProvider = nextAuthProvider;
    _authProvider!.addListener(_onAuthChanged);
    _onAuthChanged();
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onAuthChanged);
    unawaited(widget.pushNotificationService.dispose());
    super.dispose();
  }

  void _onAuthChanged() {
    final userId = _authProvider?.currentUser?.id;
    unawaited(widget.pushNotificationService.syncTokenForUser(userId));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        if (auth.isRestoring) {
          return const _AuthRestoringShell();
        }
        if (!auth.isAuthenticated) {
          return const LoginScreen();
        }
        return const MainScaffold();
      },
    );
  }
}

/// Shown while AuthProvider is awaiting Firebase Auth state from IndexedDB on
/// app start. Faster perceived load than a blank screen + spinner: the user
/// sees the church branding immediately and an inline status row below it.
class _AuthRestoringShell extends StatelessWidget {
  const _AuthRestoringShell();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '竹圍靈糧福音中心',
                style: theme.textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 12),
                  Text('載入中…', style: theme.textTheme.titleMedium),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
