import 'package:flutter_test/flutter_test.dart';

import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';

void main() {
  // ── EventOption.fromJson / toJson ──────────────────────────────────────────
  group('EventOption 序列化', () {
    test('fromJson → toJson 來回轉換不變', () {
      const original = EventOption(name: '聖餐主日', color: 0xFFF39C12);
      final json = original.toJson();
      final restored = EventOption.fromJson(json);
      expect(restored.name, original.name);
      expect(restored.color, original.color);
    });

    test('fromJson：缺少 color 欄位時使用預設顏色', () {
      final e = EventOption.fromJson({'name': '復活節'});
      expect(e.name, '復活節');
      expect(e.color, 0xFFF39C12);
    });

    test('fromJson：缺少 name 欄位時 name 為空字串', () {
      final e = EventOption.fromJson({'color': 0xFF123456});
      expect(e.name, '');
      expect(e.color, 0xFF123456);
    });

    test('fromJson：name 非 String 時回退空字串', () {
      final e = EventOption.fromJson({'name': 42, 'color': 0xFFF39C12});
      expect(e.name, '');
    });

    test('fromJson：color 非 int 時回退預設顏色', () {
      final e = EventOption.fromJson({'name': '聖誕', 'color': '紅色'});
      expect(e.color, 0xFFF39C12);
    });

    test('copyWith 只更新 name 時 color 不變', () {
      const original = EventOption(name: '舊名', color: 0xFF001122);
      final updated = original.copyWith(name: '新名');
      expect(updated.name, '新名');
      expect(updated.color, 0xFF001122);
    });
  });

  // ── RosterEntry ────────────────────────────────────────────────────────────
  group('RosterEntry', () {
    test('assignedUserIds：返回去重後的 uid 列表，保持首次出現順序', () {
      final entry = RosterEntry(
        role: '領會',
        people: const ['Alice', 'Bob'],
        personIdsByName: const {
          'Alice': 'uid-a',
          'Bob': 'uid-b',
        },
      );
      expect(entry.assignedUserIds, ['uid-a', 'uid-b']);
    });

    test('assignedUserIds：重複 uid 只出現一次', () {
      final entry = RosterEntry(
        role: '敬拜',
        people: const ['Alice', 'Carol'],
        personIdsByName: const {
          'Alice': 'uid-a',
          'Carol': 'uid-a', // 同一人兩個名字
        },
      );
      expect(entry.assignedUserIds, ['uid-a']);
    });

    test('assignedUserIds：空白 uid 被過濾掉', () {
      final entry = RosterEntry(
        role: '講員',
        people: const ['Dave'],
        personIdsByName: const {'Dave': '   '},
      );
      expect(entry.assignedUserIds, isEmpty);
    });

    test('assignedUserIds：personIdsByName 為空時回傳空列表', () {
      final entry = RosterEntry(
        role: '司琴',
        people: const ['待定'],
      );
      expect(entry.assignedUserIds, isEmpty);
    });

    test('copyWith 只更新 role 時其他欄位保持不變', () {
      final original = RosterEntry(
        role: '領會',
        people: const ['A'],
        peopleOrder: const ['A'],
        personIdsByName: const {'A': 'uid-a'},
      );
      final updated = original.copyWith(role: '敬拜主領');
      expect(updated.role, '敬拜主領');
      expect(updated.people, ['A']);
      expect(updated.peopleOrder, ['A']);
      expect(updated.personIdsByName, {'A': 'uid-a'});
    });
  });

  // ── ServiceRoster ─────────────────────────────────────────────────────────
  group('ServiceRoster', () {
    ServiceRoster makeRoster({
      String id = 'test-id',
      List<String> specialEvents = const [],
      Map<String, int> customEventColors = const {},
      List<RosterEntry>? duties,
    }) {
      return ServiceRoster(
        id: id,
        date: DateTime(2026, 3, 1),
        type: ServiceType.sundayService,
        serviceName: '主日崇拜',
        duties: duties ??
            [
              RosterEntry(role: '領會', people: const ['A']),
            ],
        specialEvents: specialEvents,
        customEventColors: customEventColors,
      );
    }

    test('specialEvents 預設為空 List', () {
      final roster = makeRoster();
      expect(roster.specialEvents, isEmpty);
    });

    test('customEventColors 預設為空 Map', () {
      final roster = makeRoster();
      expect(roster.customEventColors, isEmpty);
    });

    test('customEventColors 有值時可正確讀取', () {
      final roster = makeRoster(
        customEventColors: {'復活節': 0xFFFFD700},
      );
      expect(roster.customEventColors['復活節'], 0xFFFFD700);
    });

    test('specialEvents 為空 list 時 copyWith 可加入事件', () {
      final original = makeRoster(specialEvents: const []);
      final updated = original.copyWith(specialEvents: ['聖餐主日']);
      expect(updated.specialEvents, ['聖餐主日']);
      // 原物件不受影響
      expect(original.specialEvents, isEmpty);
    });

    test('copyWith 只更新 customEventColors 時其他欄位不變', () {
      final original = makeRoster(
        specialEvents: const ['聖餐'],
        customEventColors: const {'舊事件': 0xFF000001},
      );
      final updated = original.copyWith(
        customEventColors: {'新事件': 0xFF000002},
      );
      expect(updated.customEventColors, {'新事件': 0xFF000002});
      expect(updated.specialEvents, ['聖餐']);
      expect(updated.id, original.id);
      expect(updated.serviceName, original.serviceName);
    });

    test('copyWith 對 duties 清空後為空 list', () {
      final roster = makeRoster();
      final updated = roster.copyWith(duties: []);
      expect(updated.duties, isEmpty);
    });
  });
}
