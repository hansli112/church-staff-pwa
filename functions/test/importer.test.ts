import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import { mapMember, mapRoster, mapServices, paletteIndex, rosterDateKey } from '../src/importer.js';

describe('self-host import mapping', () => {
  test('members: ministries become duties, small groups and unknown groups are dropped', () => {
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
      { serviceType: 'sundayService', duties: ['司琴', '招待'] },
      { serviceType: 'youth', duties: [] },
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
