import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:martha/data/memory/memory_backend.dart';
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

/// 主日崇拜's 喜樂小組 and 青年崇拜's 青年小組 (#85).
void withSmallGroups(MemoryBackend b) => b.smallGroups['grace'] = {
  'joy': const SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday'),
  'young': const SmallGroupDetails(id: 'young', name: '青年小組', service: 'youth'),
};

void main() {
  testWidgets("an admin puts a member in their service's 小組, changing nothing else", (tester) async {
    final b = seededChurch();
    withSmallGroups(b);
    b.addMember(
      'grace',
      staffMei.copyWith(
        zones: const [
          Zone(serviceType: 'sunday', duties: ['司琴', '招待']),
        ],
      ),
    );
    await pumpApp(tester, b);
    await go(tester, '/me/members/mei');
    expect(find.text('在青年小組'), findsNothing, reason: "青年崇拜's: not one of her 牧區");
    await tapText(tester, '在喜樂小組');
    final member = (await b.church('grace').allMembers()).singleWhere((m) => m.uid == 'mei');
    expect(member.smallGroups, {'joy'});
    expect(member.zones.single.duties, ['司琴', '招待']);
    expect(member.groups, isEmpty);
    expect(member.role, Role.staff);

    await tapText(tester, '在喜樂小組');
    expect((await b.church('grace').allMembers()).singleWhere((m) => m.uid == 'mei').smallGroups, isEmpty);
  });

  testWidgets("leads see each member's 小組, and a pending member's old names, but cannot edit them", (tester) async {
    final b = seededChurch(as: editor);
    withSmallGroups(b);
    b.addMember('grace', staffMei.copyWith(smallGroups: {'joy'}));
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
    expect(findShownContaining('喜樂小組'), findsOneWidget);
    await tapText(tester, '李美玉');
    expect(findShown('屬於這個牧區'), findsNothing, reason: 'the read-only list does not open the member editor');
    await tester.scrollUntilVisible(find.textContaining('主日崇拜：恩典小組'), 150, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('主日崇拜：恩典小組'), findsOneWidget);
  });
}
