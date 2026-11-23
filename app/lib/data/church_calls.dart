part of 'backend.dart';

/// A write the backend makes for the church, sent as is to one of
/// functions/src's callables ([callable]): no Firestore of the app's own
/// in it. [ChurchData.run] makes it; [ChurchCalls] names each.
///
/// The memory backend does each the way its functions/src file does, and
/// EchoingChurchData shows those that change what is listed at once.
sealed class ChurchCall<R> {
  const ChurchCall();

  /// The callable's name in functions/src/index.ts.
  String get callable;

  /// What it is sent, besides the church's ID.
  Map<String, Object?> get data;

  /// What it answers, from what the callable returned.
  R answer(Map<String, Object?> data);
}

/// A [ChurchCall] answering nothing.
sealed class _Write extends ChurchCall<void> {
  const _Write();

  @override
  void answer(Map<String, Object?> data) {}
}

int _count(Object? n) => (n as num?)?.toInt() ?? 0;

final class AnswerJoinRequest extends _Write {
  const AnswerJoinRequest(this.uid, {required this.allow});
  final String uid;
  final bool allow;

  @override
  String get callable => 'answerJoinRequest';

  @override
  Map<String, Object?> get data => {'uid': uid, 'allow': allow};
}

final class DeleteSmallGroup extends _Write {
  const DeleteSmallGroup(this.id);
  final String id;

  @override
  String get callable => 'editSmallGroup';

  @override
  Map<String, Object?> get data => {'op': 'delete', 'id': id};
}

final class OrderSmallGroups extends _Write {
  const OrderSmallGroups(this.service, this.ids);
  final String service;
  final List<String> ids;

  @override
  String get callable => 'editSmallGroup';

  @override
  Map<String, Object?> get data => {'op': 'order', 'service': service, 'ids': ids};
}

final class NotifyPlanned extends ChurchCall<PlannedNotice> {
  const NotifyPlanned(this.serviceType);
  final String serviceType;

  @override
  String get callable => 'notifyPlanned';

  @override
  Map<String, Object?> get data => {'serviceId': serviceType};

  @override
  PlannedNotice answer(Map<String, Object?> data) => (people: _count(data['people']), later: data['later'] == true);
}

final class AskCover extends ChurchCall<int> {
  const AskCover(this.roster, this.duty);
  final Roster roster;
  final String duty;

  @override
  String get callable => 'askCover';

  @override
  Map<String, Object?> get data => {'serviceId': roster.type, 'dateKey': roster.day.key, 'duty': duty};

  @override
  int answer(Map<String, Object?> data) => _count(data['asked']);
}

final class AskSwap extends _Write {
  const AskSwap(this.roster, this.duty, this.other, this.uid);
  final Roster roster;
  final String duty;
  final Roster other;
  final String uid;

  @override
  String get callable => 'askSwap';

  @override
  Map<String, Object?> get data => {
    'serviceId': roster.type,
    'dateKey': roster.day.key,
    'duty': duty,
    'with': uid,
    'withDateKey': other.day.key,
  };
}

final class AnswerSwap extends _Write {
  const AnswerSwap(this.id, {required this.yes});
  final String id;
  final bool yes;

  @override
  String get callable => 'answerSwap';

  @override
  Map<String, Object?> get data => {'id': id, 'yes': yes};
}

final class UndoSwap extends _Write {
  const UndoSwap(this.id);
  final String id;

  @override
  String get callable => 'undoSwap';

  @override
  Map<String, Object?> get data => {'id': id};
}

final class WithdrawSwap extends _Write {
  const WithdrawSwap(this.id);
  final String id;

  @override
  String get callable => 'withdrawSwap';

  @override
  Map<String, Object?> get data => {'id': id};
}

final class AskUnavailable extends ChurchCall<int> {
  const AskUnavailable(this.serviceType, {required this.from, required this.to});
  final String serviceType;
  final Day from;
  final Day to;

  @override
  String get callable => 'askUnavailable';

  @override
  Map<String, Object?> get data => {
    'serviceId': serviceType,
    'from': from.key.substring(0, 7),
    'to': to.key.substring(0, 7),
  };

  @override
  int answer(Map<String, Object?> data) => _count(data['people']);
}

final class RemindUnavailable extends ChurchCall<int> {
  const RemindUnavailable(this.serviceType);
  final String serviceType;

  @override
  String get callable => 'remindUnavailable';

  @override
  Map<String, Object?> get data => {'serviceId': serviceType};

  @override
  int answer(Map<String, Object?> data) => _count(data['people']);
}

final class SetGroupMember extends _Write {
  const SetGroupMember(
    this.uid,
    this.group, {
    required this.member,
    this.duties = const [],
    this.smallGroups = const [],
  });
  final String uid;
  final ChurchGroup group;
  final bool member;
  final List<String> duties;
  final List<String> smallGroups;

  @override
  String get callable => 'setGroupMember';

  @override
  Map<String, Object?> get data => {
    'uid': uid,
    ...switch (group) {
      ServiceGroup(:final id) => {'service': id, if (member) 'duties': duties, if (member) 'smallGroups': smallGroups},
      // A 事工 has no 同工 of its own (#94); nobody asks.
      MinistryGroup() || GatheringGroup() => throw const CloudException(CloudErrorCode.unknown),
      SmallGroup(:final id) => {'smallGroup': id},
    },
    'member': member,
  };
}

final class AddByName extends ChurchCall<String> {
  const AddByName(this.name, this.serviceType);
  final String name;
  final String serviceType;

  @override
  String get callable => 'addByName';

  @override
  Map<String, Object?> get data => {'name': name, 'service': serviceType};

  @override
  String answer(Map<String, Object?> data) => data['id']! as String;
}

/// On a duty's list ([on]) or off it.
final class SetDuty extends _Write {
  const SetDuty(this.uid, this.serviceType, this.duty, {required this.on});
  final String uid;
  final String serviceType;
  final String duty;
  final bool on;

  @override
  String get callable => 'setDuty';

  @override
  Map<String, Object?> get data => {'uid': uid, 'service': serviceType, 'duty': duty, 'on': on};
}

final class SetTimeZone extends _Write {
  const SetTimeZone(this.timeZone);
  final ChurchTimeZone timeZone;

  @override
  String get callable => 'setChurchTimeZone';

  @override
  Map<String, Object?> get data => {'timeZone': timeZone.id};
}

final class DeleteChurch extends _Write {
  const DeleteChurch();

  @override
  String get callable => 'deleteChurch';

  @override
  Map<String, Object?> get data => const {};
}

final class RestoreChurch extends _Write {
  const RestoreChurch();

  @override
  String get callable => 'restoreChurch';

  @override
  Map<String, Object?> get data => const {};
}

final class MergePending extends _Write {
  const MergePending(this.pendingId, this.uid);
  final String pendingId;
  final String uid;

  @override
  String get callable => 'mergePending';

  @override
  Map<String, Object?> get data => {'pendingId': pendingId, 'uid': uid};
}

final class RenamePending extends _Write {
  const RenamePending(this.id, this.name);
  final String id;
  final String name;

  @override
  String get callable => 'renamePending';

  @override
  Map<String, Object?> get data => {'pendingId': id, 'name': name};
}

final class RenameMember extends _Write {
  const RenameMember(this.uid, this.name);
  final String uid;
  final String name;

  @override
  String get callable => 'renameMember';

  @override
  Map<String, Object?> get data => {'uid': uid, 'name': name};
}

final class AskClaim extends _Write {
  const AskClaim(this.pendingId);
  final String? pendingId;

  @override
  String get callable => 'askClaim';

  @override
  Map<String, Object?> get data => {'pendingId': pendingId};
}

final class AnswerClaim extends _Write {
  const AnswerClaim(this.uid, {required this.allow});
  final String uid;
  final bool allow;

  @override
  String get callable => 'answerClaim';

  @override
  Map<String, Object?> get data => {'uid': uid, 'allow': allow};
}

/// Each [ChurchCall], by name, as the app asks for them.
extension ChurchCalls on ChurchData {
  /// The caller says they are pending member [pendingId]; null takes it
  /// back. The admins are told.
  Future<void> askClaim(String? pendingId) => run(AskClaim(pendingId));

  /// An admin answers member [uid]'s ask: [allow] merges the pending member
  /// they named into them. Either way the ask goes.
  Future<void> answerClaim(String uid, {required bool allow}) => run(AnswerClaim(uid, allow: allow));

  /// Renames pending member [id] (admins and 行政), on the rosters they are
  /// on too: a typo fixed. [CloudErrorCode.duplicateName] for a name
  /// someone in the church has.
  Future<void> renamePending(String id, String name) => run(RenamePending(id, name));

  /// 改同工的名字: admins and 行政 call member [uid] [name] in this church
  /// only, on its rosters too; their own new account name is theirs
  /// everywhere again. [CloudErrorCode.duplicateName] for a name someone in
  /// the church has.
  Future<void> renameMember(String uid, String name) => run(RenameMember(uid, name));

  /// Lets [uid] in, as an invite would (no 身分, no 牧區), or turns them
  /// down (admins). Letting in a request no longer waiting is
  /// [CloudReason.requestGone]; while the church takes none,
  /// [CloudReason.requestsClosed].
  Future<void> answerJoinRequest(String uid, {required bool allow}) => run(AnswerJoinRequest(uid, allow: allow));

  /// Closes 小組 [id], taking it off its 小組長 and 同工; its 人數 stay.
  Future<void> deleteSmallGroup(String id) => run(DeleteSmallGroup(id));

  /// Puts [service]'s 小組 in the order of [ids], every one of them: who
  /// opens them (Member.mayEditSmallGroup). Refused
  /// ([CloudErrorCode.conflict]) once its 小組 are not [ids].
  Future<void> orderSmallGroups(String service, List<String> ids) => run(OrderSmallGroups(service, ids));

  /// 通知同工 for [serviceType], by someone who arranges it: everyone put
  /// on or taken off its days in 安排服事 since hears it, one push each.
  /// In quiet hours ([PlannedNotice.later]) they wait until 7:00.
  Future<PlannedNotice> notifyPlanned(String serviceType) => run(NotifyPlanned(serviceType));

  /// 請人代 for my [duty] on [roster], a service's day from today on:
  /// everyone on the duty's list free that day ([coverAsked]). How many it
  /// asked; with nobody, the leads and those serving that day are told
  /// instead and it is 0. One open request per duty and day.
  Future<int> askCover(Roster roster, String duty) => run(AskCover(roster, duty));

  /// 和別週交換: my [duty] on [roster] for [uid]'s on [other], a day of the
  /// same service from tomorrow on. Asks them alone.
  Future<void> askSwap(Roster roster, String duty, Roster other, String uid) => run(AskSwap(roster, duty, other, uid));

  /// 我來 or 接受 ([yes]), or 不方便, to request [id], by one it asks. A
  /// request no longer open, or no longer holding, is refused with
  /// [CloudReason.swapClosed].
  Future<void> answerSwap(String id, {required bool yes}) => run(AnswerSwap(id, yes: yes));

  /// 復原 of taking request [id], soon after and while the rosters are as
  /// it left them; [CloudErrorCode.conflict] once they moved on.
  Future<void> undoSwap(String id) => run(UndoSwap(id));

  /// 收回: who asked takes request [id] back.
  Future<void> withdrawSwap(String id) => run(WithdrawSwap(id));

  /// 通知同工填 (#91), by whoever arranges [serviceType]: one push each to
  /// [askedToFill], for the months of [from] to [to]. How many it told.
  Future<int> askUnavailable(String serviceType, {required Day from, required Day to}) =>
      run(AskUnavailable(serviceType, from: from, to: to));

  /// 再通知 (#91), by whoever arranges [serviceType]: one push again to
  /// each its last 通知同工填 told who is still here and has not sent since.
  /// How many.
  Future<int> remindUnavailable(String serviceType) => run(RemindUnavailable(serviceType));

  /// 加為同工 ([member] true; for a service with the [duties] they serve and
  /// their [smallGroups] there) or 移出 [group], a service or a 小組 (a
  /// 事工 has no 同工 of its own, #94): by an admin, or by its 負責人 for a
  /// plain 同工 (Member.mayMove). Changes nothing else on member [uid].
  Future<void> setGroupMember(
    String uid,
    ChurchGroup group, {
    required bool member,
    List<String> duties = const [],
    List<String> smallGroups = const [],
  }) => run(SetGroupMember(uid, group, member: member, duties: duties, smallGroups: smallGroups));

  /// 加入同工 by [name]: someone who does not use the app, made one of
  /// [serviceType]'s 同工 without an account (a pending member, no email),
  /// by whoever may add a plain 同工 to it. [CloudErrorCode.duplicateName]
  /// for a name someone in the church has. Their ID.
  Future<String> addByName(String name, String serviceType) => run(AddByName(name, serviceType));

  /// Puts member [uid] on the list of [duty] in [serviceType] (#94),
  /// applied to the member as they are when written: one of its 同工 now
  /// if they were not, and nothing else on them changes. Only a duty the
  /// service has; by whoever edits its list (Member.editsDutyList).
  Future<void> grantDuty(String uid, String serviceType, String duty) => run(SetDuty(uid, serviceType, duty, on: true));

  /// Takes member [uid] off the list of [duty] in [serviceType], the same
  /// way; still one of its 同工. Any duty, one gone from the service too.
  Future<void> revokeDuty(String uid, String serviceType, String duty) =>
      run(SetDuty(uid, serviceType, duty, on: false));

  /// Sets the church's time zone (admins). Rosters keep their dates; the
  /// calendar's times are then shown on the new clock.
  Future<void> setTimeZone(ChurchTimeZone timeZone) => run(SetTimeZone(timeZone));

  /// Deletes the church while it is open (admins); restorable for 30 days.
  Future<void> deleteChurch() => run(const DeleteChurch());

  /// Reopens the church its admin deleted under 30 days ago; an open church
  /// stays open. A suspended one, or one deleted longer ago, is
  /// [CloudErrorCode.churchClosed].
  Future<void> restoreChurch() => run(const RestoreChurch());

  /// Merges a pending member into a member (admins).
  Future<void> mergePending(String pendingId, String uid) => run(MergePending(pendingId, uid));
}
