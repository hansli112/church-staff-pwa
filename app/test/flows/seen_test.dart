import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  testWidgets('the app open writes the day on my account, and again on another day back in it', (tester) async {
    var now = testNow;
    final b = seededChurch(as: staffMei, clock: () => now);
    await pumpApp(tester, b);
    expect(b.users['mei']!.seenOn, '2026-10-01', reason: 'the day on UTC+8, as the daily stats count');

    now = testNow.add(const Duration(days: 1));
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settle(tester);
    expect(b.users['mei']!.seenOn, '2026-10-02');
  });
}
