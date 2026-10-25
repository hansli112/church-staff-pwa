import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/firebase/codec.dart';
import 'package:martha/domain/models.dart';

/// 申請加入 (#88) as Firestore keeps it.
void main() {
  final asked = DateTime.utc(2026, 10, 1, 1);

  test('a request reads back with its note and when it was turned down', () {
    final r = joinRequestFromJson('carol', {
      'uid': 'carol',
      'name': '新朋友',
      'email': 'carol@example.com',
      'note': '我是敬拜團的小明',
      'createdAt': Timestamp.fromDate(asked),
      'rejectedAt': Timestamp.fromDate(asked.add(const Duration(hours: 1))),
    });
    expect((r.uid, r.name, r.email, r.note), ('carol', '新朋友', 'carol@example.com', '我是敬拜團的小明'));
    expect(r.createdAt.isAtSameMomentAs(asked), isTrue);
    expect(r.rejectedAt!.isAtSameMomentAs(asked.add(const Duration(hours: 1))), isTrue);
    expect(r.stateAt(asked.add(const Duration(days: 1))), JoinRequestState.rejected);
  });

  test('missing fields are empty; one with no time is gone', () {
    final r = joinRequestFromJson('carol', {});
    expect((r.name, r.email, r.note, r.rejectedAt), ('', '', '', null));
    expect(r.stateAt(asked), isNull);
  });

  test('a church takes requests unless its admin turned them off', () {
    expect(churchFromJson('grace', {'name': '恩典堂'}).takesJoinRequests, isTrue);
    expect(churchFromJson('grace', {'name': '恩典堂', 'joinRequestsClosed': true}).takesJoinRequests, isFalse);
  });
}
