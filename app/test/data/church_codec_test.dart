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

  test('多人服事 goes to Firestore and back; a service that never set it has none', () {
    final json = {
      'id': 'sunday',
      'name': '主日崇拜',
      'weekday': 7,
      'enabled': true,
      'duties': ['司會', '招待'],
      'events': <Object>[],
    };
    expect(serviceFromJson(json).manyDuties, isNull);
    expect(serviceToJson(serviceFromJson(json)), json);
    final many = {
      ...json,
      'manyDuties': ['招待'],
    };
    expect(serviceFromJson(many).manyDuties, ['招待']);
    expect(serviceToJson(serviceFromJson(many)), many);
  });

  test(
    "a service on several days keeps them; older apps read the first as its weekday, one day's has weekday alone",
    () {
      final json = {
        'id': 'morning',
        'name': '晨更',
        'weekday': 1,
        'weekdays': [1, 2, 3, 4, 5],
        'enabled': true,
        'duties': ['帶領'],
        'events': <Object>[],
      };
      expect(serviceFromJson(json).weekdays, [1, 2, 3, 4, 5]);
      expect(serviceToJson(serviceFromJson(json)), json);
      expect(serviceFromJson({...json, 'weekdays': null}).weekdays, [1]);
      expect(serviceToJson(serviceFromJson(json).copyWith(weekdays: [7])), {...json, 'weekday': 7}..remove('weekdays'));
    },
  );
}
