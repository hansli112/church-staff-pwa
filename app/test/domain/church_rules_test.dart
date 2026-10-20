import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/core/languages.dart';
import 'package:martha/data/firebase/codec.dart';
import 'package:martha/data/memory/memory_backend.dart';
import 'package:martha/domain/day.dart';
import 'package:martha/domain/models.dart';

/// The rows functions/test/churchRules.test.ts runs too: both sides must agree.
final _rules = jsonDecode(File('../testdata/church_rules.json').readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> _rows(String name) => (_rules[name] as List).cast<Map<String, dynamic>>();

List<String> _strings(Object? v) => (v as List).cast<String>();

/// A member with the fields of row [f]: role, groups, 身分 and what they lead.
Member _member(String uid, Map<String, dynamic> f) => Member(
  uid: uid,
  name: uid,
  role: Role.values.byName(f['role'] as String? ?? 'staff'),
  groups: {for (final g in _strings(f['groups'] ?? const [])) ?Group.byId(g)},
  identities: [
    for (final i in (f['identities'] as List?) ?? const []) ?Identity.fromJson(i),
    for (final t in _strings(f['leadTypes'] ?? const [])) ServiceLead(t),
    for (final m in _strings(f['leadMinistries'] ?? const [])) MinistryLead(m),
    for (final g in _strings(f['leadSmallGroups'] ?? const [])) SmallGroupLead(g),
  ],
);

void main() {
  test("a new church starts with the default services, in its maker's language", () {
    final rules = _rules['defaultServices'] as Map<String, dynamic>;
    expect(rules.keys, [for (final l in AppLanguage.values) l.tag]);
    for (final l in AppLanguage.values) {
      expect([for (final s in defaultServices[l]!) serviceToJson(s)], rules[l.tag], reason: l.tag);
    }
  });

  group('dutyRename', () {
    for (final r in _rows('dutyRename')) {
      test(r['why'] as String, () {
        expect(
          validDutyRename(
            before: _strings(r['before']),
            after: _strings(r['after']),
            from: r['from'] as String,
            to: r['to'] as String,
          ),
          r['ok'],
        );
      });
    }
  });

  group('rosterIdentity', () {
    for (final r in _rows('rosterIdentity')) {
      test(r['why'] as String, () {
        final roster = Roster(
          type: 'sunday',
          day: Day(2026, 10, 18),
          duties: [
            for (final d in (r['duties'] as List).cast<Map<String, dynamic>>())
              Duty(
                role: d['role'] as String,
                people: _strings(d['people']),
                uids: (d['uids'] as Map).cast<String, String>(),
              ),
          ],
        );
        expect(roster.dutiesOf(uid: r['uid'] as String), r['holds']);
      });
    }
  });

  group('movedMembers', () {
    for (final r in _rows('movedMembers')) {
      test(r['why'] as String, () {
        final m = movedMember(id: 'old', name: '李美玉', email: '', source: r['in'] as Map<String, dynamic>);
        final out = r['out'] as Map<String, dynamic>;
        expect(m.role.name, out['role']);
        expect([for (final g in m.groups) g.id], out['groups']);
        expect([
          for (final z in m.zones) {'serviceType': z.serviceType, 'duties': z.duties, 'smallGroups': z.smallGroups},
        ], out['zones']);
        expect([for (final k in m.mutedNotifications) k.name], out['muted']);
      });
    }
  });

  group('rosterEditing', () {
    for (final r in _rows('rosterEditing')) {
      test(r['why'] as String, () {
        final member = Member(
          uid: 'u',
          name: '美玉',
          role: Role.values.byName(r['role'] as String),
          groups: {for (final g in _strings(r['groups'])) Group.values.firstWhere((x) => x.id == g)},
          zones: [for (final t in _strings(r['zoneTypes'])) Zone(serviceType: t)],
          identities: [
            for (final t in _strings(r['leadTypes'])) ServiceLead(t),
            for (final m in _strings(r['leadMinistries'])) MinistryLead(m),
          ],
        );
        final roster = r['roster'] as String;
        expect(
          roster == 'event' ? member.canEditEventRoster(r['eventGroup'] as String?) : member.canEditRosters(roster),
          r['may'],
        );
      });
    }
  });

  group('ledDuties', () {
    Roster? day(Object? duties, Object? events) => duties == null
        ? null
        : Roster(
            type: 'sunday',
            day: Day(2030, 10, 6),
            duties: [
              for (final d in duties as List) Duty(role: d['role'] as String, people: _strings(d['people'])),
            ],
            events: [
              for (final e in (events as List?) ?? const [])
                EventTag(name: e['name'] as String, color: e['color'] as int),
            ],
          );
    for (final r in _rows('ledDuties')) {
      test(r['why'] as String, () {
        expect(
          mayChangeLedDuties(
            _strings(r['roles']).toSet(),
            day(r['before'], r['beforeEvents']),
            day(r['after'], r['afterEvents']),
          ),
          r['may'],
        );
      });
    }
  });

  group('groupMembership', () {
    const member = _member;
    for (final r in _rows('groupMembership')) {
      test(r['why'] as String, () {
        final g = r['group'] as Map<String, dynamic>;
        final ChurchGroup group = g['smallGroup'] is String
            ? SmallGroup(g['smallGroup'] as String)
            : g['service'] is String
            ? ServiceGroup(g['service'] as String)
            : MinistryGroup(g['ministry'] as String);
        expect(
          member(
            'caller',
            r['caller'] as Map<String, dynamic>,
          ).mayMove(member('target', r['target'] as Map<String, dynamic>), group, service: g['service'] as String?),
          r['may'],
        );
      });
    }
  });

  group('eventWriting', () {
    for (final r in _rows('eventWriting')) {
      test(r['why'] as String, () {
        final m = _member('u', r['member'] as Map<String, dynamic>);
        expect(m.mayWriteEvent(r['before'] as String?, r['after'] as String?), r['may']);
      });
    }
  });

  group('smallGroupEditing', () {
    for (final r in _rows('smallGroupEditing')) {
      test(r['why'] as String, () {
        final m = _member('u', r['member'] as Map<String, dynamic>);
        expect(m.mayEditSmallGroup(r['before'] as String?, r['after'] as String?), r['may']);
      });
    }
  });

  group('attendanceAccess', () {
    for (final r in _rows('attendanceAccess')) {
      test(r['why'] as String, () {
        final m = _member('u', r['member'] as Map<String, dynamic>);
        final key = r['group'] as String;
        final service = r['smallGroupService'] as String?;
        expect(m.writesAttendance(key, smallGroupService: service), r['writes'], reason: 'writes');
        expect(m.readsAttendance(key, smallGroupService: service), r['reads'], reason: 'reads');
      });
    }
  });

  group('attendanceDue', () {
    for (final r in _rows('attendanceDue')) {
      test(r['why'] as String, () {
        final meets = r['meets'] as Map<String, dynamic>;
        final pause = r['pause'] as Map<String, dynamic>?;
        expect(
          attendanceDue(
            Meets(
              weekday: meets['weekday'] as int?,
              roster: meets['roster'] as bool?,
              every: meets['every'] as int? ?? 1,
              startsOn: Day.tryParse(meets['startsOn'] as String?),
            ),
            since: Day.parse(r['since'] as String),
            pause: pause == null
                ? null
                : AttendancePause(from: Day.parse(pause['from'] as String), until: Day.parse(pause['until'] as String)),
            day: Day.parse(r['day'] as String),
          ),
          r['due'],
        );
      });
    }
  });
}
