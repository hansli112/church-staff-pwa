import 'package:flutter_test/flutter_test.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/getting_started.dart';
import 'package:martha/domain/models.dart';

const sunday = Service(id: 'sunday', name: '主日崇拜', weekday: DateTime.sunday, duties: ['司會', '司琴']);
const youth = Service(id: 'youth', name: '青年崇拜', weekday: DateTime.saturday, duties: ['司會']);
const closed = Service(id: 'closed', name: '晚堂', weekday: DateTime.sunday, enabled: false);
const services = ServiceSettings(services: [sunday, youth, closed]);
const worship = Ministry(id: 'worship', name: '敬拜團', duties: [MinistryDuty('youth', '司琴')]);
const care = Ministry(id: 'care', name: '關懷事工');
const joy = SmallGroupDetails(id: 'joy', name: '喜樂小組', service: 'sunday');

Roster day(String type, Map<String, List<String>> people) => Roster(
  type: type,
  day: Day(2026, 11, 1),
  duties: [for (final MapEntry(:key, :value) in people.entries) Duty(role: key, people: value)],
);

List<GettingStarted> of(
  Member me, {
  List<Member> others = const [],
  int pending = 0,
  List<Roster> rosters = const [],
  bool attendanceOn = false,
  List<SmallGroupDetails> smallGroups = const [joy],
  bool invited = false,
  bool servicesSeen = false,
}) => gettingStarted(
  me: me,
  members: [me, ...others],
  pending: pending,
  services: services,
  ministries: const MinistrySettings(ministries: [worship, care]),
  smallGroups: smallGroups,
  rosters: rosters,
  attendanceOn: attendanceOn,
  invited: invited,
  servicesSeen: servicesSeen,
);

/// The steps of the one 身分 shown, as where each is.
List<(StartStep, StartState)> states(List<GettingStarted> starts) => [
  for (final s in starts.single.steps) (s.step, s.state),
];

/// The steps of the one 身分 shown that are not done yet.
List<({StartStep step, ChurchGroup? group})> left(List<GettingStarted> starts) => [
  for (final s in starts.single.steps)
    if (s.state != StartState.done) (step: s.step, group: s.group),
];

void main() {
  const admin = Member(uid: 'a', name: '王牧師', role: Role.admin);
  const staff = Member(uid: 's', name: '李美玉');

  test('a new church: its admin sets the services, invites, puts them in, and arranges, in that order', () {
    const todo = StartState.todo, done = StartState.done;
    expect(states(of(admin, smallGroups: const [])), [
      (StartStep.services, todo),
      (StartStep.invite, todo),
      (StartStep.addStaff, StartState.locked),
      (StartStep.smallGroups, todo),
      (StartStep.arrange, todo),
    ], reason: 'nobody to put in a service before someone joins');
    expect(states(of(admin))[3], (StartStep.smallGroups, done));
    expect(of(admin).single.next?.step, StartStep.services);

    final seen = of(admin, servicesSeen: true, invited: true);
    expect(states(seen).take(2), [(StartStep.services, done), (StartStep.invite, StartState.waiting)]);
    expect(seen.single.next?.step, StartStep.arrange, reason: 'waiting on invites, 小組 optional');
    expect(seen.single.after(seen.single.steps.first)?.step, StartStep.arrange);

    final joined = of(admin, others: [staff], servicesSeen: true);
    expect(states(joined).skip(1).first, (StartStep.invite, done));
    expect(joined.single.next, (step: StartStep.addStaff, group: const ServiceGroup('sunday'), state: todo));
    expect(
      of(admin, pending: 1, servicesSeen: true).single.next?.step,
      StartStep.addStaff,
      reason: 'someone moved from self-host counts as joined',
    );

    const inSunday = Member(
      uid: 'h',
      name: '陳志豪',
      zones: [Zone(serviceType: 'sunday')],
    );
    expect(
      of(admin, others: [inSunday], servicesSeen: true).single.steps[2],
      (step: StartStep.addStaff, group: const ServiceGroup('youth'), state: done),
      reason: 'someone in any service will do; it opens one with nobody yet',
    );

    expect(
      states(
        of(
          admin,
          rosters: [
            day('sunday', {'司會': []}),
          ],
        ),
      ).last,
      (StartStep.arrange, todo),
      reason: 'a day with nobody on it is not arranged yet',
    );
    expect(
      of(
        admin,
        others: [inSunday],
        servicesSeen: true,
        smallGroups: const [],
        rosters: [
          day('sunday', {
            '司會': ['王牧師'],
          }),
        ],
      ),
      isEmpty,
      reason: 'all done but the optional 小組',
    );
    expect(
      of(
        admin,
        others: [staff],
        rosters: [
          day('sunday', {
            '司會': ['王牧師'],
          }),
        ],
      ),
      isEmpty,
      reason: 'a church with days arranged has set its services and its 同工 (a church long in use)',
    );
  });

  test('an admin is shown only what an admin does: the rest is part of it', () {
    final pastor = admin.withIdentities(const [AdminIdentity(), ServiceLead('sunday'), OfficeIdentity()]);
    expect(of(pastor).map((g) => g.identity), [const AdminIdentity()]);
    final wholeChurch = admin.withIdentities(const [PastorIdentity(null)]);
    expect(of(wholeChurch).map((g) => g.identity), [const PastorIdentity(null)]);
  });

  test("a service's 負責人 adds its 同工, then plans its weeks", () {
    final lead = staff.withIdentities(const [ServiceLead('sunday')]);
    const inSunday = Member(
      uid: 'h',
      name: '陳志豪',
      zones: [Zone(serviceType: 'sunday')],
    );
    const inYouth = Member(
      uid: 'y',
      name: 'John',
      zones: [Zone(serviceType: 'youth')],
    );
    expect(of(lead, others: [admin, inYouth]), [
      const GettingStarted(ServiceLead('sunday'), [
        (step: StartStep.addStaff, group: ServiceGroup('sunday'), state: StartState.todo),
        (step: StartStep.planWeeks, group: ServiceGroup('sunday'), state: StartState.todo),
      ]),
    ]);
    expect(
      left(
        of(
          lead,
          others: [inSunday],
          rosters: [
            day('youth', {
              '司會': ['John'],
            }),
          ],
        ),
      ),
      [(step: StartStep.planWeeks, group: const ServiceGroup('sunday'))],
      reason: 'another service arranged is not this one',
    );
    expect(
      of(
        lead,
        others: [inSunday],
        rosters: [
          day('sunday', {
            '司琴': ['陳志豪'],
          }),
        ],
      ),
      isEmpty,
    );
  });

  test('a 牧者 of some services does it for each one still held, open or not', () {
    final pastor = staff.withIdentities(const [
      PastorIdentity(['sunday', 'youth', 'closed', 'gone']),
    ]);
    expect(
      left(
        of(
          pastor,
          rosters: [
            day('youth', {
              '司會': ['李美玉'],
            }),
          ],
        ),
      ),
      [
        (step: StartStep.addStaff, group: const ServiceGroup('sunday')),
        (step: StartStep.planWeeks, group: const ServiceGroup('sunday')),
        (step: StartStep.addStaff, group: const ServiceGroup('youth')),
      ],
      reason: 'a disabled service and one no longer there are left out',
    );
  });

  test("a 事工's 負責人 puts someone on its duties' lists and plans a service where it leads a duty", () {
    final lead = staff.withIdentities(const [MinistryLead('worship')]);
    // On 司琴's list: one of 敬拜團's (#94).
    const player = Member(
      uid: 'p',
      name: '彈琴的',
      zones: [
        Zone(serviceType: 'youth', duties: ['司琴']),
      ],
    );
    expect(left(of(lead)), [
      (step: StartStep.addStaff, group: const MinistryGroup('worship')),
      (step: StartStep.planWeeks, group: const ServiceGroup('youth')),
    ]);
    expect(
      left(
        of(
          lead,
          others: [player],
          rosters: [
            day('youth', {
              '司會': ['李美玉'],
            }),
          ],
        ),
      ),
      [(step: StartStep.planWeeks, group: const ServiceGroup('youth'))],
      reason: 'a duty it does not lead is not its arranging',
    );
    expect(
      of(
        lead,
        others: [player],
        rosters: [
          day('youth', {
            '司琴': ['彈琴的'],
          }),
        ],
      ),
      isEmpty,
    );

    final careLead = staff.withIdentities(const [MinistryLead('care'), MinistryLead('gone')]);
    expect(left(of(careLead)), [
      (step: StartStep.addStaff, group: const MinistryGroup('care')),
    ], reason: 'one linking no duty has nothing to arrange; one deleted, nothing at all');
  });

  test('a 小組長 adds its 同工, and says when it meets while 回報人數 is on', () {
    final leader = staff.withIdentities(const [SmallGroupLead('joy')]);
    expect(left(of(leader)), [(step: StartStep.addStaff, group: const SmallGroup('joy'))]);
    expect(left(of(leader, attendanceOn: true)).map((s) => s.step), [StartStep.addStaff, StartStep.meets]);
    expect(
      left(of(leader, attendanceOn: true, smallGroups: [joy.copyWith(weekday: () => DateTime.friday)])),
      [(step: StartStep.addStaff, group: const SmallGroup('joy'))],
    );
    expect(of(leader, smallGroups: const []), isEmpty, reason: 'a 小組 closed');
  });

  test('行政 arranges; a plain 同工 has nothing to start', () {
    final office = staff.withIdentities(const [OfficeIdentity()]);
    expect(of(office), [
      const GettingStarted(OfficeIdentity(), [(step: StartStep.arrange, group: null, state: StartState.todo)]),
    ]);
    expect(
      of(
        office,
        rosters: [
          day('sunday', {
            '司會': ['王牧師'],
          }),
        ],
      ),
      isEmpty,
    );
    expect(of(staff), isEmpty);
  });
}
