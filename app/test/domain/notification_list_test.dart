import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';

NotificationItem _at(String id, String cid, int minute) => NotificationItem(
  id: id,
  churchId: cid,
  kind: NotificationKind.reminder,
  title: '',
  body: '',
  link: '/home',
  at: DateTime.utc(2026).add(Duration(minutes: minute)),
);

void main() {
  final all = [_at('a', 'C1', 10), _at('b', 'C2', 30), _at('c', 'C1', 20)];

  test("one church's, newest first, whatever order they came in", () {
    expect([for (final n in NotificationList('C1', all, null).items) n.id], ['c', 'a']);
  });

  test('opening it sees it up to its newest; nothing is written once nothing is unread', () {
    final never = NotificationList('C1', all, null);
    expect(never.unread, 2);
    expect(never.seenOnOpening, DateTime.utc(2026).add(const Duration(minutes: 20)));
    expect(never.seenAt(never.seenOnOpening).seenOnOpening, isNull);
  });

  test('what came after it was seen is unread', () {
    final list = NotificationList('C1', all, DateTime.utc(2026).add(const Duration(minutes: 10)));
    expect([for (final n in list.items) list.isUnread(n)], [true, false]);
    expect(list.unread, 1);
  });

  test('tapping one sees up to it when nothing older is unread; seen is a time, so it would take those too', () {
    final never = NotificationList('C1', all, null);
    expect(never.seenOnTapping('a'), DateTime.utc(2026).add(const Duration(minutes: 10)));
    // 'a' is older and unread: tapping 'c' leaves both.
    expect(never.seenOnTapping('c'), isNull);
    final aSeen = never.seenAt(never.seenOnTapping('a'));
    expect(aSeen.seenOnTapping('c'), DateTime.utc(2026).add(const Duration(minutes: 20)));
    // Already read, another church's, or not in the list yet: nothing.
    expect(aSeen.seenOnTapping('a'), isNull);
    expect(never.seenOnTapping('b'), isNull);
    expect(never.seenOnTapping('x'), isNull);
  });
}
