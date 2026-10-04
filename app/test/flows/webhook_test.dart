import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

Finder field(String label) => find.widgetWithText(TextField, label);

const hook = 'https://n8n.example/webhook/abc';

void main() {
  testWidgets('an admin sets up a webhook; the secret is shown once', (tester) async {
    final b = seededChurch();
    final out = captureOutbox(tester);
    await pumpApp(tester, b);
    await go(tester, '/me/church');
    await tapText(tester, '外部通知');

    await tester.enterText(field('接收網址'), 'http://n8n.example');
    await tapText(tester, '儲存');
    expect(find.text('請輸入 https:// 開頭的網址'), findsOneWidget);

    await tester.enterText(field('接收網址'), hook);
    await tapText(tester, '服事表異動');
    await tapText(tester, '儲存');
    expect(b.webhooks['grace'], const WebhookSettings(url: hook, calendar: true, roster: false));
    final secret = b.webhookSecrets['grace']!;
    expect(find.text(secret), findsOneWidget);
    expect(find.text('只會顯示這一次。請貼到接收端，用來驗證通知是馬大別忙送的。'), findsOneWidget);
    await tapText(tester, '複製密鑰');
    expect(out.copied, [secret]);
    await tapText(tester, '完成');
    expect(find.text(secret), findsNothing, reason: 'never shown again');
    expect(find.text('n8n.example/webhook/abc'), findsOneWidget);
  });

  testWidgets('a typed secret is used and not shown back', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me/webhook');
    await tester.enterText(field('接收網址'), hook);
    await tester.enterText(field('密鑰（選填，留空會自動產生）'), 'short');
    await tapText(tester, '儲存');
    expect(find.text('密鑰至少要 16 個字元'), findsOneWidget);
    await tester.enterText(field('密鑰（選填，留空會自動產生）'), 'our-shared-secret-2026');
    await tapText(tester, '儲存');
    expect(b.webhookSecrets['grace'], 'our-shared-secret-2026');
    expect(find.text('密鑰'), findsNothing, reason: 'no secret dialog');
  });

  testWidgets('switches, a test, and the last delivery', (tester) async {
    final b = seededChurch()
      ..webhooks['grace'] = const WebhookSettings(url: hook, calendar: true)
      ..webhookSecrets['grace'] = 'whsec_existing';
    await pumpApp(tester, b);
    await go(tester, '/me/webhook');

    await tapText(tester, '服事表異動');
    expect(b.webhooks['grace']!.roster, isTrue);
    await tapText(tester, '行事曆異動');
    expect(b.webhooks['grace']!.calendar, isFalse);

    await tapText(tester, '傳送測試');
    expect(b.webhookSent, [('grace', 'ping')]);
    expect(find.text('成功'), findsOneWidget);
    expect(find.textContaining('上次送出：'), findsOneWidget);
    expect(find.textContaining('・成功'), findsOneWidget);

    b.webhookAnswer = const WebhookDelivery(ok: false, status: 500, error: WebhookDeliveryError.http);
    await tapText(tester, '傳送測試');
    expect(find.textContaining('・對方回應 500'), findsOneWidget);
    b.webhookAnswer = const WebhookDelivery(ok: false, error: WebhookDeliveryError.timeout);
    await tapText(tester, '傳送測試');
    expect(find.textContaining('・逾時'), findsOneWidget);
  });

  testWidgets('a new secret replaces the old one and is shown once', (tester) async {
    final b = seededChurch()
      ..webhooks['grace'] = const WebhookSettings(url: hook, calendar: true)
      ..webhookSecrets['grace'] = 'whsec_existing';
    await pumpApp(tester, b);
    await go(tester, '/me/webhook');
    await tapText(tester, '換新的密鑰');
    expect(find.text('舊的密鑰會立刻失效，接收端要改用新的。'), findsOneWidget);
    await tapText(tester, '自動產生');
    final secret = b.webhookSecrets['grace']!;
    expect(secret, isNot('whsec_existing'));
    expect(find.text(secret), findsOneWidget);
  });

  testWidgets('turning it off asks first', (tester) async {
    final b = seededChurch()
      ..webhooks['grace'] = const WebhookSettings(url: hook)
      ..webhookSecrets['grace'] = 'whsec_existing';
    await pumpApp(tester, b);
    await go(tester, '/me/webhook');
    await tapText(tester, '關閉外部通知');
    await tapText(tester, '取消');
    expect(b.webhooks['grace'], isNotNull);
    await tapText(tester, '關閉外部通知');
    await tapText(tester, '關閉');
    expect(b.webhooks['grace'], isNull);
    expect(b.webhookSecrets['grace'], isNull);
  });

  testWidgets('only admins see it', (tester) async {
    await pumpApp(tester, seededChurch(as: editor));
    await go(tester, '/me/church');
    expect(find.text('外部通知'), findsNothing);
  });
}
