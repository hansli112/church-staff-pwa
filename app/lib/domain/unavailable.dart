/// 不能服事的日子 (#91): the days a member says they cannot serve. A day
/// is a whole day in every service; stretches of them carry an optional
/// note for whoever arranges.
library;

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
