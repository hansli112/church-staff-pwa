import 'package:church_staff_pwa/core/config/church_config.dart';
import 'package:church_staff_pwa/core/config/service_catalog.dart';
import 'package:church_staff_pwa/features/services/presentation/providers/service_catalog_provider.dart';
import 'package:church_staff_pwa/features/services/presentation/screens/service_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/church_test_config.dart';
import 'support/in_memory_service_settings.dart';

Future<InMemoryServiceSettings> _pump(WidgetTester tester) async {
  final repo = InMemoryServiceSettings();
  final provider = ServiceCatalogProvider(repo, reload: (_) async => false);
  await tester.pumpWidget(
    ChangeNotifierProvider<ServiceCatalogProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ServiceSettingsScreen(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  late ChurchConfig deployed;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    deployed = testChurchConfig();
    ServiceCatalog.resetForTesting(deployed);
  });
  tearDown(() => ServiceCatalog.resetForTesting(deployed));

  testWidgets('列出部署設定的聚會和星期', (tester) async {
    await _pump(tester);
    final first = deployed.services.first;
    expect(find.text('${first.label}｜${first.name}'), findsOneWidget);
    expect(find.text('每週${weekdayLabel(first.weekday)}'), findsWidgets);
  });

  testWidgets('新增一個聚會並儲存：寫入清單、ids 只增不減', (tester) async {
    final repo = await _pump(tester);
    await tester.tap(find.text('新增聚會'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '簡稱'), '禱告');
    await tester.enterText(find.widgetWithText(TextFormField, '完整名稱'), '週三禱告會');
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('星期三').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();
    expect(find.text('禱告｜週三禱告會'), findsOneWidget);

    await tester.tap(find.byTooltip('儲存'));
    await tester.pumpAndSettle();
    final saved = repo.document!.services!;
    expect(saved.length, deployed.services.length + 1);
    final prayer = saved.last;
    expect(prayer.label, '禱告');
    expect(prayer.weekday, 3);
    expect(
      RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(prayer.id),
      isTrue,
    );
    expect(repo.document!.ids, containsAll(deployed.services.map((s) => s.id)));
    expect(find.byType(ServiceSettingsScreen), findsNothing, reason: '存好回上一頁');
  });

  testWidgets('簡稱不能跟別的聚會重複', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('新增聚會'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '簡稱'),
      deployed.services.first.label,
    );
    await tester.enterText(find.widgetWithText(TextFormField, '完整名稱'), '另一個');
    await tester.tap(find.text('確定'));
    await tester.pumpAndSettle();
    expect(find.text('已經有同樣簡稱的聚會'), findsOneWidget);
  });

  testWidgets('全部停用就不能存', (tester) async {
    final repo = await _pump(tester);
    for (final _ in deployed.services) {
      await tester.tap(
        find.byWidgetPredicate((w) => w is Switch && w.value).first,
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('儲存'));
    await tester.pumpAndSettle();
    expect(find.text('至少要有一個聚會是開啟的。'), findsOneWidget);
    expect(repo.saves, 0);
  });

  testWidgets('改了沒存就離開會先問', (tester) async {
    final repo = await _pump(tester);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('還沒儲存'), findsOneWidget);
    await tester.tap(find.text('不儲存，離開'));
    await tester.pumpAndSettle();
    expect(find.byType(ServiceSettingsScreen), findsNothing);
    expect(repo.saves, 0);
  });
}
