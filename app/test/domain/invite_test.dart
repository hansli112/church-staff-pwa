import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';

// One invite link a set of 聚會: 建立 with the set a live link joins shares
// that link again. Sets are compared as the list shows them, by the 聚會
// the church still has.
void main() {
  Invite invite(List<String> zoneTypes) =>
      Invite(code: 'C', churchId: 'grace', churchName: '恩典堂', expiresAt: DateTime(2026, 12), zoneTypes: zoneTypes);
  const services = {'sunday', 'youth'};

  test('the same 聚會, in any order, is the same link; one more or fewer is another', () {
    expect(invite(['youth', 'sunday']).joinsJust({'sunday', 'youth'}, services), isTrue);
    expect(invite(['sunday']).joinsJust({'sunday', 'youth'}, services), isFalse);
    expect(invite(['sunday', 'youth']).joinsJust({'sunday'}, services), isFalse);
    expect(invite([]).joinsJust({}, services), isTrue, reason: '只加入教會');
  });

  test('a 聚會 since deleted does not count: the link is what the list shows', () {
    expect(invite(['sunday', 'gone']).joinsJust({'sunday'}, services), isTrue);
    expect(invite(['gone']).joinsJust({}, services), isTrue, reason: 'shown as 只加入教會');
  });
}
