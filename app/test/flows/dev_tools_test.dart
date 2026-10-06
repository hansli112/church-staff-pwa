import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/core/telemetry.dart';
import 'package:martha/state/session.dart';

import '../support/harness.dart';
import '../support/seed.dart';

class _CrashCounter extends NoTelemetry {
  var crashes = 0;

  @override
  void testCrash() => crashes++;
}

void main() {
  testWidgets('a development build crashes on purpose, to check Crashlytics', (tester) async {
    final telemetry = _CrashCounter();
    await pumpApp(tester, seededChurch(), overrides: [telemetryProvider.overrideWithValue(telemetry)]);
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/me');
    await settle(tester);

    await tester.scrollUntilVisible(find.text('測試當機'), 200);
    await tester.tap(find.text('測試當機'));
    await settle(tester);

    expect(telemetry.crashes, 1);
  });
}
