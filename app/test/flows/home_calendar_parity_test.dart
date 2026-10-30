import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

class CountingCalendarBackend extends MemoryBackend {
  CountingCalendarBackend({super.clock});

  final reads = <String>[];

  @override
  ChurchData church(String churchId) => CountingCalendarData(this, churchId);
}

class CountingCalendarData extends MemoryChurchData {
  CountingCalendarData(this.backend, String churchId) : super(backend, churchId);

  final CountingCalendarBackend backend;

  @override
  CalendarData get calendar => _calendar;
  late final _calendar = _CountingCalendar(backend, this);
}

class _CountingCalendar extends MemoryCalendarData {
  _CountingCalendar(this.backend, super.church);

  final CountingCalendarBackend backend;

  @override
  Future<List<CalendarEvent>> events(String month) {
    backend.reads.add(month);
    return super.events(month);
  }
}

void main() {
  testWidgets('home shows only three unfinished activities across the month boundary using existing calendar state', (
    tester,
  ) async {
    final b = CountingCalendarBackend(clock: () => DateTime.utc(2026, 10, 31, 1));
    b.addChurch('恩典堂', id: 'grace');
    b.setServices('grace', const [sundayService]);
    b.addMember('grace', pastor);
    b.addMember('grace', staffMei);
    b.auth.signInAs('mei@example.com', uid: staffMei.uid);
    b.users[staffMei.uid] = const UserProfile(uid: 'mei', name: '李美玉');
    b.connectCalendar('grace', calendarName: '教會行事曆');
    b.calendarEvents['grace'] = [
      CalendarEvent(id: 'finished', title: '已結束的早禱', start: DateTime(2026, 10, 31, 6), end: DateTime(2026, 10, 31, 7)),
      CalendarEvent(
        id: 'retreat',
        title: '同工退修會',
        start: DateTime(2026, 10, 30),
        end: DateTime(2026, 11, 2),
        allDay: true,
      ),
      CalendarEvent(id: 'prayer', title: '月底禱告', start: DateTime(2026, 10, 31, 19), end: DateTime(2026, 10, 31, 21)),
      CalendarEvent(id: 'meeting', title: '同工會', start: DateTime(2026, 11, 1, 19), end: DateTime(2026, 11, 1, 20)),
      CalendarEvent(id: 'fourth', title: '第四個活動', start: DateTime(2026, 11, 2, 19), end: DateTime(2026, 11, 2, 20)),
    ];
    await pumpApp(tester, b);
    expect(find.text('近期活動'), findsOneWidget);
    expect(find.text('同工退修會'), findsOneWidget, reason: 'an ongoing multi-day event appears only once');
    expect(find.text('月底禱告'), findsOneWidget);
    expect(find.text('同工會'), findsOneWidget);
    expect(find.text('已結束的早禱'), findsNothing);
    expect(find.text('第四個活動'), findsNothing);
    expect(b.reads, ['2026-10', '2026-11']);

    await tester.ensureVisible(find.text('同工會'));
    await tester.tap(find.text('同工會'));
    await settle(tester);
    expect(find.text('同工會'), findsNWidgets(2), reason: 'the home entry opens the same read-only event details');
    expect(find.text('編輯活動'), findsNothing, reason: 'home does not grant calendar edit permission');
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/calendar');
    await settle(tester);
    expect(
      b.reads,
      ['2026-10', '2026-11', '2026-09'],
      reason: 'the calendar tab reuses the months home read, and reads only the month before ahead',
    );
  });
}
