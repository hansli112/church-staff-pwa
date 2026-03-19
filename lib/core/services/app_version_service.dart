import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class AppVersionInfo {
  const AppVersionInfo({required this.generatedAt});

  final DateTime generatedAt;
}

class AppVersionService {
  const AppVersionService();

  Future<AppVersionInfo?> fetchVersionInfo() async {
    final candidates = [
      Uri.base.resolve('version.json'),
      Uri.base.resolve('/version.json'),
    ];

    for (final uri in candidates) {
      try {
        final response = await http.get(uri);
        if (response.statusCode != 200) {
          continue;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final generatedAtRaw = data['generated_at'];
        DateTime? generatedAt;
        if (generatedAtRaw is String && generatedAtRaw.isNotEmpty) {
          generatedAt = DateTime.tryParse(generatedAtRaw);
        }

        generatedAt ??= _parseLastModified(response);
        if (generatedAt == null) continue;

        return AppVersionInfo(generatedAt: generatedAt.toLocal());
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  DateTime? _parseLastModified(http.Response response) {
    final value = response.headers['last-modified'];
    if (value == null || value.isEmpty) return null;
    try {
      return DateFormat(
        "EEE, dd MMM yyyy HH:mm:ss 'GMT'",
        'en_US',
      ).parseUtc(value);
    } catch (_) {
      return null;
    }
  }
}
