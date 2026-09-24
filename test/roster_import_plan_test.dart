import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/event_option.dart';
import 'package:church_staff_pwa/features/roster/domain/entities/service_roster.dart';
import 'package:church_staff_pwa/features/roster/domain/roster_import.dart';

// 名字都是虛構的（repo 是公開的）。

const _type = ServiceType.youth;

User _user(String id, String name, List<String> ministries) => User(
  id: id,
  name: name,
  email: '$id@example.com',
  username: id,
  role: UserRole.staff,
  zones: [UserZoneInfo(serviceType: _type, ministries: ministries)],
);

ServiceRoster _roster(
  String date, {
  List<RosterEntry> duties = const [],
  List<String> events = const [],
  Map<String, int> colors = const {},
}) => ServiceRoster(
  id: 'r-$date',
  date: DateTime.parse(date),
  type: _type,
  serviceName: '青崇',
  duties: duties,
  specialEvents: events,
  customEventColors: colors,
);

final _users = [
  _user('u1', '林書安', ['敬拜', '司琴']),
  _user('u2', '郭子謙', ['司琴']),
];

RosterImportPlan _plan(
  Object json, {
  List<ServiceRoster>? rosters,
  Map<ServiceType, List<String>>? templates,
  bool templatesLoaded = true,
  List<EventOption> eventOptions = const [],
}) => planRosterImport(
  input: jsonEncode(json),
  type: _type,
  users: _users,
  rosters: rosters ?? [_roster('2026-10-03')],
  templates: templatesLoaded
      ? templates ??
            {
              _type: ['司琴', '敬拜'],
            }
      : null,
  eventOptions: eventOptions,
);

RosterImportReady _ready(RosterImportPlan plan) {
  if (plan is RosterImportReady) return plan;
  fail('被擋下了：${(plan as RosterImportRejected).message}');
}

String _rejection(RosterImportPlan plan) {
  if (plan is RosterImportRejected) return plan.message;
  fail('應該被擋下');
}

void main() {
  group('擋下整份匯入', () {
    test('JSON 壞掉時直接回解析錯誤，不去對服事表', () {
      expect(
        _rejection(
          planRosterImport(
            input: '{',
            type: _type,
            users: _users,
            rosters: const [],
            templates: {},
            eventOptions: const [],
          ),
        ),
        'JSON 格式錯誤',
      );
    });

    test('樣板還沒載入時，帶 duties 的匯入不能進行', () {
      final message = _rejection(
        _plan([
          {
            'date': '2026-10-03',
            'duties': [
              {
                'role': '敬拜',
                'people': ['林書安'],
              },
            ],
          },
        ], templatesLoaded: false),
      );
      expect(message, contains('尚未載入'));
    });

    test('這個崇拜沒有樣板時擋下，並說要找管理員', () {
      final message = _rejection(
        _plan(
          [
            {
              'date': '2026-10-03',
              'duties': [
                {
                  'role': '敬拜',
                  'people': ['林書安'],
                },
              ],
            },
          ],
          templates: {
            ServiceType.children: ['司琴'],
          },
        ),
      );
      expect(message, contains(_type.label));
      expect(message, contains('請管理員'));
    });

    test('只帶 events 的匯入不需要樣板', () {
      final plan = _ready(
        _plan([
          {
            'date': '2026-10-03',
            'events': ['聖餐'],
          },
        ], templatesLoaded: false),
      );
      expect(plan.updates.single.specialEvents, ['聖餐']);
    });
  });

  group('對到現有服事表', () {
    test('服事照樣板排序，名字換成全名並帶上 uid', () {
      final plan = _ready(
        _plan([
          {
            'date': '2026-10-03',
            'duties': [
              {
                'role': '敬拜',
                'people': ['書安'],
              },
              {
                'role': '司琴',
                'people': ['郭子謙'],
              },
            ],
          },
        ]),
      );
      final duties = plan.updates.single.duties;
      expect(duties.map((d) => d.role), ['司琴', '敬拜']);
      expect(duties[1].people, ['林書安']);
      expect(duties[1].personIdsByName, {'林書安': 'u1'});
    });

    test('找不到的日期列進 missingDates，不寫', () {
      final plan = _ready(
        _plan([
          {
            'date': '2026-10-03',
            'events': ['聖餐'],
          },
          {
            'date': '2026-10-10',
            'events': ['聖餐'],
          },
        ]),
      );
      expect(plan.updates.map((r) => r.id), ['r-2026-10-03']);
      expect(plan.summary.missingDates, ['2026-10-10']);
      expect(plan.summary.updated, 1);
    });

    test('只帶 duties 的那天，活動與顏色原樣保留', () {
      final existing = _roster(
        '2026-10-03',
        events: ['洗禮'],
        colors: {'洗禮': 0xFF123456},
      );
      final plan = _ready(
        _plan(
          [
            {
              'date': '2026-10-03',
              'duties': [
                {
                  'role': '敬拜',
                  'people': ['林書安'],
                },
              ],
            },
          ],
          rosters: [existing],
        ),
      );
      final updated = plan.updates.single;
      expect(updated.specialEvents, ['洗禮']);
      expect(updated.customEventColors, {'洗禮': 0xFF123456});
    });

    test('只帶 events 的那天，服事原樣保留；活動與顏色整批換掉', () {
      final duty = RosterEntry(role: '敬拜', people: const ['林書安']);
      final existing = _roster(
        '2026-10-03',
        duties: [duty],
        events: ['洗禮'],
        colors: {'洗禮': 0xFF123456},
      );
      final plan = _ready(
        _plan(
          [
            {
              'date': '2026-10-03',
              'events': ['聖餐'],
            },
          ],
          rosters: [existing],
        ),
      );
      final updated = plan.updates.single;
      expect(updated.duties, [duty]);
      expect(updated.specialEvents, ['聖餐']);
      expect(updated.customEventColors, isEmpty);
    });
  });

  group('報告', () {
    test('排到沒設定的服事：每個人都在 details 裡，服事排序過', () {
      final plan = _ready(
        _plan([
          {
            'date': '2026-10-03',
            'duties': [
              {
                'role': '敬拜',
                'people': ['郭子謙'],
              },
              {
                'role': '音控',
                'people': ['郭子謙'],
              },
            ],
          },
        ]),
      );
      expect(plan.summary.roleMismatchDetails, {
        '郭子謙': ['敬拜', '音控'],
      });
    });

    test('名單上沒有的人照寫進服事表，也列進報告', () {
      final plan = _ready(
        _plan([
          {
            'date': '2026-10-03',
            'duties': [
              {
                'role': '敬拜',
                'people': ['何宥廷'],
              },
            ],
          },
        ]),
      );
      expect(plan.updates.single.duties.single.people, ['何宥廷']);
      expect(plan.summary.notInRosterNames, ['何宥廷']);
      expect(plan.summary.hasIssues, isTrue);
    });

    test('活動清單裡沒有的活動列進 notInEventCatalog', () {
      final plan = _ready(
        _plan(
          [
            {
              'date': '2026-10-03',
              'events': ['聖餐', '感恩聚餐'],
            },
          ],
          eventOptions: const [EventOption(name: '聖餐', color: 0xFFAAAAAA)],
        ),
      );
      expect(plan.summary.notInEventCatalog, ['感恩聚餐']);
    });
  });

  test('外來講員列進報告，但不算問題', () {
    final plan = _ready(
      _plan(
        [
          {
            'date': '2026-10-03',
            'duties': [
              {
                'role': '信息',
                'people': ['溫以諾'],
              },
            ],
          },
        ],
        templates: {
          _type: ['信息'],
        },
      ),
    );
    expect(plan.updates.single.duties.single.people, ['溫以諾']);
    expect(plan.summary.guestSpeakerNames, ['溫以諾']);
    expect(plan.summary.notInRosterNames, isEmpty);
    expect(plan.summary.hasIssues, isFalse);
  });

  test('app 裡只有 roster_import.dart 直接用 parser', () {
    // 直接呼叫 parseRosterImportJson 會繞過樣板檢查、依日期合併與報告 ——
    // 以前這段編排寫在畫面裡，bug 都出在那裡。
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            !file.path.endsWith('roster_import.dart') &&
            !file.path.endsWith('roster_import_parser.dart') &&
            file.readAsStringSync().contains('roster_import_parser.dart'))
          file.path,
    ];
    expect(offenders, isEmpty);
  });

  group('同工排序', () {
    test('照圖片上的先後學，只帶活動的日期不算', () {
      final ready = _ready(
        _plan(
          [
            {
              'date': '2026-10-03',
              'duties': [
                {
                  'role': '司琴',
                  'people': ['郭子謙', '林書安'],
                },
              ],
            },
            // 只帶活動：那天的服事還是舊的（林書安在前），不能拿來學。
            {
              'date': '2026-10-10',
              'events': ['聖餐'],
            },
          ],
          rosters: [
            _roster('2026-10-03'),
            _roster(
              '2026-10-10',
              duties: [
                RosterEntry(role: '司琴', people: ['林書安', '郭子謙']),
              ],
            ),
          ],
        ),
      );
      expect(ready.staffOrder.rankingOf('司琴'), ['郭子謙', '林書安']);
    });

    test('名單外的人不進排序', () {
      final ready = _ready(
        _plan([
          {
            'date': '2026-10-03',
            'duties': [
              {
                'role': '司琴',
                'people': ['外請甲', '郭子謙', '林書安'],
              },
            ],
          },
        ]),
      );
      expect(ready.staffOrder.rankingOf('司琴'), ['郭子謙', '林書安']);
    });

    test('只帶活動的匯入沒有東西可學', () {
      final ready = _ready(
        _plan([
          {
            'date': '2026-10-03',
            'events': ['聖餐'],
          },
        ]),
      );
      expect(ready.staffOrder.isEmpty, isTrue);
    });
  });

  test('rosterDateKey 補零', () {
    expect(rosterDateKey(DateTime(2026, 1, 4)), '2026-01-04');
  });
}
