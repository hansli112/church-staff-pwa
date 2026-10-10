import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_async/fake_async.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/firebase/firebase_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

void main() {
  test('a single changed roster reuses the other decoded documents without reading their data again', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final values = <List<Roster>>[];
      final sub = fixture.backend.church('grace').rosters(from: Day(2026, 10, 1)).listen(values.add);
      time.flushMicrotasks();
      final first = _day('2026-10-04', people: ['A']);
      final second = _day('2026-10-11', people: ['B']);
      fixture.days.emit([first, second]);
      fixture.events.emit([]);
      time.flushMicrotasks();
      final unchanged = values.single.last;
      final changed = _day('2026-10-04', people: ['C']);
      fixture.days.emit([changed, second], changed: [changed]);
      time.flushMicrotasks();

      expect(values.last.first.duties.single.people, ['C']);
      expect(values.last.last, same(unchanged));
      expect(second.dataReads, 1, reason: 'the SDK document data is not re-read for an unchanged roster');
      expect(changed.dataReads, 1);
      unawaited(sub.cancel());
      time.flushMicrotasks();
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('server-only reads reconcile changes in a suppressed cache snapshot before its server acknowledgement', () {
    fakeAsync((time) {
      final fixture = _Fixture(serverReads: true);
      final values = <List<Roster>>[];
      final sub = fixture.backend.church('grace').rosters(from: Day(2026, 10, 1)).listen(values.add);
      time.flushMicrotasks();
      fixture.days.emit([
        _day('2026-10-04', people: ['A']),
      ]);
      fixture.events.emit([]);
      time.flushMicrotasks();
      final changed = _day('2026-10-04', people: ['B']);
      fixture.days.emit([changed], fromCache: true);
      time.flushMicrotasks();
      expect(values, hasLength(1), reason: 'serverReads still suppresses cache values');
      fixture.days.emit([changed], changed: []);
      time.flushMicrotasks();

      expect(values.last.single.duties.single.people, ['B']);
      expect(fixture.days.metadataOptions, [true]);
      expect(fixture.events.metadataOptions, [true]);
      unawaited(sub.cancel());
      time.flushMicrotasks();
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('a server timestamp change retains the decoded roster and sorted result when domain content is unchanged', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final values = <List<Roster>>[];
      final sub = fixture.backend.church('grace').rosters(from: Day(2026, 10, 1)).listen(values.add);
      time.flushMicrotasks();
      fixture.days.emit([
        _day('2026-10-04', people: ['A']),
      ]);
      fixture.events.emit([]);
      time.flushMicrotasks();
      final first = values.single;
      final acknowledged = _day('2026-10-04', people: ['A']);
      acknowledged.values['updatedAt'] = Timestamp.fromMillisecondsSinceEpoch(1);
      fixture.days.emit([acknowledged]);
      time.flushMicrotasks();

      expect(values.last.single, same(first.single));
      expect(values.last, same(first), reason: 'unchanged domain content needs no new sorted list');
      expect(acknowledged.dataReads, 1);
      unawaited(sub.cancel());
      time.flushMicrotasks();
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('day-query duplicates win only when decodable, retaining the event-query fallback otherwise', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final values = <List<Roster>>[];
      final sub = fixture.backend.church('grace').rosters(from: Day(2026, 10, 1)).listen(values.add);
      time.flushMicrotasks();
      final eventVersion = _event('2026-12-24', title: 'Event source');
      fixture.events.emit([eventVersion]);
      time.flushMicrotasks();
      expect(values, isEmpty, reason: 'both sources must have a first snapshot');
      final dayVersion = _event('2026-12-24', title: 'Day source');
      fixture.days.emit([dayVersion]);
      time.flushMicrotasks();
      expect(values.single.single.forEvent?.title, 'Day source');

      final broken = _event('2026-12-24')..values.remove('eventId');
      fixture.days.emit([broken]);
      time.flushMicrotasks();
      expect(values.last.single.forEvent?.title, 'Event source');
      expect(eventVersion.dataReads, 1, reason: 'changing the duplicate does not decode the event source again');
      fixture.days.emit([dayVersion]);
      time.flushMicrotasks();
      expect(values.last.single.forEvent?.title, 'Day source');
      expect(values.last, hasLength(1));
      unawaited(sub.cancel());
      time.flushMicrotasks();
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('the two full-range queries retain far-future services, ongoing events and cached undecodable documents', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final values = <List<Roster>>[];
      final sub = fixture.backend.church('grace').rosters(from: Day(2026, 10, 1)).listen(values.add);
      time.flushMicrotasks();
      final sunday = _day('2026-10-04');
      final youth = _day('2026-10-04', type: 'youth');
      final far = _day('2028-01-02');
      final missingType = _DocumentSnapshot('missing', {'dateKey': '2026-11-01'});
      final invalidDate = _DocumentSnapshot('invalid', {'dateKey': '2026-11-31', 'type': 'sunday'});
      final ongoing = _event('2026-09-29', end: '2026-10-02', eventId: 'retreat');
      fixture.days.emit([sunday, youth, missingType, invalidDate, far]);
      fixture.events.emit([ongoing]);
      time.flushMicrotasks();

      expect(values.single.map((r) => r.id), [
        'ev_retreat',
        '2026-10-04_sunday',
        '2026-10-04_youth',
        '2028-01-02_sunday',
      ]);
      expect(values.single.first.lastDay, Day(2026, 10, 2));
      expect(fixture.db.filters, [('grace', 'dateKey', '2026-10-01'), ('grace', 'endDateKey', '2026-10-01')]);
      expect(fixture.days.orders, [('dateKey', false)]);
      fixture.days.emit([sunday, youth, missingType, invalidDate, far], changed: []);
      time.flushMicrotasks();
      expect(missingType.dataReads, 1);
      expect(invalidDate.dataReads, 1);
      expect(values.last, same(values.first));
      final repaired = _DocumentSnapshot('missing', {'dateKey': '2026-11-01', 'type': 'sunday'});
      fixture.days.emit([sunday, youth, repaired, invalidDate, far], changed: [repaired]);
      time.flushMicrotasks();
      expect(values.last.map((r) => r.id), contains('2026-11-01_sunday'));
      unawaited(sub.cancel());
      time.flushMicrotasks();
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('a retried query starts a fresh change baseline and removes documents no longer present', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final values = <List<Roster>>[];
      final errors = <Object>[];
      final sub = fixture.backend
          .church('grace')
          .rosters(from: Day(2026, 10, 1))
          .listen(values.add, onError: errors.add);
      time.flushMicrotasks();
      fixture.days.emit([
        _day('2026-10-04', people: ['A']),
        _day('2026-10-11', people: ['B']),
      ]);
      fixture.events.emit([]);
      time.flushMicrotasks();
      fixture.days.updates.addError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
      time.flushMicrotasks();
      expect(errors, isEmpty);
      expect(fixture.days.updates.hasListener, isFalse);
      time.elapse(const Duration(milliseconds: 300));
      time.flushMicrotasks();
      final fresh = _day('2026-10-04', people: ['C']);
      fixture.days.emit([fresh], changed: []);
      time.flushMicrotasks();

      expect(fixture.days.opens, 2);
      expect(fixture.events.opens, 1);
      expect(values.last.single.duties.single.people, ['C']);
      expect(fresh.dataReads, 1, reason: 'first snapshot of the retry is read fully, independently of docChanges');
      expect(errors, isEmpty);
      unawaited(sub.cancel());
      time.flushMicrotasks();
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('roster source errors retain translation, retry exhaustion and later live updates', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final values = <List<Roster>>[];
      final errors = <Object>[];
      final sub = fixture.backend
          .church('grace')
          .rosters(from: Day(2026, 10, 1))
          .listen(values.add, onError: errors.add);
      time.flushMicrotasks();
      fixture.days.emit([
        _day('2026-10-04', people: ['A']),
      ]);
      fixture.events.emit([]);
      time.flushMicrotasks();
      fixture.events.updates.addError(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
      time.flushMicrotasks();
      expect(errors.single, isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.unavailable));
      final unexpected = StateError('synthetic SDK fault');
      fixture.events.updates.addError(unexpected);
      time.flushMicrotasks();
      expect(errors.last, same(unexpected));
      for (var attempt = 0; attempt < 5; attempt++) {
        fixture.days.updates.addError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
        time.flushMicrotasks();
        if (attempt < 4) {
          expect(errors, hasLength(2));
          time.elapse(Duration(milliseconds: 300 * (attempt + 1)));
          time.flushMicrotasks();
        }
      }
      expect(errors, hasLength(3));
      expect(errors.last, isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.permissionDenied));
      fixture.days.emit([
        _day('2026-10-04', people: ['B']),
      ]);
      time.flushMicrotasks();
      expect(values.last.single.duties.single.people, ['B']);
      unawaited(sub.cancel());
      time.flushMicrotasks();
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('pause, resume, cancellation and fresh church subscriptions do not reuse another subscription cache', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final values = <List<Roster>>[];
      final sub = fixture.backend.church('grace').rosters(from: Day(2026, 10, 1)).listen(values.add);
      time.flushMicrotasks();
      fixture.days.emit([
        _day('2026-10-04', people: ['A']),
      ]);
      fixture.events.emit([]);
      time.flushMicrotasks();
      sub.pause();
      final changed = _day('2026-10-04', people: ['B']);
      fixture.days.emit([changed]);
      time.flushMicrotasks();
      expect(values, hasLength(1));
      expect(changed.dataReads, 0);
      sub.resume();
      time.flushMicrotasks();
      expect(values.last.single.duties.single.people, ['B']);
      unawaited(sub.cancel());
      time.flushMicrotasks();
      expect(fixture.days.updates.hasListener, isFalse);
      expect(fixture.events.updates.hasListener, isFalse);
      fixture.days.emit([
        _day('2026-10-04', people: ['Late']),
      ]);
      time.flushMicrotasks();
      expect(values, hasLength(2));

      final other = <List<Roster>>[];
      final otherSub = fixture.backend.church('hope').rosters(from: Day(2026, 10, 1)).listen(other.add);
      time.flushMicrotasks();
      fixture.db.query('hope', 'dateKey').emit([
        _day('2026-10-04', people: ['Other church']),
      ], changed: []);
      fixture.db.query('hope', 'endDateKey').emit([]);
      time.flushMicrotasks();
      expect(other.single.single.duties.single.people, ['Other church']);
      unawaited(otherSub.cancel());
      time.flushMicrotasks();

      final reopened = <List<Roster>>[];
      final reopenedSub = fixture.backend.church('grace').rosters(from: Day(2026, 10, 1)).listen(reopened.add);
      time.flushMicrotasks();
      final fresh = _day('2026-10-04', people: ['New account']);
      fixture.days.emit([fresh], changed: []);
      fixture.events.emit([]);
      time.flushMicrotasks();
      expect(reopened.single.single.duties.single.people, ['New account']);
      expect(reopened.single.single, isNot(same(values.last.single)));
      expect(fresh.dataReads, 1);
      unawaited(reopenedSub.cancel());
      time.flushMicrotasks();
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('cancelling while refused prevents a pending retry from reopening either query', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final values = <List<Roster>>[];
      final errors = <Object>[];
      final sub = fixture.backend
          .church('grace')
          .rosters(from: Day(2026, 10, 1))
          .listen(values.add, onError: errors.add);
      time.flushMicrotasks();
      fixture.days.updates.addError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
      time.flushMicrotasks();
      unawaited(sub.cancel());
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 4));
      time.flushMicrotasks();

      expect(fixture.days.opens, 1);
      expect(fixture.events.opens, 1);
      expect(fixture.days.updates.hasListener, isFalse);
      expect(fixture.events.updates.hasListener, isFalse);
      expect(values, isEmpty);
      expect(errors, isEmpty);
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('event moves, source removal, cancellation and restoration stay live across month boundaries', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final values = <List<Roster>>[];
      final sub = fixture.backend.church('grace').rosters(from: Day(2026, 10, 1)).listen(values.add);
      time.flushMicrotasks();
      fixture.days.emit([_event('2026-10-02', end: '2026-10-04')]);
      fixture.events.emit([_event('2026-10-02', end: '2026-10-04')]);
      time.flushMicrotasks();
      final moved = _event('2026-09-30', end: '2026-10-03', title: 'Moved retreat');
      fixture.events.emit([moved]);
      time.flushMicrotasks();
      expect(values.last.single.day, Day(2026, 10, 2), reason: 'the old day-query version still has precedence');
      fixture.days.emit([], changed: []);
      time.flushMicrotasks();
      expect(values.last.single.day, Day(2026, 9, 30));
      expect(values.last.single.lastDay, Day(2026, 10, 3));
      final cancelled = _event('2026-09-30', end: '2026-10-03', title: 'Moved retreat');
      cancelled.values['cancelledAt'] = Timestamp.fromMillisecondsSinceEpoch(1);
      fixture.events.emit([cancelled]);
      time.flushMicrotasks();
      expect(
        values.last.single.forEvent?.cancelled,
        isTrue,
        reason: 'ChurchData preserves cancellation for its consumer to filter',
      );
      fixture.events.emit([moved]);
      time.flushMicrotasks();
      expect(values.last.single.forEvent?.cancelled, isFalse);
      fixture.events.emit([], changed: []);
      time.flushMicrotasks();
      expect(values.last, isEmpty);
      unawaited(sub.cancel());
      time.flushMicrotasks();
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('two subscribers to the same church keep separate decoded caches until each is cancelled', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final first = <List<Roster>>[];
      final second = <List<Roster>>[];
      final firstSub = fixture.backend.church('grace').rosters(from: Day(2026, 10, 1)).listen(first.add);
      final secondSub = fixture.backend.church('grace').rosters(from: Day(2026, 10, 1)).listen(second.add);
      time.flushMicrotasks();
      final doc = _day('2026-10-04');
      fixture.days.emit([doc]);
      fixture.events.emit([]);
      time.flushMicrotasks();
      expect(first.single.single, isNot(same(second.single.single)));
      expect(doc.dataReads, 2);
      unawaited(firstSub.cancel());
      time.flushMicrotasks();
      expect(fixture.days.updates.hasListener, isTrue);
      fixture.days.emit([
        _day('2026-10-04', people: ['B']),
      ]);
      time.flushMicrotasks();
      expect(first, hasLength(1));
      expect(second.last.single.duties.single.people, ['B']);
      unawaited(secondSub.cancel());
      time.flushMicrotasks();
      expect(fixture.days.updates.hasListener, isFalse);
      expect(fixture.events.updates.hasListener, isFalse);
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('the roster stream completes after both query sources and first() cancels its source subscriptions', () async {
    final fixture = _Fixture();
    final first = fixture.backend.church('grace').rosters(from: Day(2026, 10, 1)).first;
    await Future<void>.delayed(Duration.zero);
    fixture.days.emit([_day('2026-10-04')]);
    fixture.events.emit([]);
    expect((await first).single.day, Day(2026, 10, 4));
    await Future<void>.delayed(Duration.zero);
    expect(fixture.days.updates.hasListener, isFalse);
    expect(fixture.events.updates.hasListener, isFalse);

    var done = false;
    final values = <List<Roster>>[];
    final sub = fixture.backend
        .church('grace')
        .rosters(from: Day(2026, 10, 1))
        .listen(values.add, onDone: () => done = true);
    await Future<void>.delayed(Duration.zero);
    fixture.days.emit([_day('2026-10-04')]);
    fixture.events.emit([]);
    await Future<void>.delayed(Duration.zero);
    await fixture.days.updates.close();
    expect(done, isFalse);
    fixture.events.emit([_event('2026-12-24')]);
    await Future<void>.delayed(Duration.zero);
    expect(values.last.map((r) => r.id), ['2026-10-04_sunday', 'ev_party']);
    await fixture.events.updates.close();
    await Future<void>.delayed(Duration.zero);
    expect(done, isTrue);
    await sub.cancel();
  });

  test('a synchronous SDK cancel fault reaches the caller instead of becoming an unhandled zone error', () async {
    for (final field in ['dateKey', 'endDateKey']) {
      final fixture = _Fixture();
      final fault = StateError('synthetic SDK cancel fault');
      fixture.db.query('grace', field).cancelFaults.add(fault);
      final zoneErrors = <Object>[];
      final finished = Completer<void>();
      Object? cancelledWith;
      unawaited(
        runZonedGuarded(
          () async {
            try {
              final sub = fixture.backend.church('grace').rosters(from: Day(2026, 10, 1)).listen((_) {});
              await Future<void>.delayed(Duration.zero);
              fixture.days.emit([_day('2026-10-04')]);
              fixture.events.emit([]);
              await Future<void>.delayed(Duration.zero);
              try {
                await sub.cancel();
              } catch (error) {
                cancelledWith = error;
              }
              await Future<void>.delayed(Duration.zero);
              await fixture.db.close();
            } finally {
              finished.complete();
            }
          },
          (error, _) => zoneErrors.add(error),
        ),
      );
      await finished.future;

      expect(cancelledWith, same(fault), reason: '$field cancellation keeps the original cancellation Future error');
      expect(zoneErrors, isEmpty);
      expect(fixture.days.updates.hasListener, isFalse);
      expect(fixture.events.updates.hasListener, isFalse);
    }
  });

  test('a failed snapshot invalidates the decoded baseline before a later partial repair', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final values = <List<Roster>>[];
      final errors = <Object>[];
      final sub = fixture.backend
          .church('grace')
          .rosters(from: Day(2026, 10, 1))
          .listen(values.add, onError: errors.add);
      time.flushMicrotasks();
      fixture.days.emit([
        _day('2026-10-04', people: ['Old A']),
        _event('2026-12-24', title: 'Valid B'),
      ]);
      fixture.events.emit([]);
      time.flushMicrotasks();
      final updatedA = _day('2026-10-04', people: ['Updated A']);
      final brokenB = _event('2026-12-24')..values['title'] = 123;
      fixture.days.emit([updatedA, brokenB]);
      time.flushMicrotasks();
      expect(errors.single, isA<TypeError>());
      expect(values, hasLength(1), reason: 'a partially decoded snapshot is not published');
      final repairedB = _event('2026-12-24', title: 'Repaired B');
      fixture.days.emit([updatedA, repairedB], changed: [repairedB]);
      time.flushMicrotasks();

      expect(values.last.first.duties.single.people, ['Updated A']);
      expect(values.last.last.forEvent?.title, 'Repaired B');
      expect(errors, hasLength(1));
      unawaited(sub.cancel());
      time.flushMicrotasks();
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('server-only reads suppress malformed cache snapshots and fully rebuild the next server snapshot', () {
    fakeAsync((time) {
      final fixture = _Fixture(serverReads: true);
      final values = <List<Roster>>[];
      final errors = <Object>[];
      final sub = fixture.backend
          .church('grace')
          .rosters(from: Day(2026, 10, 1))
          .listen(values.add, onError: errors.add);
      time.flushMicrotasks();
      fixture.days.emit([
        _day('2026-10-04', people: ['Old A']),
        _event('2026-12-24', title: 'Valid B'),
      ]);
      fixture.events.emit([]);
      time.flushMicrotasks();
      final updatedA = _day('2026-10-04', people: ['Updated A']);
      final brokenB = _event('2026-12-24')..values['title'] = 123;
      fixture.days.emit([updatedA, brokenB], fromCache: true);
      time.flushMicrotasks();

      expect(errors, isEmpty, reason: 'the original server-only listener filters this cache snapshot before decoding');
      expect(values, hasLength(1));
      final repairedB = _event('2026-12-24', title: 'Repaired B');
      fixture.days.emit([updatedA, repairedB], changed: [repairedB]);
      time.flushMicrotasks();
      expect(values.last.first.duties.single.people, ['Updated A']);
      expect(values.last.last.forEvent?.title, 'Repaired B');
      expect(errors, isEmpty);
      unawaited(sub.cancel());
      time.flushMicrotasks();
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('an update from the other query cannot replace a decoding failure with stale rosters', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final values = <List<Roster>>[];
      final errors = <Object>[];
      final sub = fixture.backend
          .church('grace')
          .rosters(from: Day(2026, 10, 1))
          .listen(values.add, onError: errors.add);
      time.flushMicrotasks();
      fixture.days.emit([
        _day('2026-10-04', people: ['Old A']),
        _event('2026-12-24', title: 'Valid B'),
      ]);
      fixture.events.emit([]);
      time.flushMicrotasks();
      final updatedA = _day('2026-10-04', people: ['Updated A']);
      final brokenB = _event('2026-12-24')..values['title'] = 123;
      fixture.days.emit([updatedA, brokenB]);
      time.flushMicrotasks();
      expect(errors.single, isA<TypeError>());
      fixture.events.emit([_event('2026-11-01', title: 'Other event', eventId: 'other')]);
      time.flushMicrotasks();

      expect(values, hasLength(1), reason: 'the failed source is not its older successful snapshot');
      expect(errors, hasLength(2), reason: 'merging still fails until the malformed source recovers');
      final repairedB = _event('2026-12-24', title: 'Repaired B');
      fixture.days.emit([updatedA, repairedB], changed: [repairedB]);
      time.flushMicrotasks();
      expect(values, hasLength(2));
      expect(values.last.first.duties.single.people, ['Updated A']);
      expect(values.last.where((r) => r.isEvent).map((r) => r.forEvent!.title), ['Other event', 'Repaired B']);
      expect(errors, hasLength(2));
      unawaited(sub.cancel());
      time.flushMicrotasks();
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });
}

_DocumentSnapshot _event(String day, {String title = 'Event', String? end, String eventId = 'party'}) =>
    _DocumentSnapshot('ev_$eventId', {
      'kind': 'event',
      'eventId': eventId,
      'title': title,
      'dateKey': day,
      'endDateKey': end ?? day,
      'duties': <Object?>[],
    });

_DocumentSnapshot _day(String day, {String type = 'sunday', List<String> people = const []}) => _DocumentSnapshot(
  '${day}_$type',
  {
    'dateKey': day,
    'type': type,
    'duties': [
      {'role': 'music', 'people': people, 'uids': <String, String>{}},
    ],
    'events': <Object?>[],
  },
);

class _Fixture {
  _Fixture({this.serverReads = false});

  final bool serverReads;
  final db = _Firestore();
  late final backend = FirebaseBackend(
    auth: _Auth(),
    firestore: db,
    functions: _Functions(),
    storage: _Storage(),
    serverReads: serverReads,
  );
  _Query get days => db.query('grace', 'dateKey');
  _Query get events => db.query('grace', 'endDateKey');
}

class _Auth extends Fake implements fa.FirebaseAuth {}

class _Functions extends Fake implements FirebaseFunctions {}

class _Storage extends Fake implements FirebaseStorage {}

class _Firestore extends Fake implements FirebaseFirestore {
  final queries = <(String, String), _Query>{};
  final filters = <(String, String, Object?)>[];

  _Query query(String church, String field) => queries.putIfAbsent((church, field), () => _Query(this));

  @override
  DocumentReference<Map<String, dynamic>> doc(String documentPath) => _Document(this, documentPath.split('/').last);

  Future<void> close() async {
    for (final query in queries.values) {
      await query.updates.close();
    }
  }
}

// External SDK handles are fakes, not application subtypes or internal test hooks.
// ignore: subtype_of_sealed_class
class _Document extends Fake implements DocumentReference<Map<String, dynamic>> {
  _Document(this.db, this.church);
  final _Firestore db;
  final String church;

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) => _Collection(db, church);
}

// ignore: subtype_of_sealed_class
class _Collection extends Fake implements CollectionReference<Map<String, dynamic>> {
  _Collection(this.db, this.church);
  final _Firestore db;
  final String church;

  @override
  Query<Map<String, dynamic>> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    db.filters.add((church, field as String, isGreaterThanOrEqualTo));
    return db.query(church, field);
  }
}

// ignore: subtype_of_sealed_class
class _Query extends Fake implements Query<Map<String, dynamic>> {
  _Query(this.firestore);

  @override
  final _Firestore firestore;
  final updates = StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast();
  final metadataOptions = <bool>[];
  final orders = <(Object, bool)>[];
  final cancelFaults = <Object>[];
  int get opens => metadataOptions.length;

  void emit(List<_DocumentSnapshot> docs, {List<_DocumentSnapshot>? changed, bool fromCache = false}) =>
      updates.add(_Snapshot(docs, changed ?? docs, fromCache));

  @override
  Query<Map<String, dynamic>> orderBy(Object field, {bool descending = false}) {
    orders.add((field, descending));
    return this;
  }

  @override
  Stream<QuerySnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) {
    metadataOptions.add(includeMetadataChanges);
    return cancelFaults.isEmpty ? updates.stream : _CancelFaultStream(updates.stream, cancelFaults.first);
  }
}

/// An external SDK subscription can fail synchronously while stopping. It is
/// deliberately not a controller onCancel Future failure: retryRefused already
/// chooses not to await the underlying SDK's asynchronous teardown.
class _CancelFaultStream<T> extends Stream<T> {
  _CancelFaultStream(this.source, this.fault);
  final Stream<T> source;
  final Object fault;

  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _CancelFaultSubscription(
    source.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError),
    fault,
  );
}

class _CancelFaultSubscription<T> extends Fake implements StreamSubscription<T> {
  _CancelFaultSubscription(this.source, this.fault);
  final StreamSubscription<T> source;
  final Object fault;

  @override
  Future<void> cancel() {
    unawaited(source.cancel());
    throw fault;
  }

  @override
  bool get isPaused => source.isPaused;

  @override
  void pause([Future<void>? resumeSignal]) => source.pause(resumeSignal);

  @override
  void resume() => source.resume();
}

// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  _Snapshot(this.docs, List<_DocumentSnapshot> changes, bool fromCache)
    : docChanges = [for (final doc in changes) _Change(doc)],
      metadata = _Metadata(fromCache);

  @override
  final List<_DocumentSnapshot> docs;
  @override
  final List<_Change> docChanges;
  @override
  final SnapshotMetadata metadata;
}

// ignore: subtype_of_sealed_class
class _DocumentSnapshot extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _DocumentSnapshot(this.id, this.values);

  @override
  final String id;
  final Map<String, dynamic> values;
  var dataReads = 0;

  @override
  Map<String, dynamic> data() {
    dataReads++;
    return values;
  }
}

// ignore: subtype_of_sealed_class
class _Change extends Fake implements DocumentChange<Map<String, dynamic>> {
  _Change(this.doc);

  @override
  final _DocumentSnapshot doc;
  @override
  DocumentChangeType get type => DocumentChangeType.modified;
}

class _Metadata extends Fake implements SnapshotMetadata {
  _Metadata(this.isFromCache);

  @override
  final bool isFromCache;
  @override
  bool get hasPendingWrites => false;
}
