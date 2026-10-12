import '../../core/languages.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/staff_order.dart';
import 'memory_backend.dart';

/// Sample church used by the offline demo and the performance baseline:
/// [memberCount] members, three services, a year of rosters. What the
/// church typed itself (its name, services, people) is in [language], as
/// a church speaking it would have it; the demo opens in the device's
/// language.
///
/// Deterministic, so screenshots and measurements are comparable run to
/// run. The emulator seed script (tools/seed) builds the same shape.
MemoryBackend demoBackend({
  int memberCount = 150,
  DateTime Function()? clock,
  bool signIn = true,
  bool newUser = false,
  AppLanguage language = AppLanguage.zhHant,
}) {
  final w = _DemoWords.of(language);
  final b = MemoryBackend(clock: clock);
  final cid = b.addChurch(w.church, id: 'demo');
  final start = b.churches[cid]!.timeZone.today(b.clock());
  // The features an admin sets up: a church link with a daily source, a
  // webhook, and two people moved from self-host who have not signed in.
  b.churchLinks[cid] = ChurchLink(
    title: w.linkTitle,
    body: w.linkBody,
    url: 'https://example.org/give',
    source: 'https://example.org/today.json',
  );
  b.linkContents[cid] = LinkContent(
    source: 'https://example.org/today.json',
    title: w.verseTitle,
    body: w.verse,
    link: 'https://example.org/bible/ps23',
    fetchedAt: b.clock().subtract(const Duration(hours: 5)),
  );
  b.webhooks[cid] = WebhookSettings(
    url: 'https://n8n.example.org/webhook/martha',
    calendar: true,
    roster: true,
    lastDelivery: WebhookDelivery(
      ok: true,
      status: 200,
      event: 'roster.changed',
      at: b.clock().subtract(const Duration(minutes: 12)),
    ),
  );
  b.webhookSecrets[cid] = 'whsec_demo';
  b.pendingMembers[cid] = {
    'old-1': PendingMember(id: 'old-1', name: w.moved[0], email: 'chiaying@example.com'),
    'old-2': PendingMember(id: 'old-2', name: w.moved[1], email: 'chunchieh@example.com'),
  };
  // Moving from self-host: whatever file is picked reads as this.
  final services = demoServicesIn(language);
  b.moveAnswer = MovePreview(
    members: 3,
    rosters: 104,
    services: [services[0].name, services[1].name],
    people: [
      MovePerson(id: 'old-a', name: w.demoPerson, email: 'demo@example.com'),
      MovePerson(id: 'old-b', name: w.moved[2], email: 'chihming@example.com'),
      MovePerson(id: 'old-c', name: w.moved[3]),
    ],
  );
  // Another church moved from self-host, with data waiting for the demo
  // account.
  final other = b.addChurch(w.otherChurch, id: 'living');
  b.pendingMembers[other] = {
    'old-demo': PendingMember(id: 'old-demo', name: w.demoPerson, email: 'demo@example.com'),
  };
  b.setServices(cid, services);
  final people = demoMembers(memberCount, language);
  for (final m in people) {
    b.addMember(cid, m);
  }
  for (final r in demoRosters(people, start, services)) {
    b.rosters[cid]![r.id] = r;
  }
  for (final s in services) {
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
    b.auth.signInAs('demo@example.com', uid: 'newcomer', name: w.newcomer);
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

/// The demo church's services in Traditional Chinese.
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

/// The demo church's services in [language]: the same services and duties,
/// in the same order, as a church writing it would name them.
List<Service> demoServicesIn(AppLanguage language) {
  final w = _DemoWords.of(language);
  return [
    for (final (i, s) in demoServices.indexed)
      Service(
        id: s.id,
        name: w.services[i],
        weekday: s.weekday,
        duties: w.duties[i],
        events: [for (final (j, e) in s.events.indexed) EventTag(name: w.events[j], color: e.color)],
      ),
  ];
}

/// The duties two people share: worship leading and ushering.
const _pairs = {
  'sunday': {1, 6},
  'youth': {1},
};

List<Member> demoMembers(int count, [AppLanguage language = AppLanguage.zhHant]) {
  final w = _DemoWords.of(language);
  final services = demoServicesIn(language);
  final members = <Member>[];
  for (var i = 0; i < count; i++) {
    final zones = <Zone>[
      for (final (j, s) in services.indexed)
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
        name: w.name(i),
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
List<Roster> demoRosters(List<Member> people, Day today, [List<Service> services = demoServices]) {
  final result = <Roster>[];
  for (final s in services) {
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
                  if (_pairs[s.id]?.contains(k) ?? false) pool[(week + k + 1) % pool.length],
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

/// What the demo church typed itself, in one language.
class _DemoWords {
  const _DemoWords({
    required this.church,
    required this.otherChurch,
    required this.linkTitle,
    required this.linkBody,
    required this.verseTitle,
    required this.verse,
    required this.moved,
    required this.demoPerson,
    required this.newcomer,
    required this.services,
    required this.duties,
    required this.events,
    required this.name,
  });

  final String church;
  final String otherChurch;
  final String linkTitle;
  final String linkBody;
  final String verseTitle;
  final String verse;

  /// People moved from self-host who have not signed in yet.
  final List<String> moved;
  final String demoPerson;
  final String newcomer;

  /// [demoServices]' names, duties and Sunday's events, in order.
  final List<String> services;
  final List<List<String>> duties;
  final List<String> events;

  /// The [i]th member's name; no two the same.
  final String Function(int i) name;

  static _DemoWords of(AppLanguage language) => switch (language) {
    AppLanguage.zhHant => _zhHant,
    AppLanguage.zhHans => _zhHans,
    AppLanguage.en => _en,
  };
}

/// A surname, then two characters of a given name.
String Function(int) _chineseNames(String surnames, String given) =>
    (i) => surnames[i % surnames.length] + given[(i * 7) % given.length] + given[(i * 13 + 3) % given.length];

final _zhHant = _DemoWords(
  church: '恩典之家',
  otherChurch: '活水教會',
  linkTitle: '主日奉獻',
  linkBody: '線上奉獻、索取收據',
  verseTitle: '今日經文　詩篇 23:1',
  verse: '耶和華是我的牧者，我必不至缺乏。',
  moved: ['林佳穎', '黃俊傑', '陳志明', '林雅婷'],
  demoPerson: '示範同工',
  newcomer: '新同工',
  services: [for (final s in demoServices) s.name],
  duties: [for (final s in demoServices) s.duties],
  events: [for (final e in demoServices.first.events) e.name],
  name: _chineseNames(
    '陳林黃張李王吳劉蔡楊許鄭謝郭洪曾邱廖賴徐周葉蘇莊呂江何蕭羅高潘簡朱鍾彭游詹胡施沈余趙盧梁顏柯孫魏翁戴范宋方',
    '志明美玲雅婷家豪俊傑淑芬怡君宗翰佳穎建宏欣怡冠宇思妤承恩惠如柏翰詩涵子軒心怡育誠文華',
  ),
);

final _zhHans = _DemoWords(
  church: '恩典之家',
  otherChurch: '活水教会',
  linkTitle: '主日奉献',
  linkBody: '线上奉献、索取收据',
  verseTitle: '今日经文　诗篇 23:1',
  verse: '耶和华是我的牧者，我必不致缺乏。',
  moved: ['林佳颖', '黄俊杰', '陈志明', '林雅婷'],
  demoPerson: '示范同工',
  newcomer: '新同工',
  services: ['主日崇拜', '青年崇拜', '祷告会'],
  duties: [
    ['领会', '敬拜主领', '司琴', '鼓手', '音控', '投影', '招待', '奉献'],
    ['领会', '敬拜主领', '吉他', '音控', '投影'],
    ['带领', '司琴'],
  ],
  events: ['圣餐', '浸礼', '特会'],
  name: _chineseNames(
    '陈林黄张李王吴刘蔡杨许郑谢郭洪曾邱廖赖徐周叶苏庄吕江何萧罗高潘简朱钟彭游詹胡施沈余赵卢梁颜柯孙魏翁戴范宋方',
    '志明美玲雅婷家豪俊杰淑芬怡君宗翰佳颖建宏欣怡冠宇思妤承恩惠如柏翰诗涵子轩心怡育诚文华',
  ),
);

const _enFirst = [
  'Grace', 'Daniel', 'Sarah', 'David', 'Rachel', 'Joshua', 'Hannah', 'Samuel', 'Esther', 'Caleb', //
  'Naomi', 'Nathan', 'Ruth', 'Isaac', 'Lydia', 'Aaron', 'Abigail', 'Elijah', 'Miriam', 'Andrew', //
  'Priscilla', 'Timothy', 'Joanna', 'Stephen', 'Deborah', 'Philip', 'Martha', 'Peter', 'Rebecca', 'James',
];
const _enLast = [
  'Lee', 'Chen', 'Wong', 'Tan', 'Lim', 'Smith', 'Johnson', 'Kim', 'Park', 'Garcia', //
  'Brown', 'Nguyen', 'Davis', 'Miller', 'Wilson', 'Moore', 'Taylor', 'Anderson', 'Thomas', 'Martin', //
  'Lin', 'Huang', 'Ng', 'Liu', 'Clark', 'Lewis', 'Walker', 'Young', 'Allen', 'King',
];

final _en = _DemoWords(
  church: 'Grace Community Church',
  otherChurch: 'Living Water Church',
  linkTitle: 'Sunday Giving',
  linkBody: 'Give online, get a receipt',
  verseTitle: 'Verse of the day: Psalm 23:1',
  verse: 'The Lord is my shepherd, I lack nothing.',
  moved: ['Joy Lin', 'Kevin Huang', 'Michael Chen', 'Emily Lin'],
  demoPerson: 'Demo Member',
  newcomer: 'New Member',
  services: ['Sunday Service', 'Youth Service', 'Prayer Meeting'],
  duties: [
    ['Host', 'Worship Leader', 'Piano', 'Drums', 'Sound', 'Slides', 'Usher', 'Offering'],
    ['Host', 'Worship Leader', 'Guitar', 'Sound', 'Slides'],
    ['Leader', 'Piano'],
  ],
  events: ['Communion', 'Baptism', 'Conference'],
  // Every first name with every surname once in 30 × 30.
  name: (i) => '${_enFirst[i % _enFirst.length]} ${_enLast[(i ~/ _enFirst.length + i) % _enLast.length]}',
);
