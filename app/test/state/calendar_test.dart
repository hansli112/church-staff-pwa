import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/calendar.dart';
import 'package:martha/state/providers.dart';

import '../support/harness.dart';
import '../support/seed.dart';

/// Counts requests at the ChurchData boundary, not inside the client cache.
class CalendarBackend extends MemoryBackend {
  CalendarBackend({DateTime Function() clock = testClock}) : super(clock: clock) {
    addChurch('恩典堂', id: 'grace');
    addMember('grace', pastor);
    auth.signInAs('pastor@example.com', uid: pastor.uid);
    connectCalendar('grace', calendarName: '教會行事曆');
  }

  final reads = <(String, String)>[];
  Completer<void>? readReplyHeld;
  Object? readError;
  CalendarEvent? saveAnswer;
  Completer<void>? saveHeld;
  Completer<void>? saveReplyHeld;
  Object? saveError;
  Completer<void>? deleteHeld;
  Object? deleteError;

  @override
  ChurchData church(String churchId) => CalendarData(this, churchId);
}

class CalendarData extends MemoryChurchData {
  CalendarData(this.backend, String churchId) : super(backend, churchId);

  final CalendarBackend backend;

  @override
  Future<List<CalendarEvent>> calendarEvents(String month) async {
    backend.reads.add((churchId, month));
    final reply = backend.readReplyHeld;
    final error = backend.readError;
    final events = await super.calendarEvents(month);
    await reply?.future;
    if (error != null) throw error;
    return events;
  }

  @override
  Future<CalendarEvent> calendarSave(CalendarEvent event, {CalendarEvent? previous, String? restoreRosterOf}) async {
    final answer = backend.saveAnswer ?? event;
    final held = backend.saveHeld;
    final error = backend.saveError;
    final reply = backend.saveReplyHeld;
    await held?.future;
    if (error != null) throw error;
    final saved = await super.calendarSave(answer, previous: previous, restoreRosterOf: restoreRosterOf);
    await reply?.future;
    return saved;
  }

  @override
  Future<void> calendarDelete(CalendarEvent event) async {
    final held = backend.deleteHeld;
    final error = backend.deleteError;
    await held?.future;
    if (error != null) throw error;
    await super.calendarDelete(event);
  }
}

Future<ProviderContainer> open(CalendarBackend backend) async {
  final container = ProviderContainer(overrides: await testOverrides(backend), retry: (_, _) => null);
  addTearDown(container.dispose);
  container.listen(appStageProvider, (_, _) {});
  container.listen(meProvider, (_, _) {});
  container.listen(calendarSettingsProvider, (_, _) {});
  await pumpEventQueue();
  return container;
}

void main() {
  test('overlapping saves that commit out of order still reconcile after a church round trip', () async {
    final b = CalendarBackend();
    b.addChurch('青年教會', id: 'youth');
    b.addMember('youth', pastor);
    b.connectCalendar('youth', calendarName: '青年行事曆');
    final original = CalendarEvent(
      id: 'meeting',
      title: '原活動',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
    );
    b.calendarEvents['grace'] = [original];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    final firstGate = Completer<void>();
    b.saveHeld = firstGate;
    final firstSaved = original.copyWith(title: '先操作但後寫入');
    final first = container.read(calendarActionsProvider).save(firstSaved, previous: original);
    final secondGate = Completer<void>();
    b.saveHeld = secondGate;
    final secondSaved = original.copyWith(title: '後操作但先寫入');
    final second = container.read(calendarActionsProvider).save(secondSaved, previous: original);
    container.read(selectedChurchProvider.notifier).select('youth');
    await pumpEventQueue();
    await container.read(calendarEventsProvider('2026-10').future);
    container.read(selectedChurchProvider.notifier).select('grace');
    await pumpEventQueue();
    expect(await container.read(calendarEventsProvider('2026-10').future), [original]);
    secondGate.complete();
    await second;
    expect(await container.read(calendarEventsProvider('2026-10').future), [secondSaved]);
    firstGate.complete();
    await first;
    await container.pump();
    expect(await container.read(calendarEventsProvider('2026-10').future), [firstSaved]);
    expect(b.reads.length, 5);
  });

  for (final scenario in [
    (name: 'not connected', settings: const CalendarSettings(calendarId: 'cal-grace', calendarName: '教會行事曆'), reads: 0),
    (
      name: 'needs reconnect',
      settings: const CalendarSettings(
        connected: true,
        needsReconnect: true,
        calendarId: 'cal-grace',
        calendarName: '教會行事曆',
      ),
      reads: 0,
    ),
    (name: 'not selected', settings: const CalendarSettings(connected: true), reads: 0),
    (
      name: 'ready',
      settings: const CalendarSettings(connected: true, calendarId: 'cal-grace', calendarName: '教會行事曆'),
      reads: 1,
    ),
  ]) {
    test('calendar month reads follow readiness when ${scenario.name}', () async {
      final b = CalendarBackend();
      b.calendars['grace'] = scenario.settings;
      final container = await open(b);
      container.listen(calendarEventsProvider('2026-10'), (_, _) {});
      expect(await container.read(calendarEventsProvider('2026-10').future), isEmpty);
      expect(b.reads.length, scenario.reads);
    });
  }

  test('a delete completed after a church round trip reconciles only its original context', () async {
    final b = CalendarBackend();
    b.addChurch('青年教會', id: 'youth');
    b.addMember('youth', pastor);
    b.connectCalendar('youth', calendarName: '青年行事曆');
    final deleted = CalendarEvent(
      id: 'meeting',
      title: '恩典堂要刪的活動',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
    );
    final otherChurch = deleted.copyWith(title: '青年教會保留活動');
    b.calendarEvents['grace'] = [deleted];
    b.calendarEvents['youth'] = [otherChurch];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    expect(await container.read(calendarEventsProvider('2026-10').future), [deleted]);
    b.deleteHeld = Completer();
    final deleting = container.read(calendarActionsProvider).delete(deleted);
    container.read(selectedChurchProvider.notifier).select('youth');
    await pumpEventQueue();
    expect(await container.read(calendarEventsProvider('2026-10').future), [otherChurch]);
    container.read(selectedChurchProvider.notifier).select('grace');
    await pumpEventQueue();
    expect(await container.read(calendarEventsProvider('2026-10').future), [deleted]);
    b.deleteHeld!.complete();
    await deleting;
    await container.pump();
    expect(await container.read(calendarEventsProvider('2026-10').future), isEmpty);
    expect(b.reads, [('grace', '2026-10'), ('youth', '2026-10'), ('grace', '2026-10'), ('grace', '2026-10')]);
    container.read(selectedChurchProvider.notifier).select('youth');
    await pumpEventQueue();
    expect(await container.read(calendarEventsProvider('2026-10').future), [otherChurch]);
  });

  test('a save completed after a church round trip reconciles the new cache of its original context', () async {
    final b = CalendarBackend();
    b.addChurch('青年教會', id: 'youth');
    b.addMember('youth', pastor);
    b.connectCalendar('youth', calendarName: '青年行事曆');
    final old = CalendarEvent(
      id: 'meeting',
      title: '恩典堂原活動',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
    );
    final otherChurch = old.copyWith(title: '青年教會活動');
    b.calendarEvents['grace'] = [old];
    b.calendarEvents['youth'] = [otherChurch];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    expect(await container.read(calendarEventsProvider('2026-10').future), [old]);
    b.saveHeld = Completer();
    final saved = old.copyWith(title: '恩典堂已儲存');
    final saving = container.read(calendarActionsProvider).save(saved, previous: old);
    container.read(selectedChurchProvider.notifier).select('youth');
    await pumpEventQueue();
    expect(await container.read(calendarEventsProvider('2026-10').future), [otherChurch]);
    container.read(selectedChurchProvider.notifier).select('grace');
    await pumpEventQueue();
    expect(await container.read(calendarEventsProvider('2026-10').future), [old]);
    b.saveHeld!.complete();
    await saving;
    await container.pump();
    expect(await container.read(calendarEventsProvider('2026-10').future), [saved]);
    expect(b.reads, [('grace', '2026-10'), ('youth', '2026-10'), ('grace', '2026-10'), ('grace', '2026-10')]);
    container.read(selectedChurchProvider.notifier).select('youth');
    await pumpEventQueue();
    expect(await container.read(calendarEventsProvider('2026-10').future), [otherChurch]);
  });

  test('a refused undo rechecks read access without hiding the other events from a member', () async {
    final b = CalendarBackend();
    final calendarEditor = pastor.copyWith(role: Role.staff, groups: {Group.calendarEditors});
    b.addMember('grace', calendarEditor);
    final other = CalendarEvent(id: 'other', title: '其他活動', start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 13));
    final deleted = CalendarEvent(
      id: 'deleted',
      title: '已刪活動',
      start: DateTime(2026, 10, 20),
      end: DateTime(2026, 10, 21),
    );
    b.calendarEvents['grace'] = [other, deleted];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    final undo = await container.read(calendarActionsProvider).delete(deleted);
    b.addMember('grace', calendarEditor.copyWith(groups: {}));
    await pumpEventQueue();
    final reply = Completer<void>();
    b.readReplyHeld = reply;
    await expectLater(
      undo(),
      throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.permissionDenied)),
    );
    await container.pump();
    expect(container.read(calendarEventsProvider('2026-10')).value, [other]);
    expect(container.read(calendarEventsProvider('2026-10')).hasError, isFalse);
    reply.complete();
    expect(await container.read(calendarEventsProvider('2026-10').future), [other]);
    expect(b.reads.length, 2);
  });

  test('a member who loses edit access can still see the complete month after a refused delete', () async {
    final b = CalendarBackend();
    final calendarEditor = pastor.copyWith(role: Role.staff, groups: {Group.calendarEditors});
    b.addMember('grace', calendarEditor);
    final other = CalendarEvent(
      id: 'other',
      title: '其他活動',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
    );
    final retained = CalendarEvent(
      id: 'retained',
      title: '不能刪的活動',
      start: DateTime(2026, 10, 20),
      end: DateTime(2026, 10, 21),
    );
    b.calendarEvents['grace'] = [other, retained];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    expect(await container.read(calendarEventsProvider('2026-10').future), [other, retained]);
    b.addMember('grace', calendarEditor.copyWith(groups: {}));
    await pumpEventQueue();
    final reply = Completer<void>();
    b.readReplyHeld = reply;
    await expectLater(
      container.read(calendarActionsProvider).delete(retained),
      throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.permissionDenied)),
    );
    await container.pump();
    expect(container.read(calendarEventsProvider('2026-10')).value, [other, retained]);
    expect(container.read(calendarEventsProvider('2026-10')).hasError, isFalse);
    reply.complete();
    expect(await container.read(calendarEventsProvider('2026-10').future), [other, retained]);
    expect(b.reads.length, 2);
  });

  test('a member who loses edit access can still see the complete month after a refused create', () async {
    final b = CalendarBackend();
    final calendarEditor = pastor.copyWith(role: Role.staff, groups: {Group.calendarEditors});
    b.addMember('grace', calendarEditor);
    final existing = CalendarEvent(
      id: 'existing',
      title: '原有活動',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
    );
    final other = CalendarEvent(
      id: 'other',
      title: '其他活動',
      start: DateTime(2026, 10, 20),
      end: DateTime(2026, 10, 21),
    );
    b.calendarEvents['grace'] = [existing, other];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    expect(await container.read(calendarEventsProvider('2026-10').future), [existing, other]);
    b.addMember('grace', calendarEditor.copyWith(groups: {}));
    await pumpEventQueue();
    final reply = Completer<void>();
    b.readReplyHeld = reply;
    final draft = CalendarEvent(title: '不能新增', start: DateTime(2026, 10, 25), end: DateTime(2026, 10, 26));
    await expectLater(
      container.read(calendarActionsProvider).save(draft),
      throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.permissionDenied)),
    );
    await container.pump();
    expect(container.read(calendarEventsProvider('2026-10')).value, [existing, other]);
    expect(container.read(calendarEventsProvider('2026-10')).hasError, isFalse);
    reply.complete();
    expect(await container.read(calendarEventsProvider('2026-10').future), [existing, other]);
    expect(b.reads.length, 2, reason: 'the refused write rechecks the independent read permission');
  });

  test('a successful delete after restored edit access reconciles the other events in a refused month', () async {
    final b = CalendarBackend();
    final calendarEditor = pastor.copyWith(role: Role.staff, groups: {Group.calendarEditors});
    b.addMember('grace', calendarEditor);
    final other = CalendarEvent(
      id: 'other',
      title: '其他活動',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
    );
    final deleted = CalendarEvent(
      id: 'deleted',
      title: '要刪的活動',
      start: DateTime(2026, 10, 20),
      end: DateTime(2026, 10, 21),
    );
    b.calendarEvents['grace'] = [other, deleted];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    expect(await container.read(calendarEventsProvider('2026-10').future), [other, deleted]);
    b.addMember('grace', calendarEditor.copyWith(groups: {}));
    await pumpEventQueue();
    b.readError = const CloudException(CloudErrorCode.permissionDenied);
    await expectLater(container.read(calendarActionsProvider).delete(deleted), throwsA(isA<CloudException>()));
    await pumpEventQueue();
    expect(container.read(calendarEventsProvider('2026-10')).hasError, isTrue);
    expect(container.read(calendarEventsProvider('2026-10')).value, anyOf(isNull, isEmpty));
    b.readError = null;
    b.addMember('grace', calendarEditor);
    await pumpEventQueue();
    final reply = Completer<void>();
    b.readReplyHeld = reply;
    await container.read(calendarActionsProvider).delete(deleted);
    await container.pump();
    expect(
      container.read(calendarEventsProvider('2026-10')).value,
      anyOf(isNull, isEmpty),
      reason: 'restored permission does not authorize reusing the old snapshot',
    );
    reply.complete();
    expect(await container.read(calendarEventsProvider('2026-10').future), [other]);
    expect(b.reads.length, 3);
  });

  test('a successful create after restored edit access reconciles a refused month', () async {
    final b = CalendarBackend();
    final calendarEditor = pastor.copyWith(role: Role.staff, groups: {Group.calendarEditors});
    b.addMember('grace', calendarEditor);
    final existing = CalendarEvent(
      id: 'existing',
      title: '原有活動',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
    );
    final draft = CalendarEvent(title: '新活動', start: DateTime(2026, 10, 20), end: DateTime(2026, 10, 21));
    b.calendarEvents['grace'] = [existing];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    expect(await container.read(calendarEventsProvider('2026-10').future), [existing]);
    b.addMember('grace', calendarEditor.copyWith(groups: {}));
    await pumpEventQueue();
    b.readError = const CloudException(CloudErrorCode.permissionDenied);
    await expectLater(container.read(calendarActionsProvider).save(draft), throwsA(isA<CloudException>()));
    await pumpEventQueue();
    expect(container.read(calendarEventsProvider('2026-10')).hasError, isTrue);
    expect(container.read(calendarEventsProvider('2026-10')).value, anyOf(isNull, isEmpty));
    b.readError = null;
    b.addMember('grace', calendarEditor);
    await pumpEventQueue();
    final reply = Completer<void>();
    b.readReplyHeld = reply;
    await container.read(calendarActionsProvider).save(draft);
    await container.pump();
    expect(
      container.read(calendarEventsProvider('2026-10')).value,
      anyOf(isNull, isEmpty),
      reason: 'neither a partial create result nor the old unauthorized snapshot is a complete month',
    );
    reply.complete();
    final events = await container.read(calendarEventsProvider('2026-10').future);
    expect(events.map((e) => e.title), ['原有活動', '新活動']);
    expect(b.reads.length, 3);
  });

  test('a failed delete keeps the event visible and propagates the error', () async {
    final b = CalendarBackend();
    final event = CalendarEvent(
      id: 'meeting',
      title: '同工會',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
    );
    b.calendarEvents['grace'] = [event];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    b.deleteHeld = Completer();
    const failure = CloudException(CloudErrorCode.unavailable);
    b.deleteError = failure;
    final deleting = container.read(calendarActionsProvider).delete(event);
    final failed = expectLater(deleting, throwsA(same(failure)));
    await pumpEventQueue();
    expect(container.read(calendarEventsProvider('2026-10')).value, [event]);
    b.deleteHeld!.complete();
    await failed;
    expect(container.read(calendarEventsProvider('2026-10')).value, [event]);
    expect(b.reads.length, 1);
  });

  test('quick repeated revisits do not extend the freshness of a fetched month beyond a minute', () async {
    var now = testNow;
    final b = CalendarBackend(clock: () => now);
    final container = await open(b);
    var shown = container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    shown.close();
    await container.pump();
    now = now.add(const Duration(seconds: 30));
    shown = container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    expect(b.reads.length, 1);
    shown.close();
    await container.pump();
    now = now.add(const Duration(seconds: 31));
    final added = CalendarEvent(id: 'added', title: '外部活動', start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 13));
    b.calendarEvents['grace'] = [added];
    shown = container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.pump();
    expect(await container.read(calendarEventsProvider('2026-10').future), [added]);
    expect(b.reads.length, 2);
    shown.close();
  });

  test(
    'saving while an unfetched month loads rereads its complete list instead of inventing a partial month',
    () async {
      final b = CalendarBackend();
      final event = CalendarEvent(
        id: 'meeting',
        title: '同工會',
        start: DateTime(2026, 11, 20),
        end: DateTime(2026, 11, 21),
      );
      b.calendarEvents['grace'] = [event];
      final reply = Completer<void>();
      b.readReplyHeld = reply;
      final container = await open(b);
      container.listen(calendarEventsProvider('2026-11'), (_, _) {});
      await pumpEventQueue();
      final external = CalendarEvent(
        id: 'external',
        title: '外部活動',
        start: DateTime(2026, 11, 10),
        end: DateTime(2026, 11, 11),
      );
      b.calendarEvents['grace']!.add(external);
      final saved = event.copyWith(title: '改名後');
      await container.read(calendarActionsProvider).save(saved, previous: event);
      await container.pump();
      expect(container.read(calendarEventsProvider('2026-11')).value, isNull);
      reply.complete();
      expect(await container.read(calendarEventsProvider('2026-11').future), [external, saved]);
      expect(b.reads.length, 2);
    },
  );

  test('pull refresh and explicit invalidation still fetch external calendar changes', () async {
    final b = CalendarBackend();
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    final external = CalendarEvent(
      id: 'external',
      title: '外部活動',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
    );
    b.calendarEvents['grace'] = [external];
    expect(await container.refresh(calendarEventsProvider('2026-10').future), [external]);
    expect(b.reads.length, 2);
    b.calendarEvents['grace'] = [];
    container.invalidate(calendarEventsProvider('2026-10'));
    expect(await container.read(calendarEventsProvider('2026-10').future), isEmpty);
    expect(b.reads.length, 3);
  });

  test('a pending snapshot cannot restore events after another month loses calendar access', () async {
    final b = CalendarBackend();
    final event = CalendarEvent(id: 'camp', title: '營會', start: DateTime(2026, 10, 31), end: DateTime(2026, 11, 3));
    b.calendarEvents['grace'] = [event];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    final reply = Completer<void>();
    b.readReplyHeld = reply;
    container.listen(calendarEventsProvider('2026-11'), (_, _) {});
    const refusal = CloudException(CloudErrorCode.permissionDenied);
    final pending = expectLater(container.read(calendarEventsProvider('2026-11').future), throwsA(same(refusal)));
    await pumpEventQueue();
    b.readReplyHeld = null;
    b.readError = refusal;
    await expectLater(container.refresh(calendarEventsProvider('2026-10').future), throwsA(same(refusal)));
    await pending;
    reply.complete();
    await pumpEventQueue();
    expect(container.read(calendarEventsProvider('2026-11')).value, anyOf(isNull, isEmpty));
    expect(container.read(calendarEventsProvider('2026-11')).error, same(refusal));
  });

  test('removing church membership clears loaded events and ignores a pending month reply', () async {
    final b = CalendarBackend();
    final event = CalendarEvent(id: 'camp', title: '營會', start: DateTime(2026, 10, 31), end: DateTime(2026, 11, 3));
    b.calendarEvents['grace'] = [event];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    final reply = Completer<void>();
    b.readReplyHeld = reply;
    container.listen(calendarEventsProvider('2026-11'), (_, _) {});
    await pumpEventQueue();
    b.members['grace']!.remove(pastor.uid);
    b.notify();
    await pumpEventQueue();
    expect(container.read(calendarEventsProvider('2026-10')).value, anyOf(isNull, isEmpty));
    expect(container.read(calendarEventsProvider('2026-11')).value, anyOf(isNull, isEmpty));
    reply.complete();
    await pumpEventQueue();
    expect(container.read(calendarEventsProvider('2026-11')).value, anyOf(isNull, isEmpty));
    expect(b.reads.length, 2);
  });

  test('undo never restores an old event into a newly selected calendar', () async {
    final b = CalendarBackend();
    final event = CalendarEvent(id: 'old', title: '同工會', start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 13));
    b.calendarEvents['grace'] = [event];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    final undo = await container.read(calendarActionsProvider).delete(event);
    await b.church('grace').calendarSelect('other', '另一行事曆');
    await pumpEventQueue();
    await expectLater(undo(), throwsA(isA<CloudException>()));
    expect(await container.read(calendarEventsProvider('2026-10').future), isEmpty);
  });

  test('a failed save leaves the displayed month unchanged before and after its error', () async {
    final b = CalendarBackend();
    final event = CalendarEvent(
      id: 'meeting',
      title: '同工會',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
    );
    b.calendarEvents['grace'] = [event];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    b.saveHeld = Completer();
    const failure = CloudException(CloudErrorCode.unavailable);
    b.saveError = failure;
    final saving = container.read(calendarActionsProvider).save(event.copyWith(title: '尚未儲存'), previous: event);
    final failed = expectLater(saving, throwsA(same(failure)));
    await pumpEventQueue();
    expect(container.read(calendarEventsProvider('2026-10')).value, [event]);
    b.saveHeld!.complete();
    await failed;
    expect(container.read(calendarEventsProvider('2026-10')).value, [event]);
    expect(b.reads.length, 1);
  });

  test('reconnecting the same calendar reloads instead of reviving its cached month', () async {
    final b = CalendarBackend();
    final event = CalendarEvent(
      id: 'meeting',
      title: '同工會',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
    );
    b.calendarEvents['grace'] = [event];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    b.calendars['grace'] = const CalendarSettings(
      connected: true,
      needsReconnect: true,
      calendarId: 'cal-grace',
      calendarName: '教會行事曆',
    );
    b.notify();
    await pumpEventQueue();
    expect(container.read(calendarEventsProvider('2026-10')).value, anyOf(isNull, isEmpty));
    final newer = event.copyWith(title: '重新連接後的活動');
    b.calendarEvents['grace'] = [newer];
    b.connectCalendar('grace', calendarName: '教會行事曆');
    await pumpEventQueue();
    expect(await container.read(calendarEventsProvider('2026-10').future), [newer]);
    expect(b.reads.length, 2);
  });

  test('changing the selected calendar clears both active and idle months before loading', () async {
    final b = CalendarBackend();
    final old = CalendarEvent(id: 'old', title: '舊行事曆活動', start: DateTime(2026, 10, 31), end: DateTime(2026, 11, 3));
    b.calendarEvents['grace'] = [old];
    final container = await open(b);
    final november = container.listen(calendarEventsProvider('2026-11'), (_, _) {});
    await container.read(calendarEventsProvider('2026-11').future);
    november.close();
    await container.pump();
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    final newer = old.copyWith(title: '新行事曆活動');
    b.calendarEvents['grace'] = [newer];
    final held = Completer<void>();
    b.calendarEventsHeld = held;
    await b.church('grace').calendarSelect('new-calendar', '新行事曆');
    await pumpEventQueue();
    expect(container.read(calendarEventsProvider('2026-10')).value, anyOf(isNull, isEmpty));
    expect(b.reads.length, 3, reason: 'only the active month reloads at selection time');
    held.complete();
    b.calendarEventsHeld = null;
    expect(await container.read(calendarEventsProvider('2026-10').future), [newer]);
    container.listen(calendarEventsProvider('2026-11'), (_, _) {});
    expect(await container.read(calendarEventsProvider('2026-11').future), [newer]);
    expect(b.reads.length, 4);
  });

  test('a quick revisit keeps the same pending month request', () async {
    final b = CalendarBackend();
    final held = Completer<void>();
    b.calendarEventsHeld = held;
    final container = await open(b);
    var shown = container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.pump();
    shown.close();
    await container.pump();
    shown = container.listen(calendarEventsProvider('2026-11'), (_, _) {});
    await container.pump();
    shown.close();
    await container.pump();
    shown = container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.pump();
    expect(b.reads, [('grace', '2026-10'), ('grace', '2026-11')]);
    held.complete();
    expect(await container.read(calendarEventsProvider('2026-10').future), isEmpty);
    shown.close();
  });

  test('a calendar access refusal clears every retained month, not just the refreshed one', () async {
    final b = CalendarBackend();
    final event = CalendarEvent(id: 'camp', title: '營會', start: DateTime(2026, 10, 31), end: DateTime(2026, 11, 3));
    b.calendarEvents['grace'] = [event];
    final container = await open(b);
    for (final month in ['2026-10', '2026-11']) {
      container.listen(calendarEventsProvider(month), (_, _) {});
      await container.read(calendarEventsProvider(month).future);
    }
    const refusal = CloudException(CloudErrorCode.permissionDenied);
    b.readError = refusal;
    await expectLater(container.refresh(calendarEventsProvider('2026-10').future), throwsA(same(refusal)));
    expect(container.read(calendarEventsProvider('2026-10')).value, anyOf(isNull, isEmpty));
    expect(container.read(calendarEventsProvider('2026-10')).error, same(refusal));
    expect(container.read(calendarEventsProvider('2026-11')).value, anyOf(isNull, isEmpty));
    expect(container.read(calendarEventsProvider('2026-11')).error, same(refusal));
    b.readError = null;
    expect(await container.refresh(calendarEventsProvider('2026-10').future), [
      event,
    ], reason: 'explicit retry can recheck access');
  });

  test('save patches a displayed month during refresh, ignores its stale reply and reconciles other events', () async {
    final b = CalendarBackend();
    final event = CalendarEvent(
      id: 'meeting',
      title: '同工會',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
    );
    b.calendarEvents['grace'] = [event];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    final external = CalendarEvent(
      id: 'external',
      title: '外部活動',
      start: DateTime(2026, 10, 14),
      end: DateTime(2026, 10, 15),
    );
    b.calendarEvents['grace']!.add(external);
    final reply = Completer<void>();
    b.readReplyHeld = reply;
    final refreshing = container.refresh(calendarEventsProvider('2026-10').future);
    await pumpEventQueue();
    final saved = event.copyWith(title: '改名後');
    await container.read(calendarActionsProvider).save(saved, previous: event);
    expect(container.read(calendarEventsProvider('2026-10')).value, [saved]);
    await container.pump();
    reply.complete();
    await refreshing;
    expect(await container.read(calendarEventsProvider('2026-10').future), [saved, external]);
    expect(b.reads.length, 3);
  });

  test('overlapping edits with replies out of order reconcile instead of restoring the older reply', () async {
    final b = CalendarBackend();
    final event = CalendarEvent(
      id: 'meeting',
      title: '同工會',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
    );
    b.calendarEvents['grace'] = [event];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    final delayedReply = Completer<void>();
    b.saveReplyHeld = delayedReply;
    final first = container.read(calendarActionsProvider).save(event.copyWith(title: '第一版'), previous: event);
    await pumpEventQueue();
    b.saveReplyHeld = null;
    final newest = event.copyWith(title: '第二版');
    await container.read(calendarActionsProvider).save(newest, previous: event);
    delayedReply.complete();
    await first;
    await container.pump();
    expect(await container.read(calendarEventsProvider('2026-10').future), [newest]);
    expect(b.reads.length, 2, reason: 'only ambiguous overlapping writes need a reconciliation read');
  });

  test('moving a multi-day event patches every retained copy, including an older external move', () async {
    final b = CalendarBackend();
    final old = CalendarEvent(
      id: 'camp',
      title: '營會',
      start: DateTime(2026, 1, 30),
      end: DateTime(2026, 2, 2),
      allDay: true,
    );
    b.calendarEvents['grace'] = [old];
    final container = await open(b);
    final january = container.listen(calendarEventsProvider('2026-01'), (_, _) {});
    await container.read(calendarEventsProvider('2026-01').future);
    january.close();
    await container.pump();
    final current = old.copyWith(start: DateTime(2026, 10, 31), end: DateTime(2026, 11, 3));
    b.calendarEvents['grace'] = [current];
    for (final month in ['2026-10', '2026-11']) {
      container.listen(calendarEventsProvider(month), (_, _) {});
      await container.read(calendarEventsProvider(month).future);
    }
    final moved = current.copyWith(title: '冬季營會', start: DateTime(2026, 11, 30), end: DateTime(2026, 12, 3));
    await container.read(calendarActionsProvider).save(moved, previous: current);
    expect(container.read(calendarEventsProvider('2026-01')).value, isEmpty);
    expect(container.read(calendarEventsProvider('2026-10')).value, isEmpty);
    expect(container.read(calendarEventsProvider('2026-11')).value, [moved]);
    expect(b.reads.length, 3);
    final other = CalendarEvent(id: 'other', title: '其他活動', start: DateTime(2026, 12, 20), end: DateTime(2026, 12, 21));
    b.calendarEvents['grace']!.add(other);
    container.listen(calendarEventsProvider('2026-12'), (_, _) {});
    expect(await container.read(calendarEventsProvider('2026-12').future), [moved, other]);
    expect(b.reads.length, 4, reason: 'an uncached month still needs the complete backend list');
  });

  test('a save finishing after a church switch never patches the next church month', () async {
    final b = CalendarBackend();
    b.addChurch('青年教會', id: 'youth');
    b.addMember('youth', pastor);
    b.connectCalendar('youth', calendarName: '青年行事曆');
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    b.saveHeld = Completer();
    final draft = CalendarEvent(title: '恩典堂活動', start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 13));
    final saving = container.read(calendarActionsProvider).save(draft);
    container.read(selectedChurchProvider.notifier).select('youth');
    await pumpEventQueue();
    await container.read(calendarEventsProvider('2026-10').future);
    b.saveHeld!.complete();
    await saving;
    expect(container.read(calendarEventsProvider('2026-10')).value, isEmpty);
    expect(b.reads, [('grace', '2026-10'), ('youth', '2026-10')]);
  });

  test('browsing many months evicts the oldest idle month before its minute expires', () async {
    final b = CalendarBackend();
    final container = await open(b);
    for (final month in ['2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07', '2026-08']) {
      final shown = container.listen(calendarEventsProvider(month), (_, _) {});
      await container.read(calendarEventsProvider(month).future);
      shown.close();
      await container.pump();
    }
    container.listen(calendarEventsProvider('2026-01'), (_, _) {});
    await container.read(calendarEventsProvider('2026-01').future);
    expect(b.reads.length, 9);
    expect(b.reads.last, ('grace', '2026-01'));
  });

  test('changing accounts clears the old month before the next account read completes', () async {
    final b = CalendarBackend();
    b.addMember('grace', staffMei);
    final old = CalendarEvent(id: 'old', title: '舊活動', start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 13));
    b.calendarEvents['grace'] = [old];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    b.calendarEventsHeld = Completer();
    b.auth.signInAs('mei@example.com', uid: staffMei.uid);
    await pumpEventQueue();
    expect(container.read(calendarEventsProvider('2026-10')).value, anyOf(isNull, isEmpty));
    expect(b.reads, [('grace', '2026-10'), ('grace', '2026-10')]);
    b.calendarEventsHeld!.complete();
    await container.read(calendarEventsProvider('2026-10').future);
  });

  test('delete removes the event immediately and undo shows the newly saved event', () async {
    final b = CalendarBackend();
    final event = CalendarEvent(
      id: 'old',
      title: '同工會',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
      allDay: true,
    );
    b.calendarEvents['grace'] = [event];
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    b.calendarEventsHeld = Completer();
    final undo = await container.read(calendarActionsProvider).delete(event);
    await container.pump();
    expect(container.read(calendarEventsProvider('2026-10')).value, isEmpty);
    await undo();
    final again = container.read(calendarEventsProvider('2026-10')).value!.single;
    expect((again.title, again.id), ('同工會', 'ev1'));
    expect(b.reads, [('grace', '2026-10')]);
    b.calendarEventsHeld!.complete();
  });

  test('a successful create shows the returned event without waiting for another month read', () async {
    final b = CalendarBackend();
    final container = await open(b);
    container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    final draft = CalendarEvent(title: '新活動', start: DateTime(2026, 10, 12), end: DateTime(2026, 10, 13), allDay: true);
    final saved = CalendarEvent(id: 'server-id', title: '新活動（已儲存）', start: draft.start, end: draft.end, allDay: true);
    b.saveAnswer = saved;
    b.calendarEventsHeld = Completer();
    await container.read(calendarActionsProvider).save(draft);
    await container.pump();
    expect(container.read(calendarEventsProvider('2026-10')).value, [saved]);
    expect(b.reads, [('grace', '2026-10')]);
    b.calendarEventsHeld!.complete();
  });

  test('an idle month expires on the backend clock and is read again', () async {
    var now = testNow;
    final b = CalendarBackend(clock: () => now);
    final container = await open(b);
    var shown = container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.read(calendarEventsProvider('2026-10').future);
    shown.close();
    await container.pump();
    now = now.add(const Duration(seconds: 61));
    final added = CalendarEvent(
      id: 'added',
      title: '新活動',
      start: DateTime(2026, 10, 12),
      end: DateTime(2026, 10, 13),
      allDay: true,
    );
    b.calendarEvents['grace'] = [added];
    shown = container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    await container.pump();
    expect(await container.read(calendarEventsProvider('2026-10').future), [added]);
    expect(b.reads, [('grace', '2026-10'), ('grace', '2026-10')]);
    shown.close();
  });

  test('returning to a visited month within a minute reuses its events', () async {
    final b = CalendarBackend();
    final meeting = CalendarEvent(
      id: 'meeting',
      title: '同工會',
      start: DateTime(2026, 10, 10, 19),
      end: DateTime(2026, 10, 10, 21),
    );
    b.calendarEvents['grace'] = [meeting];
    final container = await open(b);
    var shown = container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    expect(await container.read(calendarEventsProvider('2026-10').future), [meeting]);
    shown.close();
    await container.pump();
    shown = container.listen(calendarEventsProvider('2026-11'), (_, _) {});
    expect(await container.read(calendarEventsProvider('2026-11').future), isEmpty);
    shown.close();
    await container.pump();
    shown = container.listen(calendarEventsProvider('2026-10'), (_, _) {});
    expect(await container.read(calendarEventsProvider('2026-10').future), [meeting]);
    expect(b.reads, [('grace', '2026-10'), ('grace', '2026-11')]);
    shown.close();
  });
}
