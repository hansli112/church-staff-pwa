import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:martha/data/admin_codec.dart';

/// Kept on the device as JSON text, read back as the reply was.
Map<Object?, Object?> _stored(Map<String, Object?> json) => jsonDecode(jsonEncode(json)) as Map;

void main() {
  test('every back-office reply reads back from its kept copy unchanged', () {
    final churches = {
      'churches': [
        {
          'id': 'grace',
          'name': '恩典堂',
          'status': 'suspended',
          'memberCount': 12,
          'admins': [
            {'uid': 'pastor', 'name': '王牧師', 'email': 'pastor@example.com', 'role': 'admin'},
          ],
        },
      ],
    };
    expect(churchSummariesToJson(churchSummariesFromJson(_stored(churches))), churches);

    final members = {
      'members': [
        {'uid': 'pastor', 'name': '王牧師', 'email': 'pastor@example.com', 'role': 'admin'},
        {'uid': 'mary', 'name': '馬利亞', 'email': 'mary@example.com', 'role': 'staff'},
      ],
    };
    expect(churchMembersToJson(churchMembersFromJson(_stored(members))), members);

    final stats = {
      'days': [
        {'date': '2026-10-18', 'users': 40, 'cost_usd': 0.42},
      ],
    };
    expect(dailyStatsToJson(dailyStatsFromJson(_stored(stats))), stats);

    final funding = {
      'costs': [
        {
          'name': 'Apple 開發者',
          'names': {'en': 'Apple Developer', 'ja': 'Apple デベロッパー'},
          'amount': 99,
          'currency': 'USD',
          'per': 'year',
        },
        {'name': '網域', 'amount': 30.5, 'currency': 'TWD', 'per': 'month'},
      ],
      'months': [
        {'month': '2026-10', 'received': 300, 'target': 800},
      ],
      'funding': {
        'month': '2026-10',
        'target': 800,
        'received': 300,
        'carried': 0,
        'monthsLeft': 2,
        'costs': [
          {
            'name': 'Apple 開發者',
            'names': {'en': 'Apple Developer'},
            'perMonth': 260,
            'per': 'year',
          },
          {'name': '網域', 'perMonth': 31, 'per': 'month'},
        ],
      },
    };
    expect(fundingOverviewToJson(fundingOverviewFromJson(_stored(funding))), funding);
  });
}
