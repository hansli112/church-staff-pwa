/// 找人代 and 交換服事 a member asks for themselves (#92): one of their
/// duties on a day of a service, taken by someone on the duty's list who
/// says yes. functions/src/swaps.ts keeps the same rules; both run
/// testdata/swaps.json.
library;

import 'package:flutter/foundation.dart';

import 'day.dart';
import 'models.dart';

/// 請人代: whoever on the list says 我來 takes it. 交換: one person, on
/// another day, says 接受 and the two trade.
enum SwapKind { cover, swap }

/// Where a request is: waiting, taken (or traded), turned down (a swap's
/// one person said 不方便), taken back by who asked, or void: the day
/// went by or the roster changed under it.
enum SwapStatus { open, taken, declined, withdrawn, voided }

/// A request, as churches/{cid}/swapRequests/{id} keeps it.
@immutable
class SwapRequest {
  const SwapRequest({
    required this.id,
    required this.kind,
    required this.serviceId,
    required this.day,
    required this.duty,
    required this.from,
    required this.fromName,
    this.asked = const [],
    this.passed = const [],
    this.to,
    this.toName,
    this.toDay,
    this.status = SwapStatus.open,
    this.taker,
    this.takerName,
  });

  final String id;
  final SwapKind kind;
  final String serviceId;
  final Day day;
  final String duty;

  /// Who asked, and their name on the roster.
  final String from;
  final String fromName;

  /// 請人代: everyone asked, and those of them who said 不方便.
  final List<String> asked;
  final List<String> passed;

  /// 交換: the one asked, their name, and their day.
  final String? to;
  final String? toName;
  final Day? toDay;

  final SwapStatus status;

  /// Who took it once it is taken.
  final String? taker;
  final String? takerName;

  bool get isOpen => status == SwapStatus.open;

  String get rosterId => Roster.idFor(serviceId, day);
  String? get toRosterId => toDay == null ? null : Roster.idFor(serviceId, toDay!);

  /// Whether [uid] may answer it while it is open.
  bool canAnswer(String uid) => kind == SwapKind.cover ? asked.contains(uid) : to == uid;

  SwapRequest copyWith({SwapStatus? status, String? taker, String? takerName, List<String>? passed}) => SwapRequest(
    id: id,
    kind: kind,
    serviceId: serviceId,
    day: day,
    duty: duty,
    from: from,
    fromName: fromName,
    asked: asked,
    passed: passed ?? this.passed,
    to: to,
    toName: toName,
    toDay: toDay,
    status: status ?? this.status,
    taker: taker ?? this.taker,
    takerName: takerName ?? this.takerName,
  );

  /// Open again after 復原: nobody has it.
  SwapRequest get reopened => SwapRequest(
    id: id,
    kind: kind,
    serviceId: serviceId,
    day: day,
    duty: duty,
    from: from,
    fromName: fromName,
    asked: asked,
    passed: passed,
    to: to,
    toName: toName,
    toDay: toDay,
  );

  @override
  bool operator ==(Object other) =>
      other is SwapRequest &&
      other.id == id &&
      other.kind == kind &&
      other.serviceId == serviceId &&
      other.day == day &&
      other.duty == duty &&
      other.from == from &&
      other.fromName == fromName &&
      listEquals(other.asked, asked) &&
      listEquals(other.passed, passed) &&
      other.to == to &&
      other.toName == toName &&
      other.toDay == toDay &&
      other.status == status &&
      other.taker == taker &&
      other.takerName == takerName;

  @override
  int get hashCode => Object.hash(id, kind, day, duty, from, status, taker, Object.hashAll(asked), to, toDay);
}

/// How long after taking a request 復原 still gives it back
/// (functions/src/swaps.ts UNDO_MS).
const swapUndoWindow = Duration(minutes: 10);

/// Whether [uid] is on [duty] of [roster], by name and uid (Roster.dutiesOf).
bool isOnDuty(Roster? roster, String duty, String uid) => roster?.dutiesOf(uid: uid).contains(duty) ?? false;

/// Whom 請人代 asks for [from]'s [duty] on [roster]: everyone else on the
/// duty's list in its service who is free that day: not on the duty
/// already, and not away (不能服事的日子, #91), in [members]' order.
List<String> coverAsked(
  Iterable<Member> members,
  Roster roster,
  String duty,
  String from, {
  Map<String, UnavailableDays> unavailable = const {},
}) => [
  for (final m in members)
    if (m.uid != from &&
        m.serves(roster.type, duty) &&
        !isOnDuty(roster, duty, m.uid) &&
        unavailable[m.uid]?.during(roster.day, roster.lastDay) == null)
      m.uid,
];

/// Whether [request] can still be taken: [from] is still on the duty of
/// [roster] (the request's day), and for 交換 its one person is still on it
/// on [other] (their day), with neither on the other's day already.
bool swapStillHolds(SwapRequest request, Roster? roster, Roster? other) {
  if (!isOnDuty(roster, request.duty, request.from)) return false;
  if (request.kind == SwapKind.cover) return true;
  final to = request.to!;
  return isOnDuty(other, request.duty, to) &&
      !isOnDuty(roster, request.duty, to) &&
      !isOnDuty(other, request.duty, request.from);
}

/// Whether [request]'s rosters are still as taking it left them, so 復原
/// can give it back: its taker where who asked was, and for 交換 who asked
/// on the taker's day (functions/src/swaps.ts undoSwap).
bool swapAsTaken(SwapRequest request, Roster? roster, Roster? other) {
  final taker = request.taker;
  if (taker == null) return false;
  if (request.kind == SwapKind.cover) {
    return isOnDuty(roster, request.duty, taker) && !isOnDuty(roster, request.duty, request.from);
  }
  return isOnDuty(roster, request.duty, taker) &&
      isOnDuty(other, request.duty, request.from) &&
      !isOnDuty(roster, request.duty, request.from) &&
      !isOnDuty(other, request.duty, taker);
}

/// [roster] with [uid] (named [name] there) on [duty] in place of
/// [replaced], where [replaced] was.
Roster replacedOnDuty(Roster roster, String duty, String replaced, String uid, String name) => roster.copyWith(
  duties: [
    for (final d in roster.duties)
      if (d.role != duty)
        d
      else
        () {
          final old = d.uids.entries.firstWhere((e) => e.value == replaced && d.people.contains(e.key)).key;
          return d.copyWith(
            people: [for (final p in d.people) p == old ? name : p],
            uids: {
              for (final e in d.uids.entries)
                if (e.key != old) e.key: e.value,
              name: uid,
            },
          );
        }(),
  ],
);
