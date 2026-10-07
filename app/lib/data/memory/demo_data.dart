import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/staff_order.dart';
import 'memory_backend.dart';

/// Sample church used by the offline demo and the performance baseline:
/// [memberCount] members, three services, a year of rosters.
///
/// Deterministic, so screenshots and measurements are comparable run to
/// run. The emulator seed script (tools/seed) builds the same shape.
MemoryBackend demoBackend({
  int memberCount = 150,
  Day? today,
  bool signIn = true,
  bool newUser = false,
}) {
  final b = MemoryBackend();
  final start = today ?? Day.today();
  final cid = b.addChurch('恩典之家', id: 'demo');
  // The features an admin sets up: a church link with a daily source, a
  // webhook, and two people moved from self-host who have not signed in.
  b.churchLinks[cid] = const ChurchLink(
    title: '主日奉獻',
    body: '線上奉獻、索取收據',
    url: 'https://example.org/give',
    source: 'https://example.org/today.json',
  );
  b.linkContents[cid] = LinkContent(
    source: 'https://example.org/today.json',
    title: '今日經文　詩篇 23:1',
    body: '耶和華是我的牧者，我必不至缺乏。',
    link: 'https://example.org/bible/ps23',
    fetchedAt: DateTime.now().subtract(const Duration(hours: 5)),
  );
  b.webhooks[cid] = WebhookSettings(
    url: 'https://n8n.example.org/webhook/martha',
    calendar: true,
    roster: true,
    lastDelivery: WebhookDelivery(
      ok: true,
      status: 200,
      event: 'roster.changed',
      at: DateTime.now().subtract(const Duration(minutes: 12)),
    ),
  );
  b.webhookSecrets[cid] = 'whsec_demo';
  b.pendingMembers[cid] = {
    'old-1': const PendingMember(id: 'old-1', name: '林佳穎', email: 'chiaying@example.com'),
    'old-2': const PendingMember(id: 'old-2', name: '黃俊傑', email: 'chunchieh@example.com'),
  };
  // Moving from self-host: whatever file is picked reads as this.
  b.moveAnswer = const MovePreview(
    members: 3,
    rosters: 104,
    services: ['主日崇拜', '青年崇拜'],
    people: [
      MovePerson(id: 'old-a', name: '示範同工', email: 'demo@example.com'),
      MovePerson(id: 'old-b', name: '陳志明', email: 'chihming@example.com'),
      MovePerson(id: 'old-c', name: '林雅婷'),
    ],
  );
  // Another church moved from self-host, with data waiting for the demo
  // account.
  final other = b.addChurch('活水教會', id: 'living');
  b.pendingMembers[other] = {
    'old-demo': const PendingMember(id: 'old-demo', name: '示範同工', email: 'demo@example.com'),
  };
  b.setServices(cid, demoServices);
  final people = demoMembers(memberCount);
  for (final m in people) {
    b.addMember(cid, m);
  }
  for (final r in demoRosters(people, start)) {
    b.rosters[cid]![r.id] = r;
  }
  for (final s in demoServices) {
    b.staffOrders[cid]![s.id] = StaffOrder({
      for (final duty in s.duties)
        duty: [
          for (final m in people)
            if (m.serves(s.id, duty)) m.name,
        ],
    });
  }
  if (newUser) {
    // Signed in with no church yet: the welcome page, a claim, moving.
    b.auth.signInAs('demo@example.com', uid: 'newcomer', name: '新同工');
  } else if (signIn) {
    final admin = people.first;
    b.auth.signInAs('demo@example.com', uid: admin.uid, name: admin.name);
    b.users[admin.uid] = UserProfile(
      uid: admin.uid,
      name: admin.name,
      email: 'demo@example.com',
    );
  }
  b.notify();
  return b;
}

const demoServices = [
  Service(
    id: 'sunday',
    name: '主日崇拜',
    weekday: DateTime.sunday,
    duties: ['司會', '敬拜主領', '司琴', '鼓', '音控', '投影', '招待', '奉獻'],
    events: [
      EventTag(name: '聖餐', color: 0),
      EventTag(name: '浸禮', color: 4),
      EventTag(name: '特會', color: 5),
    ],
  ),
  Service(
    id: 'youth',
    name: '青年崇拜',
    weekday: DateTime.saturday,
    duties: ['司會', '敬拜主領', '吉他', '音控', '投影'],
  ),
  Service(
    id: 'prayer',
    name: '禱告會',
    weekday: DateTime.wednesday,
    duties: ['帶領', '司琴'],
  ),
];

const _surnames = '陳林黃張李王吳劉蔡楊許鄭謝郭洪曾邱廖賴徐周葉蘇莊呂江何蕭羅高潘簡朱鍾彭游詹胡施沈余趙盧梁顏柯孫魏翁戴范宋方';
const _given = '志明美玲雅婷家豪俊傑淑芬怡君宗翰佳穎建宏欣怡冠宇思妤承恩惠如柏翰詩涵子軒心怡育誠文華';

List<Member> demoMembers(int count) {
  final members = <Member>[];
  for (var i = 0; i < count; i++) {
    final name =
        _surnames[i % _surnames.length] + _given[(i * 7) % _given.length] + _given[(i * 13 + 3) % _given.length];
    final zones = <Zone>[
      for (final (j, s) in demoServices.indexed)
        if ((i + j) % 3 != 2)
          Zone(
            serviceType: s.id,
            duties: [
              for (final (k, duty) in s.duties.indexed)
                if ((i + k * 5 + j) % 6 == 0) duty,
            ],
          ),
    ];
    members.add(
      Member(
        uid: 'm$i',
        name: name,
        email: 'member$i@example.com',
        role: i == 0
            ? Role.admin
            : i % 10 == 0
            ? Role.leader
            : Role.staff,
        groups: i % 15 == 1 ? {Group.rosterEditors} : const {},
        zones: zones,
      ),
    );
  }
  return members;
}

/// A year of saved rosters for every service, starting four weeks before
/// [today].
List<Roster> demoRosters(List<Member> people, Day today) {
  final result = <Roster>[];
  for (final s in demoServices) {
    var day = today.addDays(-28).nextOnOrAfter(s.weekday);
    for (var week = 0; week < 52; week++, day = day.addDays(7)) {
      result.add(
        Roster(
          type: s.id,
          day: day,
          events: [if (week % 4 == 0 && s.events.isNotEmpty) s.events.first],
          duties: [
            for (final (k, duty) in s.duties.indexed)
              () {
                final pool = [
                  for (final m in people)
                    if (m.serves(s.id, duty)) m,
                ];
                if (pool.isEmpty) return Duty(role: duty);
                final picks = {
                  pool[(week + k) % pool.length],
                  if (duty == '招待' || duty == '敬拜主領') pool[(week + k + 1) % pool.length],
                }.toList();
                return Duty(
                  role: duty,
                  people: [for (final p in picks) p.name],
                  uids: {for (final p in picks) p.name: p.uid},
                );
              }(),
          ],
        ),
      );
    }
  }
  return result;
}
