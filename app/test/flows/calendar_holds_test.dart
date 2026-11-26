import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/features/calendar/calendar_screen.dart';

void main() {
  test('a duty is mine by name, or through my 小組 while its name is still on it', () {
    const byName = Duty(role: '招待', people: ['李美玉'], uids: {'李美玉': 'mei'});
    const byGroup = Duty(role: '招待', people: ['喜樂小組'], groups: {'喜樂小組': 'joy'});
    const groupGone = Duty(role: '招待', groups: {'喜樂小組': 'joy'});
    expect(holds(byName, 'mei', const {}), isTrue);
    expect(holds(byGroup, 'mei', const {'joy'}), isTrue);
    expect(holds(byGroup, 'mei', const {'peace'}), isFalse);
    expect(holds(groupGone, 'mei', const {'joy'}), isFalse, reason: 'taken off the day');
  });
}
