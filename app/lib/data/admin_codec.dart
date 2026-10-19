/// The back office's callable replies <-> domain model. Each toJson gives
/// the reply's own shape, so a copy kept on this device ([SavedReads]) reads
/// back through the same fromJson as the reply did.
library;

import '../domain/day.dart';
import '../domain/models.dart';
import 'backend.dart';

typedef ReplyJson = Map<Object?, Object?>;

List<ChurchSummary> churchSummariesFromJson(ReplyJson d) => [
  for (final raw in d['churches'] as List<dynamic>? ?? const [])
    if (raw is Map)
      ChurchSummary(
        id: raw['id'] as String,
        name: raw['name'] as String,
        status: ChurchStatus.values.firstWhere((s) => s.name == raw['status'], orElse: () => ChurchStatus.suspended),
        memberCount: (raw['memberCount'] as num?)?.toInt() ?? 0,
        admins: [
          for (final a in raw['admins'] as List<dynamic>? ?? const [])
            if (a is Map) _member(a, role: Role.admin),
        ],
      ),
];

Map<String, Object?> churchSummariesToJson(List<ChurchSummary> churches) => {
  'churches': [
    for (final c in churches)
      {
        'id': c.id,
        'name': c.name,
        'status': c.status.name,
        'memberCount': c.memberCount,
        'admins': [for (final a in c.admins) _memberToJson(a)],
      },
  ],
};

List<Member> churchMembersFromJson(ReplyJson d) => [
  for (final raw in d['members'] as List<dynamic>? ?? const [])
    if (raw is Map) _member(raw, role: Role.values.firstWhere((r) => r.name == raw['role'], orElse: () => Role.staff)),
];

Map<String, Object?> churchMembersToJson(List<Member> members) => {
  'members': [for (final m in members) _memberToJson(m)],
};

Member _member(Map<Object?, Object?> raw, {required Role role}) => Member(
  uid: raw['uid'] as String,
  name: raw['name'] as String? ?? '',
  email: raw['email'] as String? ?? '',
  role: role,
);

Map<String, Object?> _memberToJson(Member m) => {'uid': m.uid, 'name': m.name, 'email': m.email, 'role': m.role.name};

List<DailyStats> dailyStatsFromJson(ReplyJson d) => [
  for (final raw in d['days'] as List<dynamic>? ?? const [])
    if (raw case {'date': final String date} when Day.tryParse(date) != null)
      DailyStats(
        day: Day.parse(date),
        values: {
          for (final e in raw.entries)
            if (e.key is String && e.value is num) e.key as String: e.value as num,
        },
      ),
];

Map<String, Object?> dailyStatsToJson(List<DailyStats> days) => {
  'days': [
    for (final d in days) {'date': d.day.key, ...d.values},
  ],
};

FundingOverview fundingOverviewFromJson(ReplyJson d) {
  final summary = d['funding'];
  return FundingOverview(
    costs: [
      for (final raw in d['costs'] as List<dynamic>? ?? const [])
        if (raw case {
          'name': final String name,
          'amount': final num amount,
          'currency': final String code,
          'per': final String per,
        } when Currency.fromCode(code) != null)
          CostItem(
            name: name,
            amount: amount,
            currency: Currency.fromCode(code)!,
            per: per == 'year' ? CostPeriod.year : CostPeriod.month,
          ),
    ],
    months: [
      for (final raw in d['months'] as List<dynamic>? ?? const [])
        if (raw case {'month': final String month, 'received': final num received, 'target': final num target})
          FundingMonth(month: month, received: received.round(), target: target.round()),
    ],
    funding: summary is Map ? fundingFromJson(Map<String, Object?>.from(summary)) : null,
  );
}

Map<String, Object?> fundingOverviewToJson(FundingOverview o) => {
  'costs': [for (final c in o.costs) costItemToJson(c)],
  'months': [
    for (final m in o.months) {'month': m.month, 'received': m.received, 'target': m.target},
  ],
  'funding': ?switch (o.funding) {
    final f? => fundingToJson(f),
    null => null,
  },
};

Map<String, Object?> costItemToJson(CostItem i) => {
  'name': i.name,
  'amount': i.amount,
  'currency': i.currency.code,
  'per': i.per.name,
};

/// Also `platform/funding`, which the support page reads.
Funding fundingFromJson(Map<String, Object?> d) {
  int n(String key) => (d[key] as num?)?.round() ?? 0;
  return Funding(
    month: d['month'] as String? ?? '',
    target: n('target'),
    received: n('received'),
    carried: n('carried'),
    monthsLeft: n('monthsLeft'),
    costs: [
      for (final c in (d['costs'] as List?) ?? const [])
        if (c is Map)
          FundingCost(
            name: c['name'] as String? ?? '',
            perMonth: (c['perMonth'] as num?)?.round() ?? 0,
            yearly: c['per'] == 'year',
          ),
    ],
  );
}

Map<String, Object?> fundingToJson(Funding f) => {
  'month': f.month,
  'target': f.target,
  'received': f.received,
  'carried': f.carried,
  'monthsLeft': f.monthsLeft,
  'costs': [
    for (final c in f.costs) {'name': c.name, 'perMonth': c.perMonth, 'per': c.yearly ? 'year' : 'month'},
  ],
};
