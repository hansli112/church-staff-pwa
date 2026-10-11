import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/domain/models.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<void> go(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.tap(target);
  await settle(tester);
}

void main() {
  testWidgets('an admin edits per-zone small groups without changing duties or permissions', (tester) async {
    final b = seededChurch();
    b.addMember(
      'grace',
      staffMei.copyWith(
        zones: const [
          Zone(serviceType: 'sunday', duties: ['司琴', '招待'], smallGroups: ['喜樂小組']),
          Zone(serviceType: 'youth', smallGroups: ['青年小組']),
        ],
      ),
    );
    await pumpApp(tester, b);
    await go(tester, '/me/members/mei');
    expect(find.text('喜樂小組'), findsOneWidget);
    await tester.ensureVisible(find.text('小組').first);
    await tester.tap(find.text('小組').first);
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, ' 喜樂小組 \n恩典小組\n喜樂小組\n\n');
    await tapText(tester, '儲存');
    final member = (await b.church('grace').allMembers()).singleWhere((m) => m.uid == 'mei');
    expect(
      member.zones.singleWhere((z) => z.serviceType == 'sunday'),
      const Zone(
        serviceType: 'sunday',
        duties: ['司琴', '招待'],
        smallGroups: ['喜樂小組', '恩典小組'],
      ),
    );
    expect(member.zones.singleWhere((z) => z.serviceType == 'youth').smallGroups, ['青年小組']);
    expect(member.groups, isEmpty);
    expect(member.role, Role.staff);

    await tester.ensureVisible(find.text('小組').first);
    await tester.tap(find.text('小組').first);
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '');
    await tapText(tester, '儲存');
    final cleared = (await b.church('grace').allMembers()).singleWhere((m) => m.uid == 'mei');
    expect(cleared.zones.singleWhere((z) => z.serviceType == 'sunday').smallGroups, isEmpty);
    expect(cleared.serves('sunday', '司琴'), isTrue);
  });

  testWidgets('roster editors can see member and pending-member small groups but cannot edit them', (tester) async {
    final b = seededChurch(as: editor);
    b.addMember(
      'grace',
      staffMei.copyWith(
        zones: const [
          Zone(serviceType: 'sunday', duties: ['司琴'], smallGroups: ['喜樂小組']),
          Zone(serviceType: 'youth', smallGroups: ['青年小組']),
        ],
      ),
    );
    b.pendingMembers['grace'] = {
      'old-hao': const PendingMember(
        id: 'old-hao',
        name: '陳同工',
        zones: [
          Zone(serviceType: 'sunday', smallGroups: ['恩典小組']),
        ],
      ),
    };
    await pumpApp(tester, b);
    await go(tester, '/me/members');
    expect(find.textContaining('主日崇拜：喜樂小組'), findsOneWidget);
    expect(find.textContaining('青年崇拜：青年小組'), findsOneWidget);
    await tapText(tester, '李美玉');
    expect(find.text('屬於這個牧區'), findsNothing, reason: 'the read-only list does not open the member editor');
    await tester.scrollUntilVisible(find.textContaining('主日崇拜：恩典小組'), 150, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('主日崇拜：恩典小組'), findsOneWidget);
    expect(find.text('小組'), findsNothing, reason: 'no small-group configuration or permission controls');
  });
}
