import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';
import 'package:martha/domain/staff_order.dart';

const sundayService = Service(
  id: 'sunday',
  name: '主日崇拜',
  weekday: DateTime.sunday,
  duties: ['司會', '司琴', '招待'],
  events: [EventTag(name: '聖餐', color: 0)],
);
const youthService = Service(id: 'youth', name: '青年崇拜', weekday: DateTime.saturday, duties: ['司會']);

const pastor = Member(uid: 'pastor', name: '王牧師', role: Role.admin);
const editor = Member(
  uid: 'editor',
  name: '林同工',
  groups: {Group.rosterEditors},
  zones: [
    Zone(serviceType: 'sunday', duties: ['司會']),
  ],
);
const staffMei = Member(
  uid: 'mei',
  name: '李美玉',
  zones: [
    Zone(serviceType: 'sunday', duties: ['司琴', '招待']),
  ],
);
const staffHao = Member(
  uid: 'hao',
  name: '陳志豪',
  zones: [
    Zone(serviceType: 'sunday', duties: ['招待']),
  ],
);
const john = Member(uid: 'john', name: 'John Chen');

/// A church with two services, five members and one saved Sunday.
/// Signs in as [as].
MemoryBackend seededChurch({Member as = pastor, List<Member> extra = const []}) {
  final b = MemoryBackend();
  final cid = b.addChurch('恩典堂', id: 'grace');
  b.setServices(cid, const [sundayService, youthService]);
  for (final m in [pastor, editor, staffMei, staffHao, john, ...extra]) {
    b.addMember(cid, m);
  }
  b.rosters[cid]![Roster.idFor('sunday', Day(2026, 10, 4))] = Roster(
    type: 'sunday',
    day: Day(2026, 10, 4),
    events: const [EventTag(name: '聖餐', color: 0)],
    duties: const [
      Duty(role: '司會', people: ['林同工'], uids: {'林同工': 'editor'}),
      Duty(role: '司琴', people: ['李美玉'], uids: {'李美玉': 'mei'}),
      Duty(role: '招待', people: ['陳志豪', '李美玉'], uids: {'陳志豪': 'hao', '李美玉': 'mei'}),
    ],
  );
  b.rosters[cid]![Roster.idFor('sunday', Day(2026, 10, 11))] = Roster(
    type: 'sunday',
    day: Day(2026, 10, 11),
    duties: const [
      Duty(role: '司會', people: ['王牧師'], uids: {'王牧師': 'pastor'}),
      Duty(role: '司琴', people: []),
      Duty(role: '招待', people: ['李美玉'], uids: {'李美玉': 'mei'}),
    ],
  );
  b.staffOrders[cid]!['sunday'] = StaffOrder({
    '招待': ['陳志豪', '李美玉'],
  });
  b.auth.signInAs('${as.uid}@example.com', uid: as.uid, name: as.name);
  b.users[as.uid] = UserProfile(uid: as.uid, name: as.name, email: '${as.uid}@example.com');
  b.notify();
  return b;
}

Roster savedDay(MemoryBackend b, int day) => b.rosters['grace']![Roster.idFor('sunday', Day(2026, 10, day))]!;

List<String> peopleOn(MemoryBackend b, int day, String role) =>
    savedDay(b, day).duties.firstWhere((d) => d.role == role).people;
