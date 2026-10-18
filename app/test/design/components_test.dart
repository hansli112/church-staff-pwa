import 'dart:math';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/design/components.dart';
import 'package:martha/core/design/tokens.dart';
import 'package:martha/features/dev/component_gallery.dart';

import '../support/harness.dart';

double _luminance(Color c) {
  double channel(double v) => v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  group('contrast (WCAG, design principles)', () {
    for (final (name, c) in [
      ('light', AppColors.light),
      ('dark', AppColors.dark),
    ]) {
      test('$name text on background and surface is at least 4.5:1', () {
        for (final bg in [c.background, c.surface, c.surfaceRaised]) {
          for (final fg in [
            c.label,
            c.secondaryLabel,
            c.accent,
            c.destructive,
          ]) {
            expect(
              contrast(fg, bg),
              greaterThanOrEqualTo(4.5),
              reason: '$fg on $bg',
            );
          }
        }
        expect(contrast(c.onAccent, c.accent), greaterThanOrEqualTo(4.5));
        expect(contrast(c.accent, c.accentSoft), greaterThanOrEqualTo(4.5));
      });

      test('$name icons that mean something (chevrons) are at least 3:1', () {
        for (final bg in [c.surface, c.surfaceRaised]) {
          expect(contrast(c.tertiaryLabel, bg), greaterThanOrEqualTo(3), reason: 'on $bg');
        }
      });

      test('$name selected segment stands out from its track, its label readable', () {
        expect(c.segment, isNot(c.fill));
        expect(contrast(c.label, c.segment), greaterThanOrEqualTo(4.5));
        expect(contrast(c.label, c.fill), greaterThanOrEqualTo(4.5));
      });
    }

    testWidgets('every event tag colour is readable in both appearances', (
      tester,
    ) async {
      for (final brightness in Brightness.values) {
        await pumpWidgetInApp(tester, const SizedBox(), brightness: brightness);
        final context = tester.element(find.byType(SizedBox).first);
        for (var i = 0; i < EventColors.count; i++) {
          final colors = EventColors.of(context, i);
          expect(
            contrast(colors.fg, colors.bg),
            greaterThanOrEqualTo(4.5),
            reason: '$brightness #$i',
          );
        }
      }
    });
  });

  group('tap targets', () {
    for (final (platform, minimum) in [
      (TargetPlatform.iOS, 44.0),
      (TargetPlatform.android, 48.0),
    ]) {
      testWidgets('rows are at least $minimum on $platform', (tester) async {
        await pumpWidgetInApp(
          tester,
          ListSection(
            children: [ListRow(title: '一', onTap: () {})],
          ),
          platform: platform,
        );
        expect(
          tester.getSize(find.byType(ListRow)).height,
          greaterThanOrEqualTo(minimum),
        );
      });
    }

    testWidgets('buttons are at least 48 tall', (tester) async {
      await pumpWidgetInApp(
        tester,
        Column(
          children: [
            PrimaryButton(label: '儲存', onPressed: () {}),
            SecondaryButton(label: '取消', onPressed: () {}),
          ],
        ),
      );
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('large text', () {
    const value = '台北（UTC+8）marthasit-dev.web.app/c/grace';

    testWidgets('a row puts its value under the title, whole', (tester) async {
      await pumpWidgetInApp(
        tester,
        ListSection(
          children: [ListRow(title: '主畫面名稱', value: value, onTap: () {})],
        ),
        textScale: 2,
      );
      final text = tester.widget<Text>(find.descendant(of: findShown(value), matching: find.byType(Text)));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(
        tester.getTopLeft(findShown(value)).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(findShown('主畫面名稱')).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('at the usual size the value stays on the trailing side', (tester) async {
      await pumpWidgetInApp(
        tester,
        const ListSection(
          children: [ListRow(title: '語言', value: '跟隨系統')],
        ),
      );
      expect(tester.getCenter(find.text('跟隨系統')).dy, tester.getCenter(find.text('語言')).dy);
    });

    testWidgets('a value too long for one line beside the title goes under it, whole, at any size', (tester) async {
      const value = '台北（UTC+8）・美國東部（UTC−4）・英國（UTC+1）';
      await pumpWidgetInApp(
        tester,
        const ListSection(
          children: [ListRow(title: '時區', value: value)],
        ),
        textScale: 1.3,
      );
      final text = tester.widget<Text>(find.descendant(of: findShown(value), matching: find.byType(Text)));
      expect(text.maxLines, isNull, reason: 'whole, not cut');
      expect(tester.getTopLeft(findShown(value)).dy, greaterThanOrEqualTo(tester.getBottomLeft(find.text('時區')).dy));
    });
  });

  testWidgets('a row’s leading icon is neutral; the accent is for actions and state', (tester) async {
    await pumpWidgetInApp(
      tester,
      ListRow(title: '通知', leading: const Icon(Symbols.notifications_rounded), onTap: () {}),
    );
    final context = tester.element(find.byIcon(Symbols.notifications_rounded));
    expect(IconTheme.of(context).color, AppColors.light.secondaryLabel);
  });

  test('white icons on the tiles of 我的 are at least 3:1', () {
    for (final tile in [
      TileColors.manage,
      TileColors.church,
      TileColors.support,
      TileColors.line,
      TileColors.neutral,
      TileColors.destructive,
    ]) {
      expect(contrast(const Color(0xFFFFFFFF), tile), greaterThanOrEqualTo(3), reason: '$tile');
    }
  });

  testWidgets('a date block shows month and date, reads the whole day, and only today is filled', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpWidgetInApp(
      tester,
      const Column(
        children: [
          DateBlock(month: '10月', day: 18, today: true, semanticLabel: '今天 · 10月18日 週日'),
          DateBlock(month: '10月', day: 25, today: false, semanticLabel: '10月25日 週日'),
        ],
      ),
    );
    expect(find.text('18'), findsOneWidget);
    expect(find.bySemanticsLabel('今天 · 10月18日 週日'), findsOneWidget);
    expect(find.bySemanticsLabel('10月'), findsNothing, reason: 'not the parts, read apart');
    Color fill(int i) =>
        (tester
                    .widget<Container>(
                      find.descendant(of: find.byType(DateBlock).at(i), matching: find.byType(Container)),
                    )
                    .decoration!
                as BoxDecoration)
            .color!;
    expect(fill(0), AppColors.light.accent);
    expect(fill(1), AppColors.light.fill);
    handle.dispose();
  });

  testWidgets('between rows with tiles the divider starts under the text, as in iOS Settings', (tester) async {
    await pumpWidgetInApp(
      tester,
      const ListSection(
        children: [
          ListRow(
            title: '同工',
            leading: IconTile(Symbols.group_rounded, color: TileColors.manage),
          ),
          ListRow(
            title: '邀請',
            leading: IconTile(Symbols.person_add_rounded, color: TileColors.manage),
          ),
        ],
      ),
    );
    final divider = tester.getTopLeft(find.byType(Divider)).dx;
    expect(divider, moreOrLessEquals(tester.getTopLeft(find.text('邀請')).dx, epsilon: 1));
  });

  testWidgets('an avatar shows the first character of the name', (tester) async {
    await pumpWidgetInApp(tester, const Avatar('陳志玲'));
    expect(find.text('陳'), findsOneWidget);
  });

  testWidgets('body text is 17pt', (tester) async {
    await pumpWidgetInApp(tester, const ListRow(title: '內文'));
    final text = tester.widget<Text>(find.text('內文'));
    expect(text.style?.fontSize, 17);
  });

  group('behaviour', () {
    testWidgets('ListRow and SwitchRow respond to taps on the whole row', (
      tester,
    ) async {
      var taps = 0;
      var value = false;
      await pumpWidgetInApp(
        tester,
        StatefulBuilder(
          builder: (context, setState) => ListSection(
            children: [
              ListRow(title: '列', onTap: () => taps++),
              SwitchRow(
                title: '開關',
                value: value,
                onChanged: (v) => setState(() => value = v),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('列'));
      await tester.tap(find.text('開關'));
      await tester.pump();
      expect(taps, 1);
      expect(value, isTrue);
    });

    testWidgets('PrimaryButton ignores taps while busy', (tester) async {
      var taps = 0;
      await pumpWidgetInApp(
        tester,
        PrimaryButton(label: '儲存', busy: true, onPressed: () => taps++),
      );
      await tester.tap(find.byType(FilledButton));
      expect(taps, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('toast offers 復原 and runs it', (tester) async {
      var undone = false;
      await pumpWidgetInApp(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showToast(context, '已刪除', onUndo: () => undone = true),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('已刪除'), findsOneWidget);
      await tester.tap(find.text('復原'));
      expect(undone, isTrue);
    });

    testWidgets('deferred undo commits after the window unless undone', (
      tester,
    ) async {
      var committed = 0;
      var restored = 0;
      await pumpWidgetInApp(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDeferredUndo(
              context,
              '已移除',
              window: const Duration(seconds: 1),
              commit: () async => committed++,
              onUndo: () => restored++,
            ),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('復原'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect((committed, restored), (0, 1));

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect((committed, restored), (1, 1));
    });

    testWidgets('confirmDestructive has 取消 and the named action', (
      tester,
    ) async {
      bool? result;
      await pumpWidgetInApp(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await confirmDestructive(
              context,
              title: '退出〈恩典堂〉？',
              message: '需要重新邀請才能回來',
              action: '退出',
            ),
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('取消'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('退出'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('SearchField clears with its button', (tester) async {
      final seen = <String>[];
      await pumpWidgetInApp(tester, SearchField(onChanged: seen.add));
      await tester.enterText(find.byType(TextField), '王');
      await tester.pump();
      await tester.tap(find.byTooltip('清除'));
      await tester.pump();
      expect(seen, ['王', '']);
    });
  });

  group('gallery', () {
    for (final brightness in Brightness.values) {
      testWidgets(
        'renders in $brightness at the largest text size without overflow',
        (tester) async {
          await pumpWidgetInApp(
            tester,
            const ComponentGallery(),
            brightness: brightness,
            textScale: 2.0,
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          await tester.drag(find.byType(ListView), const Offset(0, -3000));
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
