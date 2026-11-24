import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/state/providers.dart';

import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  testWidgets('my name on its way counts as saving, as a change to the church does', (tester) async {
    final b = seededChurch();
    late WidgetRef widgetRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: await testOverrides(b),
        child: Consumer(
          builder: (context, ref, _) {
            widgetRef = ref;
            ref.watch(savingProvider);
            ref.watch(profileProvider);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final profile = widgetRef.read(profileProvider).value!;
    expect(widgetRef.read(savingProvider).value, isFalse);

    b.writeHeld = Completer();
    final saving = saveProfile(widgetRef, profile, name: '李美玉二');
    await tester.pump();
    expect(widgetRef.read(savingProvider).value, isTrue);

    b.writeHeld!.complete();
    await saving;
    await tester.pump();
    expect(widgetRef.read(savingProvider).value, isFalse);
    await tester.pump(const Duration(seconds: 10));
  });
}
