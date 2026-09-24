import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:church_staff_pwa/features/roster/data/roster_import_service.dart';
import 'package:church_staff_pwa/features/roster/presentation/widgets/photo_import_progress.dart';

void main() {
  group('photoImportProgressText', () {
    test('within the usual time, says how long and that retries happen', () {
      final text = photoImportProgressText(const Duration(seconds: 12));
      expect(text, contains('已經 12 秒'));
      expect(text, contains('一分鐘左右'));
      expect(text, isNot(contains('比平常久')));
    });

    test('past the usual time, says it is slow and counts down to timeout', () {
      final elapsed = RosterImportService.usualDuration;
      final text = photoImportProgressText(elapsed);
      final remaining = (RosterImportService.timeout - elapsed).inSeconds;
      expect(text, contains('比平常久'));
      expect(text, contains('最多再等 $remaining 秒'));
    });

    test('at the timeout, never shows a negative countdown', () {
      final text = photoImportProgressText(
        RosterImportService.timeout + const Duration(seconds: 3),
      );
      expect(text, isNot(contains('-')));
      expect(text, contains('快要逾時'));
    });
  });

  testWidgets('ticks every second while shown, and stops when removed', (
    tester,
  ) async {
    final show = ValueNotifier(true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, visible, _) =>
                visible ? const PhotoImportProgress() : const SizedBox(),
          ),
        ),
      ),
    );

    String shown() => tester
        .widget<Text>(find.byKey(const ValueKey('photo-import-progress')))
        .data!;

    expect(shown(), contains('已經 0 秒'));
    // Stopwatch is real time, not fake async, so drive both: the timer fires
    // on the fake clock, the text reads whatever really elapsed. Only assert
    // that the text changed, not to which second.
    await tester.runAsync(() => Future.delayed(const Duration(seconds: 1)));
    await tester.pump(const Duration(seconds: 1));
    expect(shown(), isNot(contains('已經 0 秒')));

    show.value = false;
    await tester.pump();
    expect(find.byType(PhotoImportProgress), findsNothing);
    // A timer left running after dispose fails the test here.
    await tester.pump(const Duration(seconds: 5));
  });
}
