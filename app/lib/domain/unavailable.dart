/// 不能服事的日子 (#91): the days a member says they cannot serve. A day
/// is a whole day in every service; stretches of them carry an optional
/// note for whoever arranges.
library;

import 'package:flutter/foundation.dart';

import 'day.dart';
import 'models.dart';

/// [from] to [to], both in, with what the member wrote about it.
class UnavailableSpan {
  const UnavailableSpan(this.from, this.to, {this.note = ''});

  final Day from;
  final Day to;
  final String note;

  bool covers(Day day) => !day.isBefore(from) && !to.isBefore(day);

  @override
  bool operator ==(Object other) =>
      other is UnavailableSpan && other.from == from && other.to == to && other.note == note;

  @override
  int get hashCode => Object.hash(from, to, note);

  @override
  String toString() => '$from–$to${note.isEmpty ? '' : ' $note'}';
}

/// A member's 不能服事的日子: stretches in order, none touching another.
class UnavailableDays {
  const UnavailableDays([this.spans = const []]);

  final List<UnavailableSpan> spans;

  bool get isEmpty => spans.isEmpty;

  /// The stretch [day] is in, if any.
  UnavailableSpan? on(Day day) {
    for (final s in spans) {
      if (s.covers(day)) return s;
    }
    return null;
  }

  /// The first stretch with a day of [from] to [to] in it: an event's
  /// roster runs over several.
  UnavailableSpan? during(Day from, Day to) {
    for (final s in spans) {
      if (!s.to.isBefore(from) && !to.isBefore(s.from)) return s;
    }
    return null;
  }

  /// [from] to [to] added. Stretches it overlaps or touches become one with
  /// it: [note], or else the first of theirs that says something.
  UnavailableDays add(Day from, Day to, {String note = ''}) {
    if (to.isBefore(from)) (from, to) = (to, from);
    var (start, end, says) = (from, to, note.trim());
    final rest = <UnavailableSpan>[];
    for (final s in spans) {
      if (s.to.addDays(1).isBefore(start) || end.addDays(1).isBefore(s.from)) {
        rest.add(s);
        continue;
      }
      if (s.from.isBefore(start)) start = s.from;
      if (s.to.isAfter(end)) end = s.to;
      if (says.isEmpty) says = s.note;
    }
    return UnavailableDays(_sorted([...rest, UnavailableSpan(start, end, note: says)]));
  }

  /// [from] to [to] (or [from] alone) taken out, splitting a stretch in
  /// two where they are inside it.
  UnavailableDays without(Day from, [Day? to]) {
    var (a, b) = (from, to ?? from);
    if (b.isBefore(a)) (a, b) = (b, a);
    return UnavailableDays([
      for (final s in spans)
        if (s.to.isBefore(a) || b.isBefore(s.from))
          s
        else ...[
          if (s.from.isBefore(a)) UnavailableSpan(s.from, a.addDays(-1), note: s.note),
          if (s.to.isAfter(b)) UnavailableSpan(b.addDays(1), s.to, note: s.note),
        ],
    ]);
  }

  /// [span] taken out whole.
  UnavailableDays remove(UnavailableSpan span) => UnavailableDays([
    for (final s in spans)
      if (s != span) s,
  ]);

  /// [span] with [note] in place of its own.
  UnavailableDays noted(UnavailableSpan span, String note) => UnavailableDays([
    for (final s in spans) s == span ? UnavailableSpan(s.from, s.to, note: note.trim()) : s,
  ]);

  /// What still matters on [today]: stretches over before it are gone.
  UnavailableDays since(Day today) => UnavailableDays([
    for (final s in spans)
      if (!s.to.isBefore(today)) s,
  ]);

  static List<UnavailableSpan> _sorted(List<UnavailableSpan> spans) => spans..sort((a, b) => a.from.compareTo(b.from));

  @override
  bool operator ==(Object other) =>
      other is UnavailableDays &&
      other.spans.length == spans.length &&
      [for (var i = 0; i < spans.length; i++) other.spans[i] == spans[i]].every((same) => same);

  @override
  int get hashCode => Object.hashAll(spans);

  @override
  String toString() => 'UnavailableDays($spans)';
}

/// Whom 通知同工填 tells (#91): everyone but [me] on the list of a duty of
/// [serviceType] that [arranges] covers.
List<Member> askedToFill(Iterable<Member> members, String serviceType, Arranges arranges, String me) => [
  for (final m in members)
    if (m.uid != me && m.zones.any((z) => z.serviceType == serviceType && z.duties.any(arranges.has))) m,
];

/// Who of [everyone] cannot serve on [roster]'s days, by uid, with the
/// stretch that says so.
Map<String, UnavailableSpan> unavailableOn(Roster roster, Map<String, UnavailableDays> everyone) => {
  for (final MapEntry(key: uid, value: days) in everyone.entries) uid: ?days.during(roster.day, roster.lastDay),
};

/// Sent at [sentAt] answers an ask made at [askedAt]: not sent before it.
bool sentSince(DateTime? sentAt, DateTime askedAt) => sentAt != null && !sentAt.isBefore(askedAt);

/// What 通知同工填 (#91) asked of me: the months [from] to [to] (each its
/// first day), asked at [at]; and when I last sent mine, if ever.
class UnavailableAsked {
  const UnavailableAsked({required this.at, required this.from, required this.to, this.sentAt});

  final DateTime at;
  final Day from;
  final Day to;
  final DateTime? sentAt;

  /// Sent since it was asked: answered.
  bool get sent => sentSince(sentAt, at);

  /// Its months not all gone by in [today]'s month.
  bool currentOn(Day today) => !to.isBefore(today.firstOfMonth);

  /// Still waiting on me on [today]: not sent, and [currentOn].
  bool waitingOn(Day today) => !sent && currentOn(today);

  @override
  bool operator ==(Object other) =>
      other is UnavailableAsked && other.at == at && other.from == from && other.to == to && other.sentAt == sentAt;

  @override
  int get hashCode => Object.hash(at, from, to, sentAt);

  @override
  String toString() => 'UnavailableAsked($from–$to at $at, sent $sentAt)';
}

/// A service's last 通知同工填 (#91) as it stands: the months [from] to [to],
/// asked at [at] of [told] (uids); of them, [sent] have sent theirs since.
class UnavailableRound {
  const UnavailableRound({
    required this.at,
    required this.from,
    required this.to,
    required this.told,
    this.sent = const {},
  });

  final DateTime at;
  final Day from;
  final Day to;
  final List<String> told;
  final Set<String> sent;

  /// Who of [told] has not sent, in the order told.
  List<String> get waiting => [
    for (final uid in told)
      if (!sent.contains(uid)) uid,
  ];

  /// Its months not all gone by in [today]'s month.
  bool currentOn(Day today) => !to.isBefore(today.firstOfMonth);

  @override
  bool operator ==(Object other) =>
      other is UnavailableRound &&
      other.at == at &&
      other.from == from &&
      other.to == to &&
      listEquals(other.told, told) &&
      setEquals(other.sent, sent);

  @override
  int get hashCode => Object.hash(at, from, to, Object.hashAll(told), Object.hashAllUnordered(sent));

  @override
  String toString() => 'UnavailableRound($from–$to at $at, told $told, sent $sent)';
}
