import 'package:martha/core/telemetry.dart';

/// Keeps what the app counts (GA4), to check it.
class RecordingTelemetry extends NoTelemetry {
  final events = <(String, Map<String, Object>?)>[];

  /// Each page as it came up, by its route's pattern.
  final screens = <String>[];

  /// The parameters of each [name] event, in order.
  List<Map<String, Object>?> named(String name) => [
    for (final (n, p) in events)
      if (n == name) p,
  ];

  @override
  void logEvent(String name, [Map<String, Object>? parameters]) => events.add((name, parameters));

  @override
  void logScreen(String name) => screens.add(name);

  /// The GA4 user property `role`, as last set.
  String? role;

  @override
  void setRole(String? role) => this.role = role;
}
