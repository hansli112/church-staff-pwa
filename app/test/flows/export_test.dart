import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/telemetry.dart';
import 'package:martha/state/export.dart';
import 'package:martha/state/session.dart';

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

class _Saver implements FileSaver {
  _Saver({this.saves = true});

  /// False: the share sheet is closed without saving.
  final bool saves;
  final files = <(String, Uint8List, String)>[];

  @override
  Future<bool> save(String name, Uint8List bytes, String mimeType) async {
    files.add((name, bytes, mimeType));
    return saves;
  }
}

class _Events extends NoTelemetry {
  final events = <(String, Map<String, Object>?)>[];

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) => events.add((name, parameters));
}

void main() {
  testWidgets('an admin exports the church into a zip', (tester) async {
    final saver = _Saver();
    final telemetry = _Events();
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [fileSaverProvider.overrideWithValue(saver), telemetryProvider.overrideWithValue(telemetry)],
    );
    await go(tester, '/me/church');
    await tester.scrollUntilVisible(find.text('匯出資料'), 200);
    await tapText(tester, '匯出資料');

    final (name, bytes, mime) = saver.files.single;
    expect(name, startsWith('martha-恩典堂-'));
    expect(mime, 'application/zip');
    final zip = ZipDecoder().decodeBytes(bytes);
    final json = jsonDecode(utf8.decode(zip.findFile('martha-export.json')!.content)) as Map<String, dynamic>;
    expect(json['church']['id'], 'grace');
    expect((json['members'] as List).length, 5);
    expect((json['rosters'] as List).length, 2);
    expect(utf8.decode(zip.findFile('服事表.csv')!.content), contains('2026-10-04,主日崇拜,招待,陳志豪、李美玉'));
    expect(telemetry.events.where((e) => e.$1 == 'church_export'), [('church_export', null)]);
    expect(find.text('已匯出'), findsOneWidget);
  });

  testWidgets('closing the share sheet without saving is not an export', (tester) async {
    final telemetry = _Events();
    await pumpApp(
      tester,
      seededChurch(),
      overrides: [
        fileSaverProvider.overrideWithValue(_Saver(saves: false)),
        telemetryProvider.overrideWithValue(telemetry),
      ],
    );
    await go(tester, '/me/church');
    await tester.scrollUntilVisible(find.text('匯出資料'), 200);
    await tapText(tester, '匯出資料');

    expect(find.text('已匯出'), findsNothing);
    expect(telemetry.events, isEmpty);
  });

  testWidgets('only admins can export', (tester) async {
    await pumpApp(tester, seededChurch(as: editor));
    await go(tester, '/me/church');
    expect(find.text('匯出資料'), findsNothing);
  });
}
