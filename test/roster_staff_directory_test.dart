import 'package:flutter_test/flutter_test.dart';

import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/roster/domain/staff_directory.dart';

// 名字都是虛構的（repo 是公開的）。

User _user(
  String id,
  String name, {
  Map<ServiceType, List<String>> ministries = const {},
}) => User(
  id: id,
  name: name,
  email: '$id@example.com',
  username: id,
  role: UserRole.staff,
  zones: [
    for (final entry in ministries.entries)
      UserZoneInfo(serviceType: entry.key, ministries: entry.value),
  ],
);

void main() {
  group('StaffDirectory.fromUsers', () {
    final staff = StaffDirectory.fromUsers([
      _user(
        'u1',
        ' 林書安 ',
        ministries: {
          ServiceType.youth: ['敬拜', ' 司琴 '],
          ServiceType.children: ['教師'],
        },
      ),
      _user(
        'u2',
        '郭子謙',
        ministries: {
          ServiceType.youth: ['司琴'],
        },
      ),
      _user('u3', '   '),
    ], ServiceType.youth);

    test('名字 trim 過，空白名字不算', () {
      expect(staff.names, ['林書安', '郭子謙']);
      expect(staff.contains('林書安'), isTrue);
    });

    test('只看這個崇拜的服事設定', () {
      expect(staff.canServe('林書安', '司琴'), isTrue);
      expect(staff.canServe('林書安', '教師'), isFalse);
    });

    test('namesForRole 依名字排序', () {
      expect(staff.namesForRole('司琴'), ['林書安', '郭子謙']..sort());
      expect(staff.namesForRole('音控'), isEmpty);
    });

    test('同名同姓：不帶 uid，也不猜是哪一位', () {
      final dup = StaffDirectory.fromUsers([
        _user('first', '林書安'),
        _user('second', '林書安'),
        _user('u2', '郭子謙'),
      ], ServiceType.youth);
      expect(dup.idOf('林書安'), isNull);
      expect(dup.idByName, {'郭子謙': 'u2'});
      expect(dup.resolve('林書安', '敬拜').status, NameMatchStatus.other);
      expect(dup.resolve('書安', '敬拜').status, NameMatchStatus.other);
    });

    test('idsOf 只回查得到 uid 的名字', () {
      expect(staff.idsOf(['林書安', '何宥廷']), {'林書安': 'u1'});
    });
  });

  group('StaffDirectory.resolve', () {
    final staff = StaffDirectory(
      names: const ['林書安', '郭子謙', '郭子安'],
      namesByRole: const {
        '敬拜': {'林書安'},
      },
    );

    test('空白與待定都是佔位', () {
      expect(staff.resolve(' ', '敬拜').name, placeholderPerson);
      expect(
        staff.resolve(placeholderPerson, '敬拜').status,
        NameMatchStatus.matched,
      );
    });

    test('全名：有設定是 matched，沒有是 roleMismatch', () {
      expect(staff.resolve('林書安', '敬拜').status, NameMatchStatus.matched);
      expect(staff.resolve('郭子謙', '敬拜').status, NameMatchStatus.roleMismatch);
    });

    test('唯一的字尾改寫成全名', () {
      final result = staff.resolve('書安', '敬拜');
      expect(result.status, NameMatchStatus.matched);
      expect(result.name, '林書安');
    });

    test('字尾對到兩位以上就不猜', () {
      // 「安」同時是林書安與郭子安的尾字。
      expect(staff.resolve('安', '敬拜').status, NameMatchStatus.other);
    });

    test('差一個字只給提示，名字不改', () {
      final result = staff.resolve('林書按', '敬拜');
      expect(result.status, NameMatchStatus.notInList);
      expect(result.name, '林書按');
      expect(result.suggestions, ['林書安']);
    });
  });
}
