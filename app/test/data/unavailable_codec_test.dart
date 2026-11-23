import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/firebase/codec.dart';
import 'package:martha/domain/day.dart';

/// 通知同工填 (#91) as Firestore keeps it: unavailableAsks/{type} and what
/// each unavailable/{uid} says was asked and sent.
void main() {
  final at = DateTime.utc(2026, 11, 20, 9);
  final ask = {
    'at': Timestamp.fromDate(at),
    'by': 'lead',
    'from': '2026-12',
    'to': '2027-01',
    'told': ['mei', 'hao', 'yu'],
  };

  test('a round: sent is who sent since it was asked, not before', () {
    final round = unavailableRoundFromJson(ask, {
      'mei': at,
      'hao': at.subtract(const Duration(days: 1)),
      'stranger': at,
    })!;
    expect((round.from, round.to), (Day(2026, 12, 1), Day(2027, 1, 1)));
    expect(round.at.isAtSameMomentAs(at), isTrue);
    expect(round.told, ['mei', 'hao', 'yu']);
    expect(round.sent, {'mei'});
    expect(round.waiting, ['hao', 'yu']);
  });

  test('an ask from before whom it told was kept, or never made, is no round', () {
    expect(unavailableRoundFromJson({...ask}..remove('told'), {}), isNull);
    expect(unavailableRoundFromJson(null, {}), isNull);
    expect(unavailableRoundFromJson({...ask, 'from': '2026-12-01'}, {}), isNull);
  });

  test('what was asked of me, and when I sent; nothing when never asked', () {
    final asked = unavailableAskedFromJson({
      'spans': [],
      'asked': {'at': Timestamp.fromDate(at), 'from': '2026-12', 'to': '2027-01'},
      'sentAt': Timestamp.fromDate(at.add(const Duration(hours: 1))),
    })!;
    expect((asked.from, asked.to, asked.sent), (Day(2026, 12, 1), Day(2027, 1, 1), true));
    expect(unavailableAskedFromJson({'spans': []}), isNull);
    expect(unavailableAskedFromJson(null), isNull);
  });
}
