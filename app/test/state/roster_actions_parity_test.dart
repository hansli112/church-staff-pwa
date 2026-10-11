import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/backend.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/roster_edit.dart';
import 'package:martha/state/providers.dart';
import 'package:martha/state/roster_actions.dart';

import '../support/harness.dart';
import '../support/seed.dart';

Future<(ProviderContainer, RosterActions)> open(MemoryBackend backend) async {
  final container = ProviderContainer(overrides: await testOverrides(backend));
  addTearDown(container.dispose);
  container.listen(appStageProvider, (_, _) {});
  container.listen(rosterEditingProvider('sunday'), (_, _) {});
  await pumpEventQueue();
  return (container, container.read(rosterActionsProvider));
}

void main() {
  test('editing another person preserves an arranged guest despite a same-name member', () async {
    final b = seededChurch();
    final before = savedDay(b, 11).copyWith(
      duties: const [
        Duty(role: '司琴', people: ['John Chen']),
      ],
    );
    b.rosters['grace']![before.id] = before;
    final (_, actions) = await open(b);

    await actions.setPeople(before, '司琴', ['John Chen', '李美玉']).done;

    final duty = savedDay(b, 11).duties.single;
    expect(duty.people, ['John Chen', '李美玉']);
    expect(duty.uids, {'李美玉': 'mei'}, reason: 'an existing guest is never rebound by member-name guessing');
  });

  test('roster listing keeps a saved far-future day beyond the draft horizon', () async {
    final b = seededChurch();
    final far = Roster(
      type: 'sunday',
      day: Day(2027, 7, 4),
      duties: const [Duty(role: '司琴')],
    );
    b.rosters['grace']![far.id] = far;
    final (container, _) = await open(b);

    final shown = container.read(serviceRostersProvider('sunday')).requireValue;

    expect(shown.where((r) => !r.saved).length, 11);
    expect(shown.last, far);
  });

  test('show more extends drafts by thirteen weeks without saving them', () async {
    final b = seededChurch();
    final (container, _) = await open(b);
    final before = container.read(serviceRostersProvider('sunday')).requireValue;
    expect(before.length, 13);

    container.read(rosterWeeksProvider('sunday').notifier).showMore();
    final extended = container.read(serviceRostersProvider('sunday')).requireValue;

    expect(extended.length, 26);
    expect(extended.last.day, Day(2027, 3, 28));
    expect(extended.last.saved, isFalse);
  });

  test('a reusable arranged guest is suggested only for that duty and remains a guest when chosen', () async {
    final b = seededChurch();
    final prior = savedDay(b, 4).copyWith(
      duties: const [
        Duty(role: '司琴', people: ['John Chen', '會員名'], uids: {'會員名': 'member'}),
        Duty(role: '招待', people: ['別的外請']),
      ],
    );
    b.rosters['grace']![prior.id] = prior;
    final (_, actions) = await open(b);

    expect(actions.guestSuggestions('sunday', '司琴'), ['John Chen']);
    await actions.setPeople(savedDay(b, 11), '司琴', ['John Chen'], guestNames: {'John Chen'}).done;

    expect(savedDay(b, 11).duties.firstWhere((d) => d.role == '司琴').uids, isEmpty);
  });

  test('future guest removal applies the preview atomically and can be undone', () async {
    final b = seededChurch();
    final guest = savedDay(b, 4).copyWith(
      duties: const [
        Duty(role: '司琴', people: ['John Chen']),
      ],
    );
    final bound = savedDay(b, 11).copyWith(
      duties: const [
        Duty(role: '司琴', people: ['John Chen'], uids: {'John Chen': 'john'}),
      ],
    );
    b.rosters['grace']![guest.id] = guest;
    b.rosters['grace']![bound.id] = bound;
    final (_, actions) = await open(b);

    final preview = actions.previewGuestRemoval('sunday', '司琴', 'John Chen');
    expect(preview.plan.before.keys, [guest.id]);
    expect(savedDay(b, 4), guest);
    final write = actions.applyFuturePreview(preview);
    await write.done;
    await pumpEventQueue();

    expect(savedDay(b, 4).duties.single.people, isEmpty);
    expect(savedDay(b, 11), bound);
    await write.undo();
    expect(savedDay(b, 4), guest);
  });

  test('a stale single-day edit refuses to overwrite a newer arranged duty', () async {
    final b = seededChurch();
    final before = savedDay(b, 11);
    final (_, actions) = await open(b);
    final newer = before.copyWith(
      duties: const [
        Duty(role: '司琴', people: ['新安排']),
      ],
    );
    b.rosters['grace']![before.id] = newer;
    b.notify();
    await pumpEventQueue();

    await expectLater(
      actions.setPeople(before, '司琴', ['李美玉']).done,
      throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.conflict)),
    );
    expect(savedDay(b, 11), newer);
  });

  test('a stale guest bulk preview rejects all dates without partially removing anyone', () async {
    final b = seededChurch();
    final first = savedDay(b, 4).copyWith(
      duties: const [
        Duty(role: '司琴', people: ['客席']),
      ],
    );
    final second = savedDay(b, 11).copyWith(
      duties: const [
        Duty(role: '司琴', people: ['客席']),
      ],
    );
    b.rosters['grace']![first.id] = first;
    b.rosters['grace']![second.id] = second;
    final (_, actions) = await open(b);
    final preview = actions.previewGuestRemoval('sunday', '司琴', '客席');
    final newer = second.copyWith(events: const [EventTag(name: '新安排', color: 1)]);
    b.rosters['grace']![second.id] = newer;
    b.notify();
    await pumpEventQueue();

    await expectLater(
      actions.applyFuturePreview(preview).done,
      throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.conflict)),
    );
    expect(savedDay(b, 4), first);
    expect(savedDay(b, 11), newer);
  });

  test('a guest bulk undo refuses a newer edit instead of restoring a stale whole day', () async {
    final b = seededChurch();
    final first = savedDay(b, 4).copyWith(
      duties: const [
        Duty(role: '司琴', people: ['客席']),
      ],
    );
    b.rosters['grace']![first.id] = first;
    final (_, actions) = await open(b);
    final write = actions.applyFuturePreview(actions.previewGuestRemoval('sunday', '司琴', '客席'));
    await write.done;
    await pumpEventQueue();
    final newer = savedDay(b, 4).copyWith(events: const [EventTag(name: '新安排', color: 1)]);
    b.rosters['grace']![first.id] = newer;
    b.notify();
    await pumpEventQueue();

    await expectLater(
      write.undo(),
      throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.conflict)),
    );
    expect(savedDay(b, 4), newer);
  });

  test('a stale swap target refuses both changes together', () async {
    final b = seededChurch();
    final first = savedDay(b, 4);
    final second = savedDay(b, 11);
    final (_, actions) = await open(b);
    final newer = second.copyWith(events: const [EventTag(name: '新安排', color: 1)]);
    b.rosters['grace']![second.id] = newer;
    b.notify();
    await pumpEventQueue();

    await expectLater(
      actions.swap('司琴', SwapSide(first, '李美玉'), SwapSide(second, null)).done,
      throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.conflict)),
    );
    expect(savedDay(b, 4), first);
    expect(savedDay(b, 11), newer);
  });

  test('adding duties refuses a stale baseline instead of losing a newer event tag', () async {
    final b = seededChurch();
    final first = savedDay(b, 4);
    final (_, actions) = await open(b);
    final newer = first.copyWith(events: const [EventTag(name: '新安排', color: 1)]);
    b.rosters['grace']![first.id] = newer;

    await expectLater(
      actions.addDuties(first, ['講道']).done,
      throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.conflict)),
    );
    expect(savedDay(b, 4), newer);
  });

  test('a different account in the same church starts with the original draft horizon', () async {
    final b = seededChurch();
    final (container, _) = await open(b);
    container.read(rosterWeeksProvider('sunday').notifier).showMore();
    expect(container.read(rosterWeeksProvider('sunday')), 26);
    b.auth.signInAs('editor@example.com', uid: 'editor', name: editor.name);
    await pumpEventQueue();

    expect(container.read(rosterWeeksProvider('sunday')), 13);
  });

  test('a stale common-event option refuses both its replacement and the day arrangement', () async {
    final b = seededChurch();
    final day = savedDay(b, 11);
    final (_, actions) = await open(b);
    final newer = sundayService.copyWith(events: const [EventTag(name: '聖餐', color: 4)]);
    b.services['grace'] = b.services['grace']!.withServices([newer, youthService]);
    const retreat = EventTag(name: '退修會', color: 2);

    await expectLater(
      actions.setEvents(day, const [retreat], addToCommon: const [retreat]).done,
      throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.conflict)),
    );
    expect(b.services['grace']!.byId('sunday'), newer);
    expect(savedDay(b, 11), day);
  });

  test('a same-text guest does not count as my service; only an explicit uid binding does', () async {
    final b = seededChurch(as: john);
    b.rosters['grace']![savedDay(b, 4).id] = savedDay(b, 4).copyWith(
      duties: const [
        Duty(role: '講道', people: ['John Chen']),
      ],
    );
    b.rosters['grace']![savedDay(b, 11).id] = savedDay(b, 11).copyWith(
      duties: const [
        Duty(role: '招待', people: ['不同顯示姓名'], uids: {'不同顯示姓名': 'john'}),
      ],
    );
    final (container, _) = await open(b);

    final mine = container.read(myServicesProvider).requireValue;

    expect(mine.map((s) => s.roster.day.key), ['2026-10-11']);
    expect(mine.single.duties, ['招待']);
  });

  for (final changed in ['common option', 'arranged day']) {
    test('combined event undo refuses a newer $changed without reverting either part', () async {
      final b = seededChurch();
      final (_, actions) = await open(b);
      const retreat = EventTag(name: '退修會', color: 2);
      final write = actions.setEvents(savedDay(b, 11), const [retreat], addToCommon: const [retreat]);
      await write.done;
      await pumpEventQueue();
      if (changed == 'common option') {
        final newer = b.services['grace']!
            .byId('sunday')!
            .copyWith(
              events: const [
                EventTag(name: '聖餐', color: 4),
                retreat,
              ],
            );
        b.services['grace'] = b.services['grace']!.withServices([newer, youthService]);
      } else {
        b.rosters['grace']![savedDay(b, 11).id] = savedDay(b, 11).copyWith(duties: const [Duty(role: '新安排')]);
      }
      b.notify();
      await pumpEventQueue();
      final currentService = b.services['grace']!.byId('sunday');
      final currentDay = savedDay(b, 11);

      await expectLater(
        write.undo(),
        throwsA(isA<CloudException>().having((e) => e.code, 'code', CloudErrorCode.conflict)),
      );
      expect(b.services['grace']!.byId('sunday'), currentService);
      expect(savedDay(b, 11), currentDay);
    });
  }
}
