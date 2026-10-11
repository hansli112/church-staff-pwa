import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'package:martha/domain/models.dart';
import 'package:martha/state/app_update.dart';
import 'package:martha/state/providers.dart';

import '../state/app_update_test.dart' show Updates;
import '../support/harness.dart';
import '../support/seed.dart';

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

class _PhotoPicker extends ImagePickerPlatform {
  _PhotoPicker({this.pending});
  final Future<List<XFile>>? pending;

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) =>
      pending ??
      Future.value([
        XFile.fromData(Uint8List.fromList([1, 2, 3]), mimeType: 'image/jpeg', name: 'roster.jpg'),
      ]);
}

void main() {
  testWidgets('a pending photo picker blocks update reload even after leaving import', (tester) async {
    final selection = Completer<List<XFile>>();
    final oldPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _PhotoPicker(pending: selection.future);
    addTearDown(() {
      ImagePickerPlatform.instance = oldPicker;
      if (!selection.isCompleted) selection.complete([]);
    });
    final updates = Updates();
    await pumpApp(tester, seededChurch(as: editor), overrides: [appUpdateGatewayProvider.overrideWithValue(updates)]);
    await go(tester, '/rosters/import/sunday');
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    await tapText(tester, '選照片');
    await go(tester, '/rosters');
    await go(tester, '/me');
    final action = container.read(appUpdateProvider.notifier);
    await action.check();
    await expectLater(
      action.apply(),
      throwsA(isA<UpdateRejected>().having((e) => e.reason, 'reason', UpdateRejection.editing)),
    );
    expect(updates.reloads, 0);
    selection.complete([]);
    await settle(tester);
    await action.apply();
    expect(updates.reloads, 1);
  });

  testWidgets('a photo picker result from a previous church cannot be recognized in the new church', (tester) async {
    final selection = Completer<List<XFile>>();
    final oldPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _PhotoPicker(pending: selection.future);
    addTearDown(() => ImagePickerPlatform.instance = oldPicker);
    final b = seededChurch(as: editor);
    b.addChurch('另一間教會', id: 'other');
    b.setServices('other', const [sundayService]);
    b.addMember('other', editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '選照片');
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    container.read(selectedChurchProvider.notifier).select('other');
    await settle(tester);
    selection.complete([
      XFile.fromData(Uint8List.fromList([1, 2, 3]), mimeType: 'image/jpeg'),
    ]);
    await settle(tester);
    expect(find.text('確認後套用'), findsNothing);
    expect(b.photosUsed['grace'] ?? 0, 0);
    expect(b.photosUsed['other'] ?? 0, 0);
  });

  testWidgets('offline, recognizing a photo says the app is read-only', (tester) async {
    final oldPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _PhotoPicker();
    addTearDown(() => ImagePickerPlatform.instance = oldPicker);
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    b.setOnline(false);
    await tapText(tester, '選照片');
    expect(find.text('目前無法連線，只能查看已取得的資料。'), findsOneWidget);
    expect(b.photosUsed['grace'] ?? 0, 0);
  });

  testWidgets('photo recognition opens the same editable canonical preview as pasted JSON', (tester) async {
    final oldPicker = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _PhotoPicker();
    addTearDown(() => ImagePickerPlatform.instance = oldPicker);
    final b = seededChurch(as: editor);
    b.recognized = [
      {
        'date': '2026-10-18',
        'duties': [
          {
            'role': '司琴',
            'people': ['李美玉'],
          },
        ],
        'events': [
          {'name': '聖餐', 'color': 5},
        ],
      },
    ];
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '選照片');
    expect(find.text('確認後套用'), findsOneWidget);
    await tester.ensureVisible(find.text('聖餐').first);
    await tester.tap(find.text('聖餐').first);
    await settle(tester);
    await tester.enterText(find.byType(TextField), '浸禮');
    await tapText(tester, '完成');
    await tapText(tester, '套用到服事表');
    expect(savedDay(b, 18).events, [const EventTag(name: '浸禮', color: 5)]);
    expect(b.photosUsed['grace'], 1);
  });

  testWidgets('pasted JSON needs candidate confirmation or explicit guest before applying', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '進階');
    await tapText(tester, '貼上 JSON');
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {
          'date': '2026-10-18',
          'duties': [
            {
              'role': '司琴',
              'people': ['美玉'],
            },
            {
              'role': '招待',
              'people': ['陳志明'],
            },
          ],
        },
      ]),
    );
    await tester.ensureVisible(find.text('預覽').last);
    await tapText(tester, '預覽');
    final apply = find.widgetWithText(FilledButton, '套用到服事表');
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    await tester.tap(find.text('美玉').first);
    await settle(tester);
    await tapText(tester, '李美玉');
    await tester.tap(find.text('陳志明').first);
    await settle(tester);
    await tapText(tester, '保留「陳志明」為外請');
    await tapText(tester, '套用到服事表');
    expect(peopleOn(b, 18, '司琴'), ['李美玉']);
    expect(peopleOn(b, 18, '招待'), ['陳志明']);
    expect(savedDay(b, 18).duties.firstWhere((d) => d.role == '司琴').uids, {'李美玉': 'mei'});
    expect(savedDay(b, 18).duties.firstWhere((d) => d.role == '招待').uids, isEmpty);
  });

  testWidgets('large text import preview keeps dates readable without horizontal overflow', (tester) async {
    await pumpApp(tester, seededChurch(as: editor), textScale: 3);
    await go(tester, '/rosters/import/sunday');
    await tester.ensureVisible(find.text('進階').last);
    await tapText(tester, '進階');
    await tester.ensureVisible(find.text('貼上 JSON').last);
    await tapText(tester, '貼上 JSON');
    await tester.scrollUntilVisible(find.byType(TextField), 300, scrollable: find.byType(Scrollable).first);
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {'date': '2026-10-18', 'duties': []},
      ]),
    );
    await tester.ensureVisible(find.text('預覽').last);
    await tapText(tester, '預覽');
    await tester.scrollUntilVisible(find.text('日期'), 200);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an exact member name can deliberately remain a guest without receiving a UID', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '進階');
    await tapText(tester, '貼上 JSON');
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {
          'date': '2026-10-18',
          'duties': [
            {
              'role': '司琴',
              'people': ['李美玉'],
            },
          ],
        },
      ]),
    );
    await tester.ensureVisible(find.text('預覽').last);
    await tapText(tester, '預覽');
    await tester.tap(find.text('李美玉').first);
    await settle(tester);
    await tapText(tester, '保留「李美玉」為外請');
    await tapText(tester, '套用到服事表');
    expect(savedDay(b, 18).duties.firstWhere((d) => d.role == '司琴').uids, isEmpty);
  });

  testWidgets('the shared preview edits date, duty, people and event color before applying', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '進階');
    await tapText(tester, '貼上 JSON');
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {
          'date': '2026-10-18',
          'duties': [
            {
              'role': '司琴',
              'people': ['李美玉'],
            },
          ],
          'events': [
            {'name': '聖餐', 'color': 0},
          ],
        },
      ]),
    );
    await tester.ensureVisible(find.text('預覽').last);
    await tapText(tester, '預覽');
    await tapText(tester, '日期');
    await tester.enterText(find.byType(TextField), '2026-10-25');
    await tapText(tester, '完成');
    await tapText(tester, '司琴');
    await tester.enterText(find.byType(TextField).at(0), '招待');
    await tester.enterText(find.byType(TextField).at(1), '陳志豪');
    await tapText(tester, '完成');
    await tester.ensureVisible(find.text('聖餐').first);
    await tester.tap(find.text('聖餐').first);
    await settle(tester);
    await tester.enterText(find.byType(TextField), '浸禮');
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await settle(tester);
    await tapText(tester, '紫');
    await tapText(tester, '完成');
    await tapText(tester, '套用到服事表');
    expect(peopleOn(b, 25, '招待'), ['陳志豪']);
    expect(savedDay(b, 25).events, [const EventTag(name: '浸禮', color: 5)]);
    expect(b.rosters['grace']!.keys.any((id) => id.startsWith('2026-10-18_')), isFalse);
  });

  testWidgets('replacement explicitly previews removed arrangements and can be undone', (tester) async {
    final b = seededChurch(as: editor);
    final before = savedDay(b, 11).copyWith(events: const [EventTag(name: '聖餐', color: 0)]);
    b.rosters['grace']![before.id] = before;
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '進階');
    await tapText(tester, '貼上 JSON');
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {
          'date': '2026-10-11',
          'duties': [
            {
              'role': '司琴',
              'people': ['李美玉'],
            },
          ],
        },
      ]),
    );
    await tester.ensureVisible(find.text('預覽').last);
    await tapText(tester, '預覽');
    await tapText(tester, '取代當天全部安排');
    await tester.scrollUntilVisible(find.text('移除司會：王牧師'), 200);
    expect(find.text('移除司會：王牧師'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('移除活動：聖餐'), 200);
    expect(find.text('移除活動：聖餐'), findsOneWidget);
    await tapText(tester, '套用到服事表');
    expect(savedDay(b, 11).duties.map((d) => d.role), ['司琴']);
    expect(savedDay(b, 11).events, isEmpty);
    await tapText(tester, '復原');
    expect(savedDay(b, 11), before);
  });

  testWidgets('an admin can repair missing duty, member qualification and common event in preview', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '進階');
    await tapText(tester, '貼上 JSON');
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {
          'date': '2026-10-18',
          'duties': [
            {
              'role': '鼓',
              'people': ['陳志豪'],
            },
          ],
          'events': [
            {'name': '浸禮', 'color': 2},
          ],
        },
      ]),
    );
    await tester.ensureVisible(find.text('預覽').last);
    await tapText(tester, '預覽');
    await tester.scrollUntilVisible(find.text('加入服事設定：鼓'), 200);
    await tapText(tester, '加入服事設定：鼓');
    await tester.scrollUntilVisible(find.text('讓陳志豪負責鼓'), 200);
    await tapText(tester, '讓陳志豪負責鼓');
    await tester.scrollUntilVisible(find.text('加入常用活動：浸禮'), 200);
    await tapText(tester, '加入常用活動：浸禮');
    expect(b.services['grace']!.byId('sunday')!.duties, contains('鼓'));
    expect(b.members['grace']!['hao']!.serves('sunday', '鼓'), isTrue);
    expect(b.services['grace']!.byId('sunday')!.events, contains(const EventTag(name: '浸禮', color: 2)));
    expect(
      b.rosters['grace']!.keys.any((id) => id.startsWith('2026-10-18_')),
      isFalse,
      reason: 'repair does not apply the import',
    );
  });

  testWidgets('invalid rows block the entire import with an actionable error and editable JSON', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '進階');
    await tapText(tester, '貼上 JSON');
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {
          'date': '2026-10-18',
          'duties': [
            {
              'role': '司琴',
              'people': ['李美玉'],
            },
          ],
        },
        {
          'date': '2026-10-25',
          'duties': [],
          'events': ['聖餐'],
        },
      ]),
    );
    await tester.ensureVisible(find.text('預覽').last);
    await tapText(tester, '預覽');
    expect(find.text('請修正資料後再匯入'), findsOneWidget);
    expect(find.textContaining('活動請填'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '套用到服事表')).onPressed, isNull);
    await tester.tap(find.byTooltip('編輯 JSON'));
    await settle(tester);
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {
          'date': '2026-10-18',
          'duties': [
            {
              'role': '司琴',
              'people': ['李美玉'],
            },
          ],
        },
        {
          'date': '2026-10-25',
          'duties': [],
          'events': [
            {'name': '聖餐', 'color': 0},
          ],
        },
      ]),
    );
    await tapText(tester, '完成');
    await tapText(tester, '套用到服事表');
    expect(peopleOn(b, 18, '司琴'), ['李美玉']);
    expect(savedDay(b, 25).events, [const EventTag(name: '聖餐', color: 0)]);
  });

  testWidgets('ordinary editors can import one-day gaps without acquiring settings repair actions', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '進階');
    await tapText(tester, '貼上 JSON');
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {
          'date': '2026-10-18',
          'duties': [
            {
              'role': '鼓',
              'people': ['陳志豪'],
            },
          ],
          'events': [
            {'name': '浸禮', 'color': 2},
          ],
        },
      ]),
    );
    await tester.ensureVisible(find.text('預覽').last);
    await tapText(tester, '預覽');
    expect(find.text('加入服事設定：鼓'), findsNothing);
    expect(find.text('讓陳志豪負責鼓'), findsNothing);
    expect(find.text('加入常用活動：浸禮'), findsNothing);
    await tapText(tester, '套用到服事表');
    expect(peopleOn(b, 18, '鼓'), ['陳志豪']);
    expect(b.services['grace']!.byId('sunday')!.duties, isNot(contains('鼓')));
    expect(b.members['grace']!['hao']!.serves('sunday', '鼓'), isFalse);
    expect(b.services['grace']!.byId('sunday')!.events, isNot(contains(const EventTag(name: '浸禮', color: 2))));
  });

  testWidgets('switching churches clears the old import preview instead of applying it to a new church', (
    tester,
  ) async {
    final b = seededChurch(as: editor);
    b.addChurch('另一間教會', id: 'other');
    b.setServices('other', const [sundayService]);
    b.addMember('other', editor);
    b.addMember('other', staffMei);
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '進階');
    await tapText(tester, '貼上 JSON');
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {
          'date': '2026-10-18',
          'duties': [
            {
              'role': '司琴',
              'people': ['李美玉'],
            },
          ],
        },
      ]),
    );
    await tester.ensureVisible(find.text('預覽').last);
    await tapText(tester, '預覽');
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    container.read(selectedChurchProvider.notifier).select('other');
    await settle(tester);
    expect(find.text('確認後套用'), findsNothing);
    expect(find.text('套用到服事表'), findsNothing);
    expect(b.rosters['other'], isEmpty);
  });

  testWidgets('apply refuses a changed roster until its new difference has been shown', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '進階');
    await tapText(tester, '貼上 JSON');
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {
          'date': '2026-10-11',
          'duties': [
            {
              'role': '司琴',
              'people': ['李美玉'],
            },
          ],
        },
      ]),
    );
    await tester.ensureVisible(find.text('預覽').last);
    await tapText(tester, '預覽');
    final day = savedDay(b, 11);
    b.rosters['grace']![day.id] = day.copyWith(
      duties: [
        for (final duty in day.duties)
          duty.role == '司琴' ? const Duty(role: '司琴', people: ['陳志豪'], uids: {'陳志豪': 'hao'}) : duty,
      ],
    );
    b.notify();
    // Deliver the backend stream, without drawing a newer preview frame.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tapText(tester, '套用到服事表');
    expect(peopleOn(b, 11, '司琴'), ['陳志豪']);
    expect(find.text('服事表已變更，請重新檢查差異後再套用'), findsOneWidget);
    expect(find.text('確認後套用'), findsOneWidget);
  });

  testWidgets('an edit made while reviewing the preview survives the import', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '進階');
    await tapText(tester, '貼上 JSON');
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        {
          'date': '2026-10-11',
          'duties': [
            {
              'role': '司琴',
              'people': ['李美玉'],
            },
          ],
        },
      ]),
    );
    await tester.ensureVisible(find.text('預覽').last);
    await tapText(tester, '預覽');
    // Meanwhile someone else sets 招待 on that day.
    final day = savedDay(b, 11);
    b.rosters['grace']![day.id] = day.copyWith(
      duties: [
        for (final d in day.duties) d.role == '招待' ? const Duty(role: '招待', people: ['陳志豪']) : d,
      ],
    );
    b.notify();
    await settle(tester);
    await tester.scrollUntilVisible(find.text('套用到服事表'), 300);
    await tapText(tester, '套用到服事表');
    expect(peopleOn(b, 11, '司琴'), ['李美玉']);
    expect(peopleOn(b, 11, '招待'), ['陳志豪']);
  });

  testWidgets('used-up photos say when they come back', (tester) async {
    final b = seededChurch();
    b.photosUsed['grace'] = 30;
    await pumpApp(tester, b);
    await go(tester, '/rosters/import/sunday');
    expect(find.textContaining('這個月的 30 張用完了'), findsOneWidget);
    expect(find.textContaining('直接安排服事表'), findsOneWidget);
    final take = tester.widget<FilledButton>(find.byType(FilledButton).first);
    expect(take.onPressed, isNull);
  });

  testWidgets('an authorized roster editor can paste the documented JSON under advanced controls', (tester) async {
    await pumpApp(tester, seededChurch(as: editor));
    await go(tester, '/rosters/import/sunday');
    await tapText(tester, '進階');
    await tapText(tester, '貼上 JSON');
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('color'), findsWidgets);
  });

  testWidgets('staff do not see photo import', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/rosters');
    expect(find.byTooltip('照片匯入'), findsNothing);
  });
}
