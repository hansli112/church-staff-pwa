import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';

void main() {
  const sunday = Service(id: 'sunday', name: '主日崇拜', weekday: 7);
  const youth = Service(id: 'youth', name: '青年崇拜', weekday: 6);
  const prayer = Service(id: 'prayer', name: '禱告會', weekday: 3);
  const services = [sunday, youth, prayer];

  group('the 服事表 tab', () {
    test('shows a member the 牧區 they belong to, in the services order', () {
      const m = Member(
        uid: 'a',
        name: '小明',
        zones: [
          Zone(serviceType: 'prayer'),
          Zone(serviceType: 'sunday', duties: ['司琴']),
        ],
      );
      expect(m.rosterServices(services), [sunday, prayer]);
    });

    test('shows admins and roster editors every service', () {
      const admin = Member(uid: 'a', name: '牧師', role: Role.admin);
      const editor = Member(
        uid: 'b',
        name: '同工',
        groups: {Group.rosterEditors},
        zones: [Zone(serviceType: 'youth')],
      );
      expect(admin.rosterServices(services), services);
      expect(editor.rosterServices(services), services);
    });

    test('shows nothing to a member in no 牧區, even in a one-service church', () {
      const m = Member(uid: 'a', name: '新朋友', groups: {Group.calendarEditors});
      expect(m.rosterServices(services), isEmpty);
      expect(m.rosterServices(const [sunday]), isEmpty);
    });
  });

  test('a member waits for a 牧區 only when the tab would be empty for them', () {
    const newcomer = Member(uid: 'a', name: '新朋友');
    expect(newcomer.waitsForZone(services), isTrue);
    expect(newcomer.waitsForZone(const []), isFalse, reason: 'nothing to show anyone');
    expect(
      const Member(
        uid: 'a',
        name: '同工',
        zones: [Zone(serviceType: 'sunday')],
      ).waitsForZone(services),
      isFalse,
    );
    expect(const Member(uid: 'a', name: '牧師', role: Role.admin).waitsForZone(services), isFalse);
    expect(const Member(uid: 'a', name: '同工', groups: {Group.rosterEditors}).waitsForZone(services), isFalse);
    // Only in a 聚會 no longer held: the tab is empty for them too.
    expect(
      const Member(
        uid: 'a',
        name: '老同工',
        zones: [Zone(serviceType: 'old')],
      ).waitsForZone(services),
      isTrue,
    );
  });
}
