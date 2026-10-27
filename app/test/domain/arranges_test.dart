import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';

void main() {
  test('all of a roster, some of its duties, or nothing', () {
    const all = Arranges.all();
    const piano = Arranges.only({'司琴'});
    expect((all.all, all.any, all.has('司會')), (true, true, true));
    expect((piano.all, piano.any, piano.has('司琴'), piano.has('司會')), (false, true, true, false));
    expect((Arranges.none.all, Arranges.none.any), (false, false));
  });

  test('the same duties are the same, so nothing rebuilds for a new set of them', () {
    // Built at run time, as the providers build them.
    Arranges only(List<String> duties) => Arranges.only(duties.toSet());
    expect(only(['司琴', '音控']), only(['音控', '司琴']));
    expect(only(['司琴']).hashCode, only(['司琴']).hashCode);
    expect(const Arranges.all(), isNot(Arranges.none));
  });
}
