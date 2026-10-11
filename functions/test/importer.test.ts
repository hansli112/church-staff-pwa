import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { buildImport, mapMember, mapRoster, mapServices, paletteIndex, rosterDateKey } from '../src/importer.js';

describe('self-host import mapping', () => {
  test('members: ministries become duties, small groups are preserved and unknown permission groups are dropped', () => {
    const m = mapMember(
      'u1',
      {
        name: ' 王大明 ',
        email: 'a@example.com',
        username: 'daming',
        role: 'leader',
        groups: ['roster-editors', 'something-else'],
        zones: [
          { serviceType: 'sundayService', smallGroups: ['小組A'], ministries: ['司琴', '招待'] },
          { serviceType: 'youth', ministries: [] },
          { bad: true },
        ],
      },
      null,
    );
    assert.equal(m.name, '王大明');
    assert.equal(m.role, 'leader');
    assert.deepEqual(m.groups, ['roster-editors']);
    assert.deepEqual(m.zones, [
      { serviceType: 'sundayService', duties: ['司琴', '招待'], smallGroups: ['小組A'] },
      { serviceType: 'youth', duties: [], smallGroups: [] },
    ]);
    assert.deepEqual(m.zoneTypes, ['sundayService', 'youth']);
  });

  test('services merge templates and event options; ids keep history', () => {
    const s = mapServices(
      {
        services: [{ id: 'sundayService', label: '主日', name: '主日崇拜', weekday: 7, enabled: true }],
        ids: ['sundayService', 'oldService'],
      },
      { sundayService: ['司會', '司琴'] },
      { sundayService: [{ name: '聖餐', color: 0xffdc2626 }, { name: ' ', color: 0 }] },
    );
    assert.deepEqual(s.services[0].duties, ['司會', '司琴']);
    assert.deepEqual(s.services[0].events, [{ name: '聖餐', color: 0 }]);
    assert.deepEqual(s.ids, ['sundayService', 'oldService']);
  });

  test('rosters: 待定 becomes empty, uids only for listed names, colours mapped', () => {
    const r = mapRoster(
      '20261004_sundayService',
      {
        type: 'sundayService',
        duties: [
          { role: '司會', people: ['王大明'], personIdsByName: { 王大明: 'u1', 離開的人: 'u9' } },
          { role: '司琴', people: ['待定'] },
        ],
        specialEvents: ['聖餐', '特會'],
        customEventColors: { 特會: 0xff7c3aed },
      },
      new Map([['sundayService/聖餐', 0]]),
    )!;
    assert.equal(r.id, '2026-10-04_sundayService');
    assert.deepEqual(r.data.duties[0].uids, { 王大明: 'u1' });
    assert.deepEqual(r.data.duties[1].people, []);
    assert.deepEqual(r.data.events, [
      { name: '聖餐', color: 0 },
      { name: '特會', color: 5 },
    ]);
  });

  test('roster dates come from dateKey, then the ID, then the timestamp in UTC+8', () => {
    assert.equal(rosterDateKey('x', { dateKey: '2026-10-04' }), '2026-10-04');
    assert.equal(rosterDateKey('20261011_youth', {}), '2026-10-11');
    const date = { toDate: () => new Date('2026-10-17T16:30:00Z') }; // 00:30 on the 18th in Taipei
    assert.equal(rosterDateKey('random', { date }), '2026-10-18');
    assert.equal(rosterDateKey('random', {}), null);
  });

  test('palette by hue', () => {
    assert.equal(paletteIndex(0xffdc2626), 0);
    assert.equal(paletteIndex(0xffea580c), 1);
    assert.equal(paletteIndex(0xffd97706), 2);
    assert.equal(paletteIndex(0xff16a34a), 3);
    assert.equal(paletteIndex(0xff2563eb), 4);
    assert.equal(paletteIndex(0xff7c3aed), 5);
    assert.equal(paletteIndex(0xff7f8c8d), 4, 'grey falls back to blue');
  });
});

describe('inferServices', () => {
  test('rebuilds the list from templates and rosters', async () => {
    const { inferServices } = await import('../src/importer.js');
    const s = inferServices({ sundayService: ['司會'], youth: ['敬拜'] }, {}, [
      { id: '20261004_sundayService', data: { type: 'sundayService', serviceName: '主日崇拜' } },
      { id: '20261011_sundayService', data: { type: 'sundayService', serviceName: '主日崇拜' } },
      { id: '20261003_youth', data: { type: 'youth', serviceName: '青崇' } },
    ]);
    assert.deepEqual(
      s.services.map((x) => [x.id, x.name, x.weekday, x.duties]),
      [
        ['sundayService', '主日崇拜', 7, ['司會']],
        ['youth', '青崇', 6, ['敬拜']],
      ],
    );
  });
});

describe('buildImport', () => {
  const snapshot = {
    users: [
      { id: 'u1', data: { name: '王大明', email: 'a@example.com', role: 'admin', zones: [{ serviceType: 'sunday', smallGroups: ['A'], ministries: ['司會'] }] } },
      { id: 'u2', data: { name: '', email: 'b@example.com', role: 'staff' } },
    ],
    settings: [
      { id: 'services', data: { services: [{ id: 'sunday', name: '主日崇拜', weekday: 7 }], ids: ['sunday'] } },
      { id: 'roster_templates', data: { sunday: ['司會', '司琴'] } },
      { id: 'event_options', data: { sunday: [{ name: '聖餐', color: 0xffdc2626 }] } },
      { id: 'devotional', data: { url: 'x' } },
    ],
    rosters: [
      { id: '20261004_sunday', data: { type: 'sunday', duties: [{ role: '司會', people: ['王大明'], personIdsByName: { 王大明: 'u1' } }], specialEvents: ['聖餐'] } },
      { id: 'broken', data: { duties: [] } },
    ],
    staffOrders: [{ id: 'sunday', data: { roles: { 司會: ['王大明'] } } }],
  };

  test('maps a whole snapshot into the hosted documents', () => {
    const out = buildImport(snapshot, 'JOINED');
    assert.deepEqual(out.members.map((m) => [m.uid, m.role, m.joinedAt]), [
      ['u1', 'admin', 'JOINED'],
      ['u2', 'staff', 'JOINED'],
    ]);
    assert.deepEqual(out.services.services[0].duties, ['司會', '司琴']);
    assert.deepEqual(out.rosters, [
      {
        id: '2026-10-04_sunday',
        data: {
          type: 'sunday',
          dateKey: '2026-10-04',
          duties: [{ role: '司會', people: ['王大明'], uids: { 王大明: 'u1' } }],
          events: [{ name: '聖餐', color: 0 }],
        },
      },
    ]);
    assert.deepEqual(out.staffOrders, [{ id: 'sunday', roles: { 司會: ['王大明'] } }]);
  });

  test('reports what was left out', () => {
    assert.deepEqual(buildImport(snapshot, null).report, {
      members: 2,
      admins: 1,
      services: ['sunday'],
      rosters: 1,
      skippedRosters: ['broken'],
      staffOrders: 1,
      droppedSettings: ['devotional'],
      smallGroupPeople: 1,
      unnamedMembers: 1,
    });
  });

  test('converts legacy member groups and reminder opt-out once, without importing FCM credentials', () => {
    const out = buildImport({
      users: [
        { id: 'opted-out', data: {
          name: '同工', role: 'staff', groups: ['roster-editors'],
          zones: [{ serviceType: 'sunday', ministries: ['司琴'], smallGroups: ['喜樂', '恩典'] }],
          notificationPrefs: { weeklyRosterReminder: false, muted: ['rosterChange'] },
          fcm: { phone: 'OLD-PROJECT-TOKEN' }, fcmTokens: ['OLD-PROJECT-TOKEN'],
        } },
        { id: 'enabled', data: { notificationPrefs: { weeklyRosterReminder: true } } },
        { id: 'default', data: {} },
      ], settings: [], rosters: [], staffOrders: [],
    }, 'JOINED');
    assert.deepEqual(out.members[0].zones, [{ serviceType: 'sunday', duties: ['司琴'], smallGroups: ['喜樂', '恩典'] }]);
    assert.deepEqual((out.members[0] as Record<string, unknown>).notificationPrefs, { muted: ['rosterChange', 'reminder'] });
    assert.deepEqual((out.members[1] as Record<string, unknown>).notificationPrefs, { muted: [] });
    assert.deepEqual((out.members[2] as Record<string, unknown>).notificationPrefs, { muted: [] });
    assert.equal(out.report.smallGroupPeople, 1, 'small groups are preserved, not reported as dropped');
    assert.equal(JSON.stringify(out).includes('OLD-PROJECT-TOKEN'), false);
    assert.equal(JSON.stringify(out).includes('weeklyRosterReminder'), false, 'only the new preference format leaves the boundary');
  });

  test('only legacy duties with an absent UID map bind unique exact original full names at the import boundary', () => {
    const sharedPrefix = '名'.repeat(40);
    const longA = `${sharedPrefix}甲`;
    const longB = `${sharedPrefix}乙`;
    const out = buildImport({
      users: [
        { id: 'unique', data: { name: '王大明' } },
        { id: 'mei', data: { name: '李美玉' } },
        { id: 'hao1', data: { name: '志豪' } },
        { id: 'hao2', data: { name: '志豪' } },
        { id: 'longA', data: { name: longA } },
        { id: 'longB', data: { name: longB } },
      ], settings: [], staffOrders: [],
      rosters: [{ id: '20261004_sunday', data: { type: 'sunday', duties: [
        { role: '司琴', people: ['王大明', '志豪', '美玉', '訪客', longA, longB, sharedPrefix] },
        { role: '敬拜', people: ['王大明', '訪客'], personIdsByName: { 王大明: 'explicit-other', 訪客: 'explicit-unknown' } },
        { role: '音控', people: ['王大明'], personIdsByName: {} },
        { role: '投影', people: ['王大明', '李美玉'], personIdsByName: { 王大明: 'unique' } },
        { role: '招待', people: [' 王大明 '] },
      ] } }],
    }, null);
    assert.deepEqual(out.rosters[0].data.duties.map((d) => d.uids), [
      { 王大明: 'unique', [longA]: 'longA', [longB]: 'longB' },
      { 王大明: 'explicit-other', 訪客: 'explicit-unknown' },
      {},
      { 王大明: 'unique' },
      {},
    ]);
    assert.equal(out.members.find((m) => m.uid === 'longA')!.name, sharedPrefix);
    assert.equal(out.members.find((m) => m.uid === 'longB')!.name, sharedPrefix, 'matching uses original source names, not truncated display names');
  });

  test('without settings/services the services come from the data', () => {
    const out = buildImport({ ...snapshot, settings: snapshot.settings.filter((s) => s.id !== 'services') }, null);
    assert.deepEqual(out.services.ids, ['sunday']);
    assert.deepEqual(out.services.services[0].duties, ['司會', '司琴']);
  });
});
