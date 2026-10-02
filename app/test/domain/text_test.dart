import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/text.dart';

void main() {
  group('nameKey', () {
    test('ignores spaces, full-width forms and case', () {
      expect(nameKey('台北 靈糧堂'), nameKey('台北靈糧堂'));
      expect(nameKey('ＴＡＩＰＥＩ'), nameKey('taipei'));
      expect(nameKey('  Grace　Church '), nameKey('gracechurch'));
    });

    test('keeps different names different', () {
      expect(nameKey('台北靈糧堂'), isNot(nameKey('台中靈糧堂')));
    });
  });

  group('matchesSearch', () {
    test('finds part of a name ignoring width and case', () {
      expect(matchesSearch('John Chen', 'ｊｏｈｎ'), isTrue);
      expect(matchesSearch('王大明', '大明'), isTrue);
      expect(matchesSearch('王大明', '小明'), isFalse);
    });

    test('an empty query matches everyone', () {
      expect(matchesSearch('王大明', '  '), isTrue);
    });
  });
}
