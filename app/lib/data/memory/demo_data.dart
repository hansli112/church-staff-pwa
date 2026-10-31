import '../../core/languages.dart';
import '../../domain/day.dart';
import '../../domain/models.dart';
import '../../domain/staff_order.dart';
import 'memory_backend.dart';

/// What the church typed: names, services, duties, its calendar.
Set<String> churchText(MemoryBackend b) => {
  for (final c in b.churches.values) c.name,
  for (final members in b.members.values)
    for (final m in members.values) m.name,
  for (final s in b.services.values)
    for (final service in s.services) ...[
      service.name,
      ...service.duties,
      for (final e in service.events) e.name,
    ],
  for (final events in b.calendarEvents.values)
    for (final e in events) e.title,
  for (final rosters in b.rosters.values)
    for (final r in rosters.values)
      for (final d in r.duties) ...[d.role, ...d.people],
};

/// Sample church used by the offline demo and the performance baseline:
/// [memberCount] members, three services, a year of rosters. What the
/// church typed itself (its name, services, people) is in [language], as
/// a church speaking it would have it; the demo opens in the device's
/// language.
///
/// Deterministic, so screenshots and measurements are comparable run to
/// run. The emulator seed script (tools/seed) builds the same shape.
///
/// [showcase] is the church the website's videos show (tools/e2e/record.mjs):
/// settled in, with nothing on 首頁 asking to be dealt with first, and its
/// 小組 reporting 人數.
MemoryBackend demoBackend({
  int memberCount = 150,
  DateTime Function()? clock,
  bool signIn = true,
  bool newUser = false,
  bool showcase = false,
  AppLanguage language = AppLanguage.zhHant,
}) {
  final w = _DemoWords.of(language);
  final b = MemoryBackend(clock: clock);
  final cid = b.addChurch(w.church, id: 'demo');
  final start = b.churches[cid]!.timeZone.today(b.clock());
  // The features an admin sets up: a church link with a daily source, a
  // webhook, and two people moved from self-host who have not signed in.
  if (!showcase) {
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
  }
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
  if (!showcase) {
    final other = b.addChurch(w.otherChurch, id: 'living');
    b.pendingMembers[other] = {
      'old-demo': PendingMember(id: 'old-demo', name: w.demoPerson, email: 'demo@example.com'),
    };
  }
  b.setServices(cid, services);
  final people = demoMembers(memberCount, language);
  for (final (i, m) in people.indexed) {
    // The first 小組 has ten people, the second, just started, three.
    final group = !showcase || i >= 13 ? null : (i < 10 ? 'sg1' : 'sg2');
    b.addMember(cid, group == null ? m : m.copyWith(smallGroups: {group}));
  }
  if (showcase) {
    b.smallGroups[cid] = {
      for (final (i, name) in w.smallGroups.indexed)
        'sg${i + 1}': SmallGroupDetails(
          id: 'sg${i + 1}',
          name: name,
          service: services.first.id,
          weekday: i == 0 ? DateTime.friday : null,
        ),
    };
    b.churches[cid] = b.churches[cid]!.copyWith(attendanceSince: () => start.addDays(-56));
    // Reported every week but the last, which is left to fill in.
    final sinceFriday = (start.weekday - DateTime.friday) % 7;
    final lastFriday = start.addDays(-(sinceFriday == 0 ? 7 : sinceFriday));
    b.attendance[cid] = {
      'small:sg1': AttendanceRecord(
        days: {for (var week = 1; week < 8; week++) lastFriday.addDays(-7 * week): AttendanceDay.count(7 + week % 3)},
      ),
    };
  }
  // The website's church has arranged the next two weeks, the rest is
  // for its videos to arrange.
  for (final r in demoRosters(people, start, services, showcase ? start.addDays(14) : null)) {
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
    // The 通知列表 (#89), none of it read yet.
    final now = b.clock();
    final sunday = start.addDays((DateTime.sunday - start.weekday) % 7);
    for (final (id, kind, body, link, ago) in [
      (
        'put-on',
        NotificationKind.rosterChange,
        w.putOn(sunday.month, sunday.day, services[0].name, services[0].duties[2]),
        '/rosters/sunday/${sunday.key}',
        const Duration(hours: 2),
      ),
      ('asked', NotificationKind.joinRequest, w.joinRequested(w.newcomer), '/me/members', const Duration(hours: 26)),
      ('left', NotificationKind.memberLeft, w.memberLeft(w.moved[2]), '/me/members', const Duration(days: 3)),
    ]) {
      b.addNotification(
        admin.uid,
        NotificationItem(
          id: id,
          churchId: cid,
          kind: kind,
          title: w.church,
          body: body,
          link: link,
          at: now.subtract(ago),
        ),
      );
    }
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

/// A year of [services]' days from four weeks before [today], everyone
/// taking turns; days after [plannedUntil] have nobody on them yet.
List<Roster> demoRosters(List<Member> people, Day today, [List<Service> services = demoServices, Day? plannedUntil]) {
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
                if (pool.isEmpty || (plannedUntil != null && day.isAfter(plannedUntil))) return Duty(role: duty);
                // Turns start this week, each duty a week after the one
                // before, so the first in each pool serves soon.
                final turn = week - 4 - k;
                final picks = {
                  pool[turn % pool.length],
                  if (_pairs[s.id]?.contains(k) ?? false) pool[(turn + 1) % pool.length],
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
    required this.putOn,
    required this.memberLeft,
    required this.joinRequested,
    required this.services,
    required this.duties,
    required this.events,
    required this.smallGroups,
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

  /// What the backend's pushes say (functions/src/languages.ts), for the
  /// 通知列表: put on [duty] of [service] on [month]/[day]; [name] left; [name]
  /// asked to join.
  final String Function(int month, int day, String service, String duty) putOn;
  final String Function(String name) memberLeft;
  final String Function(String name) joinRequested;

  /// [demoServices]' names, duties and Sunday's events, in order.
  final List<String> services;
  final List<List<String>> duties;
  final List<String> events;

  /// The [showcase] church's 小組: the first meets on Fridays, the second
  /// has not said when yet.
  final List<String> smallGroups;

  /// The [i]th member's name; no two the same.
  final String Function(int i) name;

  static _DemoWords of(AppLanguage language) => switch (language) {
    AppLanguage.zhHant => _zhHant,
    AppLanguage.zhHans => _zhHans,
    AppLanguage.en => _en,
    AppLanguage.ja => _ja,
    AppLanguage.ko => _ko,
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
  putOn: (m, d, service, duty) => '你被排進 $m/$d $service：$duty',
  memberLeft: (name) => '「$name」退出了教會',
  joinRequested: (name) => '「$name」申請加入教會',
  services: [for (final s in demoServices) s.name],
  duties: [for (final s in demoServices) s.duties],
  events: [for (final e in demoServices.first.events) e.name],
  smallGroups: ['喜樂小組', '以馬內利小組'],
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
  putOn: (m, d, service, duty) => '你被排入 $m/$d $service：$duty',
  memberLeft: (name) => '“$name”退出了教会',
  joinRequested: (name) => '“$name”申请加入教会',
  services: ['主日崇拜', '青年崇拜', '祷告会'],
  duties: [
    ['领会', '敬拜主领', '司琴', '鼓手', '音控', '投影', '招待', '奉献'],
    ['领会', '敬拜主领', '吉他', '音控', '投影'],
    ['带领', '司琴'],
  ],
  events: ['圣餐', '浸礼', '特会'],
  smallGroups: ['喜乐小组', '以马内利小组'],
  name: _chineseNames(
    '陈林黄张李王吴刘蔡杨许郑谢郭洪曾邱廖赖徐周叶苏庄吕江何萧罗高潘简朱钟彭游詹胡施沈余赵卢梁颜柯孙魏翁戴范宋方',
    '志明美玲雅婷家豪俊杰淑芬怡君宗翰佳颖建宏欣怡冠宇思妤承恩惠如柏翰诗涵子轩心怡育诚文华',
  ),
);

const _enMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

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
  putOn: (m, d, service, duty) => 'You’re on ${_enMonths[m - 1]} $d $service: $duty',
  memberLeft: (name) => '$name left the church',
  joinRequested: (name) => '$name asked to join the church',
  services: ['Sunday Service', 'Youth Service', 'Prayer Meeting'],
  duties: [
    ['Host', 'Worship Leader', 'Piano', 'Drums', 'Sound', 'Slides', 'Usher', 'Offering'],
    ['Host', 'Worship Leader', 'Guitar', 'Sound', 'Slides'],
    ['Leader', 'Piano'],
  ],
  events: ['Communion', 'Baptism', 'Conference'],
  // Every first name with every surname once in 30 × 30.
  smallGroups: ['Joy Group', 'Emmanuel Group'],
  name: (i) => '${_enFirst[i % _enFirst.length]} ${_enLast[(i ~/ _enFirst.length + i) % _enLast.length]}',
);

const _jaLast = [
  '佐藤', '鈴木', '高橋', '田中', '伊藤', '渡辺', '山本', '中村', '小林', '加藤', //
  '吉田', '山田', '佐々木', '山口', '松本', '井上', '木村', '林', '清水', '山崎', //
  '森', '池田', '橋本', '阿部', '石川', '山下', '中島', '石井', '小川', '前田',
];
const _jaFirst = [
  '美咲', '大輔', '恵', '誠', '真理', '聡', '陽子', '健太', '由美', '翔', //
  '愛', '拓也', '優子', '直樹', '舞', '亮', '香織', '慎也', '彩', '和也', //
  '友美', '悠', '千尋', '光', '恵美', '信', '望', '結衣', '恵子', '創',
];

final _ja = _DemoWords(
  church: '恵みの教会',
  otherChurch: '生ける水教会',
  linkTitle: '主日献金',
  linkBody: 'オンライン献金・領収書の発行',
  verseTitle: '今日のみことば　詩編 23:1',
  verse: '主は羊飼い、わたしには何も欠けることがない。',
  moved: ['山田 花子', '佐藤 健', '鈴木 一郎', '高橋 葵'],
  demoPerson: 'デモ用メンバー',
  newcomer: '新しいメンバー',
  putOn: (m, d, service, duty) => '$m月$d日 $serviceの担当になりました：$duty',
  memberLeft: (name) => '$nameが教会を退出しました',
  joinRequested: (name) => '$nameが教会への参加を申請しました',
  services: ['主日礼拝', '青年礼拝', '祈祷会'],
  duties: [
    ['司会', '賛美リード', '奏楽', 'ドラム', '音響', 'スライド', '受付', '献金'],
    ['司会', '賛美リード', 'ギター', '音響', 'スライド'],
    ['司会', '奏楽'],
  ],
  events: ['聖餐式', '洗礼式', '特別集会'],
  // Every surname with every given name once in 30 × 30.
  smallGroups: ['喜びの小グループ', 'インマヌエル小グループ'],
  name: (i) => '${_jaLast[i % _jaLast.length]} ${_jaFirst[(i ~/ _jaLast.length + i) % _jaFirst.length]}',
);

const _koLast = ['김', '이', '박', '최', '정', '강', '조', '윤', '장', '임', '한', '오', '서', '신', '권', '황', '안', '송', '류', '홍'];
const _koFirst = [
  '민준', '서연', '지훈', '하은', '예준', '지민', '도윤', '수아', '시우', '서윤', //
  '주원', '지유', '하준', '채원', '은우', '다은', '건우', '소율', '현우', '예린', //
  '성민', '은혜', '요한', '사랑', '믿음', '소망', '다니엘', '한나', '지성', '유진',
];

final _ko = _DemoWords(
  church: '은혜교회',
  otherChurch: '생수교회',
  linkTitle: '주일 헌금',
  linkBody: '온라인 헌금, 기부금 영수증 신청',
  verseTitle: '오늘의 말씀　시편 23:1',
  verse: '여호와는 나의 목자시니 내게 부족함이 없으리로다',
  moved: ['김지영', '이준호', '박성민', '최유나'],
  demoPerson: '데모 멤버',
  newcomer: '새 멤버',
  putOn: (m, d, service, duty) => '$m월 $d일 $service 봉사에 배정됐어요: $duty',
  memberLeft: (name) => '$name 님이 교회를 나갔어요',
  joinRequested: (name) => '$name 님이 교회 가입을 신청했어요',
  services: ['주일예배', '청년예배', '기도회'],
  duties: [
    ['사회', '찬양 인도', '반주', '드럼', '음향', '자막', '안내', '헌금'],
    ['사회', '찬양 인도', '기타', '음향', '자막'],
    ['인도', '반주'],
  ],
  events: ['성찬', '세례', '특별집회'],
  // No two the same for up to 160 people: 21 × 1–7 is never a multiple of 30.
  smallGroups: ['기쁨 소그룹', '임마누엘 소그룹'],
  name: (i) => _koLast[i % _koLast.length] + _koFirst[(i ~/ _koLast.length + i) % _koFirst.length],
);
