import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/design/components.dart' show SecondaryButton;
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/rosters/roster_note.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../support/harness.dart';
import '../support/seed.dart';

// 備註 of a day's roster: text and files, written by whoever arranges any
// of the day, read by everyone.

const _id = '2026-10-11_sunday';
const worship = Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]);

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

PickedNoteFile pdf(String name, [int bytes = 10]) => (name: name, type: 'application/pdf', bytes: Uint8List(bytes));

/// The picker gives [next] when asked, then nothing.
List<PickedNoteFile> next = [];
final picker = notePickerProvider.overrideWithValue(() async {
  final out = next;
  next = [];
  return out;
});

void main() {
  setUp(() => next = []);

  testWidgets('who arranges the day writes a note with files; everyone sees it, links and files open', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b, overrides: [picker]);
    await go(tester, '/rosters/sunday/2026-10-11');

    await tapText(tester, '新增備註');
    await tester.enterText(find.byType(TextField), '歌單：奇異恩典\n和弦譜：https://drive.google.com/x');
    next = [pdf('恩典夠我用.pdf'), (name: '練唱.m4a', type: 'audio/mp4', bytes: Uint8List(5))];
    await tapText(tester, '加入檔案');
    expect(find.text('恩典夠我用.pdf'), findsOneWidget);
    expect(find.text('練唱.m4a'), findsOneWidget);
    expect(find.text('最多 5 個檔案，每個 20 MB 以內\n服事過後 30 天自動刪除'), findsOneWidget);
    await tapText(tester, '完成');

    final note = b.rosterNotes['grace']![_id]!;
    expect(note.text, '歌單：奇異恩典\n和弦譜：https://drive.google.com/x');
    expect([for (final f in note.files) f.name], ['恩典夠我用.pdf', '練唱.m4a']);
    expect(find.text('備註'), findsOneWidget, reason: 'its header at the bottom');
    expect(find.textContaining('drive.google.com/x'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText(includeSemanticsLabels: false).contains('和弦譜：drive.google.com/x'),
      ),
      findsOneWidget,
      reason: 'a link shows without its https://',
    );

    // 李美玉 only looks: she sees it, without a way to change it.
    final launched = captureLaunches();
    b.auth.signInAs('mei@example.com', uid: staffMei.uid, name: staffMei.name);
    await pumpApp(tester, b, overrides: [picker]);
    await go(tester, '/rosters/sunday/2026-10-11');
    expect(find.text('恩典夠我用.pdf'), findsOneWidget);
    await tapText(tester, '恩典夠我用.pdf');
    expect(launched.opened, isEmpty, reason: 'memory files have no web address; real ones open out of the app');
    await tester.tap(find.byType(RosterNoteSection));
    await settle(tester);
    expect(find.text('加入檔案'), findsNothing, reason: 'she cannot change it');

    // On the list, the day says it has a note.
    await go(tester, '/rosters');
    expect(find.byIcon(Symbols.sticky_note_2_rounded), findsOneWidget);
  });

  testWidgets('with no note, only who arranges sees 新增備註', (tester) async {
    await pumpApp(tester, seededChurch(as: staffMei));
    await go(tester, '/rosters/sunday/2026-10-11');
    expect(find.text('新增備註'), findsNothing);
    expect(find.text('備註'), findsNothing);
  });

  testWidgets("a 事工's 負責人 writes the note of a day they arrange some of", (tester) async {
    final b = seededChurch(
      extra: [
        staffMei.withIdentities(const [MinistryLead('worship')]),
      ],
      as: staffMei,
    );
    b.ministries['grace'] = const MinistrySettings(ministries: [worship], ids: ['worship']);
    await pumpApp(tester, b, overrides: [picker]);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '新增備註');
    await tester.enterText(find.byType(TextField), '7:30 到');
    await tapText(tester, '完成');
    expect(b.rosterNotes['grace']![_id]!.text, '7:30 到');
  });

  testWidgets('a file is taken off with its ×; emptied, the note goes', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b, overrides: [picker]);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '新增備註');
    next = [pdf('a.pdf')];
    await tapText(tester, '加入檔案');
    await tapText(tester, '完成');
    expect(b.rosterNotes['grace']![_id]!.files, hasLength(1));

    // A file opens; the rest of the note opens it to change.
    await tester.tap(
      find.descendant(of: find.byType(RosterNoteSection), matching: find.byIcon(Symbols.chevron_right_rounded)),
    );
    await settle(tester);
    expect(find.text('加入檔案'), findsOneWidget, reason: 'the sheet is open');
    await tester.tap(find.descendant(of: find.byType(NoteSheet), matching: find.byIcon(Symbols.close_rounded)));
    await settle(tester);
    expect(find.descendant(of: find.byType(NoteSheet), matching: find.text('a.pdf')), findsNothing);
    await tapText(tester, '完成');
    expect(b.rosterNotes['grace']![_id], isNull);
    expect(find.text('新增備註'), findsOneWidget);
  });

  testWidgets('at most 5 files, none over 20 MB; 加入檔案 goes at 5', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b, overrides: [picker]);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '新增備註');
    next = [pdf('big.pdf', 20971521)];
    await tapText(tester, '加入檔案');
    expect(find.text('「big.pdf」超過 20 MB'), findsOneWidget);
    expect(find.text('big.pdf'), findsNothing);
    next = [(name: 'video.mov', type: 'video/quicktime', bytes: null)];
    await tapText(tester, '加入檔案');
    expect(find.text('「video.mov」超過 20 MB'), findsOneWidget, reason: 'too big to read: the picker gives no bytes');

    next = [for (var i = 1; i <= 6; i++) pdf('$i.pdf')];
    await tapText(tester, '加入檔案');
    expect(find.text('最多 5 個檔案'), findsOneWidget);
    expect(find.text('5.pdf'), findsOneWidget);
    expect(find.text('6.pdf'), findsNothing);
    expect(find.text('加入檔案'), findsNothing);
  });

  testWidgets('any kind of file goes on it: a Word file shows as a document', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b, overrides: [picker]);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '新增備註');
    const docx = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    next = [(name: '流程.docx', type: docx, bytes: Uint8List(4))];
    await tapText(tester, '加入檔案');
    await tapText(tester, '完成');
    expect(b.rosterNotes['grace']![_id]!.files.single.type, docx);
    expect(find.byIcon(Symbols.description_rounded), findsOneWidget);
  });

  testWidgets('closed without 完成, files picked are taken back', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b, overrides: [picker]);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '新增備註');
    next = [pdf('a.pdf')];
    await tapText(tester, '加入檔案');
    expect(b.noteUploads['grace'], hasLength(1));
    await tapText(tester, '取消');
    await tapText(tester, '放棄變更');
    expect(b.noteUploads['grace'], isEmpty);
    expect(b.rosterNotes['grace']?[_id], isNull);
  });

  testWidgets('a past day shows its note but nobody changes it', (tester) async {
    final b = seededChurch(as: editor);
    b.rosterNotes['grace'] = {'2026-09-27_sunday': const RosterNote(text: '上週的備註')};
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-09-27');
    expect(find.text('上週的備註'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(RosterNoteSection), matching: find.byIcon(Symbols.chevron_right_rounded)),
      findsNothing,
    );
  });

  testWidgets('a link in it opens out of the app, without the 。 after it', (tester) async {
    final b = seededChurch(as: staffMei);
    b.rosterNotes['grace'] = {_id: const RosterNote(text: '和弦譜：https://drive.google.com/x。')};
    final launched = captureLaunches();
    await pumpApp(tester, b);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tester.tapOnText(find.textRange.ofSubstring('drive.google.com/x'));
    await settle(tester);
    expect(launched.opened, ['https://drive.google.com/x']);
  });

  testWidgets('a picture shows as a picture, not by its name', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b, overrides: [picker]);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '新增備註');
    next = [(name: '座位圖.png', type: 'image/png', bytes: Uint8List(4))];
    await tapText(tester, '加入檔案');
    await tapText(tester, '完成');
    expect(b.rosterNotes['grace']![_id]!.files.single.isImage, isTrue);
    final section = find.byType(RosterNoteSection);
    expect(find.descendant(of: section, matching: find.text('座位圖.png')), findsNothing);
    expect(find.descendant(of: section, matching: find.bySemanticsLabel('座位圖.png')), findsOneWidget);
  });

  testWidgets('a file that does not go up is left off, and it says so', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b, overrides: [picker]);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '新增備註');
    b.failNextWrite = Exception('offline');
    next = [pdf('a.pdf')];
    await tapText(tester, '加入檔案');
    expect(find.text('「a.pdf」沒有上傳成功'), findsOneWidget);
    expect(find.descendant(of: find.byType(NoteSheet), matching: find.text('a.pdf')), findsNothing);
    expect(b.noteUploads['grace'] ?? const {}, isEmpty);
  });

  testWidgets('完成 waits for the files still going up', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b, overrides: [picker]);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '新增備註');
    b.writeDelay = const Duration(seconds: 2);
    next = [pdf('a.pdf')];
    await tester.tap(find.text('加入檔案'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('a.pdf'), findsOneWidget, reason: 'on the sheet while it goes up');
    SecondaryButton done() => tester.widget(find.widgetWithText(SecondaryButton, '完成'));
    expect(done().onPressed, isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(done().onPressed, isNotNull, reason: 'up');
    b.writeDelay = Duration.zero;
    await tapText(tester, '完成');
    expect([for (final f in b.rosterNotes['grace']![_id]!.files) f.name], ['a.pdf']);
  });

  testWidgets('closed while a file goes up, it is taken back once up', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b, overrides: [picker]);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '新增備註');
    b.writeDelay = const Duration(seconds: 2);
    next = [pdf('a.pdf')];
    await tester.tap(find.text('加入檔案'));
    await tester.pump(const Duration(milliseconds: 500));
    await tapText(tester, '取消');
    await tapText(tester, '放棄變更');
    expect(find.byType(NoteSheet), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await settle(tester);
    expect(b.noteUploads['grace'] ?? const {}, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a file taken off before 完成 is taken back at once', (tester) async {
    final b = seededChurch(as: editor);
    await pumpApp(tester, b, overrides: [picker]);
    await go(tester, '/rosters/sunday/2026-10-11');
    await tapText(tester, '新增備註');
    next = [pdf('a.pdf')];
    await tapText(tester, '加入檔案');
    expect(b.noteUploads['grace'], hasLength(1));
    await tester.tap(find.descendant(of: find.byType(NoteSheet), matching: find.byIcon(Symbols.close_rounded)));
    await settle(tester);
    expect(b.noteUploads['grace'], isEmpty);
  });

  group("an event's roster", () {
    Roster party({required Day day}) => Roster(
      type: '',
      day: day,
      duties: const [
        Duty(role: '主持', people: ['李美玉'], uids: {'李美玉': 'mei'}),
      ],
      forEvent: RosterEvent(eventId: 'xmas', title: '聖誕晚會', lastDay: day),
    );

    testWidgets('who arranges it writes its note once it is saved', (tester) async {
      final b = seededChurch(extra: const [office], as: office);
      b.rosters['grace']!['ev_xmas'] = party(day: Day(2026, 10, 9));
      await pumpApp(tester, b, overrides: [picker]);
      await go(tester, '/rosters/event/xmas');
      await tapText(tester, '新增備註');
      await tester.enterText(find.descendant(of: find.byType(NoteSheet), matching: find.byType(TextField)), '6:00 彩排');
      await tapText(tester, '完成');
      expect(b.rosterNotes['grace']!['ev_xmas']!.text, '6:00 彩排');
      expect(find.text('6:00 彩排'), findsOneWidget);
    });

    testWidgets('not while it is a draft nobody saved', (tester) async {
      final b = seededChurch(extra: const [office], as: office);
      b.connectCalendar('grace', calendarName: '教會行事曆');
      b.calendarEvents['grace'] = [
        CalendarEvent(id: 'xmas', title: '聖誕晚會', start: DateTime(2026, 10, 9, 19), end: DateTime(2026, 10, 9, 21)),
      ];
      await pumpApp(tester, b);
      await go(tester, '/calendar');
      await tapText(tester, '聖誕晚會');
      await tapText(tester, '安排服事');
      expect(find.text('沿用其他活動'), findsOneWidget, reason: 'on its roster');
      expect(find.text('新增備註'), findsNothing);
    });
  });
}
