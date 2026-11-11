import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/firebase/codec.dart';

void main() {
  test(
    "an open church with a logo keeps room for it before its URL is looked up; a closed one's is never looked up",
    () {
      expect(churchFromJson('zw', {'name': '竹圍', 'status': 'active', 'logoVersion': '3'}).hasLogo, isTrue);
      expect(churchFromJson('zw', {'name': '竹圍', 'status': 'active'}).hasLogo, isFalse);
      expect(churchFromJson('zw', {'name': '竹圍', 'status': 'active', 'logoVersion': ''}).hasLogo, isFalse);
      expect(churchFromJson('zw', {'name': '竹圍', 'status': 'suspended', 'logoVersion': '3'}).hasLogo, isFalse);
    },
  );
}
