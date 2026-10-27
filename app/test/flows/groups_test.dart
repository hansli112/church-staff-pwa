import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await settle(tester);
}

Future<void> go(WidgetTester tester, String path) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(path);
  await settle(tester);
}

void main() {
  testWidgets('an admin makes a 事工, links its duties and names its 負責人 (#82)', (tester) async {
    final b = seededChurch();
    await pumpApp(tester, b);
    await go(tester, '/me');
    await tapText(tester, '聚會與事工');
    await tapText(tester, '新增事工');
    await tester.enterText(find.byType(TextField), '敬拜團');
    await tapText(tester, '儲存');
    final ministry = b.ministries['grace']!.ministries.single;
    expect(ministry.name, '敬拜團');
    expect(find.text('敬拜團'), findsWidgets, reason: 'its page opened');

    await tapText(tester, '服事項目');
    await tapText(tester, '司琴');
    await tapText(tester, '完成');
    expect(b.ministries['grace']!.ministries.single.duties, const [MinistryDuty('sunday', '司琴')]);

    await tapText(tester, '指派負責人');
    await tapText(tester, '陳志豪');
    expect(b.members['grace']!['hao']!.leadMinistries, [ministry.id]);
  });

  testWidgets('a lead adds whoever served as a 同工, and takes them out', (tester) async {
    // 李美玉 played 司琴 on 10/4 without being one of 敬拜團.
    final b = seededChurch(
      as: staffHao,
      extra: [
        staffHao.withIdentities(const [MinistryLead('worship')]),
      ],
    );
    b.ministries['grace'] = const MinistrySettings(
      ministries: [
        Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]),
      ],
      ids: ['worship'],
    );
    await pumpApp(tester, b);
    await go(tester, '/me');
    await tapText(tester, '敬拜團');
    expect(find.text('排過敬拜團的服事，還不是同工'), findsOneWidget);
    expect(find.text('司琴 1 次'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel('把李美玉加為敬拜團同工'), findsOneWidget);
    semantics.dispose();
    await tapText(tester, '加為同工');
    expect(b.members['grace']!['mei']!.ministries, {'worship'});
    expect(find.text('已把李美玉加為敬拜團同工'), findsOneWidget);

    await tapText(tester, '移出');
    expect(b.members['grace']!['mei']!.ministries, isEmpty);
    expect(find.text('已把李美玉移出敬拜團'), findsOneWidget);
    await tapText(tester, '復原');
    expect(b.members['grace']!['mei']!.ministries, {'worship'});
  });

  testWidgets('a lead adds anyone plain in the church, and moves no one who holds a 身分', (tester) async {
    final b = seededChurch(
      as: staffHao,
      extra: [
        staffHao.withIdentities(const [MinistryLead('worship')]),
      ],
    );
    b.ministries['grace'] = const MinistrySettings(
      ministries: [Ministry(id: 'worship', name: '敬拜團')],
      ids: ['worship'],
    );
    await pumpApp(tester, b);
    await go(tester, '/me/groups/ministry/worship');
    await tapText(tester, '加入同工');
    expect(find.text('林同工'), findsNothing, reason: '主日崇拜 負責人: a 身分');
    expect(find.text('王牧師'), findsNothing, reason: 'an admin');
    await tapText(tester, 'John Chen');
    expect(b.members['grace']!['john']!.ministries, {'worship'});
    expect(find.text('移出'), findsOneWidget);
  });

  testWidgets('who served it but holds a 身分 is not offered to a lead: that is the admin\'s', (tester) async {
    final b = seededChurch(
      as: staffHao,
      extra: [
        staffHao.withIdentities(const [MinistryLead('worship')]),
      ],
    );
    b.ministries['grace'] = const MinistrySettings(
      ministries: [
        Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('sunday', '司琴')]),
      ],
      ids: ['worship'],
    );
    // 林同工, 主日崇拜's 負責人, played 司琴 on 10/11 too.
    b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, 11))] = Roster(
      type: 'sunday',
      day: Day(2026, 10, 11),
      duties: const [
        Duty(role: '司琴', people: ['林同工'], uids: {'林同工': 'editor'}),
      ],
    );
    await pumpApp(tester, b);
    await go(tester, '/me/groups/ministry/worship');
    expect(find.text('李美玉'), findsOneWidget);
    expect(find.text('林同工'), findsNothing);
    expect(find.text('加為同工'), findsOneWidget);
  });

  testWidgets("a service's 負責人 adds a helper to its 同工 with the duties they served", (tester) async {
    final b = seededChurch(as: editor);
    b.rosters['grace']![Roster.idFor('youth', Day(2026, 10, 10))] = Roster(
      type: 'youth',
      day: Day(2026, 10, 10),
      duties: const [
        Duty(role: '司會', people: ['John Chen'], uids: {'John Chen': 'john'}),
      ],
    );
    b.members['grace']!['editor'] = editor.withIdentities(const [ServiceLead('youth')]);
    await pumpApp(tester, b);
    await go(tester, '/me/groups/service/youth');
    await tapText(tester, '加為同工');
    final added = b.members['grace']!['john']!;
    expect(added.zoneTypes, ['youth']);
    expect(added.serves('youth', '司會'), isTrue);
  });
}
