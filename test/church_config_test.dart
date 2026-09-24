import 'dart:convert';
import 'dart:io';

import 'package:church_staff_pwa/core/config/church_config.dart';
import 'package:church_staff_pwa/core/config/default_church_config.dart';
import 'package:church_staff_pwa/core/types/service_type.dart';
import 'package:church_staff_pwa/features/auth/domain/entities/user.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> defaults() =>
    jsonDecode(defaultChurchConfigJson) as Map<String, dynamic>;

void main() {
  late ChurchConfig previous;
  setUp(() => previous = ChurchConfig.current);
  tearDown(() => ChurchConfig.current = previous);

  test(
    'public default config stays in sync and only enables core features',
    () {
      expect(
        defaults(),
        jsonDecode(File('config/church.example.json').readAsStringSync()),
      );
      final config = ChurchConfig.fromJson(defaults());
      expect(config.toJson(), defaults());
      expect(config.features.toJson().values, everyElement(isFalse));
      expect(config.devotional.enabled, isFalse);
    },
  );

  test('gatherings can be renamed or added without changing their IDs', () {
    ChurchConfig.current = ChurchConfig.fromJson({
      ...defaults(),
      'services': [
        {
          'id': 'sundayService',
          'label': '早堂',
          'name': '早堂聚會',
          'weekday': 5,
          'enabled': true,
        },
        {
          'id': 'evening',
          'label': '晚堂',
          'name': '晚堂聚會',
          'weekday': 5,
          'enabled': true,
        },
      ],
    });
    expect(ServiceType.values.map((s) => s.name), ['sundayService', 'evening']);
    expect(ServiceType.values.first, ServiceType.sundayService);
    expect(ServiceType.sundayService.label, '早堂');
    expect(ServiceType.sundayService.weekday, 5);
    expect(ServiceType.fromName('evening'), const ServiceType('evening'));
    expect(
      {const ServiceType('evening'): 'value'}[ServiceType.fromName('evening')],
      'value',
    );
  });

  test(
    'disabled gatherings remain identifiable; unknown IDs never become Sunday',
    () {
      final config = defaults();
      (config['services'] as List).first['enabled'] = false;
      ChurchConfig.current = ChurchConfig.fromJson(config);
      expect(ServiceType.values, contains(ServiceType.sundayService));
      expect(ServiceType.sundayService.enabled, isFalse);
      final unknown = ServiceType.fromName('archived');
      expect(unknown, isNot(ServiceType.sundayService));
      expect(unknown.label, 'archived');
      expect(unknown.enabled, isFalse);
      expect(() => unknown.weekday, throwsStateError);
    },
  );

  test(
    'unknown user zones round trip but grant no configured roster access',
    () {
      final user = User.fromJson({
        'id': 'test-user',
        'name': 'Test User',
        'username': 'test',
        'role': 'staff',
        'zones': [
          {
            'serviceType': 'archived',
            'ministries': ['招待'],
          },
        ],
        'groups': ['roster-editors'],
      });
      expect(user.zones.single.serviceType.name, 'archived');
      expect(user.allowedRosterTypes, isEmpty);
      expect(user.toJson()['zoneTypes'], ['archived']);
      expect(
        UserZoneInfo.fromJson({'serviceType': 'evening'}).serviceType.name,
        'evening',
      );
    },
  );

  test('invalid schema, timezones, flags, IDs and weekdays fail early', () {
    final invalid = <Map<String, dynamic>>[
      {...defaults(), 'schemaVersion': 2},
      {...defaults(), 'timeZone': 'Not/AZone'},
      {
        ...defaults(),
        'features': {'calendar': 'true'},
      },
      {...defaults(), 'services': []},
      {
        ...defaults(),
        'services': [
          {'id': '../bad', 'label': 'A', 'name': 'A', 'weekday': 1},
        ],
      },
      {
        ...defaults(),
        'services': [
          {'id': 'a', 'label': 'A', 'name': 'A', 'weekday': 0},
        ],
      },
      {
        ...defaults(),
        'services': [
          {'id': 'a', 'label': 'A', 'name': 'A', 'weekday': 1},
          {'id': 'a', 'label': 'B', 'name': 'B', 'weekday': 2},
        ],
      },
    ];
    for (final data in invalid) {
      expect(() => ChurchConfig.fromJson(data), throwsFormatException);
    }
  });

  test(
    'devotional sources and click links must be credential-free HTTPS URLs',
    () {
      for (final url in [
        'http://example.com',
        'javascript:alert(1)',
        'https://name:secret@example.com',
        '',
      ]) {
        expect(
          () => ChurchConfig.fromJson({
            ...defaults(),
            'devotional': {
              'enabled': true,
              'dataUrl': url,
              'linkUrl': 'https://example.com/read',
              'sourceName': '閱讀',
            },
          }),
          throwsFormatException,
        );
      }
      final config = ChurchConfig.fromJson({
        ...defaults(),
        'devotional': {
          'enabled': true,
          'dataUrl': 'https://example.com/feed.json',
          'linkUrl': 'https://example.com/read',
          'sourceName': '閱讀',
          'fetchUrl': 'https://example.com/source',
          'fetchFormat': 'dailyBibleHtml',
        },
      });
      expect(config.devotional.linkUrl, 'https://example.com/read');
      expect(config.toJson()['devotional']['fetchFormat'], 'dailyBibleHtml');
    },
  );

  test('icon paths cannot escape the published directory', () {
    for (final path in [
      '../secret.png',
      '/absolute.png',
      'https://example.com/icon.png',
    ]) {
      expect(
        () => ChurchConfig.fromJson({
          ...defaults(),
          'icons': {...defaults()['icons'], 'favicon': path},
        }),
        throwsFormatException,
      );
    }
  });
}
