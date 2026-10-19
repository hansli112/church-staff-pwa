import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A read's last answer as this device kept it.
typedef SavedAnswer = ({Object? json, DateTime readAt});

/// The last answers of a few server reads, kept on this device for one
/// account so their pages show at once ([SavedRead]). Selecting another
/// account, or none, drops them all: nothing of one account shows to the
/// next. Only answers the server gave belong here.
class SavedReads {
  SavedReads(this._prefs);
  final SharedPreferences _prefs;
  static const _key = 'martha.saved.v1';
  static const _max = 20;

  String? _scope;
  bool _selected = false;
  final _answers = <String, SavedAnswer>{};
  Future<void> _pending = Future.value();

  /// Whose answers these are: one account of one project, or none.
  void select(String? scope) {
    if (_selected && scope == _scope) return;
    _selected = true;
    _scope = scope;
    _answers.clear();
    try {
      final raw = jsonDecode(_prefs.getString(_key) ?? 'null');
      if (scope != null && raw is Map && raw['scope'] == scope && raw['answers'] is Map) {
        for (final MapEntry(:key, :value) in (raw['answers'] as Map).entries) {
          if (key is String && value is Map && value['readAt'] is String) {
            _answers[key] = (json: value['json'], readAt: DateTime.parse(value['readAt'] as String));
          }
        }
        return;
      }
    } catch (_) {
      // Malformed or unavailable device storage keeps nothing.
      _answers.clear();
    }
    _persist();
  }

  SavedAnswer? read(String key) => _answers[key];

  Future<void> save(String key, Object? json, {required DateTime readAt}) {
    if (_scope == null) return Future.value();
    _answers
      ..remove(key)
      ..[key] = (json: json, readAt: readAt.toUtc());
    while (_answers.length > _max) {
      _answers.remove(_answers.keys.first);
    }
    return _persist();
  }

  Future<void> forget(String key) {
    if (_answers.remove(key) == null) return _pending;
    return _persist();
  }

  Future<void> _persist() {
    final encoded = _scope == null || _answers.isEmpty
        ? null
        : jsonEncode({
            'scope': _scope,
            'answers': {
              for (final MapEntry(:key, :value) in _answers.entries)
                key: {'json': value.json, 'readAt': value.readAt.toIso8601String()},
            },
          });
    return _pending = _pending.then((_) async {
      try {
        encoded == null ? await _prefs.remove(_key) : await _prefs.setString(_key, encoded);
      } catch (_) {
        // A copy for showing sooner must not fail the read it copies.
      }
    });
  }
}
