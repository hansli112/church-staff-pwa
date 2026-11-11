import 'package:flutter_test/flutter_test.dart';
import 'package:martha/state/support.dart';

void main() {
  final zhuwei = churchIcons.values.single;

  IconChange? next(String? current, {bool supporter = false, bool known = true, bool member = true}) =>
      nextAppIcon(current: current, supporter: supporter, churchKnown: known, church: member ? zhuwei : null);

  test("a church's own icon is never put on by itself: its members pick it", () {
    expect(next(null), isNull);
    expect(next(null, known: false), isNull);
  });

  test("a lapsed subscription's icon goes back to the app's", () {
    expect(next('Purple'), (to: null));
    expect(next('Purple', member: false), (to: null));
    expect(next('Purple', known: false), (to: null), reason: 'signed out too');
    expect(next('Purple', supporter: true), isNull);
  });

  test('leaving the church takes its icon off; a kept one stays', () {
    expect(next(zhuwei.iconId, member: false), (to: null));
    expect(next(zhuwei.iconId), isNull);
    expect(next(zhuwei.iconId, member: false, known: false), isNull, reason: 'not while signed out');
  });
}
