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
        expect(roster == 'event' ? member.canEditEventRosters : member.canEditRosters(roster), r['may']);
      });
    }
  });
}
