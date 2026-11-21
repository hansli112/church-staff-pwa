import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/staff.dart';

const _mei = Member(
  uid: 'mei',
  name: '李美玉',
  zones: [Zone(serviceType: 'sunday')],
);
const _hao = Member(uid: 'hao', name: '陳志豪');

void main() {
  test('the 同工 without an account are listed after the members, as members', () {
    final staff = Staff(
      [_mei, _hao],
      pending: const [
        PendingMember(
          id: 'p1',
          name: '王小明',
          zones: [
            Zone(serviceType: 'sunday', duties: ['司琴']),
          ],
        ),
      ],
    );
    expect([for (final m in staff.all) m.uid], ['mei', 'hao', 'p1']);
    expect(staff.all.last.serves('sunday', '司琴'), isTrue);
    expect(staff.noAccount, {'p1'});
  });

  test("one without an account under a member's name is that member, waiting to be merged", () {
    final staff = Staff(
      [_mei],
      pending: const [PendingMember(id: 'p1', name: ' 李美玉')],
    );
    expect([for (final m in staff.all) m.uid], ['mei']);
    expect(staff.waitingToMerge(_mei)?.id, 'p1');
    expect(staff.waitingToMerge(_hao), isNull);
  });

  test('two waiting under one name: neither is offered to merge', () {
    final staff = Staff(
      [_mei],
      pending: const [
        PendingMember(id: 'p1', name: '李美玉'),
        PendingMember(id: 'p2', name: '李美玉'),
      ],
    );
    expect(staff.waitingToMerge(_mei), isNull);
  });

  test('a name is taken however it is written: spaces, width, case', () {
    final staff = Staff(
      const [Member(uid: 'a', name: 'Amy Lin')],
      pending: const [PendingMember(id: 'p1', name: '王小明')],
    );
    expect(staff.hasName('amylin'), isTrue);
    expect(staff.hasName('ＡＭＹ ＬＩＮ'), isTrue);
    expect(staff.hasName(' 王小明 '), isTrue);
    expect(staff.hasName('王小'), isFalse);
    expect(staff.hasName('  '), isFalse);
  });

  test('a search finds those whose name has it, in the order listed', () {
    final staff = Staff([_mei, _hao, const Member(uid: 'yu', name: '吳美玉')]);
    expect([for (final m in staff.search('美 玉')) m.uid], ['mei', 'yu']);
    expect(staff.search('').length, 3);
  });
}
