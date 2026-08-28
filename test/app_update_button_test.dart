import 'dart:async';

import 'package:church_staff_pwa/core/services/app_update_service.dart';
import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/auth/domain/repositories/auth_repository.dart';
import 'package:church_staff_pwa/features/auth/presentation/providers/session_provider.dart';
import 'package:church_staff_pwa/features/auth/presentation/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// 個人頁的「檢查更新」。
///
/// 真正的交接（waiting / skipWaiting / controllerchange）在
/// `web/app_update.js`，那邊有自己的一組測試（web-tests/app_update.test.js）。
/// 這裡守的是接到 UI 上的那一段：按鈕在什麼情況出現、按下去之後使用者看到
/// 什麼 —— 尤其是失敗時不能看起來像「檢查過了，沒事」，那正是這顆按鈕存在的
/// 情境（使用者已經不相信畫面上的版本了）。
class _FakeUpdateService implements AppUpdateService {
  _FakeUpdateService({
    required this.result,
    this.isSupported = true,
    this.error,
    this.gate,
  });

  final AppUpdateResult result;
  final Object? error;

  /// 給「檢查中」那個測試用：不完成的話，按鈕就停在等待狀態。
  final Completer<void>? gate;

  @override
  final bool isSupported;

  int calls = 0;

  @override
  Future<AppUpdateResult> checkForUpdate() async {
    calls += 1;
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return result;
  }
}

const _user = User(
  id: 'u1',
  name: '測試者',
  email: 'a@b.c',
  username: 'tester',
  role: UserRole.member,
);

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<User?> getCachedUser() async => _user;
  @override
  Future<User?> getCurrentUser() async => _user;
  @override
  Future<void> writeCachedUser(User user) async {}
  @override
  Future<User?> login(String username, String password) async => _user;
  @override
  Future<void> logout() async {}
  @override
  Future<List<User>> getUsers() async => const [_user];
  @override
  Future<void> addUser(User user, String password) async {}
  @override
  Future<void> updateUser(User user, {String? password}) async {}
  @override
  Future<void> deleteUser(String id) async {}
}

Future<void> _pumpProfile(
  WidgetTester tester,
  _FakeUpdateService updateService,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => SessionProvider(_FakeAuthRepository()),
      child: MaterialApp(home: ProfileScreen(updateService: updateService)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('已是最新版本時說清楚', (tester) async {
    final service = _FakeUpdateService(result: AppUpdateResult.latest);
    await _pumpProfile(tester, service);

    await tester.tap(find.text('檢查更新'));
    await tester.pumpAndSettle();

    expect(service.calls, 1);
    expect(find.text('已經是最新版本'), findsOneWidget);
  });

  testWidgets('找到新版時告訴使用者正在換', (tester) async {
    // 換完頁面會自己重載，所以這句話只會出現一下下 —— 但沒有它，按下去到
    // 重載之間畫面完全沒有反應。
    final service = _FakeUpdateService(result: AppUpdateResult.updating);
    await _pumpProfile(tester, service);

    await tester.tap(find.text('檢查更新'));
    await tester.pumpAndSettle();

    expect(find.text('找到新版本，正在更新…'), findsOneWidget);
  });

  testWidgets('檢查失敗要說出來，不能靜靜地回「已是最新」', (tester) async {
    final service = _FakeUpdateService(
      result: AppUpdateResult.latest,
      error: Exception('offline'),
    );
    await _pumpProfile(tester, service);

    await tester.tap(find.text('檢查更新'));
    await tester.pumpAndSettle();

    expect(find.textContaining('檢查更新失敗'), findsOneWidget);
    expect(find.text('已經是最新版本'), findsNothing);
  });

  testWidgets('檢查中不能重複按', (tester) async {
    final gate = Completer<void>();
    final service = _FakeUpdateService(
      result: AppUpdateResult.latest,
      gate: gate,
    );
    await _pumpProfile(tester, service);

    await tester.tap(find.text('檢查更新'));
    await tester.pump(); // 讓 setState 生效，但結果還沒回來

    expect(find.text('檢查中…'), findsOneWidget);
    final button = tester.widget<InkWell>(
      find.ancestor(of: find.text('檢查中…'), matching: find.byType(InkWell)),
    );
    expect(button.onTap, isNull, reason: '按著不放也只會送出一次');

    gate.complete();
    await tester.pumpAndSettle();
    expect(service.calls, 1);
    expect(find.text('檢查更新'), findsOneWidget, reason: '結束後回到原本的字');
  });

  testWidgets('是頁尾的註腳，不是一顆按鈕', (tester) async {
    // 平常不必按（載入與切回前景都會自己檢查），所以它要跟旁邊的版本資訊
    // 一樣是灰色小字 —— 一顆主色的 TextButton 會比它上面那行還搶眼。
    final service = _FakeUpdateService(result: AppUpdateResult.latest);
    await _pumpProfile(tester, service);

    expect(find.byType(TextButton), findsNothing);
    final label = tester.widget<Text>(find.text('檢查更新'));
    final caption = Theme.of(
      tester.element(find.text('檢查更新')),
    ).textTheme.bodySmall;
    expect(label.style?.fontSize, caption?.fontSize);
    expect(label.style?.color, Colors.grey.shade600);
  });

  testWidgets('不支援的環境（非 web）不顯示按鈕', (tester) async {
    final service = _FakeUpdateService(
      result: AppUpdateResult.unsupported,
      isSupported: false,
    );
    await _pumpProfile(tester, service);

    expect(find.text('檢查更新'), findsNothing);
  });
}
