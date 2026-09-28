import 'dart:convert';

import '../time/time_zone_database.dart';
import 'default_church_config.dart';

/// 部署者提供的公開設定。憑證不屬於這份設定，也不應進入前端 bundle。
class ChurchConfig {
  ChurchConfig._({
    required this.appName,
    required this.shortName,
    required this.timeZone,
    required this.services,
    required this.features,
    required this.devotional,
    required this.icons,
  });

  static ChurchConfig current = ChurchConfig.fromJson(
    jsonDecode(
          const String.fromEnvironment(
            'CHURCH_CONFIG_JSON',
            defaultValue: defaultChurchConfigJson,
          ),
        )
        as Map<String, dynamic>,
  );

  final String appName;
  final String shortName;
  final String timeZone;
  final List<ServiceDefinition> services;
  final ChurchFeatures features;
  final DevotionalConfig devotional;
  final Map<String, String> icons;

  ServiceDefinition? service(String id) {
    for (final service in services) {
      if (service.id == id) return service;
    }
    return null;
  }

  factory ChurchConfig.fromJson(Map<String, dynamic> json) {
    _checkKeys(json, const [
      'schemaVersion',
      'appName',
      'shortName',
      'timeZone',
      'services',
      'features',
      'devotional',
      'icons',
    ]);
    if (json['schemaVersion'] != 1) {
      throw const FormatException('不支援的教會設定版本');
    }
    final timeZone = _text(json, 'timeZone');
    try {
      timeZoneLocation(timeZone);
    } catch (_) {
      throw FormatException('無效的 IANA 時區：$timeZone');
    }
    final rawServices = json['services'];
    if (rawServices is! List ||
        rawServices.isEmpty ||
        rawServices.length > 20) {
      throw const FormatException('services 必須包含 1 至 20 種聚會');
    }
    final services = rawServices
        .map((raw) => ServiceDefinition.fromJson(_object(raw, 'service')))
        .toList();
    if (services.map((s) => s.id).toSet().length != services.length) {
      throw const FormatException('聚會 ID 不可重複');
    }
    final rawIcons = _object(json['icons'], 'icons');
    _checkKeys(rawIcons, const [
      'favicon',
      'icon192',
      'icon512',
      'maskable192',
      'maskable512',
    ]);
    final icons = rawIcons.map((key, value) {
      if (value is! String ||
          value.length > 240 ||
          !RegExp(
            r'^[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*\.png$',
          ).hasMatch(value)) {
        throw FormatException('圖示必須是安全的相對 PNG 路徑：$key');
      }
      return MapEntry(key, value);
    });
    for (final key in [
      'favicon',
      'icon192',
      'icon512',
      'maskable192',
      'maskable512',
    ]) {
      if (!icons.containsKey(key)) throw FormatException('缺少圖示：$key');
    }
    return ChurchConfig._(
      appName: _text(json, 'appName'),
      shortName: _text(json, 'shortName', max: 40),
      timeZone: timeZone,
      services: List.unmodifiable(services),
      features: ChurchFeatures.fromJson(_object(json['features'], 'features')),
      devotional: DevotionalConfig.fromJson(
        _object(json['devotional'], 'devotional'),
      ),
      icons: Map.unmodifiable(icons),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'appName': appName,
    'shortName': shortName,
    'timeZone': timeZone,
    'services': services.map((s) => s.toJson()).toList(),
    'features': features.toJson(),
    'devotional': devotional.toJson(),
    'icons': icons,
  };
}

class ServiceDefinition {
  const ServiceDefinition({
    required this.id,
    required this.label,
    required this.name,
    required this.weekday,
    required this.enabled,
  });

  final String id;
  final String label;
  final String name;
  final int weekday;
  final bool enabled;

  factory ServiceDefinition.fromJson(Map<String, dynamic> json) {
    _checkKeys(json, const ['id', 'label', 'name', 'weekday', 'enabled']);
    final id = _text(json, 'id', max: 64);
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(id) ||
        const ['constructor', 'prototype'].contains(id)) {
      throw FormatException('無效的聚會 ID：$id');
    }
    final weekday = json['weekday'];
    if (weekday is! int || weekday < 1 || weekday > 7) {
      throw FormatException('聚會 $id 的 weekday 必須是 1 至 7');
    }
    return ServiceDefinition(
      id: id,
      label: _text(json, 'label', max: 40),
      name: _text(json, 'name'),
      weekday: weekday,
      enabled: _flag(json, 'enabled'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'name': name,
    'weekday': weekday,
    'enabled': enabled,
  };
}

class ChurchFeatures {
  const ChurchFeatures({
    this.calendar = false,
    this.photoImport = false,
    this.pushNotifications = false,
    this.lineNotifications = false,
  });

  final bool calendar;
  final bool photoImport;
  final bool pushNotifications;
  final bool lineNotifications;

  factory ChurchFeatures.fromJson(Map<String, dynamic> json) {
    _checkKeys(json, const [
      'calendar',
      'photoImport',
      'pushNotifications',
      'lineNotifications',
    ]);
    final result = ChurchFeatures(
      calendar: _flag(json, 'calendar'),
      photoImport: _flag(json, 'photoImport'),
      pushNotifications: _flag(json, 'pushNotifications'),
      lineNotifications: _flag(json, 'lineNotifications'),
    );
    if (result.lineNotifications && !result.calendar) {
      throw const FormatException('LINE 行事曆通知需要啟用行事曆');
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    'calendar': calendar,
    'photoImport': photoImport,
    'pushNotifications': pushNotifications,
    'lineNotifications': lineNotifications,
  };
}

class DevotionalConfig {
  const DevotionalConfig({
    required this.enabled,
    required this.dataUrl,
    required this.linkUrl,
    required this.sourceName,
    this.fetchUrl = '',
    this.fetchFormat = 'json',
  });

  final bool enabled;
  final String dataUrl;
  final String linkUrl;
  final String sourceName;
  final String fetchUrl;
  final String fetchFormat;

  factory DevotionalConfig.fromJson(Map<String, dynamic> json) {
    _checkKeys(json, const [
      'enabled',
      'dataUrl',
      'linkUrl',
      'sourceName',
      'fetchUrl',
      'fetchFormat',
    ]);
    final enabled = _flag(json, 'enabled');
    final format = json['fetchFormat'] ?? 'json';
    if (format != 'json' && format != 'dailyBibleHtml') {
      throw const FormatException('不支援的每日靈糧抓取格式');
    }
    return DevotionalConfig(
      enabled: enabled,
      dataUrl: _httpsUrl(json, 'dataUrl', isRequired: enabled),
      linkUrl: _httpsUrl(json, 'linkUrl', isRequired: enabled),
      sourceName: _text(json, 'sourceName'),
      fetchUrl: _httpsUrl(
        {'fetchUrl': json['fetchUrl'] ?? ''},
        'fetchUrl',
        isRequired: false,
      ),
      fetchFormat: format as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'dataUrl': dataUrl,
    'linkUrl': linkUrl,
    'sourceName': sourceName,
    'fetchUrl': fetchUrl,
    'fetchFormat': fetchFormat,
  };
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$field 必須是物件');
  }
  return value;
}

void _checkKeys(Map<String, dynamic> json, List<String> allowed) {
  if (json.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('不支援的設定欄位；憑證不能放在公開設定檔');
  }
}

String _text(Map<String, dynamic> json, String field, {int max = 100}) {
  final value = json[field];
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > max ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw FormatException('$field 必須是 1 至 $max 字的純文字');
  }
  return value;
}

bool _flag(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! bool) throw FormatException('$field 必須是布林值');
  return value;
}

String _httpsUrl(
  Map<String, dynamic> json,
  String field, {
  required bool isRequired,
}) {
  final value = json[field];
  if (value is! String ||
      value.length > 2048 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw FormatException('$field 必須是安全的 URL 字串');
  }
  if (value.isEmpty && !isRequired) return '';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw FormatException('$field 必須是 HTTPS 網址');
  }
  return value;
}
