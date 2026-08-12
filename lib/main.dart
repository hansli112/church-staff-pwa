import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'core/services/push_notification_service.dart';
import 'core/widgets/perf_hud.dart';
import 'core/widgets/scroll_bench_screen.dart';
import 'features/roster/data/repositories/firestore_roster_repository.dart';
import 'features/roster/presentation/providers/roster_provider.dart';
import 'features/auth/data/repositories/firebase_auth_repository.dart';
import 'features/auth/data/repositories/firestore_group_settings_repository.dart';
import 'features/auth/presentation/providers/session_provider.dart';
import 'features/auth/presentation/providers/user_admin_provider.dart';
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
    // persistenceEnabled 預設為 true（IndexedDB），明示以確保行為清晰。
    // cacheSizeBytes 維持預設 40MB，對本應用來說足夠。
    persistenceEnabled: true,
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

  // fromSeed 會跑一整套 Material color 演算法，結果永遠一樣，算一次就好。
  static final ColorScheme _colorScheme = ColorScheme.fromSeed(
    seedColor: Colors.blue,
    brightness: Brightness.light,
  );

  /// 用 `?perf=1` 開啟畫面上的即時效能數字（[PerfHud]）。
  ///
  /// 注意不能用 Flutter 內建的 `showPerformanceOverlay` —— 它在 Web 上是
  /// 沒有實作的 no-op，引擎只會印一行警告，畫面上什麼都不會出現。
  ///
  /// 預設關閉，一般使用者不會遇到。
  static final bool _showPerfHud =
      Uri.base.queryParameters['perf'] == '1' || _benchMode;

  /// 用 `?bench=1` 進入捲動基準測試（不需要登入），並自動打開 HUD。
  static final bool _benchMode = Uri.base.queryParameters['bench'] == '1';

  @override
  Widget build(BuildContext context) {
    final colorScheme = _colorScheme;
    return MultiProvider(
      providers: [
        Provider<PushNotificationService>.value(value: pushNotificationService),

        // SessionProvider — 管理登入狀態，最上游。
        ChangeNotifierProvider(
          create: (_) => SessionProvider(FirebaseAuthRepository()),
        ),

        // UserAdminProvider — 依賴 SessionProvider。
        // 使用 ChangeNotifierProxyProvider 注入 session，讓它在登出時自動清 cache。
        ChangeNotifierProxyProvider<SessionProvider, UserAdminProvider>(
          create: (ctx) => UserAdminProvider(
            FirebaseAuthRepository(),
            ctx.read<SessionProvider>(),
          ),
          update: (_, session, prev) {
            // prev 不會是 null（create 已建立）；update 僅在依賴變動時呼叫。
            // UserAdminProvider 自己監聽 session，此處不需額外操作。
            return prev!;
          },
        ),

        // RosterProvider — session 變動時清 cache 並重抓。
        ChangeNotifierProxyProvider<SessionProvider, RosterProvider>(
          create: (_) => RosterProvider(FirestoreRosterRepository()),
          update: (_, session, prev) {
            prev ??= RosterProvider(FirestoreRosterRepository());
            prev.onSessionChanged(session.currentUser?.id);
            return prev;
          },
        ),

        // GroupSettingsProvider — session 變動時清 cache 並重抓。
        ChangeNotifierProxyProvider<SessionProvider, GroupSettingsProvider>(
          create: (_) =>
              GroupSettingsProvider(FirestoreGroupSettingsRepository()),
          update: (_, session, prev) {
            prev ??= GroupSettingsProvider(FirestoreGroupSettingsRepository());
            prev.onSessionChanged(session.currentUser?.id);
            return prev;
          },
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
        home: _benchMode
            ? const ScrollBenchScreen()
            : AuthWrapper(pushNotificationService: pushNotificationService),
        debugShowCheckedModeBanner: false,
        builder: _showPerfHud
            ? (context, child) => PerfHud(child: child ?? const SizedBox())
            : null,
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
  SessionProvider? _sessionProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextSessionProvider = context.read<SessionProvider>();
    if (_sessionProvider == nextSessionProvider) return;

    _sessionProvider?.removeListener(_onSessionChanged);
    _sessionProvider = nextSessionProvider;
    _sessionProvider!.addListener(_onSessionChanged);
    _onSessionChanged();
  }

  @override
  void dispose() {
    _sessionProvider?.removeListener(_onSessionChanged);
    unawaited(widget.pushNotificationService.dispose());
    super.dispose();
  }

  void _onSessionChanged() {
    final userId = _sessionProvider?.currentUser?.id;
    unawaited(widget.pushNotificationService.syncTokenForUser(userId));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (context, session, _) {
        if (session.isRestoring) {
          return const _AuthRestoringShell();
        }
        if (!session.isAuthenticated) {
          return const LoginScreen();
        }
        return const MainScaffold();
      },
    );
  }
}

/// Shown while SessionProvider is awaiting Firebase Auth state from IndexedDB on
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
