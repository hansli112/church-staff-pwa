import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/state/providers.dart';
import 'package:martha/state/roster_actions.dart';

import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  test('granting a duty adds it to the member as they are now, keeping another admin’s change', () async {
    final b = seededChurch();
    final container = ProviderContainer(overrides: await testOverrides(b));
    addTearDown(container.dispose);
    container.listen(appStageProvider, (_, _) {});
    container.listen(rosterEditingProvider('sunday'), (_, _) {});
    await pumpEventQueue();
    final stale = b.members['grace']!['mei']!;

    // Meanwhile another admin makes her a roster editor.
    b.members['grace']!['mei'] = stale.copyWith(groups: {Group.rosterEditors});
    b.notify();
    await pumpEventQueue();

    await container.read(rosterActionsProvider).grantDuty(stale, 'sunday', '音控');
    final now = b.members['grace']!['mei']!;
    expect(now.groups, {Group.rosterEditors}, reason: 'the newer change is kept');
    expect(now.serves('sunday', '音控'), isTrue);
  });
}
