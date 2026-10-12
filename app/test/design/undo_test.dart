import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/core/zh_tw_localizations.dart';
import 'package:martha/l10n/app_localizations.dart';

void main() {
  testWidgets('復原寫入失敗會顯示結果，不把按下復原當成成功', (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: const [
          L10n.delegate,
          ...zhTwLocalizationsDelegates,
        ],
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showToast(context, '已修改', onUndo: () => pending.future),
              child: const Text('修改'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('復原'));
    await tester.pump();
    pending.completeError(StateError('write refused'));
    await tester.pumpAndSettle();
    expect(find.text('復原失敗，請再試一次'), findsOneWidget);
  });

  testWidgets('復原寫入完成才顯示已復原', (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'TW'),
        localizationsDelegates: const [
          L10n.delegate,
          ...zhTwLocalizationsDelegates,
        ],
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showToast(context, '已修改', onUndo: () => pending.future),
              child: const Text('修改'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('復原'));
    await tester.pump();
    expect(find.text('已復原'), findsNothing);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('已復原'), findsOneWidget);
  });
}
