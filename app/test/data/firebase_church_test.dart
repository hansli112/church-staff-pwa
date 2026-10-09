import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_async/fake_async.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/firebase/firebase_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/env.dart';

void main() {
  test('church metadata arrives before its resolved Storage logo URL on any origin', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final churches = <Church?>[];
      final sub = fixture.backend.church('grace').church().listen(churches.add);
      time.flushMicrotasks();

      fixture.db.doc('churches/grace').emit({
        'name': '恩典教會',
        'status': 'active',
        'logoVersion': '1234',
      });
      time.flushMicrotasks();

      expect(churches, hasLength(1));
      expect(churches.single?.name, '恩典教會');
      expect(churches.single?.isActive, isTrue);
      expect(churches.single?.logoUrl, isNull);
      expect(fixture.storage.pending('grace').isCompleted, isFalse);

      const url =
          'https://firebasestorage.googleapis.com/v0/b/test-bucket/o/churches%2Fgrace%2Flogo.png'
          '?alt=media&token=grace-logo';
      fixture.storage.pending('grace').complete(url);
      time.flushMicrotasks();

      expect(churches, hasLength(2));
      expect(churches.last?.name, '恩典教會');
      expect(churches.last?.logoUrl, url);

      unawaited(sub.cancel());
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('same-version snapshots stay immediate and logo enrichment preserves the latest metadata', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final churches = <Church?>[];
      final sub = fixture.backend.church('grace').church().listen(churches.add);
      time.flushMicrotasks();
      final doc = fixture.db.doc('churches/grace');
      doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234', 'homeName': '恩典'});
      time.flushMicrotasks();
      doc.emit({'name': '新恩典教會', 'status': 'active', 'logoVersion': '1234', 'homeName': '新恩典'});
      time.flushMicrotasks();

      expect(churches.map((c) => c?.name), ['恩典教會', '新恩典教會']);
      expect(churches.last?.logoUrl, isNull);
      expect(fixture.storage.downloads, 1);
      const url = 'https://storage.example.test/grace-logo.png?token=1234';
      fixture.storage.pending('grace').complete(url);
      time.flushMicrotasks();

      expect(churches, hasLength(3));
      expect(churches.last?.name, '新恩典教會');
      expect(churches.last?.homeName, '新恩典');
      expect(churches.last?.logoUrl, url);
      doc.emit({'name': '再改名教會', 'status': 'active', 'logoVersion': '1234', 'homeName': '再改名'});
      time.flushMicrotasks();
      expect(churches, hasLength(4));
      expect(churches.last?.name, '再改名教會');
      expect(churches.last?.logoUrl, url);
      expect(fixture.storage.downloads, 1);

      unawaited(sub.cancel());
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('an older logo reply cannot replace a newer version or its metadata', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final churches = <Church?>[];
      final sub = fixture.backend.church('grace').church().listen(churches.add);
      time.flushMicrotasks();
      final doc = fixture.db.doc('churches/grace');
      doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      doc.emit({'name': '新恩典教會', 'status': 'active', 'logoVersion': '5678', 'homeName': '新恩典'});
      time.flushMicrotasks();

      expect(churches.map((c) => c?.name), ['恩典教會', '新恩典教會']);
      expect(churches.last?.logoUrl, isNull);
      const newUrl = 'https://storage.example.test/grace-new.png?token=5678';
      fixture.storage.pending('grace', 1).complete(newUrl);
      time.flushMicrotasks();
      expect(churches.last?.logoUrl, newUrl);
      fixture.storage.pending('grace').complete('https://storage.example.test/grace-old.png?token=1234');
      time.flushMicrotasks();

      expect(churches, hasLength(3));
      expect(churches.last?.name, '新恩典教會');
      expect(churches.last?.homeName, '新恩典');
      expect(churches.last?.logoUrl, newUrl);
      doc.emit({'name': '最新恩典教會', 'status': 'active', 'logoVersion': '5678'});
      time.flushMicrotasks();
      expect(churches.last?.name, '最新恩典教會');
      expect(churches.last?.logoUrl, newUrl);
      expect(fixture.storage.downloads, 2);

      unawaited(sub.cancel());
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('closing a church drops pending logo replies and clears its image cache', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final churches = <Church?>[];
      final sub = fixture.backend.church('grace').church().listen(churches.add);
      time.flushMicrotasks();
      final doc = fixture.db.doc('churches/grace');
      doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      doc.emit({'name': '停用的恩典教會', 'status': 'suspended', 'logoVersion': '1234'});
      time.flushMicrotasks();

      expect(churches, hasLength(2));
      expect(churches.last?.name, '停用的恩典教會');
      expect(churches.last?.isActive, isFalse);
      expect(churches.last?.logoUrl, isNull);
      fixture.storage.pending('grace').complete('https://storage.example.test/grace-old.png');
      time.flushMicrotasks();
      expect(churches, hasLength(2));

      doc.emit({'name': '恢復的恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      expect(churches.last?.name, '恢復的恩典教會');
      expect(churches.last?.logoUrl, isNull);
      expect(fixture.storage.downloads, 2);
      const freshUrl = 'https://storage.example.test/grace-restored.png';
      fixture.storage.pending('grace', 1).complete(freshUrl);
      time.flushMicrotasks();
      expect(churches.last?.isActive, isTrue);
      expect(churches.last?.logoUrl, freshUrl);

      unawaited(sub.cancel());
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('a deleted church stays closed when a pending logo completes', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final churches = <Church?>[];
      final sub = fixture.backend.church('grace').church().listen(churches.add);
      time.flushMicrotasks();
      final doc = fixture.db.doc('churches/grace');
      doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      final deletedAt = DateTime.utc(2026, 10, 9);
      doc.emit({'name': '刪除的恩典教會', 'status': 'deleted', 'logoVersion': '1234', 'deletedAt': deletedAt});
      time.flushMicrotasks();
      expect(churches.last?.name, '刪除的恩典教會');
      expect(churches.last?.status, ChurchStatus.deleted);
      expect(churches.last?.deletedAt, deletedAt);
      expect(churches.last?.logoUrl, isNull);
      fixture.storage.pending('grace').complete('https://storage.example.test/grace-deleted.png');
      time.flushMicrotasks();
      expect(churches, hasLength(2));
      expect(churches.last?.isActive, isFalse);
      expect(churches.last?.logoUrl, isNull);

      unawaited(sub.cancel());
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('removing or invalidating a logo keeps metadata and drops pending replies', () {
    for (final version in [null, '', 1234]) {
      fakeAsync((time) {
        final fixture = _Fixture();
        final churches = <Church?>[];
        final sub = fixture.backend.church('grace').church().listen(churches.add);
        time.flushMicrotasks();
        final doc = fixture.db.doc('churches/grace');
        doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
        time.flushMicrotasks();
        doc.emit({'name': '沒有圖片的恩典教會', 'status': 'active', 'logoVersion': version});
        time.flushMicrotasks();
        expect(churches.last?.name, '沒有圖片的恩典教會');
        expect(churches.last?.isActive, isTrue);
        expect(churches.last?.logoUrl, isNull);
        fixture.storage.pending('grace').complete('https://storage.example.test/grace-removed.png');
        time.flushMicrotasks();
        expect(churches, hasLength(2));

        doc.emit({'name': '新圖片的恩典教會', 'status': 'active', 'logoVersion': '1234'});
        time.flushMicrotasks();
        expect(churches.last?.name, '新圖片的恩典教會');
        expect(churches.last?.logoUrl, isNull);
        const freshUrl = 'https://storage.example.test/grace-restored.png';
        fixture.storage.pending('grace', 1).complete(freshUrl);
        time.flushMicrotasks();
        expect(churches.last?.logoUrl, freshUrl);

        unawaited(sub.cancel());
        unawaited(fixture.db.close());
        time.flushMicrotasks();
      });
    }
  });

  test('version changes, logo removal and closed or missing churches clear a cached image', () {
    final changes = <Map<String, dynamic>?>[
      {'name': '新恩典教會', 'status': 'active', 'logoVersion': '5678'},
      {'name': '新恩典教會', 'status': 'active'},
      {'name': '新恩典教會', 'status': 'suspended', 'logoVersion': '1234'},
      {'name': '新恩典教會', 'status': 'deleted', 'logoVersion': '1234'},
      null,
    ];
    for (final changed in changes) {
      fakeAsync((time) {
        final fixture = _Fixture();
        final churches = <Church?>[];
        final sub = fixture.backend.church('grace').church().listen(churches.add);
        time.flushMicrotasks();
        final doc = fixture.db.doc('churches/grace');
        doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
        time.flushMicrotasks();
        const oldUrl = 'https://storage.example.test/grace-old.png';
        fixture.storage.pending('grace').complete(oldUrl);
        time.flushMicrotasks();
        expect(churches.last?.logoUrl, oldUrl);

        doc.emit(changed);
        time.flushMicrotasks();
        expect(churches, hasLength(3));
        expect(churches.last?.logoUrl, isNull);
        if (changed == null) {
          expect(churches.last, isNull);
        } else {
          expect(churches.last?.name, '新恩典教會');
        }

        unawaited(sub.cancel());
        unawaited(fixture.db.close());
        time.flushMicrotasks();
      });
    }
  });

  test('a missing church document cannot be resurrected by a pending logo reply', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final churches = <Church?>[];
      final sub = fixture.backend.church('grace').church().listen(churches.add);
      time.flushMicrotasks();
      final doc = fixture.db.doc('churches/grace');
      doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      doc.emit(null);
      time.flushMicrotasks();
      expect(churches, hasLength(2));
      expect(churches.last, isNull);
      fixture.storage.pending('grace').complete('https://storage.example.test/grace-deleted.png');
      time.flushMicrotasks();
      expect(churches, hasLength(2));
      expect(churches.last, isNull);

      doc.emit({'name': '新建的恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      expect(churches.last?.name, '新建的恩典教會');
      expect(churches.last?.logoUrl, isNull);
      const url = 'https://storage.example.test/grace-created.png';
      fixture.storage.pending('grace', 1).complete(url);
      time.flushMicrotasks();
      expect(churches.last?.name, '新建的恩典教會');
      expect(churches.last?.logoUrl, url);

      unawaited(sub.cancel());
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('canceled logo replies cannot update a switched or reopened church stream', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final grace = <Church?>[];
      final hope = <Church?>[];
      final reopened = <Church?>[];
      final first = fixture.backend.church('grace').church().listen(grace.add);
      time.flushMicrotasks();
      fixture.db.doc('churches/grace').emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      unawaited(first.cancel());
      time.flushMicrotasks();

      final second = fixture.backend.church('hope').church().listen(hope.add);
      time.flushMicrotasks();
      fixture.db.doc('churches/hope').emit({'name': '盼望教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      const graceUrl = 'https://storage.example.test/grace.png';
      fixture.storage.pending('grace').complete(graceUrl);
      time.flushMicrotasks();
      expect(grace, hasLength(1));
      expect(hope, hasLength(1));
      expect(hope.single?.name, '盼望教會');
      expect(hope.single?.logoUrl, isNull);

      final third = fixture.backend.church('grace').church().listen(reopened.add);
      time.flushMicrotasks();
      fixture.db.doc('churches/grace').emit({'name': '再開的恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      expect(reopened.first?.name, '再開的恩典教會');
      expect(reopened.first?.logoUrl, isNull);
      expect(reopened.last?.name, '再開的恩典教會');
      expect(reopened.last?.logoUrl, graceUrl);
      expect(grace, hasLength(1));

      const hopeUrl = 'https://storage.example.test/hope.png';
      fixture.storage.pending('hope').complete(hopeUrl);
      time.flushMicrotasks();
      expect(hope, hasLength(2));
      expect(hope.last?.name, '盼望教會');
      expect(hope.last?.logoUrl, hopeUrl);
      expect(reopened.last?.logoUrl, graceUrl);

      unawaited(second.cancel());
      unawaited(third.cancel());
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('failed optional logo IO leaves metadata available and permits a later logo version', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final churches = <Church?>[];
      final errors = <Object>[];
      final sub = fixture.backend.church('grace').church().listen(churches.add, onError: errors.add);
      time.flushMicrotasks();
      final doc = fixture.db.doc('churches/grace');
      doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      fixture.storage
          .pending('grace')
          .completeError(
            FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'),
          );
      time.flushMicrotasks();

      expect(errors, isEmpty);
      expect(churches, hasLength(1));
      expect(churches.single?.name, '恩典教會');
      expect(churches.single?.logoUrl, isNull);
      doc.emit({'name': '改名的恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      expect(churches.last?.name, '改名的恩典教會');
      expect(churches.last?.logoUrl, isNull);
      expect(fixture.storage.downloads, 1);

      doc.emit({'name': '改名的恩典教會', 'status': 'active', 'logoVersion': '5678'});
      time.flushMicrotasks();
      expect(churches.last?.logoUrl, isNull);
      const url = 'https://storage.example.test/grace-recovered.png';
      fixture.storage.pending('grace', 1).complete(url);
      time.flushMicrotasks();
      expect(churches.last?.name, '改名的恩典教會');
      expect(churches.last?.logoUrl, url);
      expect(errors, isEmpty);

      unawaited(sub.cancel());
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('a synchronous optional Storage failure cannot suppress core metadata', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      fixture.storage.lookupError = FirebaseException(plugin: 'firebase_storage', code: 'unauthorized');
      final churches = <Church?>[];
      final errors = <Object>[];
      final sub = fixture.backend.church('grace').church().listen(churches.add, onError: errors.add);
      time.flushMicrotasks();
      final doc = fixture.db.doc('churches/grace');
      doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();

      expect(churches, hasLength(1));
      expect(churches.single?.name, '恩典教會');
      expect(churches.single?.logoUrl, isNull);
      expect(errors, isEmpty);
      doc.emit({'name': '改名的恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      expect(churches.last?.name, '改名的恩典教會');
      expect(errors, isEmpty);

      unawaited(sub.cancel());
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('unexpected logo faults remain stream errors without blocking metadata', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final churches = <Church?>[];
      final errors = <Object>[];
      final sub = fixture.backend.church('grace').church().listen(churches.add, onError: errors.add);
      time.flushMicrotasks();
      final doc = fixture.db.doc('churches/grace');
      doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      final fault = StateError('broken logo adapter');
      fixture.storage.pending('grace').completeError(fault);
      time.flushMicrotasks();

      expect(churches.single?.name, '恩典教會');
      expect(churches.single?.logoUrl, isNull);
      expect(errors, [same(fault)]);
      doc.emit({'name': '改名的恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      expect(churches.last?.name, '改名的恩典教會');
      expect(errors, hasLength(1));

      unawaited(sub.cancel());
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('a logo reply cannot replace a church read error before a fresh snapshot', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final events = <Object?>[];
      final sub = fixture.backend.church('grace').church().listen(events.add, onError: events.add);
      time.flushMicrotasks();
      final doc = fixture.db.doc('churches/grace');
      doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      doc.updates.addError(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
      time.flushMicrotasks();
      expect(events, hasLength(2));
      expect(events.last, isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.unavailable));

      const url = 'https://storage.example.test/grace.png';
      fixture.storage.pending('grace').complete(url);
      time.flushMicrotasks();
      expect(events, hasLength(2));
      expect(events.last, isA<CloudException>());

      doc.emit({'name': '最新恩典教會', 'status': 'active', 'logoVersion': '1234', 'homeName': '最新恩典'});
      time.flushMicrotasks();
      expect(events, hasLength(4));
      final metadata = events[2] as Church;
      final enriched = events.last as Church;
      expect(metadata.name, '最新恩典教會');
      expect(metadata.logoUrl, isNull);
      expect(enriched.name, '最新恩典教會');
      expect(enriched.homeName, '最新恩典');
      expect(enriched.logoUrl, url);
      expect(fixture.storage.downloads, 1);

      unawaited(sub.cancel());
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('a logo reply cannot replace an exhausted permission-denied read error', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final events = <Object?>[];
      final sub = fixture.backend.church('grace').church().listen(events.add, onError: events.add);
      time.flushMicrotasks();
      final doc = fixture.db.doc('churches/grace');
      doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      for (var attempt = 0; attempt < 5; attempt++) {
        doc.updates.addError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
        time.flushMicrotasks();
        if (attempt < 4) {
          expect(events, hasLength(1));
          time.elapse(Duration(milliseconds: 300 * (attempt + 1)));
          time.flushMicrotasks();
        }
      }
      expect(events, hasLength(2));
      expect(events.last, isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.permissionDenied));

      const url = 'https://storage.example.test/grace.png';
      fixture.storage.pending('grace').complete(url);
      time.flushMicrotasks();
      expect(events, hasLength(2));
      expect(events.last, isA<CloudException>());

      doc.emit({'name': '恢復讀取的恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      expect(events, hasLength(4));
      expect((events[2] as Church).name, '恢復讀取的恩典教會');
      expect((events.last as Church).name, '恢復讀取的恩典教會');
      expect((events.last as Church).logoUrl, url);
      expect(fixture.storage.downloads, 1);

      unawaited(sub.cancel());
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('church source errors stay translated and subsequent metadata stays live', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final churches = <Church?>[];
      final errors = <Object>[];
      final sub = fixture.backend.church('grace').church().listen(churches.add, onError: errors.add);
      time.flushMicrotasks();
      final doc = fixture.db.doc('churches/grace');
      doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      doc.updates.addError(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
      time.flushMicrotasks();
      expect(errors.single, isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.unavailable));

      doc.emit({'name': '最新恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      expect(churches.last?.name, '最新恩典教會');
      expect(churches.last?.logoUrl, isNull);
      const url = 'https://storage.example.test/grace.png';
      fixture.storage.pending('grace').complete(url);
      time.flushMicrotasks();
      expect(churches, hasLength(3));
      expect(churches.last?.name, '最新恩典教會');
      expect(churches.last?.logoUrl, url);
      expect(errors, hasLength(1));

      unawaited(sub.cancel());
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('church subscriptions keep pause, resume and source cancellation behavior', () {
    fakeAsync((time) {
      final fixture = _Fixture();
      final churches = <Church?>[];
      final sub = fixture.backend.church('grace').church().listen(churches.add);
      time.flushMicrotasks();
      final doc = fixture.db.doc('churches/grace');
      doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      sub.pause();
      doc.emit({'name': '最新恩典教會', 'status': 'active', 'logoVersion': '1234'});
      time.flushMicrotasks();
      expect(churches, hasLength(1));
      sub.resume();
      time.flushMicrotasks();
      expect(churches, hasLength(2));
      expect(churches.last?.name, '最新恩典教會');
      const url = 'https://storage.example.test/grace.png';
      fixture.storage.pending('grace').complete(url);
      time.flushMicrotasks();
      expect(churches.last?.name, '最新恩典教會');
      expect(churches.last?.logoUrl, url);

      unawaited(sub.cancel());
      time.flushMicrotasks();
      expect(doc.updates.hasListener, isFalse);
      doc.emit({'name': '已取消的恩典教會', 'status': 'active', 'logoVersion': '5678'});
      time.flushMicrotasks();
      expect(churches, hasLength(3));
      unawaited(fixture.db.close());
      time.flushMicrotasks();
    });
  });

  test('source completion does not await a logo or accept late logo replies', () {
    for (final failed in [false, true]) {
      fakeAsync((time) {
        final fixture = _Fixture();
        final churches = <Church?>[];
        final errors = <Object>[];
        var done = false;
        final sub = fixture.backend
            .church('grace')
            .church()
            .listen(
              churches.add,
              onError: errors.add,
              onDone: () => done = true,
            );
        time.flushMicrotasks();
        final doc = fixture.db.doc('churches/grace');
        doc.emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
        time.flushMicrotasks();
        unawaited(doc.updates.close());
        time.flushMicrotasks();
        expect(done, isTrue);
        expect(churches.single?.logoUrl, isNull);
        if (failed) {
          fixture.storage.pending('grace').completeError(StateError('late logo failure'));
        } else {
          fixture.storage.pending('grace').complete('https://storage.example.test/grace-late.png');
        }
        time.flushMicrotasks();
        expect(churches, hasLength(1));
        expect(errors, isEmpty);

        unawaited(sub.cancel());
        unawaited(fixture.db.close());
        time.flushMicrotasks();
      });
    }
  });

  test(
    'browser logos preserve the resolved Storage URL independently of page and invite origins',
    () {
      fakeAsync((time) {
        // Run on the local Chrome test server with an unrelated WEB_ORIGIN.
        expect(Uri.base.origin, isNot(Env.current.webOrigin));
        final fixture = _Fixture();
        final churches = <Church?>[];
        final sub = fixture.backend.church('grace').church().listen(churches.add);
        time.flushMicrotasks();
        fixture.db.doc('churches/grace').emit({'name': '恩典教會', 'status': 'active', 'logoVersion': '1234'});
        time.flushMicrotasks();
        expect(churches.single?.name, '恩典教會');
        expect(churches.single?.logoUrl, isNull);

        const url = 'https://alternate-storage.example.test/grace.png?alt=media&token=exact-sdk-token';
        fixture.storage.pending('grace').complete(url);
        time.flushMicrotasks();
        expect(churches.last?.name, '恩典教會');
        expect(churches.last?.logoUrl, url);

        unawaited(sub.cancel());
        unawaited(fixture.db.close());
        time.flushMicrotasks();
      });
    },
    skip: !kIsWeb || const String.fromEnvironment('WEB_ORIGIN') == '',
  );
}

class _Fixture {
  final db = _Firestore();
  final storage = _Storage();
  late final backend = FirebaseBackend(
    auth: _Auth(),
    firestore: db,
    functions: _Functions(),
    storage: storage,
  );
}

class _Auth extends Fake implements fa.FirebaseAuth {}

class _Functions extends Fake implements FirebaseFunctions {}

class _Firestore extends Fake implements FirebaseFirestore {
  final documents = <String, _Document>{};

  @override
  _Document doc(String documentPath) => documents.putIfAbsent(
    documentPath,
    () => _Document(this, documentPath.split('/').last),
  );

  Future<void> close() async {
    for (final doc in documents.values) {
      await doc.updates.close();
    }
  }
}

// Test double for the external SDK handle, not a production subtype.
// ignore: subtype_of_sealed_class
class _Document extends Fake implements DocumentReference<Map<String, dynamic>> {
  _Document(this.firestore, this.id);

  @override
  final FirebaseFirestore firestore;

  @override
  final String id;

  final updates = StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast();

  void emit(Map<String, dynamic>? data) => updates.add(_Snapshot(id, data));

  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) => updates.stream;
}

// Test double for the external SDK snapshot, not a production subtype.
// ignore: subtype_of_sealed_class
class _Snapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snapshot(this.id, this.values);

  @override
  final String id;
  final Map<String, dynamic>? values;

  @override
  bool get exists => values != null;

  @override
  Map<String, dynamic>? data() => values;
}

class _Storage extends Fake implements FirebaseStorage {
  final requests = <String, List<Completer<String>>>{};
  Object? lookupError;
  int get downloads => requests.values.fold(0, (total, pending) => total + pending.length);

  Completer<String> pending(String churchId, [int index = 0]) => requests['churches/$churchId/logo.png']![index];

  @override
  Reference ref([String? path]) => _Logo(this, path!);
}

class _Logo extends Fake implements Reference {
  _Logo(this.storage, this.path);

  @override
  final _Storage storage;
  final String path;

  @override
  Future<String> getDownloadURL() {
    if (storage.lookupError case final error?) throw error;
    final reply = Completer<String>();
    storage.requests.putIfAbsent(path, () => []).add(reply);
    return reply.future;
  }
}
