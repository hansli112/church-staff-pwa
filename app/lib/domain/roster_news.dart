/// 服事表異動, before the backend reads any document: where a roster write
/// came from and what waits for 通知同工 (#90). functions/src/rosterNews.ts
/// keeps the same; both run testdata/roster_changes.json.
library;

import 'package:flutter/foundation.dart';

/// Where a roster write came from, as the app writes it (`via`). The
/// backend tells people by it; it writes others of its own, which the app
/// may not (firestore.rules).
enum RosterVia {
  /// An edit of the day: told at once.
  app,

  /// 安排服事: the pushes wait for 通知同工.
  plan,

  /// A whole import, or its undo: only the webhook hears, once.
  import
  ;

  /// Whether the pushes wait for 通知同工.
  bool get waitsForNotice => this == plan;
}

/// What waits for 通知同工 for one person on one day once a change puts
/// them from [before] to [after]: the duties they had before the first
/// change that waits, or null for nothing. [waiting] is what waited until
/// now. [told] when this change reaches them some other way (made outside
/// 安排服事, or by them): then it is taken as having always been so. Once
/// they have what they had before, nothing is left to tell.
List<String>? plannedAfter(
  List<String>? waiting, {
  required List<String> before,
  required List<String> after,
  required bool told,
}) {
  if (waiting == null) return told || setEquals(before.toSet(), after.toSet()) ? null : before;
  final roles = told
      ? [
          for (final r in waiting)
            if (after.contains(r) || !before.contains(r)) r,
          for (final r in after)
            if (!before.contains(r) && !waiting.contains(r)) r,
        ]
      : waiting;
  return setEquals(roles.toSet(), after.toSet()) ? null : roles;
}
