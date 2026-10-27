import 'package:flutter_test/flutter_test.dart';
import 'package:martha/state/support.dart';

void main() {
  final zhuwei = churchIcons.values.single;

  IconChange? next(
    String? current, {
    bool supporter = false,
    bool known = true,
    bool member = true,
    bool placed = false,
  }) => nextAppIcon(
    current: current,
    supporter: supporter,
    churchKnown: known,
    church: member ? zhuwei : null,
    placedBefore: placed,
  );

  test("a church's own icon goes on once, over the default only", () {
    expect(next(null), (to: zhuwei.iconId, placed: zhuwei));
    expect(next(null, placed: true), isNull, reason: 'put back, it stays back');
    expect(next('Purple', supporter: true), isNull, reason: 'a supporter picked theirs');
    expect(next(null, known: false), isNull, reason: 'not before my churches are known');
  });

  test("a lapsed subscription's icon goes, and the church's takes its place at once", () {
    expect(next('Purple'), (to: zhuwei.iconId, placed: zhuwei));
    expect(next('Purple', member: false), (to: null, placed: null));
    expect(next('Purple', known: false), (to: null, placed: null), reason: 'signed out too');
  });

  test('leaving the church takes its icon off; a kept one stays', () {
    expect(next(zhuwei.iconId, member: false), (to: null, placed: null));
    expect(next(zhuwei.iconId), isNull);
    expect(next(zhuwei.iconId, member: false, known: false), isNull, reason: 'not while signed out');
  });
}
